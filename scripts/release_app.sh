#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_SCRIPT="${ROOT_DIR}/scripts/build_app.sh"
SOURCE_APP="${ROOT_DIR}/dist/FlightLog.app"
INSTALL_APP="/Applications/FlightLog.app"
ZIP_PATH="${HOME}/Desktop/FlightLog-macOS-arm64.zip"
ZIP_PUBLISHER="${ROOT_DIR}/scripts/atomic_publish_zip.sh"
COMMIT_GUARD="${ROOT_DIR}/scripts/release_commit_guard.sh"
ZIP_TEMP="$(mktemp "${ZIP_PATH}.tmp.XXXXXX")"
rm -f "${ZIP_TEMP}"
STAGING_APP="/Applications/.FlightLog.app.release.$$"
BACKUP_APP="/Applications/.FlightLog.app.backup.$(date +%Y%m%d%H%M%S)"
VERIFY_DIR="$(mktemp -d "${TMPDIR:-/tmp}/flightlog-release-verify.XXXXXX")"
HAD_PREVIOUS=false
NEW_INSTALLED=false
RELEASE_SUCCEEDED=false
EXPECTED_ZIP_SHA256=""
EXPECTED_ZIP_SIZE=""
SMOKE_PID=""

cleanup() {
    set +e
    if [[ -n "${SMOKE_PID}" ]] && kill -0 "${SMOKE_PID}" 2>/dev/null; then
        kill -TERM "${SMOKE_PID}" 2>/dev/null
        wait "${SMOKE_PID}" 2>/dev/null
    fi
    rm -rf "${STAGING_APP}" "${VERIFY_DIR}"
    rm -f "${ZIP_TEMP}"
    commit_observed="${RELEASE_SUCCEEDED}"
    if [[ "${commit_observed}" != true ]] \
        && [[ -n "${EXPECTED_ZIP_SHA256}" ]] \
        && "${COMMIT_GUARD}" "${ZIP_PATH}" "${EXPECTED_ZIP_SHA256}"; then
        commit_observed=true
    fi
    if [[ "${commit_observed}" != true ]]; then
        if [[ "${NEW_INSTALLED}" == true ]]; then
            rm -rf "${INSTALL_APP}"
        fi
        if [[ "${HAD_PREVIOUS}" == true && -e "${BACKUP_APP}" ]]; then
            mv "${BACKUP_APP}" "${INSTALL_APP}"
        fi
    fi
}
trap cleanup EXIT

"${BUILD_SCRIPT}"
codesign --verify --deep --strict --verbose=2 "${SOURCE_APP}"

pkill -TERM -x FlightLog 2>/dev/null || true
for _ in {1..50}; do
    pgrep -x FlightLog >/dev/null || break
    sleep 0.1
done
if pgrep -x FlightLog >/dev/null; then
    echo "FlightLog 未能在安装前退出。" >&2
    exit 1
fi

ditto "${SOURCE_APP}" "${STAGING_APP}"
codesign --verify --deep --strict --verbose=2 "${STAGING_APP}"
if [[ -e "${INSTALL_APP}" ]]; then
    HAD_PREVIOUS=true
    mv "${INSTALL_APP}" "${BACKUP_APP}"
fi
if ! mv "${STAGING_APP}" "${INSTALL_APP}"; then
    exit 1
fi
NEW_INSTALLED=true
if ! codesign --verify --deep --strict --verbose=2 "${INSTALL_APP}"; then
    exit 1
fi

xattr -cr "${INSTALL_APP}"
codesign --verify --deep --strict --verbose=2 "${INSTALL_APP}"
COPYFILE_DISABLE=1 ditto -c -k --sequesterRsrc --keepParent \
    --norsrc --noextattr "${INSTALL_APP}" "${ZIP_TEMP}"
if zipinfo -1 "${ZIP_TEMP}" | awk '
    /^__MACOSX\// || /(^|\/)\._/ { found = 1 }
    END { exit(found ? 0 : 1) }
'; then
    zip -d "${ZIP_TEMP}" '__MACOSX/*' >/dev/null
fi
python3 - "${ZIP_TEMP}" <<'PY'
import sys
import zipfile

with zipfile.ZipFile(sys.argv[1]) as archive:
    names = archive.namelist()
