#!/usr/bin/env bash
set -euo pipefail
project=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
out=${P5_RESULTS:?}
if [[ "${1:-}" == --terminal ]]; then
    if bash "$project/run_qemu.sh"; then
        printf '0\n' > "$out/logs/demo-exit-code.txt"
    else
        status=$?; printf '%s\n' "$status" > "$out/logs/demo-exit-code.txt"; exit "$status"
    fi
    exit 0
fi
xvfb-run --auto-servernum --server-args='-screen 0 1404x804x24 -nolisten tcp' \
    xterm -geometry 140x40+0+0 -fn 10x20 -b 2 -bw 0 +sb \
    -bg '#10141c' -fg '#e6edf3' -cr '#58a6ff' -title 'P5 real slab cache and cross-module allocation' \
    -e bash "$project/screens.sh" --terminal
test "$(cat "$out/logs/demo-exit-code.txt")" = 0
test "$(find "$out/screenshots" -name '*.png' | wc -l)" = 8
echo P5_ALL_REQUIREMENTS_VERIFIED
