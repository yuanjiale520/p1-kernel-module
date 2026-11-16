#!/usr/bin/env bash
set -euo pipefail
project=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
out=${P3_RESULTS:?}
if [[ "${1:-}" == --terminal ]]; then
    for name in 01_open_kernel_code 02_write_kernel_code 03_mkdir_kernel_code 04_mount_module_code; do
        printf '\033[2J\033[H'
        cat "$out/code-pages/$name.txt"
        sleep 1
        scrot -o "$out/screenshots/$name.png"
    done
    if bash "$project/run_qemu.sh"; then
        printf '0\n' > "$out/logs/demo-exit-code.txt"
    else
        status=$?
        printf '%s\n' "$status" > "$out/logs/demo-exit-code.txt"
        exit "$status"
    fi
    exit 0
fi
xvfb-run --auto-servernum --server-args='-screen 0 1480x994x24 -nolisten tcp' \
    xterm -geometry 164x66+0+0 -fn 9x15 -b 2 -bw 0 +sb \
    -bg '#10141c' -fg '#e6edf3' -cr '#58a6ff' -title 'P3 actual code and kernel execution' \
    -e bash "$project/screens.sh" --terminal
test "$(cat "$out/logs/demo-exit-code.txt")" = 0
test "$(find "$out/screenshots" -name '*.png' | wc -l)" = 8
printf 'P3_ALL_REQUIREMENTS_VERIFIED\n'
