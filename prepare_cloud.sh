#!/usr/bin/env bash
# This setup is for a GitHub-hosted Ubuntu VM, never the local WSL environment.
set -euo pipefail
[[ "${GITHUB_ACTIONS:-}" == true ]] || {
    printf 'Run this script in GitHub Actions only.\n' >&2
    exit 2
}
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
mkdir -p logs screenshots

sudo apt-get update -qq
sudo apt-get install -y build-essential kmod util-linux xvfb xauth xterm \
    scrot xfonts-base

release=$(uname -r)
kdir="/lib/modules/$release/build"
if [[ ! -r "$kdir/Makefile" ]]; then
    sudo apt-get install -y "linux-headers-$release"
fi
test -r "$kdir/Makefile"
test -s "$kdir/Module.symvers"

compiler_major=''
for config_file in "$kdir/.config" "/boot/config-$release"; do
    if [[ -r "$config_file" ]]; then
        compiler_major=$(sed -nE \
            '/^CONFIG_CC_VERSION_TEXT=/{s/.*\) ([0-9]+)\..*/\1/p;q;}' "$config_file")
        [[ -z "$compiler_major" ]] || break
    fi
done
if [[ -n "$compiler_major" ]]; then
    if ! command -v "gcc-$compiler_major" >/dev/null 2>&1; then
        sudo apt-get install -y "gcc-$compiler_major"
    fi
    p1_cc="gcc-$compiler_major"
else
    p1_cc=gcc
fi
printf 'P1_CC=%s\n' "$p1_cc" >> "$GITHUB_ENV"
printf '%s\n' "$kdir" > .kernel-build-path
{
    uname -a
    cat /etc/os-release
    "$p1_cc" --version
    printf 'Repository: %s\nCommit: %s\nRun: %s\n' \
        "$GITHUB_REPOSITORY" "$GITHUB_SHA" "$GITHUB_RUN_ID"
} > logs/cloud-environment.txt
bash ./check_env.sh | tee logs/cloud-preflight.txt
