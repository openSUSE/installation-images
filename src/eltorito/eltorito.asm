;
; Allows no-emulation boot on BIOSes that support only 1.44MB floppy emulation.
;

boot_ofs	equ 7c00h
magic2_value	equ 64028295h
magic3_value	equ 56d9ea34h
magic4_value	equ 50a95748h
magic5_value	equ 383a1fc0h
magic4_ofs	equ 209
magic5_ofs	equ 631
el_torito_drive	equ 0efh
max_sectors	equ 4

%define		deb_debug 0


; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

%macro		write_str 1
		%ifnidn %1,si
		mov si,%1
		%endif
		call print_str
%endmacro

%macro		write_char 1
		%ifnidn %1,al
		mov al,%1
		%endif
		call print_char
%endmacro

%macro		write_hex1 1
		%ifnidn %1,al
		mov al,%1
		%endif
		call print_hex1
%endmacro

%macro		write_hex2 1
		%ifnidn %1,ax
		mov ax,%1
		%endif
		call print_hex2
%endmacro

%macro		write_hex4 1
		%ifnidn %1,eax
		mov eax,%1
		%endif
		call print_hex4
%endmacro

; seg, start, count
%macro		write_hex 3
		push word %1
		pop es
		%ifnidn %3,cx
		mov cx,%3
		%endif
		%ifnidn %2,si
		mov si,%2
		%endif
		call print_hex
%endmacro

%macro		get_key 0
		xor ax,ax
		int 16h
%endmacro


; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

%if deb_debug

%macro		deb_num4_s 3
		mov [cs:deb_tmp1],eax
		mov eax,%3
		mov word [cs:print_pos],(%1+80*%2)*2
		call print_hex4
		mov word [cs:print_pos],-1
		mov eax,[cs:deb_tmp1]
%endmacro

%macro		deb_num4 3
		mov eax,%3
		mov word [cs:print_pos],(%1+80*%2)*2
		call print_hex4
		mov word [cs:print_pos],-1
%endmacro

%macro		deb_num2_s 3
		mov [cs:deb_tmp1],ax
		mov ax,%3
		mov word [cs:print_pos],(%1+80*%2)*2
		call print_hex2
		mov word [cs:print_pos],-1
		mov ax,[cs:deb_tmp1]
%endmacro

%macro		deb_num2 3
		mov ax,%3
		mov word [cs:print_pos],(%1+80*%2)*2
		call print_hex2
		mov word [cs:print_pos],-1
%endmacro

%macro		deb_num1_s 3
		mov [cs:deb_tmp1],al
		mov al,%3
		mov word [cs:print_pos],(%1+80*%2)*2
		call print_hex1
		mov word [cs:print_pos],-1
		mov al,[cs:deb_tmp1]
%endmacro

%macro		deb_num1 3
		mov al,%3
		mov word [cs:print_pos],(%1+80*%2)*2
		call print_hex1
		mov word [cs:print_pos],-1
%endmacro

%macro		deb_str 3
		mov si,%3
		mov word [cs:print_pos],(%1+80*%2)*2
		call print_str_cs
		mov word [cs:print_pos],-1
%endmacro

%macro		deb_char 3
		mov al,%3
		mov word [cs:print_pos],(%1+80*%2)*2
		call print_char
		mov word [cs:print_pos],-1
%endmacro

; x, y, count, start
%macro		deb_hex 4
		mov cx,%3
		mov si,%4
		mov word [cs:print_pos],(%1+80*%2)*2
		call print_hex
		mov word [cs:print_pos],-1
%endmacro

%endif

; enable data break point
%macro		deb_set_bp_data 1
		mov eax,dr7
		and eax,~((3 << (2*%1)) + (0fh << (16 + 4*%1)))
		or eax,300h + (3 << (2*%1)) + (3 << (16 + 4*%1))
		mov dr7,eax
%endmacro

; enable code break point
%macro		deb_set_bp_code 1
		mov eax,dr7
		and eax,~((3 << (2*%1)) + (0fh << (16 + 4*%1)))
		or eax,300h + (3 << (2*%1)) + (0 << (16 + 4*%1))
		mov dr7,eax
%endmacro

; disable break point
%macro		deb_clr_bp 1
		mov eax,dr7
		and eax,~((3 << (2*%1)) + (0fh << (16 + 4*%1)))
		mov dr7,eax
%endmacro


; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
; part 1

		section .text

		org 0

                jmp main

		db 'SuSE'

		times 8 - ($-$$) db ' '

; boot info table; written by mkisofs
boot_info.pvd	dd 0
boot_info.start	dd 0
		times 14-2 dd 0

main:
                cli
		jmp boot_ofs >> 4 : main_10
