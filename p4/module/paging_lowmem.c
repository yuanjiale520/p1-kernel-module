// P4 extension of the supplied paging_lowmem.c. x86-64, four-level demo.
#include <linux/init.h>
#include <linux/module.h>
#include <linux/mm.h>
#include <linux/sched/mm.h>
#include <linux/proc_fs.h>
#include <linux/seq_file.h>
#include <linux/vmalloc.h>
#include <asm/pgtable.h>
#include <asm/io.h>

static unsigned long vaddr; /* Original allocation: never shadow this variable. */
static void *alias;
static struct mm_struct *held_mm;
static unsigned long cr0, cr3, root, target, expected, result;
static unsigned long slots[5], values[5];
static const char * const names[] = { "pgd", "p4d", "pud", "pmd", "pte" };
static const char message[] = "hello world from kernel: P4 physical memory verified";
#define DATA_OFFSET 0x123UL

static int walk(void)
{
    pgd_t *pgd = (pgd_t *)__va(root) + pgd_index(target);
    p4d_t *p4d;
    pud_t *pud;
    pmd_t *pmd;
    pte_t *pte;
    if (pgd_none(*pgd) || !pgd_present(*pgd)) return -EFAULT;
    p4d = p4d_offset(pgd, target);
    if (p4d_none(*p4d) || !p4d_present(*p4d)) return -EFAULT;
    pud = pud_offset(p4d, target);
    if (pud_none(*pud) || !pud_present(*pud) || pud_large(*pud)) return -EFAULT;
    pmd = pmd_offset(pud, target);
    if (pmd_none(*pmd) || !pmd_present(*pmd) || pmd_large(*pmd)) return -EFAULT;
    pte = pte_offset_kernel(pmd, target);
    if (!pte_present(*pte)) return -EFAULT;
    slots[0] = virt_to_phys(pgd); values[0] = pgd_val(*pgd);
    slots[1] = virt_to_phys(p4d); values[1] = p4d_val(*p4d);
    slots[2] = virt_to_phys(pud); values[2] = pud_val(*pud);
    slots[3] = virt_to_phys(pmd); values[3] = pmd_val(*pmd);
    slots[4] = virt_to_phys(pte); values[4] = pte_val(*pte);
    result = (pte_pfn(*pte) << PAGE_SHIFT) | (target & ~PAGE_MASK);
    return result == expected ? 0 : -EINVAL;
}

static int report(struct seq_file *s, void *unused)
{
    int i;
#define OUT(key, value) seq_printf(s, key "=0x%lx\n", (unsigned long)(value))
    OUT("cr0", cr0); OUT("cr3", cr3); OUT("root", root);
    OUT("direct_base", vaddr); OUT("direct_va", vaddr + DATA_OFFSET);
    OUT("alias_base", (unsigned long)alias); OUT("vaddr", target);
    OUT("offset", DATA_OFFSET); OUT("paddr", result); OUT("expected", expected);
    OUT("mask", PTE_PFN_MASK); OUT("page_size", PAGE_SIZE);
    OUT("pgdir_shift", PGDIR_SHIFT); OUT("p4d_shift", P4D_SHIFT);
    OUT("pud_shift", PUD_SHIFT); OUT("pmd_shift", PMD_SHIFT); OUT("page_shift", PAGE_SHIFT);
    OUT("pgd_entries", PTRS_PER_PGD); OUT("p4d_entries", PTRS_PER_P4D);
    OUT("pud_entries", PTRS_PER_PUD); OUT("pmd_entries", PTRS_PER_PMD);
    OUT("pte_entries", PTRS_PER_PTE);
    for (i = 0; i < 5; i++) {
        seq_printf(s, "%s_slot=0x%lx\n", names[i], slots[i]);
        seq_printf(s, "%s_raw=0x%lx\n", names[i], values[i]);
    }
    seq_printf(s, "message=%s\n", message);
    return 0;
}
static int report_open(struct inode *inode, struct file *file)
{ return single_open(file, report, NULL); }
static const struct proc_ops report_ops = {
    .proc_open = report_open, .proc_read = seq_read,
    .proc_lseek = seq_lseek, .proc_release = single_release,
};

static void release_memory(void)
{
    if (alias) { vunmap(alias); alias = NULL; }
    if (vaddr) { free_page(vaddr); vaddr = 0; }
    if (held_mm) { mmput(held_mm); held_mm = NULL; }
}
static int __init v2p_init(void)
{
    struct page *page;
    int err;
    if (PGDIR_SHIFT != 39 || PTRS_PER_P4D != 1) return -EOPNOTSUPP;
    vaddr = __get_free_page(GFP_KERNEL | __GFP_ZERO);
    if (!vaddr) return -ENOMEM;
    memcpy((char *)vaddr + DATA_OFFSET, message, sizeof(message));
    page = virt_to_page((void *)vaddr);
    alias = vmap(&page, 1, VM_MAP, PAGE_KERNEL);
    if (!alias) { err = -ENOMEM; goto fail; }
    target = (unsigned long)alias + DATA_OFFSET;
    if (strcmp((char *)target, message)) { err = -EFAULT; goto fail; }
    /* Hold the loader's mm, including its PGD, until all RAM reads finish. */
    held_mm = current->mm;
    if (!held_mm) { err = -EINVAL; goto fail; }
    mmget(held_mm);
    asm volatile("mov %%cr0,%0" : "=r"(cr0));
    asm volatile("mov %%cr3,%0" : "=r"(cr3));
    root = cr3 & PTE_PFN_MASK;
    if (root != virt_to_phys(held_mm->pgd)) { err = -EINVAL; goto fail; }
    expected = virt_to_phys((void *)(vaddr + DATA_OFFSET));
    err = walk();
    if (err) goto fail;
    if (!proc_create("p4_walk", 0400, NULL, &report_ops)) { err = -ENOMEM; goto fail; }
    pr_info("paging_lowmem: CR3=0x%lx v_addr=0x%lx p_addr=0x%lx VERIFIED\n",
            cr3, target, result);
    return 0;
fail:
    release_memory();
    return err;
}
static void __exit v2p_exit(void)
{
    remove_proc_entry("p4_walk", NULL);
    release_memory();
    pr_info("paging_lowmem: alias unmapped, original page freed, mm reference released\n");
}
module_init(v2p_init);
module_exit(v2p_exit);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("P4 original page plus 4K alias and complete page-table walk");
