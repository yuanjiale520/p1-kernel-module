#!/usr/bin/env bash
set -euo pipefail
out=${P3_RESULTS:?}
timeout 240 qemu-system-x86_64 -accel tcg,thread=multi -cpu qemu64 -smp 2 -m 768 \
    -kernel "$out/images/bzImage" -initrd "$out/images/initramfs.img" \
    -drive "file=$out/images/ext4.img,format=raw,if=virtio" \
    -drive "file=$out/images/btrfs.img,format=raw,if=virtio" \
    -append 'console=ttyS0 rdinit=/init quiet loglevel=3 panic=-1' \
    -nographic -nic none -no-reboot > >(tee "$out/logs/qemu-console.log") 2>&1 &
pid=$!
trap 'kill "$pid" 2>/dev/null || true' EXIT
capture_marker() {
    local marker=$1 filename=$2 ready=0
    for n in $(seq 1 2000); do
        if grep -q "$marker" "$out/logs/qemu-console.log" 2>/dev/null; then ready=1; break; fi
        if ! kill -0 "$pid" 2>/dev/null; then break; fi
        sleep 0.1
    done
    (( ready )) || return 1
    sleep 1
    scrot -o "$out/screenshots/$filename.png"
}
capture_marker P3_OPEN_OK 05_open_ext4_trace
capture_marker P3_WRITE_OK 06_write_btrfs_trace
capture_marker P3_MKDIR_OK 07_mkdir_both_trace
capture_marker P3_MOUNTS_OK 08_mounted_filesystems
wait "$pid"
trap - EXIT
grep -q P3_GUEST_SUCCESS "$out/logs/qemu-console.log"
if grep -q 'P3_FAIL\|Kernel panic' "$out/logs/qemu-console.log"; then exit 1; fi
