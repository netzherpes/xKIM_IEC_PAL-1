
all:	xKIM.hex xKIM-ram.hex samplext.hex samplext-ram.hex

xKIM.hex: xKIM-0.bin xKIM-1.bin
	srec_cat xKIM-0.bin -binary -offset 0xE000 xKIM-1.bin -binary -offset 0xFFFA -o $@ -Intel -address_length=2

xKIM-0.bin xKIM-1.bin: xKIM.o xKIM.cfg
	ld65 -C xKIM.cfg -vm -m xKIM.map xKIM.o

xKIM.o: xKIM.s diskfunc.s pario.s parproto.inc 
	ca65 -g -l xKIM.lst xKIM.s

xKIM-ram.hex: xKIM-ram.bin
	srec_cat xKIM-ram.bin -binary -offset 0xB000 -o $@ -Intel -address_length=2

xKIM-ram.bin: xKIM-ram.o xKIM-ram.cfg
	ld65 -C xKIM-ram.cfg -vm -m xKIM-ram.map -o $@ xKIM-ram.o 

xKIM-ram.o: xKIM.s diskfunc.s pario.s parproto.inc 
	ca65 -D RAM_BASED=1 -g -l xKIM-ram.lst -o $@ xKIM.s

samplext.hex: samplext-0.bin samplext-1.bin
	srec_cat samplext-0.bin -binary -offset 0x0400 samplext-1.bin -binary -offset 0xDFFC -o $@ -Intel -address_length=2

samplext-0.bin samplext-1.bin: samplext.o samplext.cfg
	ld65 -C samplext.cfg -vm -m samplext.map samplext.o

samplext-ram.hex: samplext-ram-0.bin samplext-ram-1.bin
	srec_cat samplext-ram-0.bin -binary -offset 0x0400 samplext-ram-1.bin -binary -offset 0xAFFC -o $@ -Intel -address_length=2

samplext-ram-0.bin samplext-ram-1.bin: samplext.o samplext-ram.cfg
	ld65 -C samplext-ram.cfg -vm -m samplext-ram.map samplext.o

samplext.o: samplext.s xkim.inc
	ca65 -g -l samplext.lst -o $@ samplext.s

clean:
	$(RM) *.o *.lst *.map *.bin

distclean: clean
	$(RM) *.hex