main_10:
                mov ax,cs
		mov ds,ax
		mov es,ax
		xor ax,ax
                mov ss,ax
                mov sp,boot_ofs
		sti
		cld

		; load remaining blocks
		mov ax,200h + prog_blocks - 1
		mov cx,2
		xor dx,dx
		mov bx,200h
		int 13h

		cmp dword [magic2],magic2_value
		jnz main_80
		cmp dword [magic3],magic3_value
		jnz main_80

		push word 40h
		pop es
		mov ax,[es:13h]
		mov dx,ax
		shl ax,6
		mov [ebda],ax

		sub dx,int13_size	; in kb
		cmp dx,8000h >> 6	; too low?
		jb main_80

		; move us out of the way
		mov [es:13h],dx
		shl dx,6
		mov es,dx
		xor si,si
		xor di,di
		mov cx,int13_size << 10	; 1k
		rep movsb

		mov ds,dx

		push dx
		push word main_30
		retf
main_30:

		sub dx,2 << 6		; 2k temp buffer
		mov [buf.seg],dx 

		mov ah,2
		int 16h
		test al,3
		jz main_40
		mov byte [debug],1
main_40:
		call find_it
		jc main_80

		call install_int13

main_50:
		write_str msg_6

		get_key

		write_str msg_nl

		call boot_cdrom

		write_str msg_7

		jmp main_50

main_80:
		write_str msg_3
		jmp $


; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
; eax: number
print_hex4:
		push eax
		shr eax,16
		call print_hex2
		pop eax
		jmp print_hex2


; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
; ax: number
print_hex2:
		push ax
		mov al,ah
		call print_hex1
		pop ax
		jmp print_hex1


; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
; al: number
print_hex1:
		push ax
		shr al,4
		call print_hex1_30
		pop ax
		and al,0fh
print_hex1_30:
		cmp al,9
		jbe print_hex1_50
		add al,7+'a'-'A'
print_hex1_50:
		add al,'0'
		call print_char
		ret


; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
; write text
; ds:si - text
;

print_str_cs:
		cs
print_str:
		lodsb
		or al,al
		jz print_str_90
		call print_char
		jmp print_str
print_str_90:
		ret


; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
; dump hex
; es:si - start
; cx - count
;

print_hex:
		or cx,cx
		jz print_hex_90
		es lodsb
		push si
		push cx
		call print_hex1
		mov al,' '
		call print_char
		pop cx
		pop si
		loop print_hex
print_hex_90:
		ret


; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
print_pos	dw 0ffffh		; cursor pos; -1 -> use BIOS

; al - char
print_char:
		cmp word [cs:print_pos],0ffffh
		jz print_char_50
		cmp al,10
		jnz print_char_30
		add word [cs:print_pos],80*2
		jmp print_char_90
print_char_30:
		cmp al,13
		jnz print_char_40
		mov ax,[cs:print_pos]
		xor dx,dx
		mov bx,80*2
		div bx
		mul bx
		mov [cs:print_pos],ax
		jmp print_char_90
print_char_40:
		push ds
		push bx
		push 0b800h
		pop ds
		mov bx,[cs:print_pos]
		mov [bx],al
		add word [cs:print_pos],2
		pop bx
		pop ds
		jmp print_char_90
print_char_50:
		mov bx,7
		mov ah,14
		int 10h

print_char_90:
		ret


; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
msg_pnl		db '.'
msg_nl		db 13, 10, 0
msg_3		db 'Sorry, your BIOS can not boot from this CD.', 13, 10, 0

		times 0x1fe-$+$$ db 0

		dw 0aa55h


; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
; part 2

magic2		dd magic2_value


; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
; some vars

msg_4		db 'BIOS uses ', 0
msg_5		db ', type ', 0
msg_5a		db ', rw', 0
msg_5b		db ', ro', 0
msg_6		db 13, 10, 'Insert CD1 or DVD and press a key to continue.', 0
msg_7		db 'Sorry, could not boot from this CD.', 13, 10, 0

debug		db 1

emu.type	db 0			; type
emu.ro		db 0			; addr is readonly
emu.addr				; seg:ofs
emu.addr.ofs	dw 0
emu.addr.seg	dw 0
emu.addr.lin	dd 0			; dto, linear

emu.sector_ofs	dd 0
emu.sector	dd 0

emu.odata_0	dd 0
emu.odata_1	dd 0

ebda		dw 0			; seg

buf.seg		dw 0			; 2k buffer segment address

dap		db 10h, 0
dap.count	db 0
		db 0
dap.ofs		dw 0
dap.seg		dw 0
dap.start	dd 0, 0

; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
int13_old	dd 0			; seg:ofs
int13_status	db 0
int13_buf	dd 0
int13_start	dd 0
int13_cnt	db 0

int13_new:
		cmp ah,42h
		jnz int13_new_90
		cmp dl,el_torito_drive
		jnz int13_new_90

		push ds
		push es

		pushad

		push ds
		pop es
		push cs
		pop ds

		mov byte [int13_status],4
		or dword [es:si+12],0
		jnz int13_new_70

		push dword [es:si+8]
		pop dword [int13_start]

		mov al,[es:si+2]
		mov [int13_cnt],al

		push dword [es:si+4]
		pop dword [int13_buf]

		call cdrom_read

