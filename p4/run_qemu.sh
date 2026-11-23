#!/usr/bin/env bash
set -euo pipefail
out=${P4_RESULTS:?}
timeout 240 qemu-system-x86_64 -accel tcg,thread=multi -cpu qemu64 -smp 2 -m 512 \
    -kernel "$out/images/bzImage" -initrd "$out/images/initramfs.img" \
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
capture_marker P4_SETUP_OK 01_environment
capture_marker P4_pgd_OK 02_PGD
capture_marker P4_p4d_OK 03_P4D_folded
capture_marker P4_pud_OK 04_PUD
capture_marker P4_pmd_OK 05_PMD
capture_marker P4_pte_OK 06_PTE
capture_marker P4_DATA_OK 07_physical_address_and_data
capture_marker P4_DIRECT_OK 08_original_address_comparison
capture_marker P4_FILEVIEW_OK 09_supplied_fileview
capture_marker P4_CLEANUP_OK 10_unload
wait "$pid"
trap - EXIT
grep -q P4_GUEST_SUCCESS "$out/logs/qemu-console.log"
if grep -q 'P4_FAIL\|P4_VERIFY_FAIL\|Kernel panic\|BUG: unable' "$out/logs/qemu-console.log"; then exit 1; fi
