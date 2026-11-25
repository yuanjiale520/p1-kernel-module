/* SPDX-License-Identifier: GPL-2.0 */
#ifndef P5_SHARED_H
#define P5_SHARED_H
#include <linux/types.h>
#include <linux/slab.h>
#include <linux/kernel.h>
#include <linux/string.h>

#define P5_CACHE_NAME "p5_lab_cache"
#define P5_MAGIC 0x5035534c41424f42ULL
#define P5_OWNER 1U
#define P5_CLIENT 2U
struct p5_object {
    u64 magic;
    u32 id;
    u32 owner;
    char text[48];
    u8 payload[64];
};
extern struct kmem_cache *p5_cache;
static inline void p5_fill(struct p5_object *obj, u32 id, u32 owner)
{
    unsigned int j;
    /* Initialize on EVERY allocation; ctor need not run again on reuse. */
    memset(obj, 0, sizeof(*obj));
    obj->magic = P5_MAGIC;
    obj->id = id;
    obj->owner = owner;
    scnprintf(obj->text, sizeof(obj->text), "%s object %u",
              owner == P5_OWNER ? "owner" : "client", id);
    for (j = 0; j < sizeof(obj->payload); j++) obj->payload[j] = (id + j) & 0xff;
}
static inline bool p5_valid(const struct p5_object *obj, u32 id, u32 owner)
{
    unsigned int j;
    if (!obj || obj->magic != P5_MAGIC || obj->id != id || obj->owner != owner) return false;
    for (j = 0; j < sizeof(obj->payload); j++)
        if (obj->payload[j] != ((id + j) & 0xff)) return false;
    return true;
}
#endif
