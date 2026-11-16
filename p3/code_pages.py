import os
import re
from pathlib import Path

project = Path(__file__).resolve().parent
kernel = Path(os.environ['P3_KERNEL'])
out = Path(os.environ['P3_RESULTS']) / 'code-pages'
out.mkdir(parents=True, exist_ok=True)

def excerpt(path, pattern, before=0, after=5, base=None):
    lines = ((base or kernel) / path).read_text().splitlines()
    found = next((i for i, line in enumerate(lines) if re.search(pattern, line)), None)
    if found is None:
        raise RuntimeError(f'Missing source anchor: {path}: {pattern}')
    start, end = max(0, found-before), min(len(lines), found+after)
    text = f'\n{path}  [actual source lines {start+1}-{end}]\n'
    return text + '\n'.join(f'{i+1:5}  {lines[i].expandtabs(4)}' for i in range(start,end)) + '\n'

def save(name, explanation, snippets):
    text = 'Linux 6.6.30 source / SHA256 verified / guest kernel 6.6.30-p3\n'
    text += explanation.strip() + '\n' + ''.join(snippets)
    (out / name).write_text(text, encoding='utf-8')
    print(name, 'lines=', len(text.splitlines()))

save('01_open_kernel_code.txt', '''
Q1. How does userspace open() reach ext4's kernel open callback?
glibc open() on x86-64 uses openat; the kernel also supports legacy open.
openat -> do_sys_open -> do_sys_openat2 -> do_filp_open -> path_openat
       -> do_open -> vfs_open -> do_dentry_open -> ext4_file_open.
Path lookup finds the inode. inode->i_fop selects ext4_file_operations;
the .open callback is invoked. On success, the fd is installed and returned.
The normal existing regular-file path is illustrated here.
''', [
    excerpt('fs/open.c', r'^SYSCALL_DEFINE4\(openat,', after=5),
    excerpt('fs/open.c', r'\bdo_filp_open\(dfd,\s*tmp', before=1, after=5),
    excerpt('fs/open.c', r'f->f_op = fops_get', after=3),
    excerpt('fs/open.c', r'open = f->f_op->open', before=1, after=6),
    excerpt('fs/ext4/file.c', r'^\s*\.open\s*=\s*ext4_file_open', after=2),
    excerpt('fs/ext4/file.c', r'^static int ext4_file_open\(', after=5),
])

save('02_write_kernel_code.txt', '''
Q2. What happens when userspace write() targets a Btrfs file?
write -> ksys_write -> vfs_write -> new_sync_write -> call_write_iter
      -> btrfs_file_write_iter -> btrfs_do_write_iter.
Without O_DIRECT: btrfs_buffered_write copies data into cached pages,
reserves space, dirties pages and records delayed-allocation ranges.
Later writeback allocates extents/checksums and updates COW metadata.
Successful buffered write() alone does not promise durable storage;
our runtime test explicitly calls fsync(). O_DIRECT takes another branch.
''', [
    excerpt('fs/read_write.c', r'^SYSCALL_DEFINE3\(write,', after=5),
    excerpt('fs/read_write.c', r'else if \(file->f_op->write_iter\)', after=3),
    excerpt('fs/read_write.c', r'ret = call_write_iter\(filp', before=2, after=3),
    excerpt('fs/btrfs/file.c', r'^\s*\.write_iter\s*=\s*btrfs_file_write_iter', after=1),
    excerpt('fs/btrfs/file.c', r'^static ssize_t btrfs_file_write_iter\(', after=4),
    excerpt('fs/btrfs/file.c', r'num_written = btrfs_buffered_write', before=4, after=3),
])

save('03_mkdir_kernel_code.txt', '''
Q3. What happens on mkdir()?
mkdir/mkdirat -> do_mkdirat -> filename_create -> vfs_mkdir.
The VFS resolves and locks the parent, checks permissions/security,
then dispatches through the PARENT directory inode's i_op->mkdir.
ext4 calls ext4_mkdir; Btrfs calls btrfs_mkdir. Each creates an inode
and directory entry and updates its own journal/transaction metadata.
The runtime test below verifies both filesystem callbacks.
''', [
    excerpt('fs/namei.c', r'^SYSCALL_DEFINE2\(mkdir,', after=5),
    excerpt('fs/namei.c', r'error = vfs_mkdir\(', before=2, after=5),
    excerpt('fs/namei.c', r'error = dir->i_op->mkdir\(', before=3, after=6),
    excerpt('fs/ext4/namei.c', r'^\s*\.mkdir\s*=\s*ext4_mkdir', after=2),
    excerpt('fs/btrfs/inode.c', r'^\s*\.mkdir\s*=\s*btrfs_mkdir', after=2),
])

save('04_mount_module_code.txt', '''
Task 2. A real loadable kernel module lists all current mount entries.
It reads the LOADER'S mount namespace through procfs's seq iterator,
using exported filp_open/kernel_read APIs, then emits each row with printk.
EOF terminates the read; split lines are retained across read buffers.
Bind mounts are separate rows. Registered-but-unmounted filesystem types
are not mounts. The runtime count is checked against /proc/self/mounts.
The lab namespace is unchanged while the two counts are compared.
''', [
    excerpt('module/p3_mounts.c', r'file = filp_open', before=2, after=29, base=project),
])
