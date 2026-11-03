ifneq ($(KERNELRELEASE),)
obj-m := p1_demo.o
p1_demo-y := main.o greeting.o arithmetic.o
else
KDIR ?= $(shell cat .kernel-build-path 2>/dev/null)
ifeq ($(strip $(KDIR)),)
KDIR := /lib/modules/$(shell uname -r)/build
endif

.PHONY: all clean check demo
all:
	$(MAKE) -C "$(KDIR)" M="$(CURDIR)" LOCALVERSION= modules

clean:
	$(MAKE) -C "$(KDIR)" M="$(CURDIR)" LOCALVERSION= clean

check:
	bash ./check_env.sh

demo:
	bash ./demo.sh
endif