int13_new_70:

		popad

		mov ah,[int13_status]

		pop es
		pop ds

		and byte [esp+4],0feh
		or ah,ah
		jz int13_new_80
		inc byte [esp+4]
int13_new_80:
		iret


int13_new_90:
		jmp far [cs:int13_old]


; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
;
; Read from cd.
;
; [int13_*]	args
;

cdrom_read:
		mov byte [int13_status],0
cdrom_read_10:
		mov ah,2
		mov al,[int13_cnt]
		or al,al
		jz cdrom_read_90
		cmp al,max_sectors
		jbe cdrom_read_30
		mov al,max_sectors
cdrom_read_30:
		call cdrom_set_addr
		les bx,[int13_buf]
		movzx edx,al
		add [int13_start],edx
		sub [int13_cnt],al
		shl dx,11-4
		add [int13_buf+2],dx
		shl al,2
		mov cx,1
		xor dx,dx
		int 13h
		call cdrom_restore_addr
		mov [int13_status],ah
		or ah,ah
		jz cdrom_read_10
cdrom_read_90:
		ret


; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
;
; Set BIOS el torito image start.
;

cdrom_set_addr:
		push eax
		cmp byte [emu.ro],0
		jz cdrom_set_addr_70
		mov word [deb_bp.handler],emu_instr
		mov byte [emu.err],0
		push dword [boot_info.start]
		pop dword [emu.sector_ofs]
		push dword [int13_start]
		pop dword [emu.sector]
		cmp byte [emu.type],1
		jnz cdrom_set_addr_30
		shl dword [emu.sector_ofs],2
		shl dword [emu.sector],2
cdrom_set_addr_30:
		mov eax,[emu.addr.lin]
		mov dr0,eax
		deb_set_bp_data 0
		jmp cdrom_set_addr_90
cdrom_set_addr_70:
		les bx,[emu.addr]
		cmp byte [emu.type],1
		jnz cdrom_set_addr_80
		sub bx,4
cdrom_set_addr_80:
		push dword [es:bx]
		pop dword [emu.odata_0]
		push dword [int13_start]
		pop dword [es:bx]
		cmp byte [emu.type],1
		jnz cdrom_set_addr_90
		push dword [es:bx+4]
		pop dword [emu.odata_1]
		mov eax,[int13_start]
		shl eax,2
		mov [es:bx+4],eax
cdrom_set_addr_90:
		pop eax
		ret


; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
;
; Restore orginal BIOS el torito image start.
;

cdrom_restore_addr:
		push eax
		cmp byte [emu.ro],0
		jz cdrom_restore_addr_70
		deb_clr_bp 0
		mov word [deb_bp.handler],0
		jmp cdrom_restore_addr_90
cdrom_restore_addr_70:
		les bx,[emu.addr]
		cmp byte [emu.type],1
		jnz cdrom_restore_addr_80
		sub bx,4
cdrom_restore_addr_80:
		push dword [emu.odata_0]
		pop dword [es:bx]
		cmp byte [emu.type],1
		jnz cdrom_restore_addr_90
		push dword [emu.odata_1]
		pop dword [es:bx+4]
cdrom_restore_addr_90:
		pop eax
		ret


; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
;
; Install new int13 handler that takes care of el torito reads.
;

install_int13:
		push word 0
		pop fs
		push dword [fs:13h*4]
		pop dword [int13_old]
		push ds
		push int13_new
		pop dword [fs:13h*4]
		ret


; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
et_magic	db 0, 'CD001', 1, 'EL TORITO SPECIFICATION'
et_magic_len	equ $ - et_magic

msg_20		db 'got volume descr', 13, 10, 0
msg_21		db 'got boot catalog', 13, 10, 0
msg_22		db 'loading boot blocks', 13, 10, 0
msg_23		db 'Error ', 0
msg_24		db ' reading CD-ROM', 0
err_io_20	db ' (controller failure)', 0
err_io_31	db ' (no media)', 0
err_io_80	db ' (drive not ready)',0

boot_cdrom:
		; look for el torito info
		mov byte [dap.count],1
		push word [buf.seg]
		pop word [dap.seg]
		mov word [dap.ofs],0
		mov dword [dap.start],011h

		mov cx,5
boot_cdrom_10:
		mov ah,42h
		mov dl,el_torito_drive
		mov si,dap
		push cx
		int 13h
		pop cx
		or ah,ah
		jz boot_cdrom_20
		loop boot_cdrom_10

		push ax
		write_str msg_23
		pop ax
		push ax
		write_hex1 ah
		write_str msg_24
		pop ax
		mov si,err_io_20
		cmp ah,20h
		jz boot_cdrom_15
		mov si,err_io_31
		cmp ah,31h
		jz boot_cdrom_15
		mov si,err_io_80
		cmp ah,80h
		jnz boot_cdrom_17
boot_cdrom_15:
		call print_str
boot_cdrom_17:
		write_str msg_pnl

		jmp boot_cdrom_90
