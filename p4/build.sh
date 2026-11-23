#!/usr/bin/env bash
set -euo pipefail
[[ "${GITHUB_ACTIONS:-}" == true ]] || exit 2
project=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
build=${P4_BUILD_DIR:?}
out=${P4_RESULTS:?}
mkdir -p "$build" "$out"/{images,logs,screenshots,source,module,config}
sudo apt-get update -qq
sudo apt-get install -y --no-install-recommends build-essential bc bison flex \
    libelf-dev libssl-dev cpio gzip xz-utils curl busybox-static \
    qemu-system-x86 xvfb xauth xterm scrot xfonts-base
archive="$build/linux-6.6.30.tar.xz"
curl -fL --retry 3 --connect-timeout 30 \
    https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.6.30.tar.xz -o "$archive"
printf 'b66a5b863b0f8669448b74ca83bd641a856f164b29956e539bbcb5fdeeab9cc6  %s\n' "$archive" \
    | sha256sum -c - | tee "$out/logs/source-checksum.txt"
tar -xJf "$archive" -C "$build"
kernel="$build/linux-6.6.30"
make -C "$kernel" ARCH=x86 KCONFIG_ALLCONFIG="$project/kernel.config" allnoconfig \
    2>&1 | tee "$out/logs/configure.log"
cp "$kernel/.config" "$out/config/kernel.config"
grep -qx 'CONFIG_X86_64=y' "$kernel/.config"
grep -qx '# CONFIG_X86_5LEVEL is not set' "$kernel/.config"
make -C "$kernel" ARCH=x86 LOCALVERSION= -j"$(nproc)" 2>&1 | tee "$out/logs/kernel-build.log"
make -C "$kernel" M="$project/module" LOCALVERSION= modules 2>&1 | tee "$out/logs/module-build.log"
gcc -static -O2 -Wall -Wextra "$project/probe.c" -o "$out/images/p4_probe" 2>&1 | tee "$out/logs/probe-build.log"
g++ -static -O2 -Wall -Wextra "$project/fileview.cpp" -o "$out/images/fileview" 2>&1 | tee "$out/logs/fileview-build.log"
cp "$kernel/arch/x86/boot/bzImage" "$out/images/bzImage"
cp "$project/module/"*.ko "$out/images/"
root="$build/rootfs"
mkdir -p "$root"/{bin,sbin,dev,proc,sys,tmp,etc,lib/modules}
cp "$(command -v busybox)" "$root/bin/busybox"
for applet in $(busybox --list); do
    [[ "$applet" == busybox ]] || ln -s busybox "$root/bin/$applet"
done
cp "$project/guest/init" "$root/init"
chmod 755 "$root/init"
cp "$out/images/p4_probe" "$out/images/fileview" "$root/bin/"
cp "$out/images/"*.ko "$root/lib/modules/"
sudo mknod -m 600 "$root/dev/console" c 5 1
sudo mknod -m 666 "$root/dev/null" c 1 3
(
    cd "$root"
    find . -print0 | cpio --null -o -H newc --owner=0:0 --quiet | gzip -9 -n
) > "$out/images/initramfs.img"
cp -a "$project/." "$out/source/"
cp "$project/module/"*.c "$project/module/Makefile" "$out/module/"
cp "$project/guest/init" "$out/config/guest-init.sh"
make -s -C "$kernel" LOCALVERSION= kernelrelease > "$out/logs/guest-version.txt"
uname -a > "$out/logs/host-version.txt"
printf 'P4_BUILD_READY\n'
