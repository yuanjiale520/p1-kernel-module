// SPDX-License-Identifier: GPL-2.0
#define pr_fmt(fmt) "p1_demo: " fmt

#include <linux/printk.h>

#include "p1_demo.h"

void p1_print_arithmetic(int a, int b)
{
	/* Widen operands before arithmetic so every pair of int inputs fits. */
	long long sum = (long long)a + b;
	long long product = (long long)a * b;

	pr_info("[arithmetic.c] %d + %d = %lld\n", a, b, sum);
	pr_info("[arithmetic.c] %d * %d = %lld\n", a, b, product);
}