boot_cdrom_20:

		cmp byte [debug],0
		jz boot_cdrom_30
		write_str msg_20
boot_cdrom_30:

		mov si,et_magic
		mov cx,et_magic_len
		xor di,di
		mov es,[dap.seg]
		repz cmpsb
		jnz boot_cdrom_90

		; read boot catalog
		push dword [es:47h]
		pop dword [dap.start]

		mov ah,42h
		mov dl,el_torito_drive
		mov si,dap
		int 13h
		or ah,ah
		jnz boot_cdrom_90

		cmp byte [debug],0
		jz boot_cdrom_40
		write_str msg_21
boot_cdrom_40:

		; bootable + no emulation
		mov ax,[es:20h]
		and ah,0fh
		cmp ax,88h
		jnz boot_cdrom_90

		mov ax,[es:22h]
		or ax,ax
		jnz boot_cdrom_50
		mov ax,7c0h
boot_cdrom_50:
		mov [dap.seg],ax
		mov ax,[es:26h]
		or ax,ax
		jz boot_cdrom_90
		cmp ax,7fh
		ja boot_cdrom_90
		add al,3
		shr al,2
		mov [dap.count],al
		push dword [es:28h]
		pop dword [dap.start]

		cmp byte [debug],0
		jz boot_cdrom_60
		write_str msg_22
boot_cdrom_60:

		; load boot sectors
		mov ah,42h
		mov dl,el_torito_drive
		mov si,dap
		int 13h
		or ah,ah
		jnz boot_cdrom_90

		mov dl,el_torito_drive
		jmp far [cs:dap.ofs]


boot_cdrom_90:
		ret


; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
;
; Find image start address.
;
; Return:
;  CF		0/1: ok/not found
;
find_it:
		call deb_init

		call find_bios

		pushf

		cmp byte [debug],0
		jz find_it_80

		popf
		pushf
		jc find_it_22

		write_str msg_4
		write_hex2 [emu.addr.seg]
		write_char ':'
		write_hex2 [emu.addr.ofs]
		write_str msg_5
		write_hex1 [emu.type]
		mov si,msg_5a
		cmp byte [emu.ro],0
		jz find_it_20
		mov si,msg_5b
find_it_20:
		write_str si
		
		write_str msg_nl

find_it_22:

		cmp byte [emu.ro],0
		jz find_it_30
		write_hex2 [emu.cs]
		write_char ':'
		write_hex2 [emu.ip]
		write_char '['
		mov cx,[emu.ip.end]
		sub cx,[emu.ip]
		inc cx
		push cx
		write_hex1 cl
		write_char ']'
		write_char ' '
		pop cx
		cmp cx,18h
		jb find_it_25
		mov cx,18h
find_it_25:
		write_hex [emu.cs],[emu.ip],cx

		write_str msg_nl
find_it_30:

;		get_key

find_it_80:
		call deb_clear

		popf

		ret


; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
;
; Scan various memory areas for image start address.
;
; Return:
;  CF		0/1: ok/not found
;

		; ofs, seg, length
bios_areas
bios_areas.ebda	dw 0, 0, 0
		dw 0ach, 40h, 100h-0ach
		dw 0, 0e800h, 8000h
		dw 0, 0f000h, 8000h
		dw 0, 0f800h, 8000h
		dw 0, 0e000h, 8000h
		dw 0, 0d800h, 8000h
		dw 0, 0d000h, 8000h
bios_areas_end	equ $

find_bios:
		mov ax,[ebda]
		mov cx,0a000h
		cmp ax,cx
		jae find_bios_40
		cmp ax,9001h
		jae find_bios_20
		mov ax,9001h
find_bios_20:
		sub cx,ax
		shl cx,4
		mov [bios_areas.ebda+2],ax
		mov [bios_areas.ebda+4],cx
find_bios_40:

		mov bx,bios_areas
find_bios_60:
		cmp word [bx+2],0
		jz find_bios_70
		les si,[bx]
		mov cx,[bx+4]
		push bx
		call find_mem
		pop bx
		jnc find_bios_90
find_bios_70:
		add bx,6
		cmp bx,bios_areas_end
		jb find_bios_60

		stc

find_bios_90:
		ret


; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
;
; Scan memory area for image start address.
;
; es:si		start
; cx		length
;
; Return:
;  CF		0/1: ok/not found
;
find_mem:
		mov eax,[es:si]
		cmp eax,[boot_info.start]
		jnz find_mem_80

		mov byte [emu.type],0
		mov byte [emu.ro],0
		push es
		push si
		pop dword [emu.addr]
		push es
		push si
		push cx
		push eax
		call test_mem
		pop eax
		pop cx
		pop si
		pop es

		jnc find_mem_90

		mov edx,eax
		shl edx,2
		cmp [es:si+4],edx
		jnz find_mem_80

		mov byte [emu.type],1
		push es
		push si
		push cx
		push eax
		add dword [emu.addr],4
		call test_mem
		pop eax
		pop cx
		pop si
		pop es

		jnc find_mem_90

