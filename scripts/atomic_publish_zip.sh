#!/bin/bash

set -euo pipefail

temporary_zip="${1:?temporary zip path is required}"
final_zip="${2:?final zip path is required}"

if [[ "${FLIGHTLOG_TEST_FAIL_ZIP_PUBLISH:-0}" == "1" ]]; then
    exit 97
fi

test -f "${temporary_zip}"
test "$(dirname "${temporary_zip}")" = "$(dirname "${final_zip}")"
mv -f "${temporary_zip}" "${final_zip}"

if [[ "${FLIGHTLOG_TEST_FAIL_ZIP_AFTER_MV:-0}" == "1" ]]; then
    exit 98
fi
