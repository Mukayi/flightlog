#!/bin/bash

set -euo pipefail

BINARY_PATH="${1:-}"
if [[ -z "${BINARY_PATH}" || ! -f "${BINARY_PATH}" ]]; then
    echo "用法：$0 <FlightLog 可执行文件路径>" >&2
    exit 2
fi

SECTION_MATCHES="$(
    otool -l "${BINARY_PATH}" |
        awk '
            /__llvm_prf_|__llvm_cov|__LLVM_COV/ {
                if (count < 20) {
                    print
                }
                count += 1
            }
        '
)"
SYMBOL_MATCHES="$(
    nm -m "${BINARY_PATH}" |
        awk '
            /__llvm_prf_|__llvm_cov|__llvm_profile|___covrec_/ {
                if (count < 20) {
                    print
                }
                count += 1
            }
        '
)"

if [[ -n "${SECTION_MATCHES}" || -n "${SYMBOL_MATCHES}" ]]; then
    echo "Release 二进制包含 LLVM coverage/profile 插桩：" >&2
    if [[ -n "${SECTION_MATCHES}" ]]; then
        printf '%s\n' "${SECTION_MATCHES}" >&2
    fi
    if [[ -n "${SYMBOL_MATCHES}" ]]; then
        printf '%s\n' "${SYMBOL_MATCHES}" >&2
    fi
    exit 1
fi

echo "Release 二进制未发现 LLVM coverage/profile 插桩：${BINARY_PATH}"
