all: mboot

mboot: mboot.asm
	nasm -f bin -o $@ -l $(@).lst $<

boottest: boottest.asm
	nasm -f bin -o $@ -l $(@).lst $<

clean:
	@rm -f mboot boottest *~ *.lst
