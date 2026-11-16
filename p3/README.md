# P3 cloud kernel filesystem experiment

The workflow compiles Linux 6.6.30-p3 with ext4, Btrfs, virtio block devices,
function tracing and module loading. It creates two real filesystem images
and boots the matching kernel inside QEMU on a GitHub-hosted Ubuntu VM.

Four screenshots show explanations and actual numbered excerpts from the
SHA256-verified source used for that kernel. Four more capture actual operations
and their ftrace records, plus a loaded module listing the current mount namespace.

The module uses the exported filp_open/kernel_read interfaces to consume procfs's
mount seq-file iterator. It does not use private unexported mount lists, and keeps
bind mounts as separate entries. Its count is checked against /proc/self/mounts.

Final screenshots are genuine scrot captures of an xterm framebuffer. No displayed
runtime results are generated from invented strings. Source explanation text is
authored commentary, clearly separated from actual numbered kernel code.

Reference kernel sources: https://www.kernel.org/pub/linux/kernel/v6.x/
Reference module APIs: https://docs.kernel.org/kbuild/modules.html
