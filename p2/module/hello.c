// SPDX-License-Identifier: GPL-2.0
#define pr_fmt(fmt) "p2_hello: " fmt
#include <linux/init.h>
#include <linux/module.h>
#include <linux/moduleparam.h>
#include <linux/printk.h>
#include <linux/utsname.h>

static char *name = "Student";
module_param(name, charp, 0444);
MODULE_PARM_DESC(name, "Greeting name");

static int __init p2_hello_init(void)
{
	pr_info("loaded on guest kernel %s\n", utsname()->release);
	pr_info("Hello, %s! The P2 optional module is running.\n", name);
	return 0;
}

static void __exit p2_hello_exit(void)
{
	pr_info("unloaded\n");
}

module_init(p2_hello_init);
module_exit(p2_hello_exit);
MODULE_LICENSE("GPL");
MODULE_AUTHOR("P2 Student");
MODULE_DESCRIPTION("P2 optional module for the self-compiled QEMU guest kernel");
