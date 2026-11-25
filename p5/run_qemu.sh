#!/usr/bin/env bash
set -euo pipefail
out=${P5_RESULTS:?}
timeout 240 qemu-system-x86_64 -accel tcg -cpu qemu64 -smp 1 -m 512 \
    -kernel "$out/images/bzImage" -initrd "$out/images/initramfs.img" \
    -append 'console=ttyS0 rdinit=/init quiet loglevel=3 panic=-1 slab_nomerge' \
    -nographic -nic none -no-reboot > >(tee "$out/logs/qemu-console.log") 2>&1 &
pid=$!
trap 'kill "$pid" 2>/dev/null || true' EXIT
capture_marker() {
    local marker=$1 filename=$2 ready=0
    for n in $(seq 1 2000); do
        if grep -q "$marker" "$out/logs/qemu-console.log" 2>/dev/null; then ready=1; break; fi
        if grep -q 'P5_FAIL\|Kernel panic' "$out/logs/qemu-console.log" 2>/dev/null; then break; fi
        if ! kill -0 "$pid" 2>/dev/null; then break; fi
        sleep 0.1
    done
    (( ready )) || return 1
    sleep 1
    scrot -o "$out/screenshots/$filename.png"
}
capture_marker P5_BASELINE_OK 01_task_and_environment
capture_marker P5_CREATE_OK 02_create_custom_cache
capture_marker P5_CROSS_MODULE_OK 03_allocate_in_second_module
capture_marker P5_SLABINFO_OK 04_find_and_explain_slabinfo
capture_marker P5_DEPENDENCY_OK 05_dependency_prevents_early_unload
capture_marker P5_FREE_CLIENT_OK 06_free_client_keep_cache
capture_marker P5_DESTROY_OK 07_destroy_cache
capture_marker P5_REPEAT_OK 08_repeat_lifecycle
wait "$pid"
trap - EXIT
grep -q P5_GUEST_SUCCESS "$out/logs/qemu-console.log"
if grep -q 'P5_FAIL\|Kernel panic\|BUG: unable' "$out/logs/qemu-console.log"; then exit 1; fi
