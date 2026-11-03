#!/usr/bin/env bash
set -euo pipefail
[[ "${GITHUB_ACTIONS:-}" == true ]] || {
    printf 'This entry point runs in GitHub Actions only.\n' >&2
    exit 2
}
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
mkdir -p logs screenshots

if [[ "${1:-}" == --terminal ]]; then
    export P1_AUTO_CAPTURE=1
    if bash ./demo.sh --batch; then
        printf '0\n' > logs/cloud-exit-code.txt
    else
        status=$?
        printf '%s\n' "$status" > logs/cloud-exit-code.txt
        exit "$status"
    fi
    exit 0
fi

# A real xterm process executes the commands in an Xvfb display. scrot captures
# this display during each test; no output image is drawn from invented text.
xvfb-run --auto-servernum --server-args='-screen 0 1480x874x24 -nolisten tcp' \
    xterm -geometry 164x58+0+0 -fn 9x15 -b 2 -bw 0 +sb \
    -bg '#10141c' -fg '#e6edf3' -cr '#58a6ff' \
    -title 'P1 / GitHub Actions Ubuntu' -e bash ./cloud-run.sh --terminal

test -r logs/cloud-exit-code.txt
status=$(cat logs/cloud-exit-code.txt)
[[ "$status" == 0 ]] || exit "$status"
for filename in 01_build 02_default 03_parameters 04_calc_unload 05_invalid; do
    test -s "screenshots/$filename.png"
done
printf 'Verified: cloud demo exited successfully and five screenshots exist.\n'
