#!/usr/bin/env bash
set -euo pipefail
out=${P2_RESULTS:?}
timeout 120 qemu-system-x86_64 \
    -accel tcg,thread=multi -cpu qemu64 -smp 2 -m 256 \
    -kernel "$out/images/bzImage" -initrd "$out/images/initramfs.img" \
    -append 'console=ttyS0 rdinit=/init quiet loglevel=3 panic=-1' \
    -nographic -nic none -no-reboot > >(tee "$out/logs/qemu-console.log") 2>&1 &
qemu_pid=$!
trap 'kill "$qemu_pid" 2>/dev/null || true' EXIT
capture_marker() {
    local marker=$1 filename=$2 ready=0
    for n in $(seq 1 1000); do
        if grep -q "$marker" "$out/logs/qemu-console.log" 2>/dev/null; then
            ready=1
            break
        fi
        if ! kill -0 "$qemu_pid" 2>/dev/null; then break; fi
        sleep 0.1
    done
    (( ready )) || return 1
    sleep 1
    scrot -o "$out/screenshots/$filename.png"
}
capture_marker P2_BOOT_READY 02_qemu_guest_kernel
capture_marker P2_MODULE_OK 03_optional_guest_module
wait "$qemu_pid"
trap - EXIT
for marker in P2_DIFFERENT_KERNELS_OK P2_MODULE_OK P2_GUEST_SUCCESS; do
    grep -q "$marker" "$out/logs/qemu-console.log"
done
if grep -q 'P2_GUEST_FAIL\|Kernel panic' "$out/logs/qemu-console.log"; then
    exit 1
fi
