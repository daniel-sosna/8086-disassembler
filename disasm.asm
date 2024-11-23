;*******************************************************;
; Author: Daniel Sosna                                  ;
; Info: The program disassembles machine code into      ;
;       instructions for the Intel 8086 microprocessor. ;
;*******************************************************;

LOCALS @@
.MODEL small
.STACK 100h

FileNameSize = 15	;Max size of the names of the entered files
CodeBufSize = 100h	;Size of the machine code block to read at a time (minimum 6)
CommandSize = 16	;Size of each line in commands file
ResultSize = 30		;max possible size of assembly instruction + 2 for newline
CommandsFile EQU "opc.map", "$"
GroupsFile EQU "opc-grp.map", "$"

JumpIfZero MACRO label
	LOCAL skip
	jnz skip
	jmp label
	skip:
ENDM
JumpIfCarry MACRO label
	LOCAL skip
	jnc skip
	jmp label
	skip:
ENDM

.DATA
	;Files
	inFileName	db FileNameSize dup(0), "$"
	inHandle	dw 0
	outFileName	db FileNameSize dup(0), "$"
	outHandle	dw 0
	commandsFileName	db CommandsFile
	commadsHandle		dw 0
	groupsFileName		db GroupsFile
	groupsHandle		dw 0
	;Messages
	newLine		db 13, 10, "$"
	msgFilesSuccess	db "Successfully opened files.", 13, 10, "$"
	msgErrOpenFile	db "[ERROR] Cannot open file ", "$"
	msgHelp		db "The program disassembles machine code into instructions for the Intel 8086 microprocessor.", 13, 10
				db "Usage: disasm.exe [options] input_file output_file", 13, 10
				db "  *Also, there have to be 'opc.map' and 'opc-grp.map' files with opcodes in the same directory.", 13, 10
				db "  options:", 13, 10
				db "    /?  Print this message.", 13, 10
				db 13, 10
				db "See README.md file for more information.", 13, 10
				db "$"
	;Other
	startIP		dw 100h
	hex			db "0123456789ABCDEF"
	resultBuf	db "0000:  ", 12 dup(?) , " "	;for command info (IP and opcode)
				db ResultSize dup(?)			;for the command itself

.DATA?	;Uninitialized data
	codeBuf		db CodeBufSize dup(?)
	commandBuf	db CommandSize dup(?)

.CODE
Start:
	mov ax, @data
	mov ds, ax

	;Get program parameters lenght and check is there are any
	mov ch, 0
	mov cl, [es:0080h]		;Program parameters lenght in bytes stored in 128-th (80h) byte of ES
	or cx, cx
	JumpIfZero PrintHelpAndCloseFiles

	;Try to find /? parameter
	push cx
	mov bx, 0081h			;Program parameters stored from 129-th (81h) byte of ES
	Search:
		cmp [es:bx], '?/'	;In the memory, low byte is stored before high ('?' is in BL, '/' - in BH)
		JumpIfZero PrintHelpAndCloseFiles
		inc bx
		loop Search

	;Get filenames from program parameters
	pop cx
	call GetFileNames

	;Open input file
	mov ax, 3D00h
	mov dx, offset inFileName
	int 21h
	JumpIfCarry ErrOpenInFile
	mov [inHandle], ax

	;Open commands file
	mov ax, 3D00h
	mov dx, offset commandsFileName
	int 21h
	JumpIfCarry ErrOpenCommsFile
	mov [commadsHandle], ax

	;Open groups file
	mov ax, 3D00h
	mov dx, offset groupsFileName
	int 21h
	JumpIfCarry ErrOpenGroupsFile
	mov [groupsHandle], ax

	;Create output file
	mov ah, 3Ch
	mov cx, 00000000b
	mov dx, offset outFileName
	int 21h
	JumpIfCarry ErrOpenOutFile
	mov [outHandle], ax

	;Print success message
	mov dx, offset msgFilesSuccess
	call PrintMsg

;-------------------------------------------------------------------

	mov bx, [inHandle]
	@@Loop:
		;Read machine code from the input file
		mov ah, 3Fh
		mov cx, CodeBufSize
		mov dx, offset codeBuf
		int 21h
		jc Exit		;if error
		or ax, ax
		jz Exit		;if 0 bytes were read

		call Dissasemble
		cmp ax, 0
		jl Exit		;if ax is negative (more bytes were read than were in the buffer)

		mov cx, 0FFFFh
		mov dx, 0
		sub dx, ax			;set offset -ax
		mov ax, 4201h
		int 21h				;move file pointer left by ax

		jmp @@Loop

