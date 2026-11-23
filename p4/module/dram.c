// Adapted from the supplied Allan Cruse dram.c (2005/2008), Linux 6.6 API.
// Read-only physical RAM device, used only in the disposable QEMU guest.
#include <linux/module.h>
#include <linux/highmem.h>
#include <linux/uaccess.h>
#include <linux/fs.h>
#include <linux/capability.h>

static int major;
static unsigned long ram_bytes = 512UL << 20;
module_param(ram_bytes, ulong, 0400);
MODULE_PARM_DESC(ram_bytes, "QEMU guest RAM address limit in bytes");
static int dram_open(struct inode *inode, struct file *file)
{ return capable(CAP_SYS_RAWIO) ? 0 : -EPERM; }
static loff_t dram_seek(struct file *file, loff_t off, int whence)
{ return fixed_size_llseek(file, off, whence, ram_bytes); }
static ssize_t dram_read(struct file *file, char __user *buf, size_t count, loff_t *pos)
{
    struct page *page;
    void *mapped;
    unsigned long pfn, offset;
    size_t missed;
    if (*pos < 0) return -EINVAL;
    if (*pos >= ram_bytes || !count) return 0;
    pfn = (unsigned long)*pos >> PAGE_SHIFT;
    if (!pfn_valid(pfn)) return -ENXIO;
    offset = (unsigned long)*pos & (PAGE_SIZE - 1);
    count = min_t(size_t, count, PAGE_SIZE - offset);
    count = min_t(size_t, count, ram_bytes - *pos);
    page = pfn_to_page(pfn);
    mapped = kmap(page);
    missed = copy_to_user(buf, (char *)mapped + offset, count);
    kunmap(page);
    if (missed == count) return -EFAULT;
    *pos += count - missed;
    return count - missed;
}
static const struct file_operations ops = {
    .owner = THIS_MODULE, .open = dram_open, .llseek = dram_seek, .read = dram_read,
};
static int __init dram_init(void)
{
    major = register_chrdev(0, "dram", &ops);
    if (major < 0) return major;
    pr_info("dram: read-only physical RAM, dynamic major=%d, limit=0x%lx\n", major, ram_bytes);
    return 0;
}
static void __exit dram_exit(void)
{
    unregister_chrdev(major, "dram");
    pr_info("dram: read-only physical RAM device removed\n");
}
module_init(dram_init);
module_exit(dram_exit);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("P4 adaptation of the supplied read-only dram driver");
