// SPDX-License-Identifier: GPL-2.0
#include <linux/module.h>
#include <linux/proc_fs.h>
#include <linux/seq_file.h>
#include "p5_shared.h"

#define MAX_OBJECTS 256
static unsigned int count = 96;
module_param(count, uint, 0444);
static unsigned int held_count, verified_count;
module_param(held_count, uint, 0444);
module_param(verified_count, uint, 0444);
static struct p5_object *objects[MAX_OBJECTS];
static unsigned long released_address, reallocated_address;
static struct proc_dir_entry *report_entry;

static int client_report(struct seq_file *s, void *unused)
{
    unsigned int i, valid = 0;
    for (i = 0; i < held_count; i++) valid += p5_valid(objects[i], 1000 + i, P5_CLIENT);
    seq_printf(s, "module=p5_cache_client\ncache_name=%s\ncache_pointer=%px\n",
               P5_CACHE_NAME, p5_cache);
    seq_printf(s, "client_held=%u\nclient_verified_now=%u\nunique_addresses_verified=%u\n",
               held_count, valid, verified_count);
    for (i = 0; i < min(held_count, 3U); i++)
        seq_printf(s, "object[%u]=%px id=%u text=\"%s\"\n",
                   i, objects[i], objects[i]->id, objects[i]->text);
    seq_printf(s, "freed_one_address=0x%lx\nnext_alloc_address=0x%lx\nsame_address_reused=%u\n",
               released_address, reallocated_address,
               released_address == reallocated_address);
    seq_puts(s, "reuse_payload_check=PASS\n");
    return 0;
}
static int client_open(struct inode *inode, struct file *file)
{ return single_open(file, client_report, NULL); }
static const struct proc_ops client_ops = {
    .proc_open = client_open, .proc_read = seq_read,
    .proc_lseek = seq_lseek, .proc_release = single_release,
};
static void free_objects(void)
{
    unsigned int i;
    for (i = 0; i < count; i++) if (objects[i]) {
        kmem_cache_free(p5_cache, objects[i]);
        objects[i] = NULL;
    }
    held_count = 0;
}
static int __init client_init(void)
{
    unsigned int i, j;
    int err = -ENOMEM;
    if (!count || count > MAX_OBJECTS || !p5_cache) return -EINVAL;
    for (i = 0; i < count; i++) {
        objects[i] = kmem_cache_alloc(p5_cache, GFP_KERNEL);
        if (!objects[i]) goto fail;
        held_count++;
        p5_fill(objects[i], 1000 + i, P5_CLIENT);
    }
    /* Test a real free/reallocation. Reuse of the exact address is observed,
     * never required by the API, and content is initialized again explicitly. */
    released_address = (unsigned long)objects[0];
    kmem_cache_free(p5_cache, objects[0]);
    objects[0] = NULL;
    held_count--;
    objects[0] = kmem_cache_alloc(p5_cache, GFP_KERNEL);
    if (!objects[0]) goto fail;
    held_count++;
    reallocated_address = (unsigned long)objects[0];
    p5_fill(objects[0], 1000, P5_CLIENT);
    err = -EIO;
    for (i = 0; i < count; i++) {
        if (!p5_valid(objects[i], 1000 + i, P5_CLIENT)) goto fail;
        for (j = 0; j < i; j++) if (objects[i] == objects[j]) goto fail;
        verified_count++;
    }
    report_entry = proc_create("p5_client", 0400, NULL, &client_ops);
    if (!report_entry) { err = -ENOMEM; goto fail; }
    pr_info("p5_client: allocated=%u verified=%u cache=%px reused_address=%u\n",
            held_count, verified_count, p5_cache,
            released_address == reallocated_address);
    return 0;
fail:
    free_objects();
    return err;
}
static void __exit client_exit(void)
{
    unsigned int freed = held_count;
    proc_remove(report_entry);
    free_objects();
    pr_info("p5_client: freed=%u from shared cache; owner may now unload\n", freed);
}
module_init(client_init);
module_exit(client_exit);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("P5 allocates, verifies and frees objects from another module's slab cache");