find_mem_80:
		inc si
		loop find_mem
		stc
find_mem_90:
		ret


; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
;
; Test single memory location.
;
; [emu.addr]	memory address
; [emu.type]	type
;
; Return:
;  CF		0/1: ok/failed
;

test_mem.msg_0	db 13, "Testing ", 0
test_mem.msg_1	db ' type ', 0
test_mem.msg_2	db ' - ', 0
test_mem.msg_3	db '1 failed: ', 0
test_mem.msg_4	db '3 failed: ', 0
test_mem.msg_5	db 'ok', 13, 10, 0
test_mem.msg_6	db 'read failed, emu ', 0

test_mem:
		cmp byte [debug],0
		jz test_mem_10

		write_str test_mem.msg_0
		write_hex2 [emu.addr+2]
		write_char ':'
		write_hex2 [emu.addr]
		write_str test_mem.msg_1
		write_hex1 [emu.type]
		write_str test_mem.msg_2

;		get_key

test_mem_10:
		call test1
		jnc test_mem_20

		cmp byte [debug],0
		jz test_mem_15

		push eax
		write_str test_mem.msg_3
		mov eax,[deb_bp.0+bp.cnt]
		cmp eax,0ffh
		jb test_mem_12
		mov eax,0ffh
test_mem_12:
		write_hex1 al
		write_str msg_nl
		pop eax

test_mem_15:
		or eax,eax
		jz test_mem_80
		call test2
		; >1 mem access is ok if address is writable
		jnc test_mem_30

		jmp test_mem_80
test_mem_20:
		call test2
		; for testing
		; stc
		jnc test_mem_30
		mov byte [emu.ro],1
		call test3
		jnc test_mem_30
		cmp byte [debug],0
		jz test_mem_80
		write_str test_mem.msg_4
		write_hex2 [ma_err]
		write_str msg_nl
		jmp test_mem_80
test_mem_30:
		call try_cdrom
		jnc test_mem_60

		cmp byte [debug],0
		jz test_mem_80
		write_str test_mem.msg_6
		write_hex1 [emu.err]
		write_str msg_nl

		jmp test_mem_80
test_mem_60:
		cmp byte [debug],0
		jz test_mem_70
		write_str test_mem.msg_5
test_mem_70:
		clc
		jmp test_mem_90
test_mem_80:
		stc
test_mem_90:
		ret


; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
;
; Read from CD.
;
; Return:
;  CF		0/1: worked/failed
;

try_magic	dd 0
try_ofs		dw 0

try_cdrom:
		mov dword [try_magic],magic4_value
		mov word [try_ofs],magic4_ofs
		call try_sector
		jc try_cdrom_90
		mov dword [try_magic],magic5_value
		mov word [try_ofs],magic5_ofs
		call try_sector
try_cdrom_90:
		ret


; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
;
; Read one sector from CD.
;
; word [try_ofs]	sector number
; dword [try_magic]	sector magic (first 4 bytes we expect)
;
; Return:
;  CF		0/1: worked/failed
;

try_sector:
		movzx eax, word [try_ofs]
		add eax,[boot_info.start]
		mov [int13_start],eax
		mov byte [int13_cnt],1
		mov word [int13_buf],0
		push word [buf.seg]
		pop word [int13_buf+2]
		call cdrom_read
		mov al,[int13_status]
		or al,al
		stc
		jnz try_sector_90
		mov eax,[try_magic]
		push word [buf.seg]
		pop es
		cmp dword [es:0],eax
		stc
		jnz try_sector_90
		clc
try_sector_90:
		ret



; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
;
; Reset debug registers.
;
deb_clear:
		; disable all breakpoints
		mov eax,dr7
		and eax,0dc00h
		mov dr7,eax

		; clear debug state
		mov eax,dr6
		and eax,~0e00fh
		mov dr6,eax

		xor eax,eax
		mov dr0,eax
		mov dr1,eax
		mov dr2,eax
		mov dr3,eax

		ret


; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
;
; Install new int 1 handler.
;
deb_init:
		call deb_clear

		push word 0
		pop es
		push cs
		push word int01_new
		pop dword [es:4]

		ret


; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
;
; Int 1 (debug) handler.
;
; Logs breakpoint events.
;

bp.addr		equ 0			; linear breakpoint address
bp.cnt		equ 4			; breakpoint matches
bp.ip		equ 8			; ip break instruction
bp.cs		equ 10			; dto, cs; must follow bp.ip
bp.csip.last	equ 12			; seg:ofs
bp.size		equ 16

deb_bp		times bp.size * 4 db 0	; list of breakpoints
deb_bp.size	equ $-deb_bp

deb_bp.0	equ deb_bp+bp.size*0
deb_bp.1	equ deb_bp+bp.size*1
deb_bp.2	equ deb_bp+bp.size*2
deb_bp.3	equ deb_bp+bp.size*3

deb_bp.handler	dw 0			; ofs

deb_bp.mask	db 0			; latest breakpoints
deb_rf		db 0			; temporary RF flag value

