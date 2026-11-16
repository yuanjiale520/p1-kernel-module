// SPDX-License-Identifier: GPL-2.0
#define pr_fmt(fmt) "p3_mounts: " fmt
#include <linux/module.h>
#include <linux/fs.h>
#include <linux/slab.h>
#include <linux/err.h>

static unsigned int mount_count;
module_param(mount_count, uint, 0444);
MODULE_PARM_DESC(mount_count, "Number of mount entries listed at load time");

/* procfs supplies the loader's mount namespace through its locked seq iterator.
 * Exported VFS APIs avoid accessing private mount lists without their locks.
 * Keep distinct bind mounts; do not confuse mounts with registered fs types. */
static int __init p3_mounts_init(void)
{
    struct file *file;
    char *chunk, *line;
    loff_t pos = 0;
    ssize_t n;
    size_t i, used = 0;
    int error = 0;

    chunk = kmalloc(4096, GFP_KERNEL);
    line = kmalloc(4096, GFP_KERNEL);
    if (!chunk || !line) { error = -ENOMEM; goto free_buffers; }
    file = filp_open("/proc/self/mounts", O_RDONLY, 0);
    if (IS_ERR(file)) { error = PTR_ERR(file); goto free_buffers; }
    pr_info("SOURCE TARGET FSTYPE OPTIONS DUMP PASS (current mount namespace)\n");
    while ((n = kernel_read(file, chunk, 4096, &pos)) > 0) {
        for (i = 0; i < n; i++) {
            if (chunk[i] == '\n') {
                line[used] = '\0';
                pr_info("mount[%u] %s\n", ++mount_count, line);
                used = 0;
            } else {
                if (used == 4095) { error = -EOVERFLOW; goto close_file; }
                line[used++] = chunk[i];
            }
        }
    }
    if (n < 0) error = n;
    if (!error && used) {
        line[used] = '\0';
        pr_info("mount[%u] %s\n", ++mount_count, line);
    }
    if (!error) pr_info("TOTAL=%u (includes bind mounts)\n", mount_count);
close_file:
    filp_close(file, NULL);
free_buffers:
    kfree(line);
    kfree(chunk);
    return error;
}

static void __exit p3_mounts_exit(void) { pr_info("unloaded\n"); }
module_init(p3_mounts_init);
module_exit(p3_mounts_exit);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("P3 list every mount in the current mount namespace");
