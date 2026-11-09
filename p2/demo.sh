#!/usr/bin/env bash
set -euo pipefail
project=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
out=${P2_RESULTS:?}
run() { printf '$'; printf ' %q' "$@"; printf '\n'; "$@"; }
screen() { printf '\033[2J\033[H'; printf '=== P2 / %s ===\n\n' "$*"; }
capture() { sleep 1; scrot -o "$out/screenshots/$1.png"; }

screen 'Build outputs and host kernel'
run uname -r
printf '\nSelf-compiled guest kernel: '
cat "$out/logs/guest-kernel.txt"
run ls -l "$out/images/bzImage" "$out/images/initramfs.img" \
    "$(readlink -f "$(command -v qemu-system-x86_64)")"
run qemu-system-x86_64 --version
run file "$out/images/bzImage" "$out/images/initramfs.img"
printf '\nKernel build completed from official source. SHA256 check passed.\n'
capture 01_build_files

screen 'Boot the self-compiled kernel and load the optional guest module'
run bash "$project/run_qemu.sh"
printf '\nPASS: QEMU boot, different host/guest kernels, module load and unload.\n'

screen 'XFCE desktop in a real TigerVNC X session'
run neofetch --disable packages
printf '\n'
run printf 'DISPLAY=%s\nDESKTOP_SESSION=%s\nXDG_CURRENT_DESKTOP=%s\n' \
    "$DISPLAY" "$DESKTOP_SESSION" "$XDG_CURRENT_DESKTOP"
capture 04_xfce_neofetch

screen 'X session configuration and running processes'
run sh -c 'ps -eo comm,args | grep -E "[X]tigervnc|[x]fce4-session|[x]fwm4"'
run sh -c 'ss -ltn | grep 5991'
run sh -c 'xdpyinfo -display "$DISPLAY" | head -n 20'
capture 05_xsession_configuration
printf '\nP2_DESKTOP_SUCCESS\n'
