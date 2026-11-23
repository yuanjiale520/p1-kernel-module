#!/usr/bin/env bash
set -euo pipefail
out=${FP_RESULTS:?}
timeout 180 qemu-system-x86_64 -accel tcg -cpu qemu64 -smp 1 -m 256 \
    -kernel "$out/images/bzImage" -initrd "$out/images/initramfs.img" \
    -append 'console=ttyS0 rdinit=/init quiet loglevel=3 panic=-1' \
    -nographic -nic none -no-reboot > >(tee "$out/logs/qemu-console.log") 2>&1 &
pid=$!
trap 'kill "$pid" 2>/dev/null || true' EXIT
capture_marker() {
    local marker=$1 filename=$2 ready=0
    for n in $(seq 1 1600); do
        if grep -q "$marker" "$out/logs/qemu-console.log" 2>/dev/null; then ready=1; break; fi
        if ! kill -0 "$pid" 2>/dev/null; then break; fi
        sleep 0.1
    done
    (( ready )) || return 1
    sleep 1
    scrot -o "$out/screenshots/$filename.png"
}
capture_marker FP_LOAD_OK 03_kernel_and_proc_entries
capture_marker FP_READ_OK 04_read_and_jiffies
capture_marker FP_WRITE_OK 05_write_and_private_data
capture_marker FP_BOUNDARY_OK 06_boundary_and_EOF
capture_marker FP_LINK_OK 07_symlink_and_permissions
capture_marker FP_CLEANUP_OK 08_unload_and_reload
wait "$pid"
trap - EXIT
grep -q FP_GUEST_SUCCESS "$out/logs/qemu-console.log"
if grep -q 'FP_FAIL\|Kernel panic\|BUG: unable' "$out/logs/qemu-console.log"; then exit 1; fi
