// SPDX-License-Identifier: GPL-2.0
#define pr_fmt(fmt) "p1_demo: " fmt

#include <linux/printk.h>

#include "p1_demo.h"

void p1_print_greeting(const char *name, int repeat)
{
	int i;

	for (i = 1; i <= repeat; i++)
		pr_info("[greeting.c] Hello, %s! (%d/%d)\n", name, i, repeat);
}