;-------------------------------------------------------------------

Exit: ;Close all opened files and exit
	mov bx, [inHandle]
	call CloseFile
	mov bx, [outHandle]
	call CloseFile
	mov bx, [commadsHandle]
	call CloseFile
	mov bx, [groupsHandle]
	call CloseFile
	;Return control to computer
	mov	ax, 4C00h
	int	21h



; =========================
; ==== Errors handling ====
; =========================

	ErrOpenInFile:
		mov dx, offset inFileName
		call PrintErrOpenFile
		jmp Exit
	ErrOpenOutFile:
		mov dx, offset outFileName
		call PrintErrOpenFile
		jmp Exit
	ErrOpenCommsFile:
		mov dx, offset commandsFileName
		call PrintErrOpenFile
		jmp Exit
	ErrOpenGroupsFile:
		mov dx, offset groupsFileName
		call PrintErrOpenFile
		jmp Exit

	PrintHelpAndCloseFiles:
		mov dx, offset msgHelp
		call PrintMsg
		jmp Exit



; ========================
; ====== Procedures ======
; ========================

;-------------------------------------------------------------------
; Dissasemble - dissasemble given block of machine code. End when
; less than 6 bytes left, because opcodes can be up to 6 bytes long
; IN
;	ax - number of bytes in a given block of machine code
;	ds:startIP - current IP (instruction pointer)
; OUT
;	Writes disassembled commands to the output file
;	ax - number of bytes left unread
;	ds:startIP - updated IP
;-------------------------------------------------------------------
Dissasemble PROC
	push bx
	push cx
	push dx
	push si
	push di
	push bp

	;Set maximum offset when there are still enough bytes left to read
	mov bp, ax
	cmp bp, CodeBufSize
	jne @@Skip			;skip if buffer is not full (e.g. it is the last block of code)
		sub bp, 5		;reserve 6 bytes for last command
	@@Skip:

	push ax
	mov si, 0
	@@ReadCommand:
		;Write current address (IP) to the result buffer
		mov ax, [startIP]
		add ax, si
		mov cx, 4
		mov di, offset resultBuf
		call WriteAsHex

		;Disassemble command and write it to the result buffer
		call GetCommand
		mov bx, cx
		push di

		;Write command's machine code to the result buffer
		xor ax, ax
		mov cx, 2		;for WriteAsHex procedure
		mov di, offset resultBuf + 7
		@@WriteOpcodeByte:
			or bx, bx
			jz @@WriteSpace			;if bx = 0
				mov ah, [codeBuf + si]
				call WriteAsHex
				dec bx
				inc si
				jmp @@Finally
		@@WriteSpace:
			mov word ptr [di], "  "
			add di, 2
		@@Finally:
			cmp di, offset resultBuf + 7 + 12
			jne @@WriteOpcodeByte	;if not the end (i.e. all 6 bytes haven't been written yet)

		;Write result (assembly command) to the output file
		mov ah, 40h
		mov bx, [outHandle]
		pop cx
		mov dx, offset resultBuf
		int 21h

		cmp si, bp
		jl @@ReadCommand			;if there is still enough opcode bytes in buffer to read

	add [startIP], si	;update IP
	pop ax
	sub ax, si			;calculate the number of unread bytes

	pop bp
	pop di
	pop si
	pop dx
	pop cx
	pop bx
	ret
Dissasemble ENDP

;-------------------------------------------------------------------
; GetCommand - disassemble one command
; IN
;	ds:si - where to start
; OUT
;	cx - number of bytes that make up the command
;	di - size of the buffer to write
;	ds:[resultBuf+20; resultBuf+CH) - disassembled command
;-------------------------------------------------------------------
GetCommand PROC
	push ax
	push bx
	push dx
	push si

	mov cx, 1
	mov di, 20			;pass first 20 bytes (they are for printing IP and opcode)

	;Get command template from opcode map by first byte
	xor ax, ax
	mov al, [codeBuf + si]
	inc si
	mov bx, [commadsHandle]
	call GetOpcodeMapLine

	;Write command template for test:
	mov bx, 0
	@@loop:
		mov al, [commandBuf + bx]
		inc bx
		mov [resultBuf + di], al
		inc di
		cmp bx, 16
		jne @@loop

	;Add new line
	mov word ptr [resultBuf + di], 0A0Dh
	add di, 2

	pop si
	pop dx
	pop bx
	pop ax
	ret
GetCommand ENDP

;-------------------------------------------------------------------
; GetOpcodeMapLine - parse a line from a file with opcode map
; IN
;	al - line number
;	bx - file hadle
; OUT
;	ds:commandBuf - parsed command line
;-------------------------------------------------------------------
GetOpcodeMapLine PROC
	push ax
	push cx
	push dx

	mov ah, CommandSize
	mul ah				;ax = al * ah = line number * line size

	;Move file pointer to the beginning of ax line
	mov cx, 0
	mov dx, ax
	mov ax, 4200h
	int 21h

	;Read line and store to the command buffer
	mov ah, 3Fh
	mov cx, 16
	mov dx, offset commandBuf
	int 21h

	pop dx
	pop cx
	pop ax
	ret
GetOpcodeMapLine ENDP

;-------------------------------------------------------------------
; WriteAsHex - store an integer in buffer in hexadecimal format
; IN
;	ah / ax - integer to convert
;	cx (2 or 4) - size of the integer:
;			2(nibbles) for 1 byte integer / 4(nibbles) - for 2 bytes
;	ds:di - output buffer
; OUT
;	An ASCII string with a number converted to hex, stored in ds:di
;	di += (2 or 4)
;-------------------------------------------------------------------
WriteAsHex PROC
	push ax
	push bx
	push cx

	@@Repeat:
	rol ax, 4
	mov bx, ax
	and bx, 000Fh
	mov bl, [bx + hex]
	mov [di], bl
	inc di
	loop @@Repeat

	pop cx
	pop bx
	pop ax
	ret
WriteAsHex ENDP

;-------------------------------------------------------------------
; PrintMsg - print message (that ends by '$') to the screen
; IN
;	ds:dx - message
;-------------------------------------------------------------------
PrintMsg PROC
	push ax
	mov ah, 9
	int 21h
	pop ax
	ret
PrintMsg ENDP

;-------------------------------------------------------------------
; PrintErrOpenFile - print file opening error message to the screen
; IN
;	ds:dx - filename
;-------------------------------------------------------------------
PrintErrOpenFile PROC
	push ax
	push dx
	mov ah, 9
	mov dx, offset msgErrOpenFile
	int 21h
	pop dx
	int 21h
	mov dx, offset newLine
	int 21h
	mov dx, offset offset msgHelp
	int 21h
	pop ax
	ret
PrintErrOpenFile ENDP

;-------------------------------------------------------------------
; GetFileNames - Parse filenames from command line parameters (if
; within parameters is a set of spaces, compiler saves them as one)
; IN
;	cx - number of bytes to read
; OUT
;	ds:inFileName - first filename
;	ds:outFileName - second filename
;-------------------------------------------------------------------
GetFileNames PROC
	push ax
	push cx
	push si
	push di

	mov si, 0082h	;Note: [ES:0081h] is always a space
	dec cx

	;Parse input file name up to first space
	mov di, offset inFileName
	@@Loop1:
		mov al, [es:si]
		cmp al, " "
		je @@Second
		mov [di], al
		inc si
		inc di
		loop @@Loop1

	;Parse output file name up to first space or the end of parameters
@@Second:
	or cx, cx
	jz @@Finish		;if parameters ended
	inc si
	dec cx
	mov di, offset outFileName
	@@Loop2:
		mov al, [es:si]
		cmp al, " "
		je @@Finish
		mov [di], al
		inc si
		inc di
		loop @@Loop2

@@Finish:
	pop di
	pop si
	pop cx
	pop ax
	ret
GetFileNames ENDP

;-------------------------------------------------------------------
; CloseFile - close file if opened
; IN
;	bx - file handle
;-------------------------------------------------------------------
CloseFile Proc
	or bx, bx
	jz @@NoClose
	push ax
	mov ah, 3Eh
	int 21h
	pop ax
@@NoClose:
	ret
CloseFile ENDP

END Start
