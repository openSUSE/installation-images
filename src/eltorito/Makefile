all: boot

eltorito: eltorito.asm
	nasm -f bin -O10 -o $@ -l $(@).lst $<

boot: eltorito
	dd if=/dev/zero of=$@ bs=1k count=1440 2>/dev/null
	dd if=eltorito of=$@ conv=notrunc 2>/dev/null
	echo -en '\x48\x57\xa9\x50' | dd of=$@ conv=notrunc bs=2k seek=209 2>/dev/null
	echo -en '\xc0\x1f\x3a\x38' | dd of=$@ conv=notrunc bs=2k seek=631 2>/dev/null

clean:
	@rm -rf eltorito boot *~ *.lst *.iso
