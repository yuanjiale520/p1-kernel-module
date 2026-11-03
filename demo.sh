#!/usr/bin/env bash
# Execute real commands, record output, and pause for manual screenshots.
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"

batch=0
[[ "${1:-}" != --batch ]] || batch=1

if [[ "${1:-}" != --inner ]]; then
    bash ./check_env.sh
    if (( EUID != 0 )); then
        sudo -v
    fi
    mkdir -p logs screenshots
    logfile="logs/run-$(date +%Y%m%d-%H%M%S)-$$.log"
    printf '\nTranscript: %s\n' "$logfile"
    export P1_DEMO_BATCH=$batch
    exec script -q -e -c 'bash ./demo.sh --inner' "$logfile"
fi

batch=${P1_DEMO_BATCH:-0}
auto_capture=${P1_AUTO_CAPTURE:-0}
if [[ "$auto_capture" == 1 && "${GITHUB_ACTIONS:-}" != true ]]; then
    printf 'Automatic screenshots are configured for the GitHub cloud runner only.\n' >&2
    exit 1
fi
student=${P1_NAME:-Student}
SUDO=()
(( EUID == 0 )) || SUDO=(sudo)
owned_module=0

run() {
    printf '$'
    printf ' %q' "$@"
    printf '\n'
    "$@"
}

cleanup() {
    if (( owned_module )); then
        "${SUDO[@]}" rmmod p1_demo || true
    fi
}
trap cleanup EXIT

load() {
    run "${SUDO[@]}" insmod ./p1_demo.ko "$@"
    owned_module=1
}

unload() {
    run "${SUDO[@]}" rmmod p1_demo
    owned_module=0
}

logs() {
    printf '$ dmesg | grep -F "p1_demo: " | tail -n %s\n' "$1"
    "${SUDO[@]}" dmesg | grep -F 'p1_demo: ' | tail -n "$1"
}

loaded() {
    printf '$ lsmod | grep "^p1_demo "\n'
    lsmod | grep '^p1_demo '
}

absent() {
    printf '$ test ! -d /sys/module/p1_demo\n'
    if [[ -d /sys/module/p1_demo ]]; then
        printf 'FAIL: p1_demo is still loaded.\n' >&2
        exit 1
    fi
    printf 'PASS: p1_demo is not loaded.\n'
}

screen() {
    if (( ! batch || auto_capture )) && [[ -t 1 ]]; then
        printf '\033[2J\033[H'
    fi
    printf '=== P1 / screenshot %s: %s ===\n\n' "$1" "$2"
    if [[ "${GITHUB_ACTIONS:-}" == true ]]; then
        printf 'Environment: GitHub-hosted Ubuntu VM / %s\n\n' "$(uname -r)"
    fi
}

pause_for_capture() {
    if [[ "$auto_capture" == 1 ]]; then
        local filename
        case "$1" in
            1) filename=01_build.png ;;
            2) filename=02_default.png ;;
            3) filename=03_parameters.png ;;
            4) filename=04_calc_unload.png ;;
            5) filename=05_invalid.png ;;
            *) return 1 ;;
        esac
        # Capture the actual X terminal framebuffer after its output is painted.
        sleep 1
        scrot -o "screenshots/$filename"
    elif (( ! batch )); then
        printf '\nSave screenshot %s now (Win+Shift+S), then press Enter. ' "$1"
        IFS= read -r
    fi
}

if [[ -d /sys/module/p1_demo ]]; then
    printf 'p1_demo is already loaded. Unload your previous test before this demo.\n' >&2
    exit 1
fi

screen 1 'three C files -> one kernel module'
run uname -r
run ls main.c greeting.c arithmetic.c p1_demo.h Makefile
run make clean
run make "CC=${P1_CC:-gcc}"
run modinfo -F name ./p1_demo.ko
run modinfo -F parm ./p1_demo.ko
pause_for_capture 1

screen 2 'default parameters / successful insertion'
load
loaded
logs 2
unload
logs 1
pause_for_capture 2

screen 3 'custom name and repeat count'
load name="$student" mode=hello repeat=2
loaded
logs 3
run cat /sys/module/p1_demo/parameters/name
run cat /sys/module/p1_demo/parameters/repeat
unload
pause_for_capture 3

screen 4 'calculation mode / successful removal'
load mode=calc a=12 b=8
loaded
logs 3
unload
logs 1
absent
pause_for_capture 4

screen 5 'invalid parameter is rejected (extra validation)'
printf '$ insmod ./p1_demo.ko mode=wrong\n'
if "${SUDO[@]}" insmod ./p1_demo.ko mode=wrong; then
    owned_module=1
    printf 'FAIL: invalid mode was unexpectedly accepted.\n' >&2
    exit 1
else
    rc=$?
    printf 'insmod exit status: %s\n' "$rc"
fi
logs 1
"${SUDO[@]}" dmesg | grep -F 'p1_demo: ' | tail -n 1 | \
    grep -F 'invalid mode: expected hello, calc, or all'
absent
pause_for_capture 5

if [[ "$auto_capture" == 1 ]]; then
    printf '\nCloud demo finished. Real terminal screenshots are in screenshots/.\n'
else
    printf '\nDemo finished. Screenshots must be saved manually; the transcript is in logs/.\n'
fi