deb_stack_local	equ 10			; extra bytes
deb_stack_regs	equ 10			; bytes for saved registers

%if deb_debug
deb_tmp1	dd 0
%endif

int01_new:
		sub sp,deb_stack_local	; we need that later

		; adjust deb_stack_regs if you want so save more registers!
		push eax
		push ecx
		push si

		cld

		mov byte [cs:deb_rf],0

		mov eax,dr6
		and eax,0fh

		mov byte [cs:deb_bp.mask],al

		jz int01_new_90

		mov si,deb_bp
int01_new_20:
		test al,1
		jz int01_new_40
		inc dword [cs:si+bp.cnt]
		mov ecx,[esp+deb_stack_regs+deb_stack_local]
		mov [cs:si+bp.ip],ecx		; cs:ip

		; don't count identical places
		cmp dword [cs:si+bp.cnt],1
		jnz int01_new_30
		mov [cs:si+bp.csip.last],ecx
int01_new_30:
		cmp dword [cs:si+bp.cnt],2
		jnz int01_new_40
		cmp ecx,[cs:si+bp.csip.last]
		jnz int01_new_40
		dec dword [cs:si+bp.cnt]

int01_new_40:
		add si,bp.size
		shr al,1
		jnz int01_new_20

%if deb_debug
		deb_num4 50,0,dr0
		deb_num4 50,1,dr1
		deb_num4 50,2,dr2
		deb_num4 50,3,dr3
		deb_num4 50,4,dr6
		deb_num4 50,5,dr7

		deb_num4 50,  7, [cs:deb_bp.0+bp.cnt]
		deb_num2 59,  7, [cs:deb_bp.0+bp.cs]
		deb_char 63,  7, ':'
		deb_num2 64,  7, [cs:deb_bp.0+bp.ip]

		deb_num4 50,  8, [cs:deb_bp.1+bp.cnt]
		deb_num2 59,  8, [cs:deb_bp.1+bp.cs]
		deb_char 63,  8, ':'
		deb_num2 64,  8, [cs:deb_bp.1+bp.ip]

		deb_num4 50,  9, [cs:deb_bp.2+bp.cnt]
		deb_num2 59,  9, [cs:deb_bp.2+bp.cs]
		deb_char 63,  9, ':'
		deb_num2 64,  9, [cs:deb_bp.2+bp.ip]

		deb_num4 50, 10, [cs:deb_bp.3+bp.cnt]
		deb_num2 59, 10, [cs:deb_bp.3+bp.cs]
		deb_char 63, 10, ':'
		deb_num2 64, 10, [cs:deb_bp.3+bp.ip]

		deb_num2 50, 12, ss
		deb_char 54, 12, ':'
		mov ax,sp
		add ax,deb_stack_regs+deb_stack_local
		deb_num2 55, 12, ax

		pushfd
		pop eax
		deb_num4 60, 12, eax
%endif

		; set RF if at least one code breakpoint matched

		mov ecx,dr6
		mov eax,dr7

		shr eax,16
		and cl,0fh
int01_new_60:
		test cl,1
		jz int01_new_70
		test ax,3
		jnz int01_new_70
		mov byte [cs:deb_rf],1
int01_new_70:
		shr ax,4
		shr cl,1
		jnz int01_new_60

		; clear dr6 state
		mov eax,dr6
		and eax,~0e00fh
		mov dr6,eax

int01_new_90:

		; fix stack so we can use iretd instead of iret (necessary
		; for RF) + call deb_bp.handler

		mov eax,[esp+deb_stack_regs+deb_stack_local]
		movzx ecx,ax
		mov [esp+deb_stack_regs+4],ecx			; ip
		shr eax,16
		mov [esp+deb_stack_regs+8],eax			; cs

		pushfd
		pop eax
		mov ax,[esp+deb_stack_regs+deb_stack_local+4]	; flags
		cmp byte [cs:deb_rf],0
		jz int01_new_95
		or eax,10000h					; set RF
int01_new_95:
		mov [esp+deb_stack_regs+12],eax			; eflags
		mov [esp+deb_stack_regs],eax			; eflags

		; we're about done

		pop si
		pop ecx
		pop eax

		; run debug handler, if any

		cmp word [cs:deb_bp.handler],0
		jz int01_new_98
		call [cs:deb_bp.handler]
int01_new_98:

		; make vmware notice the RF change, too (vmware ignores RF
		; in iretd)
		popfd

		; we're done

		iretd


; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
;
; Find instruction that accesses a memory location.
;
; [ma_data]	data address
; [ma_func]	test function
;
; return:
;
; [emu.cs]			cs
; [emu.ip] - [emu.ip.end]	ptr to first and last instruction bytes
; [ma_err]			0: ok, != 0: error bitmap
;

err_m_no_data		equ 0	; no data access logged
err_m_multi_data	equ 1	; > 1 data access logged
err_m_no_code		equ 2	; no code bp logged
err_m_multi_code	equ 3	; > 1 code bp logged
err_m_code_no_data	equ 4	; inconsistency: 1 code bp, no data access

