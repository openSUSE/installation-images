all: mboot boot

mboot: mboot.asm
	nasm -f bin -o $@ -l $(@).lst $<

boot: boot.asm
	nasm -f bin -o $@ -l $(@).lst $<

boottest: boottest.asm
	nasm -f bin -o $@ -l $(@).lst $<

clean:
	@rm -f boot mboot boottest *~ *.lst
