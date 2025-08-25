# This file is part of the TinyCore MicroKernel for the Foenix F256.
# Copyright 2022, 2023 Jessie Oberreuter <Gadget@HackwrenchLabs.com>.
# SPDX-License-Identifier: GPL-3.0-only

always: jr.bin

clean:
	rm -f *.lst *.bin *.map *~ labels.txt
	rm -f kernel/*~ f256/*~ hardware/*~ docs/*~
	(cd fat32; make clean)

####### Kernel ###########################################

KERNEL	= \
	kernel/api.asm \
	kernel/calls.asm \
	kernel/calls_ip.asm \
	kernel/calls_tcp.asm \
	kernel/clock.asm \
	kernel/debug.asm \
	kernel/delay.asm \
	kernel/device.asm \
	kernel/errors.asm \
	kernel/event.asm \
	kernel/fs.asm \
	kernel/kernel.asm \
	kernel/log.asm \
	kernel/net.asm \
	kernel/net_icmp.asm \
	kernel/net_ip.asm \
	kernel/net_tcp.asm \
	kernel/net_udp.asm \
	kernel/pages.asm \
	kernel/stream.asm \
	kernel/threads.asm \
	kernel/token.asm \
	kernel/user.asm \
	

###### Jr kernel ###################################

Jr	= \
	f256/audio.asm \
	f256/clock.asm \
	f256/console.asm \
	f256/dips.asm \
	f256/fat32.asm \
	f256/flash.asm \
	f256/iec.asm \
	f256/interrupt_def.asm \
	f256/irq.asm \
	f256/jiffy.asm \
	f256/jr.asm \
	f256/k2_lcd.asm \
	f256/kbd_cbm.asm \
	f256/kbd_f256k.asm \
	f256/kbd_f256k2.asm \
	f256/keyboard.asm \
	f256/serial.asm \
	f256/TinyVicky_Def.asm \
	hardware/16550.asm \
	hardware/hardware.asm \
	hardware/iec.asm \
	hardware/keys.asm \
	hardware/ps2_auto.asm \
	hardware/ps2_f256.asm \
	hardware/ps2_kbd2.asm \
	hardware/rtc_bq4802.asm \
	hardware/slip.asm \
	hardware/WM8776.asm \

DATE 	= $(shell date +\"%d/%m/%y\ %H\")
MAGIC	= $(shell date +\"%s\")
COPT 	= -C -Wall -Werror -Wno-shadow -x --verbose-list  --labels=labels.txt


jr.bin: Makefile $(Jr) $(KERNEL) fat32.bin
	(cd fat32; make)
	cp fat32/fat32.bin .
	64tass $(COPT) $(filter %.asm, $^) -b -L $(basename $@).lst -o $@ -D DATE_STR=\"$(DATE)\" -D MAGIC=$(MAGIC)
	dd if=$@ of=3b.bin ibs=8192 obs=8192 skip=0 count=1
	dd if=$@ of=3c.bin ibs=8192 obs=8192 skip=1 count=1
	dd if=$@ of=3d.bin ibs=8192 obs=8192 skip=2 count=1
	dd if=$@ of=3e.bin ibs=8192 obs=8192 skip=3 count=1
	dd if=$@ of=3f.bin ibs=8192 obs=8192 skip=5 count=1
	cat 3b.bin 3c.bin 3d.bin 3e.bin 3f.bin >$@
	cp 3b.bin 3c.bin 3d.bin 3e.bin 3f.bin bin


fat32.bin: fat32
	(cd fat32; make)
	cp fat32/$@ .