ma_data		dd 0		; seg:ofs
ma_data_lin	dd 0		; dto, linear
ma_func		dw 0		; ofs test function
ma_ip_min	dw 0		; min ofs
ma_err		dw 0		; error bitmask, see err_*

find_ma:
		xor eax,eax
		mov [deb_bp.0+bp.cnt],eax
		mov [ma_err],ax
		mov ax,word [ma_data]
		movzx edx,word [ma_data+2]
		shl edx,4
		add eax,edx
		mov [ma_data_lin],eax
		mov dr0,eax
		deb_set_bp_data 0

		push ds
		call word [ma_func]
		pop ds

		cmp dword [deb_bp.0+bp.cnt],1
		jz find_ma_20
		jb find_ma_15
		mov ax,1 << err_m_multi_data
		jmp find_ma_80
find_ma_15:
		mov ax,1 << err_m_no_data
		jmp find_ma_80
find_ma_20:

		mov ax,word [deb_bp.0+bp.ip]
		mov dx,word [deb_bp.0+bp.cs]

		dec ax

		mov [emu.ip.end],ax
		mov [emu.ip],ax
		mov [emu.cs],dx

		mov bx,ax
		sub bx,11h		; max instruction length we expect
		jnc find_ma_30
		xor bx,bx
find_ma_30:
		mov [ma_ip_min],bx

find_ma_32:
		movzx eax,word [emu.ip]
		movzx edx,word [emu.cs]
		shl edx,4
		add eax,edx
		mov dr2,eax
		deb_set_bp_code 2

		xor eax,eax
		mov [deb_bp.0+bp.cnt],eax
		mov [deb_bp.2+bp.cnt],eax

		push ds
		call word [ma_func]
		pop ds

		cmp dword [deb_bp.2+bp.cnt],1
		jz find_ma_40
		mov ax,1 << err_m_multi_code
		ja find_ma_80

		; code bp did not match
		mov ax,[emu.ip]
		cmp ax,[ma_ip_min]
		mov ax,1 << err_m_no_code
		jz find_ma_80

		dec word [emu.ip]
		jmp find_ma_32
find_ma_40:

		; one code bp match -> we have instruction

		; just checking...
		cmp dword [deb_bp.0+bp.cnt],1
		mov ax,1 << err_m_code_no_data
		jnz find_ma_80

		; we have it

%if deb_debug

		deb_num2 10, 2, [emu.cs]
		deb_char 14, 2, ':'
		deb_num2 15, 2, [emu.ip]

		deb_num2 10, 3, [emu.cs]
		deb_char 14, 3, ':'
		deb_num2 15, 3, [emu.ip.end]

%endif

		jmp find_ma_90

find_ma_80:
		or [ma_err],ax
find_ma_90:

		deb_clr_bp 0
		deb_clr_bp 2

		ret


; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
;
; Identify prefix.
;
; al		op code
; es = ds
;
; Return:
;  ah: 0 = no prefix, 1 = prefix, 2 = osp, 4 = asp
;  changes no other regs
;

pref_es		equ 26h
pref_cs		equ 2eh
pref_ss		equ 36h
pref_ds		equ 3eh
pref_fs		equ 64h
pref_gs		equ 65h

pref_all	db 0f0h, 0f2h, 0f3h, pref_es, pref_cs, pref_ss, pref_ds, pref_fs, pref_gs
pref.size	equ $-pref_all

pref_osp	equ 2
pref_asp	equ 4

is_prefix:
		push di
		push cx
		mov ah,pref_osp
		cmp al,66h
		jz is_prefix_90
		mov ah,pref_asp
		cmp al,67h
		jz is_prefix_90
		mov ah,0
		mov di,pref_all
		mov cx,pref.size
		repnz scasb
		jnz is_prefix_90
		mov ah,1
is_prefix_90:
		pop cx
		pop di
		ret


; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
;
; Save & restore registers.
;
; Note: can't change flags.
;

emu.ip.end	dw 0		; last byte of instr
emu.ip		dw 0		; ofs of instr
emu.cs		dw 0		; seg of instr; must follow emu.ip
emu.ds		dw 0
emu.es		dw 0
emu.fs		dw 0

; Note: order matters!
emu.eax		dd 0
emu.ecx		dd 0
emu.edx		dd 0
emu.ebx		dd 0
emu.esp		dd 0
emu.ebp		dd 0
emu.esi		dd 0
emu.edi		dd 0

emu.err		db 0
emu.prefix	db 0

reg_save:
		mov [cs:emu.ds],ds
		push cs
		pop ds
		mov [emu.es],es
		mov [emu.fs],fs
		mov [emu.eax],eax
		mov [emu.ebx],ebx
		mov [emu.ecx],ecx
		mov [emu.edx],edx
		mov [emu.esi],esi
		mov [emu.edi],edi
		mov [emu.ebp],ebp

		cld

		ret

