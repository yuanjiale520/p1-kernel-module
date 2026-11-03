// SPDX-License-Identifier: GPL-2.0
#define pr_fmt(fmt) "p1_demo: " fmt

#include <linux/errno.h>
#include <linux/init.h>
#include <linux/module.h>
#include <linux/moduleparam.h>
#include <linux/printk.h>
#include <linux/string.h>

#include "p1_demo.h"

static char *name = "BJTU";
module_param(name, charp, 0444);
MODULE_PARM_DESC(name, "Greeting name, 1 to 32 bytes");

static char *mode = "hello";
module_param(mode, charp, 0444);
MODULE_PARM_DESC(mode, "Output mode: hello, calc, or all");

static int repeat = 1;
module_param(repeat, int, 0444);
MODULE_PARM_DESC(repeat, "Greeting repetitions, 1 to 5");

static int a = 7;
module_param(a, int, 0444);
MODULE_PARM_DESC(a, "First signed integer for calculation");

static int b = 5;
module_param(b, int, 0444);
MODULE_PARM_DESC(b, "Second signed integer for calculation");

static int __init p1_demo_init(void)
{
	if (!name || !name[0] || strnlen(name, 33) > 32 ||
	    strchr(name, '\n') || strchr(name, '\r')) {
		pr_err("invalid name: use 1 to 32 bytes without line breaks\n");
		return -EINVAL;
	}

	if (repeat < 1 || repeat > 5) {
		pr_err("invalid repeat=%d: expected 1 to 5\n", repeat);
		return -EINVAL;
	}

	if (!mode || (strcmp(mode, "hello") && strcmp(mode, "calc") &&
		      strcmp(mode, "all"))) {
		pr_err("invalid mode: expected hello, calc, or all\n");
		return -EINVAL;
	}

	pr_info("loaded: mode=%s name=%s repeat=%d a=%d b=%d\n",
		mode, name, repeat, a, b);

	if (!strcmp(mode, "hello") || !strcmp(mode, "all"))
		p1_print_greeting(name, repeat);

	if (!strcmp(mode, "calc") || !strcmp(mode, "all"))
		p1_print_arithmetic(a, b);

	return 0;
}

static void __exit p1_demo_exit(void)
{
	pr_info("unloaded\n");
}

module_init(p1_demo_init);
module_exit(p1_demo_exit);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("P1 student");
MODULE_DESCRIPTION("P1: a parameterized Linux module built from three C files");
MODULE_VERSION("1.0");
