always: fat32.bin

clean: 
	rm -f *.o *# *~ *.lst *.lbl *.map *.bin

.SUFFIXES:

CONFIGS	= f256jr.cfg

OBJS = \
	f256jr.o \
	fat32.o \
	sdcard.o \
	text_input.o \
	zeropage.o \
	match.o \
	mkfs.o \

fat32.bin: $(OBJS) $(CONFIGS) Makefile

%.o %.lst: %.s
	ca65 -t none --cpu 65C02 $< -l $(basename $@).lst

%.s: %.c
	cc65 -g --cpu 65C02 -t none -Os -I ../include -D_F256JR_ -T $< -o $@

%.bin:
	ld65 -C $(CONFIGS) -o $@ $(filter %.o, $^) $(LIBS) -m $(basename $@).map -Ln $(basename $@).lbl

