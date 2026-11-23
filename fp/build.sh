#!/usr/bin/env bash
set -euo pipefail
[[ "${GITHUB_ACTIONS:-}" == true ]] || exit 2
project=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
build=${FP_BUILD_DIR:?}
out=${FP_RESULTS:?}
mkdir -p "$build" "$out"/{images,logs,screenshots,source,config,notes}
sudo apt-get update -qq
sudo apt-get install -y --no-install-recommends build-essential bc bison flex \
    cpio gzip xz-utils curl qemu-system-x86 xvfb xauth xterm scrot xfonts-base \
    poppler-utils python3 libmpc3 libgmp10
curl -fL --retry 3 https://cdn.kernel.org/pub/linux/kernel/v2.6/linux-2.6.29.tar.xz -o "$build/linux.tar.xz"
curl -fL --retry 3 https://mirrors.edge.kernel.org/pub/tools/crosstool/files/bin/x86_64/4.9.4/x86_64-gcc-4.9.4-nolibc-x86_64-linux.tar.xz -o "$build/toolchain.tar.xz"
printf 'ed990f585ce3f050e42d4cec053862419b8280efbd588f847c610108d318e06c  %s\n' "$build/linux.tar.xz" | sha256sum -c - | tee "$out/logs/kernel-checksum.txt"
printf 'a6f88855a0dce615262c6de528bf07de409012f1fdd4b24abe0ce13fd25ef781  %s\n' "$build/toolchain.tar.xz" | sha256sum -c - | tee "$out/logs/toolchain-checksum.txt"
tar -xJf "$build/linux.tar.xz" -C "$build"
tar -xJf "$build/toolchain.tar.xz" -C "$build"
curl -fL --retry 3 https://old-releases.ubuntu.com/ubuntu/pool/main/m/mpfr4/libmpfr4_3.1.6-1_amd64.deb -o "$build/libmpfr4.deb"
dpkg-deb -x "$build/libmpfr4.deb" "$build/compat"
export LD_LIBRARY_PATH="$build/compat/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
sha256sum "$build/libmpfr4.deb" > "$out/logs/compat-library-checksum.txt"
kernel="$build/linux-2.6.29"
python3 - "$kernel" "$out/logs/compatibility-patch.txt" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1]) / 'kernel/timeconst.pl'
s = p.read_text()
assert 'defined(@val)' in s
p.write_text(s.replace('defined(@val)', '@val'))
pathlib.Path(sys.argv[2]).write_text('Modern Perl compatibility: kernel/timeconst.pl\n- if (!defined(@val))\n+ if (!@val)\n')
PY
cc=$(find "$build" -type f -path '*/bin/x86_64-linux-gcc' -print -quit)
test -n "$cc"
cross=${cc%gcc}
"$cc" --version | tee "$out/logs/compiler.txt"
cat > "$build/hostcc" <<'EOF'
#!/bin/sh
exec gcc -fcommon -fno-pie -no-pie "$@"
EOF
chmod +x "$build/hostcc"
make -C "$kernel" ARCH=x86_64 CROSS_COMPILE="$cross" HOSTCC="$build/hostcc" \
    KCONFIG_ALLCONFIG="$project/kernel.config" allnoconfig 2>&1 | tee "$out/logs/configure.log"
grep -qx 'CONFIG_X86_64=y' "$kernel/.config"
grep -qx 'CONFIG_PROC_FS=y' "$kernel/.config"
grep -qx 'CONFIG_MODULES=y' "$kernel/.config"
make -C "$kernel" ARCH=x86_64 CROSS_COMPILE="$cross" HOSTCC="$build/hostcc" \
    LOCALVERSION= -j"$(nproc)" 2>&1 | tee "$out/logs/kernel-build.log"
make -C "$kernel" ARCH=x86_64 CROSS_COMPILE="$cross" HOSTCC="$build/hostcc" \
    M="$project/module" LOCALVERSION= modules 2>&1 | tee "$out/logs/module-build.log"
cp "$kernel/arch/x86/boot/bzImage" "$out/images/bzImage"
cp "$project/module/procfs_example.ko" "$out/images/"
curl -fL --retry 3 https://busybox.net/downloads/binaries/1.31.0-defconfig-multiarch-musl/busybox-x86_64 -o "$out/images/busybox"
chmod 755 "$out/images/busybox"
sha256sum "$out/images/busybox" > "$out/logs/busybox-checksum.txt"
root="$build/rootfs"
mkdir -p "$root"/{bin,sbin,dev,proc,sys,tmp,etc,lib/modules}
cp "$out/images/busybox" "$root/bin/busybox"
for applet in $("$out/images/busybox" --list); do
    [[ "$applet" == busybox ]] || ln -s busybox "$root/bin/$applet"
done
cp "$project/guest/init" "$root/init"
chmod 755 "$root/init"
cp "$out/images/procfs_example.ko" "$root/lib/modules/"
sudo mknod -m 600 "$root/dev/console" c 5 1
sudo mknod -m 666 "$root/dev/null" c 1 3
(
    cd "$root"
    find . -print0 | cpio --null -o -H newc --owner=0:0 --quiet | gzip -9 -n
) > "$out/images/initramfs.img"
cp "$kernel/.config" "$out/config/kernel.config"
cp -a "$project/." "$out/source/"
cp "$project/notes/"*.txt "$out/notes/"
make -s -C "$kernel" ARCH=x86_64 CROSS_COMPILE="$cross" LOCALVERSION= kernelrelease > "$out/logs/guest-version.txt"
{
    echo '=== FP / actual cloud build evidence ==='
    echo 'Selected assignment route: (1) find a compatible kernel and debug the tutorial.'
    echo "GitHub repository: ${GITHUB_REPOSITORY}"
    echo "Commit: ${GITHUB_SHA}"
    echo 'Kernel release:'
    cat "$out/logs/guest-version.txt"
    echo 'Compiler:'
    head -n 1 "$out/logs/compiler.txt"
    echo 'Downloaded official source checksums:'
    cat "$out/logs/kernel-checksum.txt" "$out/logs/toolchain-checksum.txt"
    cat "$out/logs/compatibility-patch.txt"
    echo 'Matching external module build (actual log):'
    tail -n 10 "$out/logs/module-build.log"
    echo
    echo 'The next screenshots are captured from a running isolated QEMU guest.'
} > "$out/notes/01_build.txt"
echo FP_BUILD_READY
