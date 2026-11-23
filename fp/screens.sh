#!/usr/bin/env bash
set -euo pipefail
project=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
out=${FP_RESULTS:?}
if [[ "${1:-}" == --terminal ]]; then
    for name in 01_build 02_debug_notes; do
        printf '\033[2J\033[H'; cat "$out/notes/$name.txt"; sleep 1
        scrot -o "$out/screenshots/$name.png"
    done
    if bash "$project/run_qemu.sh"; then
        for name in 09_atune_architecture 10_atune_method_and_conclusion; do
            printf '\033[2J\033[H'; cat "$out/notes/$name.txt"; sleep 1
            scrot -o "$out/screenshots/$name.png"
        done
        printf '0\n' > "$out/logs/demo-exit-code.txt"
    else
        status=$?; printf '%s\n' "$status" > "$out/logs/demo-exit-code.txt"; exit "$status"
    fi
    exit 0
fi
xvfb-run --auto-servernum --server-args='-screen 0 1404x804x24 -nolisten tcp' \
    xterm -geometry 140x40+0+0 -fn 10x20 -b 2 -bw 0 +sb \
    -bg '#10141c' -fg '#e6edf3' -cr '#58a6ff' -title 'FP procfs reproduction and A-Tune feature study' \
    -e bash "$project/screens.sh" --terminal
test "$(cat "$out/logs/demo-exit-code.txt")" = 0
test "$(find "$out/screenshots" -name '*.png' | wc -l)" = 10
echo FP_ALL_REQUIREMENTS_VERIFIED