reg_restore:
		mov eax,[emu.eax]
		mov ebx,[emu.ebx]
		mov ecx,[emu.ecx]
		mov edx,[emu.edx]
		mov esi,[emu.esi]
		mov edi,[emu.edi]
		mov ebp,[emu.ebp]
		mov fs,[emu.fs]
		mov es,[emu.es]
		mov ds,[emu.ds]
		ret


; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
;
; Emulate instruction (expects match in breakpoint 0).
;
emu_instr:
		call reg_save

		cmp byte [emu.err],0
		jnz emu_instr_90

		mov ax,[deb_bp.0+bp.ip]
		dec ax
		cmp ax,[emu.ip.end]
		jz emu_instr_20
		mov byte [emu.err],1
		jmp emu_instr_90
emu_instr_20:
		push ds
		pop es

		mov byte [emu.prefix],0

		lfs si,[emu.ip]
emu_instr_30:
		fs lodsb
		cmp si,[emu.ip.end]
		jbe emu_instr_32
		mov byte [emu.err],4
		jmp emu_instr_90
emu_instr_32:
		call is_prefix
		or [emu.prefix],ah
		or ah,ah
		jnz emu_instr_30

		; cl: emu.op
		; ch: emu.dst_reg

		mov cx,0ff00h

		cmp al,3		; add r,e
		jnz emu_instr_35
		mov cl,1
		jmp emu_instr_50
emu_instr_35:
		cmp al,0a1h		; mov ax,[m]
		jnz emu_instr_36
		mov cl,2
		mov ch,0
		jmp emu_instr_50
emu_instr_36:
		cmp al,08bh		; mov ax,e
		jnz emu_instr_37
		mov cl,2
		jmp emu_instr_50
emu_instr_37:
		; more instructions...

emu_instr_50:
		or cl,cl
		jnz emu_instr_55
		or byte [emu.err],2
		jmp emu_instr_90
emu_instr_55:
		cmp ch,0ffh
		jnz emu_instr_56
		mov ch,[fs:si]
		shr ch,3
		and ch,7
emu_instr_56:

		; cl: emu.op
		; ch: emu.dst_reg

		movzx si,ch
		shl si,2
		add si,emu.eax

		mov eax,[si]

		cmp cl,1
		jnz emu_instr_70
		sub eax,[emu.sector_ofs]
		add eax,[emu.sector]
		jmp emu_instr_80
emu_instr_70:
		cmp cl,2
		jnz emu_instr_78
		mov eax,[emu.sector]
		jmp emu_instr_80
emu_instr_78:
		; more opcodes

emu_instr_80:
		mov [si],ax
		test byte [emu.prefix],pref_osp
		jz emu_instr_85
		mov [si],eax
emu_instr_85:

emu_instr_90:
		call reg_restore
		ret


; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
;
; Read one sector from (emulated) floppy.
;
; Note: varies the track number to make it trickier for the BIOS to cache it.
;

read_floppy.cyl	db 0

read_floppy:
		mov es,[buf.seg]
		xor bx,bx
		mov ax,201h
		mov cl,1
		xor byte [read_floppy.cyl],20h
		mov ch,[read_floppy.cyl]
		xor dx,dx
		int 13h
		ret


; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
;
; Check whether emu.addr is used during disk i/o.
;
; dword [emu.addr]		data address (seg:ofs)
;
; Return:
;  eax				access count
;  dword [emu.addr.lin]		data address (linear)
;  CF				0/1: used/not used
;

test1:
		xor eax,eax
		mov [deb_bp.0+bp.cnt],eax
		mov ax,word [emu.addr.ofs]
		movzx edx,word [emu.addr.seg]
		shl edx,4
		add eax,edx
		mov [emu.addr.lin],eax

		mov dr0,eax
		deb_set_bp_data 0

		call read_floppy

		deb_clr_bp 0

		mov eax,[deb_bp.0+bp.cnt]
		cmp eax,1
		jbe test1_90
		stc
test1_90:
		ret



; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
;
; Check whether [emu.addr] is writable.
;
; Return:
;  CF			0/1: writable/readonly
;

test2:
		les bx,[emu.addr]
		mov eax,[es:bx]
		mov edx,eax
		not edx
		mov [es:bx],edx
		cmp edx,[es:bx]
		mov [es:bx],eax
		jz test2_90
		stc
test2_90:
		ret



; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
;
; Find memory access instruction.
;
; dword [emu.addr]	data address (seg:ofs)
;
; Return:
;  word [ma_err]	error code (0: ok)
;  CF			0/1: ok/not found (or not suitable)
;

test3:
		push dword [emu.addr]
		pop dword [ma_data]
		mov word [ma_func],read_floppy
		call find_ma
		cmp word [ma_err],0
		jz test3_90
		stc
test3_90:
		ret



; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
; at program end
magic3		dd magic3_value


; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
; end of code needed for int13 handling

; size in kb
int13_size	equ (($ - $$) + 0x3ff) >> 10

prog_blocks	equ (($ - $$) + 511) >> 9

