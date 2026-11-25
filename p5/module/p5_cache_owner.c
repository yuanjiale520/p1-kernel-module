// SPDX-License-Identifier: GPL-2.0
#include <linux/module.h>
#include <linux/proc_fs.h>
#include <linux/seq_file.h>
#include "p5_shared.h"

struct kmem_cache *p5_cache;
EXPORT_SYMBOL_GPL(p5_cache);
#define LOCAL_OBJECTS 4
static struct p5_object *objects[LOCAL_OBJECTS];
static unsigned int held_count;
module_param(held_count, uint, 0444);
static struct proc_dir_entry *report_entry;

static void object_ctor(void *p)
{
    memset(p, 0, sizeof(struct p5_object));
    /* A non-NULL constructor also prevents this cache from being merged. */
}
static int owner_report(struct seq_file *s, void *unused)
{
    unsigned int i, valid = 0;
    for (i = 0; i < held_count; i++) valid += p5_valid(objects[i], i, P5_OWNER);
    seq_printf(s, "module=p5_cache_owner\ncache_name=%s\ncache_pointer=%px\n",
               P5_CACHE_NAME, p5_cache);
    seq_printf(s, "requested_object_bytes=%zu\nowner_held=%u\nowner_verified=%u\n",
               sizeof(struct p5_object), held_count, valid);
    if (held_count)
        seq_printf(s, "sample_address=%px id=%u text=\"%s\" magic=0x%016llx\n",
                   objects[0], objects[0]->id, objects[0]->text,
                   (unsigned long long)objects[0]->magic);
    return 0;
}
static int owner_open(struct inode *inode, struct file *file)
{ return single_open(file, owner_report, NULL); }
static const struct proc_ops owner_ops = {
    .proc_open = owner_open, .proc_read = seq_read,
    .proc_lseek = seq_lseek, .proc_release = single_release,
};
static void free_local(void)
{
    while (held_count) {
        held_count--;
        kmem_cache_free(p5_cache, objects[held_count]);
        objects[held_count] = NULL;
    }
}
static int __init owner_init(void)
{
    unsigned int i;
    BUILD_BUG_ON(sizeof(struct p5_object) != 128);
    p5_cache = kmem_cache_create(P5_CACHE_NAME, sizeof(struct p5_object),
                                 0, SLAB_HWCACHE_ALIGN, object_ctor);
    if (!p5_cache) return -ENOMEM;
    for (i = 0; i < LOCAL_OBJECTS; i++) {
        objects[i] = kmem_cache_alloc(p5_cache, GFP_KERNEL);
        if (!objects[i]) goto fail;
        held_count++;
        p5_fill(objects[i], i, P5_OWNER);
    }
    report_entry = proc_create("p5_owner", 0400, NULL, &owner_ops);
    if (!report_entry) goto fail;
    pr_info("p5_owner: created %s cache=%px object_bytes=%zu held=%u\n",
            P5_CACHE_NAME, p5_cache, sizeof(struct p5_object), held_count);
    return 0;
fail:
    free_local();
    kmem_cache_destroy(p5_cache);
    p5_cache = NULL;
    return -ENOMEM;
}
static void __exit owner_exit(void)
{
    unsigned int freed = held_count;
    proc_remove(report_entry);
    free_local();
    kmem_cache_destroy(p5_cache);
    p5_cache = NULL;
    pr_info("p5_owner: freed=%u, destroyed cache %s\n", freed, P5_CACHE_NAME);
}
module_init(owner_init);
module_exit(owner_exit);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("P5 creates a named slab cache and exports it to another module");
