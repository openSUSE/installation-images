;
; A minimal boot loader that just prints a message.
;
; Author: snwint@suse.de

		cli
		xor cx,cx
		mov ss,cx
		mov sp,cx
		mov ds,cx
		mov es,cx
		sti
		cld

		; print some message, then stop
		call print
print:
		pop si
		add si,msg - print
print_10:
		lodsb
		or al,al
		jz $
		mov bx,7
		mov ah,14
		int 10h
		jmp print_10
msg:
