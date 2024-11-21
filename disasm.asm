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
ResultSize = 50		;22 + max size of assembly instruction we possibly can get
			;50 = IP(5+2) + Opcode(12+1) + command(28) + NL(2)
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
	resultBuf	db "0000:  ", 12 dup(?) , " ", ResultSize-20 dup(?)

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

	;Read from input file
	mov bx, [inHandle]
	mov cx, CodeBufSize
	mov dx, offset codeBuf
	@@Loop:
		mov ah, 3Fh
		int 21h
		jc Exit		;if error
		or ax, ax
		jz Exit		;if 0 bytes has been read
		call Dissasemble
		;TODO:
		;1) move ax last bytes to the start
		;2) read 100-x to dx+ax
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
; less than 6 bytes left, because opcodes can be up to 6 bytes long.
; IN
; 	ax - number of bytes in machine code
; OUT
;	Writes disassembled commands to the output file
;	ax - number of bytes left unread
;-------------------------------------------------------------------
Dissasemble PROC
	push bx
	push cx
	push dx
	push si
	push di
	push bp

	mov bp, ax
	sub bp, 6	;save maximum index, when there still enough bytes left to read
	mov si, 0
	@@Loop:
		;Write current address (IP) to the result buffer
		mov ax, si
		add ax, 100h
		mov di, offset resultBuf
		;call WriteAsHex 
		;WriteAsHex: ax -> toHex -> ds:di
		;			 di += (2 or 4)

		;Disassemble command and write it to the result buffer
		call GetCommand
		xor bx, bx
		mov bl, ch		;bx - number of opcode bytes
		mov ch, 0		;cx - result line size

		;Write command's machine code to the result buffer
		xor ax, ax
		mov di, offset resultBuf + 7
		@@WriteOpcodeByte:
			or bx, bx
			jz @@WriteSpace			;if bx = 0
				mov al, [codeBuf + si]
				;call WriteAsHex
				dec bx
				inc si
				jmp @@Finally
		@@WriteSpace:
			mov word ptr [di], "  "
		@@Finally:
			add di, 2
			cmp di, offset resultBuf + 7 + 12
			jne @@WriteOpcodeByte	;if not end, i.e. 6 bytes haven't been written yet

		;Write result (assembly command) to the output file
		mov ah, 40h
		mov bx, [outHandle]
		mov dx, offset resultBuf
		int 21h

		cmp si, bp
		jle @@Loop		;if enough opcode bytes left in buffer to read
	mov ax, si

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
; 	si - where to start
; OUT
;	ch - number of bytes that make up the command
;	cl - size of the buffer to write
;	ds:[resultBuf+20; resultBuf+CH) - disassembled command 
;-------------------------------------------------------------------
GetCommand PROC
	push ax
	push di

	xor cx, cx
	mov ch, 1
	mov di, 20			;pass first 20 bytes (they are for printing IP and opcode)

	;For test:
	mov al, [codeBuf + si]
	mov [resultBuf + di], al
	inc di
	;TODO: disassemble command

	;Add new line
	mov word ptr [resultBuf + di], 0A0Dh
	add di, 2

	add cx, di			;move di to cl (it works, because di, in fact, uses only low byte)

	pop di
	pop ax
	ret 
GetCommand ENDP

;-------------------------------------------------------------------
; PrintMsg - print message (that ends by '$') to the screen
; IN
; 	ds:dx - message
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
; 	ds:dx - filename
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
; 	cx - number of bytes to read
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
; 	bx - file handle
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
