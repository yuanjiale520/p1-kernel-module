/*
 * Debugged version of Erik Mouw's procfs-guide Chapter 5 example.
 * Original Copyright (C) 2001 Erik Mouw. GPL version 2 or later.
 * Reproduces the legacy API on Linux 2.6.29 (FP option 1).
 * Changes: bounded formatting, EOF/offset handling, write-length validation,
 * mutex protection, complete error cleanup; tutorial interfaces are retained.
 */
#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/init.h>
#include <linux/proc_fs.h>
#include <linux/jiffies.h>
#include <linux/mutex.h>
#include <asm/uaccess.h>

#define DIR_NAME "procfs_example"
#define FOOBAR_LEN 8
struct fb_data_t { const char *name; char value[FOOBAR_LEN + 1]; };
static struct fb_data_t foo = { "foo", "foo" }, bar = { "bar", "bar" };
static struct proc_dir_entry *dir, *foo_file, *bar_file, *ticks_file, *link_file;
static DEFINE_MUTEX(value_lock);

static int read_slice(char *page, char **start, off_t off, int count, int *eof, int len)
{
    if (off >= len) { *eof = 1; return 0; }
    *start = page + off;
    len -= off;
    if (len <= count) *eof = 1;
    return min(len, count);
}
static int read_ticks(char *page, char **start, off_t off, int count, int *eof, void *data)
{
    int len = scnprintf(page, PAGE_SIZE, "jiffies = %lu\n", jiffies);
    return read_slice(page, start, off, count, eof, len);
}
static int read_foobar(char *page, char **start, off_t off, int count, int *eof, void *data)
{
    struct fb_data_t *fb = data;
    int len;
    mutex_lock(&value_lock);
    len = scnprintf(page, PAGE_SIZE, "%s = '%s'\n", fb->name, fb->value);
    mutex_unlock(&value_lock);
    return read_slice(page, start, off, count, eof, len);
}
static int write_foobar(struct file *file, const char __user *buffer, unsigned long count, void *data)
{
    struct fb_data_t *fb = data;
    char tmp[FOOBAR_LEN + 1];
    if (count > FOOBAR_LEN) return -E2BIG;
    if (!count) return 0;
    if (copy_from_user(tmp, buffer, count)) return -EFAULT;
    tmp[count] = '\0';
    mutex_lock(&value_lock);
    memcpy(fb->value, tmp, count + 1);
    mutex_unlock(&value_lock);
    pr_info("procfs_example: shared write callback file=%s count=%lu\n", fb->name, count);
    return count;
}
static void remove_entries(void)
{
    if (link_file) { remove_proc_entry("jiffies_too", dir); link_file = NULL; }
    if (bar_file) { remove_proc_entry("bar", dir); bar_file = NULL; }
    if (foo_file) { remove_proc_entry("foo", dir); foo_file = NULL; }
    if (ticks_file) { remove_proc_entry("jiffies", dir); ticks_file = NULL; }
    if (dir) { remove_proc_entry(DIR_NAME, NULL); dir = NULL; }
}
static int __init example_init(void)
{
    dir = proc_mkdir(DIR_NAME, NULL);
    if (!dir) return -ENOMEM;
    dir->owner = THIS_MODULE;
    ticks_file = create_proc_read_entry("jiffies", 0444, dir, read_ticks, NULL);
    if (!ticks_file) goto fail;
    ticks_file->owner = THIS_MODULE;
    foo_file = create_proc_entry("foo", 0644, dir);
    if (!foo_file) goto fail;
    foo_file->data = &foo;
    foo_file->read_proc = read_foobar;
    foo_file->write_proc = write_foobar;
    foo_file->owner = THIS_MODULE;
    bar_file = create_proc_entry("bar", 0644, dir);
    if (!bar_file) goto fail;
    bar_file->data = &bar;
    bar_file->read_proc = read_foobar;
    bar_file->write_proc = write_foobar;
    bar_file->owner = THIS_MODULE;
    link_file = proc_symlink("jiffies_too", dir, "jiffies");
    if (!link_file) goto fail;
    link_file->owner = THIS_MODULE;
    pr_info("procfs_example: initialised legacy procfs example with 8-byte values\n");
    return 0;
fail:
    remove_entries();
    return -ENOMEM;
}
static void __exit example_exit(void)
{
    remove_entries();
    pr_info("procfs_example: removed all files, symlink and directory\n");
}
module_init(example_init);
module_exit(example_exit);
MODULE_AUTHOR("Erik Mouw; FP debug adaptation");
MODULE_DESCRIPTION("procfs-guide Chapter 5 compatibility experiment");
MODULE_LICENSE("GPL");
