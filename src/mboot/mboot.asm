;
; A minimal boot loader for the master boot record that works with our hard
; disk boot images.
;
; The code assumes that our system is in the first partition table and this
; partition is tagged as active. Note that no checks a done, we simply fail
; badly if these conditions are not met.
;
; Author: snwint@suse.de


mboot_ofs	equ 600h
part_ofs	equ mboot_ofs + 1beh
boot_ofs	equ 7c00h

		cli
		xor cx,cx
		mov si,boot_ofs
		mov ss,cx
		mov sp,cx
		mov ds,cx
		mov es,cx
		sti

		; move us out of the way
		cld
		mov di,mboot_ofs
		mov ch,1
		rep movsw
		jmp 0:(mboot_start + mboot_ofs)

mboot_start:
		; read the boot block
		mov si,part_ofs
		mov dx,[si]		; disk, head
		mov cx,[si + 2]		; sector / track
		mov bx,boot_ofs		; buffer
		mov ax,201h		; read 1 sector
		int 13h
		jc mboot_error

		; just make sure, we got a boot block
		cmp word [bx + 1feh],0aa55h
		jnz mboot_error

		; so we can later easily determine we booted via hd
		mov byte [bx + 3],19

		; start boot program
		jmp bx

		; print some error message, then stop
mboot_error:
		mov si,err_msg + mboot_ofs
mboot_error_10:
		lodsb
		or al,al
		jz $
		mov bx,7
		mov ah,14
		int 10h
		jmp mboot_error_10

err_msg:
		db 'Sorry, didn', 27h, 't find boot loader, stopped.', 10, 13, 0

