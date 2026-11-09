#!/usr/bin/env bash
set -euo pipefail
[[ "${GITHUB_ACTIONS:-}" == true ]] || {
    printf 'P2 builds run on GitHub Actions only.\n' >&2
    exit 2
}
project=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
build=${P2_BUILD_DIR:?}
out=${P2_RESULTS:?}
mkdir -p "$build" "$out"/{images,logs,screenshots,config,source/module,qa}
date -u +%FT%TZ > "$out/logs/build-started.txt"

sudo apt-get update -qq
sudo apt-get install -y --no-install-recommends \
    build-essential bc bison flex libelf-dev libssl-dev cpio gzip xz-utils \
    curl busybox-static qemu-system-x86 qemu-utils \
    tigervnc-standalone-server xfce4 xfce4-terminal dbus-x11 xauth xterm \
    x11-utils x11-xserver-utils wmctrl scrot xfonts-base neofetch \
    fonts-dejavu-core

version=6.6.30
archive="$build/linux-$version.tar.xz"
curl -fL --retry 3 --connect-timeout 30 \
    "https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-$version.tar.xz" -o "$archive"
printf 'b66a5b863b0f8669448b74ca83bd641a856f164b29956e539bbcb5fdeeab9cc6  %s\n' \
    "$archive" | sha256sum -c - | tee "$out/logs/source-checksum.txt"
tar -xJf "$archive" -C "$build"
kernel="$build/linux-$version"

make -C "$kernel" ARCH=x86 KCONFIG_ALLCONFIG="$project/kernel.config" allnoconfig \
    2>&1 | tee "$out/logs/kernel-configure.log"
make -C "$kernel" ARCH=x86 -j"$(nproc)" LOCALVERSION= \
    2>&1 | tee "$out/logs/kernel-build.log"
cp "$kernel/arch/x86/boot/bzImage" "$out/images/bzImage"
cp "$kernel/.config" "$out/config/kernel.config"
make -s -C "$kernel" LOCALVERSION= kernelrelease > "$out/logs/guest-kernel.txt"
uname -r > "$out/logs/host-kernel.txt"
test "$(cat "$out/logs/host-kernel.txt")" != "$(cat "$out/logs/guest-kernel.txt")"

make -C "$kernel" M="$project/module" LOCALVERSION= modules \
    2>&1 | tee "$out/logs/module-build.log"
cp "$project/module/p2_hello.ko" "$out/images/"
cp "$project/module/hello.c" "$project/module/Makefile" "$out/source/module/"

root="$build/rootfs"
mkdir -p "$root"/{bin,sbin,dev,proc,sys,tmp,etc/init.d,lib/modules}
cp "$(command -v busybox)" "$root/bin/busybox"
for applet in $(busybox --list); do
    [[ "$applet" == busybox ]] || ln -s busybox "$root/bin/$applet"
done
cp "$project/guest/init" "$root/init"
chmod 755 "$root/init"
ln -s ../init "$root/sbin/init"
cp "$out/logs/host-kernel.txt" "$root/etc/host-kernel"
printf 'NAME="P2 BusyBox Linux"\nPRETTY_NAME="P2 BusyBox initramfs"\nID=p2-busybox\n' \
    > "$root/etc/os-release"
cp "$out/images/p2_hello.ko" "$root/lib/modules/"
sudo mknod -m 600 "$root/dev/console" c 5 1
sudo mknod -m 666 "$root/dev/null" c 1 3
(
    cd "$root"
    find . -print0 | cpio --null --create --format=newc --owner=0:0 --quiet | gzip -9 -n
) > "$out/images/initramfs.img"
cp "$root/init" "$out/config/guest-init.sh"
cp "$project/kernel.config" "$out/config/requested-kernel.config"
cp "$project"/*.sh "$project/README.md" "$out/source/"

qemu=$(readlink -f "$(command -v qemu-system-x86_64)")
{
    printf '=== Long format file information ===\n'
    ls -l "$out/images/bzImage" "$out/images/initramfs.img" "$qemu"
    printf '\n=== QEMU version ===\n'
    qemu-system-x86_64 --version
    printf '\n=== BusyBox static binary ===\n'
    file "$root/bin/busybox"
} > "$out/logs/file-info.txt"
export P2_PROJECT="$project"
python3 - <<'PY'
import datetime, hashlib, json, os, pathlib, subprocess
out = pathlib.Path(os.environ['P2_RESULTS'])
def command(*args):
    return subprocess.check_output(args, text=True).strip()
meta = {
    'host_kernel': command('uname', '-r'),
    'guest_kernel': (out / 'logs/guest-kernel.txt').read_text().strip(),
    'host_os': next(x.split('=', 1)[1].strip('"') for x in pathlib.Path('/etc/os-release').read_text().splitlines() if x.startswith('PRETTY_NAME=')),
    'qemu_version': command('qemu-system-x86_64', '--version').splitlines()[0],
    'busybox_package': command('dpkg-query', '-W', '-f=${Version}', 'busybox-static'),
    'commit': os.environ['GITHUB_SHA'],
    'run_url': f"https://github.com/{os.environ['GITHUB_REPOSITORY']}/actions/runs/{os.environ['GITHUB_RUN_ID']}",
    'created_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'files': {},
}
for p in (out / 'images').iterdir():
    meta['files'][p.name] = {'bytes': p.stat().st_size, 'sha256': hashlib.sha256(p.read_bytes()).hexdigest()}
(out / 'metadata.json').write_text(json.dumps(meta, ensure_ascii=False, indent=2), encoding='utf-8')
PY
printf 'P2_BUILD_READY\n'
