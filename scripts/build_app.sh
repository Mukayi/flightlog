#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

APP_VERSION="1.0"
DIST_DIR="${ROOT_DIR}/dist"
APP_PATH="${DIST_DIR}/FlightLog.app"
STAGING_PATH="${DIST_DIR}/.FlightLog.app.tmp"
CONTENTS_DIR="${STAGING_PATH}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
SCRATCH_DIR="${ROOT_DIR}/.build-app"
BINARY_CHECK_SCRIPT="${ROOT_DIR}/scripts/check_release_binary.sh"
RESOURCE_CHECK_SCRIPT="${ROOT_DIR}/scripts/validate_airport_resources.py"
ICON_GENERATOR="${ROOT_DIR}/scripts/generate_icon.sh"
ICON_PATH="${ROOT_DIR}/Assets/FlightLog.icns"
APP_ICON_CHECK_SCRIPT="${ROOT_DIR}/scripts/verify_app_icon.py"
SMOKE_DIRECTORY=""
SMOKE_PID=""

if [[ ! -x "${BINARY_CHECK_SCRIPT}" ]]; then
    echo "缺少可执行的 Release 二进制检查脚本：${BINARY_CHECK_SCRIPT}" >&2
    exit 1
fi
if [[ ! -x "${ICON_GENERATOR}" ]]; then
    echo "缺少可执行的图标生成脚本：${ICON_GENERATOR}" >&2
    exit 1
fi
if [[ ! -f "${APP_ICON_CHECK_SCRIPT}" ]]; then
    echo "缺少 app 图标验证脚本：${APP_ICON_CHECK_SCRIPT}" >&2
    exit 1
fi

cleanup() {
    if [[ -n "${SMOKE_PID}" ]] && kill -0 "${SMOKE_PID}" 2>/dev/null; then
        kill -TERM "${SMOKE_PID}" 2>/dev/null || true
        wait "${SMOKE_PID}" 2>/dev/null || true
    fi
    if [[ -n "${SMOKE_DIRECTORY}" ]]; then
        rm -rf "${SMOKE_DIRECTORY}"
    fi
    rm -rf "${STAGING_PATH}" "${SCRATCH_DIR}"
}
trap cleanup EXIT

"${ICON_GENERATOR}"
if [[ ! -f "${ICON_PATH}" ]]; then
    echo "图标生成后未找到：${ICON_PATH}" >&2
    exit 1
fi

rm -rf "${SCRATCH_DIR}"
SWIFT_BUILD_ARGUMENTS=(
    --package-path "${ROOT_DIR}"
    --scratch-path "${SCRATCH_DIR}"
    --configuration release
    --disable-code-coverage
    --product FlightLog
)

echo "在独立 scratch path 中构建无覆盖率插桩的 Release"
swift build "${SWIFT_BUILD_ARGUMENTS[@]}"
BIN_DIR="$(
    swift build \
        --package-path "${ROOT_DIR}" \
        --scratch-path "${SCRATCH_DIR}" \
        --configuration release \
        --disable-code-coverage \
        --show-bin-path
)"
EXECUTABLE_PATH="${BIN_DIR}/FlightLog"
RESOURCE_BUNDLE_PATH="${BIN_DIR}/FlightLog_FlightLog.bundle"

if [[ ! -x "${EXECUTABLE_PATH}" ]]; then
    echo "未找到 Release 可执行文件：${EXECUTABLE_PATH}" >&2
    exit 1
fi
if [[ ! -d "${RESOURCE_BUNDLE_PATH}" ]]; then
    echo "未找到 Swift Package 资源包：${RESOURCE_BUNDLE_PATH}" >&2
    exit 1
fi
RESOURCE_SOURCE_DIR="${RESOURCE_BUNDLE_PATH}"
if [[ -d "${RESOURCE_BUNDLE_PATH}/Contents/Resources" ]]; then
    RESOURCE_SOURCE_DIR="${RESOURCE_BUNDLE_PATH}/Contents/Resources"
fi
if [[ ! -f "${RESOURCE_SOURCE_DIR}/airports.json" ]]; then
    echo "资源包缺少 airports.json。" >&2
    exit 1
fi
python3 "${RESOURCE_CHECK_SCRIPT}" "${RESOURCE_SOURCE_DIR}"

mkdir -p "${DIST_DIR}"
rm -rf "${STAGING_PATH}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

install -m 755 "${EXECUTABLE_PATH}" "${MACOS_DIR}/FlightLog"
install -m 644 \
    "${RESOURCE_SOURCE_DIR}/airports.json" \
    "${RESOURCES_DIR}/airports.json"
install -m 644 \
    "${RESOURCE_SOURCE_DIR}/AIRPORT_DATA_LICENSE.md" \
    "${RESOURCES_DIR}/AIRPORT_DATA_LICENSE.md"
install -m 644 "${ICON_PATH}" "${RESOURCES_DIR}/FlightLog.icns"
if ! cmp -s "${ICON_PATH}" "${RESOURCES_DIR}/FlightLog.icns"; then
    echo "app 内图标与生成图标不一致。" >&2
    exit 1
fi

"${BINARY_CHECK_SCRIPT}" "${MACOS_DIR}/FlightLog"

cat > "${CONTENTS_DIR}/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh_CN</string>
    <key>CFBundleDisplayName</key>
    <string>航班日志</string>
    <key>CFBundleExecutable</key>
    <string>FlightLog</string>
    <key>CFBundleIdentifier</key>
    <string>local.flightlog.FlightLog</string>
    <key>CFBundleIconFile</key>
    <string>FlightLog.icns</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>FlightLog</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${APP_VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${APP_VERSION}</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.travel</string>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

plutil -lint "${CONTENTS_DIR}/Info.plist"
xattr -cr "${STAGING_PATH}"
codesign --force --deep --sign - "${STAGING_PATH}"
codesign --verify --deep --strict --verbose=2 "${STAGING_PATH}"

rm -rf "${APP_PATH}"
mv "${STAGING_PATH}" "${APP_PATH}"
codesign --verify --deep --strict --verbose=2 "${APP_PATH}"
"${BINARY_CHECK_SCRIPT}" "${APP_PATH}/Contents/MacOS/FlightLog"
python3 "${RESOURCE_CHECK_SCRIPT}" "${APP_PATH}/Contents/Resources"
python3 "${APP_ICON_CHECK_SCRIPT}" "${APP_PATH}" "${ICON_PATH}"

SMOKE_DIRECTORY="$(mktemp -d "${TMPDIR:-/tmp}/flightlog-smoke.XXXXXX")"
SMOKE_HOME="${SMOKE_DIRECTORY}/home"
SMOKE_LOG="${SMOKE_DIRECTORY}/app.log"
mkdir -p "${SMOKE_HOME}"
SMOKE_STORE="${SMOKE_HOME}/Library/Application Support/FlightLog/FlightLog.store"
HOME="${SMOKE_HOME}" CFFIXED_USER_HOME="${SMOKE_HOME}" \
    "${APP_PATH}/Contents/MacOS/FlightLog" \
    >"${SMOKE_LOG}" 2>&1 &
SMOKE_PID=$!
for _ in {1..80}; do
    if [[ -f "${SMOKE_STORE}" ]] && kill -0 "${SMOKE_PID}" 2>/dev/null; then
        break
    fi
    if ! kill -0 "${SMOKE_PID}" 2>/dev/null; then
        echo "真实 app 在隔离 store ready 前退出。" >&2
        wait "${SMOKE_PID}" || true
        SMOKE_PID=""
        test -f "${SMOKE_LOG}" && awk 'NR <= 80 { print }' "${SMOKE_LOG}" >&2
        exit 1
    fi
    sleep 0.25
done
if [[ ! -f "${SMOKE_STORE}" ]]; then
    echo "真实 app 未在 20 秒内创建隔离 SwiftData store。" >&2
    exit 1
fi
kill -TERM "${SMOKE_PID}"
wait "${SMOKE_PID}" 2>/dev/null || true
SMOKE_PID=""
python3 - "${SMOKE_LOG}" <<'PY'
import pathlib
import sys

text = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8", errors="replace")
lowered = text.lower()
for forbidden in ("fatal error", "uncaught exception"):
    if forbidden in lowered:
        raise SystemExit(f"隔离 launch 日志包含 {forbidden}")
PY
echo "隔离 HOME 正常 launch smoke 通过：已创建 store 且进程保持运行。"

echo "已生成并验证：${APP_PATH}"
