#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_ASSETS_DIR="${ROOT_DIR}/Assets"
ASSETS_DIR="${FLIGHTLOG_ICON_OUTPUT_DIR:-${SOURCE_ASSETS_DIR}}"
SOURCE_PATH="${SOURCE_ASSETS_DIR}/FlightLogIconSource.png"
MASTER_PATH="${ASSETS_DIR}/FlightLogIconMaster.png"
ICONSET_PATH="${ASSETS_DIR}/FlightLog.iconset"
ICNS_PATH="${ASSETS_DIR}/FlightLog.icns"
RENDERER="${ROOT_DIR}/scripts/render_icon_master.swift"
SMALL_RENDERER="${ROOT_DIR}/scripts/render_icon_small.swift"
VERIFIER="${ROOT_DIR}/scripts/verify_icon_alpha.swift"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/flightlog-icon.XXXXXX")"

cleanup() {
    rm -rf "${TEMP_DIR}"
}
trap cleanup EXIT

for command in xcrun sips iconutil; do
    if ! command -v "${command}" >/dev/null 2>&1; then
        echo "缺少图标生成工具：${command}" >&2
        exit 1
    fi
done
if [[ ! -f "${SOURCE_PATH}" ]]; then
    echo "缺少原创图标源：${SOURCE_PATH}" >&2
    exit 1
fi
if [[ ! -f "${RENDERER}" || ! -f "${SMALL_RENDERER}" || ! -f "${VERIFIER}" ]]; then
    echo "缺少图标渲染或验证脚本。" >&2
    exit 1
fi

TEMP_MASTER="${TEMP_DIR}/FlightLogIconMaster.png"
TEMP_ICONSET="${TEMP_DIR}/FlightLog.iconset"
TEMP_ICNS="${TEMP_DIR}/FlightLog.icns"
mkdir -p "${TEMP_ICONSET}" "${ASSETS_DIR}"

xcrun swift "${RENDERER}" "${SOURCE_PATH}" "${TEMP_MASTER}"
xcrun swift "${VERIFIER}" "${TEMP_MASTER}"

declare -a ICON_SPECS=(
    "16:icon_16x16.png"
    "32:icon_16x16@2x.png"
    "32:icon_32x32.png"
    "64:icon_32x32@2x.png"
    "128:icon_128x128.png"
    "256:icon_128x128@2x.png"
    "256:icon_256x256.png"
    "512:icon_256x256@2x.png"
    "512:icon_512x512.png"
    "1024:icon_512x512@2x.png"
)

for specification in "${ICON_SPECS[@]}"; do
    size="${specification%%:*}"
    filename="${specification#*:}"
    if [[ "${size}" == "16" || "${size}" == "32" ]]; then
        xcrun swift \
            "${SMALL_RENDERER}" \
            "${TEMP_MASTER}" \
            "${size}" \
            "${TEMP_ICONSET}/${filename}"
    else
        sips \
            --resampleHeightWidth "${size}" "${size}" \
            "${TEMP_MASTER}" \
            --out "${TEMP_ICONSET}/${filename}" \
            >/dev/null
    fi
done

xcrun swift "${VERIFIER}" "${TEMP_ICONSET}/icon_16x16.png"
xcrun swift "${VERIFIER}" "${TEMP_ICONSET}/icon_32x32.png"
iconutil -c icns "${TEMP_ICONSET}" -o "${TEMP_ICNS}"
iconutil -c iconset "${TEMP_ICNS}" -o "${TEMP_DIR}/roundtrip.iconset"

install -m 644 "${TEMP_MASTER}" "${MASTER_PATH}"
install -m 644 "${TEMP_ICNS}" "${ICNS_PATH}"
rm -rf "${ICONSET_PATH}"
mv "${TEMP_ICONSET}" "${ICONSET_PATH}"

echo "已生成：${MASTER_PATH}"
echo "已生成：${ICONSET_PATH}"
echo "已生成：${ICNS_PATH}"
