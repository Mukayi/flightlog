#!/bin/bash

set -euo pipefail

final_zip="${1:?final zip path is required}"
expected_sha256="${2:?expected SHA256 is required}"

test -f "${final_zip}"
actual_sha256="$(shasum -a 256 "${final_zip}" | awk '{print $1}')"
test "${actual_sha256}" = "${expected_sha256}"
