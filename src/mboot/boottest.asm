boot_ofs	equ 7c00h

		cli
		xor cx,cx
		mov si,boot_ofs
		mov ss,cx
		mov sp,cx
		mov ds,cx
		mov es,cx
		sti

		cld
		jmp 0:(boot_start + boot_ofs)

boot_start:
		mov si,msg_1 + boot_ofs
		call print
		jmp $

print:
		lodsb
		or al,al
		jnz print_10
		ret
print_10:
		mov bx,7
		mov ah,14
		int 10h
		jmp print

msg_1:
		db 'Hi there!', 10, 13, 0

		times 7feh-($-$$) db 0
		dw 0aa55h
