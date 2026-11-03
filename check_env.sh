#!/usr/bin/env bash
# Read-only checks. This script neither installs packages nor loads modules.
set -u

failed=0
ok() { printf '[OK] %s\n' "$*"; }
bad() { printf '[MISSING] %s\n' "$*"; failed=1; }

printf '=== P1 Linux environment check ===\n'
if [[ -r /etc/os-release ]]; then
    cat /etc/os-release
fi
release=$(uname -r)
project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
if [[ -z "${KDIR:-}" && -s "$project_dir/.kernel-build-path" ]]; then
    KDIR=$(cat "$project_dir/.kernel-build-path")
fi
kdir=${KDIR:-/lib/modules/$release/build}
printf '\nKernel: %s\nBuild directory: %s\n\n' "$release" "$kdir"

for tool in gcc make insmod rmmod lsmod modinfo dmesg script grep tail; do
    if command -v "$tool" >/dev/null 2>&1; then
        ok "$tool: $(command -v "$tool")"
    else
        bad "$tool"
    fi
done

if [[ -r "$kdir/Makefile" ]]; then
    ok 'Kernel Makefile exists (the build symlink is not dangling)'
else
    bad 'Matching kernel build files; a build symlink alone is insufficient'
fi
for file in include/generated/autoconf.h include/generated/utsrelease.h; do
    if [[ -r "$kdir/$file" ]]; then
        ok "$file"
    else
        bad "$file (kernel build tree is not ready)"
    fi
done

if [[ -r "$kdir/include/generated/utsrelease.h" ]]; then
    built_release=$(sed -n 's/^#define UTS_RELEASE "\(.*\)"/\1/p' \
        "$kdir/include/generated/utsrelease.h")
    if [[ "$built_release" == "$release" ]]; then
        ok 'Build-tree release matches the running kernel'
    else
        bad "Release mismatch: build=$built_release; running=$release"
    fi
fi

config=''
if [[ -r /proc/config.gz ]] && command -v gzip >/dev/null 2>&1; then
    config=$(gzip -dc /proc/config.gz)
elif [[ -r "/boot/config-$release" ]]; then
    config=$(cat "/boot/config-$release")
elif [[ -r "$kdir/.config" ]]; then
    config=$(cat "$kdir/.config")
fi
if [[ -n "$config" ]]; then
    printf '\nModule configuration:\n'
    printf '%s\n' "$config" | grep -E '^CONFIG_(MODULES|MODVERSIONS|MODULE_SIG_FORCE)=' || true
    if ! grep -qx 'CONFIG_MODULES=y' <<< "$config"; then
        bad 'CONFIG_MODULES=y is required'
    fi
    if grep -qx 'CONFIG_MODVERSIONS=y' <<< "$config" && [[ ! -s "$kdir/Module.symvers" ]]; then
        bad 'CONFIG_MODVERSIONS=y requires Module.symvers from a full matching build'
    fi
else
    printf '[INFO] Kernel config unavailable; CONFIG_MODULES was not verified.\n'
fi

printf '\n'
if (( failed )); then
    printf 'NOT READY. See README.md and WSL_SETUP.md.\n'
    exit 1
fi
printf 'BUILD CHECKS PASSED. Runtime loading still needs to be verified.\n'