bad = [
    name for name in names
    if name.startswith("__MACOSX/")
    or name.startswith("._")
    or "/._" in name
]
if bad:
    raise SystemExit(f"zip 仍含 AppleDouble：{bad}")
if not names or not all(
    name == "FlightLog.app/" or name.startswith("FlightLog.app/")
    for name in names
):
    raise SystemExit("zip 包含 FlightLog.app 以外内容")
PY

ditto -x -k "${ZIP_TEMP}" "${VERIFY_DIR}"
EXTRACTED_APP="${VERIFY_DIR}/FlightLog.app"
codesign --verify --deep --strict --verbose=2 "${EXTRACTED_APP}"
plutil -lint "${EXTRACTED_APP}/Contents/Info.plist"
"${ROOT_DIR}/scripts/check_release_binary.sh" \
    "${EXTRACTED_APP}/Contents/MacOS/FlightLog"
python3 "${ROOT_DIR}/scripts/validate_airport_resources.py" \
    "${EXTRACTED_APP}/Contents/Resources"
python3 "${ROOT_DIR}/scripts/verify_app_icon.py" \
    "${EXTRACTED_APP}" "${ROOT_DIR}/Assets/FlightLog.icns"

installed_executable_sha256="$(
    shasum -a 256 "${INSTALL_APP}/Contents/MacOS/FlightLog" | awk '{print $1}'
)"
extracted_executable_sha256="$(
    shasum -a 256 "${EXTRACTED_APP}/Contents/MacOS/FlightLog" | awk '{print $1}'
)"
installed_airports_sha256="$(
    shasum -a 256 "${INSTALL_APP}/Contents/Resources/airports.json" | awk '{print $1}'
)"
extracted_airports_sha256="$(
    shasum -a 256 "${EXTRACTED_APP}/Contents/Resources/airports.json" | awk '{print $1}'
)"
test "${installed_executable_sha256}" = "${extracted_executable_sha256}"
test "${installed_airports_sha256}" = "${extracted_airports_sha256}"

SMOKE_HOME="${VERIFY_DIR}/home"
SMOKE_LOG="${VERIFY_DIR}/normal-launch.log"
SMOKE_STORE="${SMOKE_HOME}/Library/Application Support/FlightLog/FlightLog.store"
mkdir -p "${SMOKE_HOME}"
HOME="${SMOKE_HOME}" CFFIXED_USER_HOME="${SMOKE_HOME}" \
    "${EXTRACTED_APP}/Contents/MacOS/FlightLog" \
    >"${SMOKE_LOG}" 2>&1 &
SMOKE_PID=$!
for _ in {1..80}; do
    if [[ -f "${SMOKE_STORE}" ]] && kill -0 "${SMOKE_PID}" 2>/dev/null; then
        break
    fi
    kill -0 "${SMOKE_PID}" 2>/dev/null || {
        echo "zip 解压 app 在正常 launch ready 前退出。" >&2
        exit 1
    }
    sleep 0.25
done
test -f "${SMOKE_STORE}"
kill -TERM "${SMOKE_PID}"
wait "${SMOKE_PID}" 2>/dev/null || true
SMOKE_PID=""

FLIGHTLOG_RELEASE_APP_PATH="${EXTRACTED_APP}" swift test \
    --package-path "${ROOT_DIR}" \
    --filter \
    ProfileSchemaMigrationTests/testPackagedReleaseMigratesWALFixtureIdempotentlyAndPreservesFailedSource

EXPECTED_ZIP_SHA256="$(shasum -a 256 "${ZIP_TEMP}" | awk '{print $1}')"
EXPECTED_ZIP_SIZE="$(stat -f %z "${ZIP_TEMP}")"
"${ZIP_PUBLISHER}" "${ZIP_TEMP}" "${ZIP_PATH}"
RELEASE_SUCCEEDED=true
if [[ -e "${BACKUP_APP}" ]]; then
    rm -rf "${BACKUP_APP}" 2>/dev/null || true
fi
echo "INSTALL_APP=${INSTALL_APP}"
echo "ZIP_PATH=${ZIP_PATH}"
echo "EXECUTABLE_SHA256=${installed_executable_sha256}"
echo "AIRPORTS_SHA256=${installed_airports_sha256}"
echo "ZIP_SHA256=${EXPECTED_ZIP_SHA256}"
echo "ZIP_SIZE=${EXPECTED_ZIP_SIZE}"
