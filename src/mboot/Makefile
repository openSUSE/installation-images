all: mboot

mboot:	mboot.asm
	nasm -f bin -o $@ -l $(@).lst $<

clean:
	@rm -f mboot *~ *.lst
