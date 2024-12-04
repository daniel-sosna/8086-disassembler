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
CommandSize = 16	;Size of each line in opcodes file
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
WriteByte MACRO byte
	mov [resultBuf + di], byte
	inc di
ENDM
WriteWord MACRO word
	mov word ptr [resultBuf + di], word
	inc di
	inc di
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
	;Parts of a command
	_Unknown	db "UNKNOWN"
	_bytePtr	db "byte ptr "
	_wordPtr	db "word ptr "
	_registers	db "al", "cl", "dl", "bl"		;mod = 11b, b
				db "ah", "ch", "dh", "bh"
				db "ax", "cx", "dx", "bx"		;mod = 11b, w
				db "sp", "bp", "si", "di"
	_addrRegs1	db "bx+si", "bx+di", "bp+si", "bp+di"	;mod != 11b, r/m < 100b
	_addrRegs2	db "si", "di", "bp", "bx"				;mod != 11b, r/m >= 100b
	_segments	db "es", "cs", "ss", "ds"		;sreg
	;_
	;Other
	hex			db "0123456789ABCDEF"
	startIP		dw 100h
	modByteFlag	dw 1			; 0 - ModR/M byte has been used, 1 - hasn't
	resultBuf	db "0000:  ", 12 dup(?) , " "	;for command info (IP and opcode)
				db ResultSize dup(?)			;for the command itself

.DATA?	;Uninitialized data
	codeBuf		db CodeBufSize dup(?)
	commandBuf	db CommandSize dup(?)
	groupsBuf	db CommandSize dup(?)

.CODE
Start:
	mov ax, @data
	mov ds, ax

	;Get program parameters length and check is there are any
	mov ch, 0
	mov cl, [es:0080h]		;Program parameters length in bytes stored in 128-th (80h) byte of ES
	or cx, cx
	JumpIfZero PrintHelpAndCloseFiles

	;Try to find /? parameter
	push cx
	mov bx, 0081h			;Program parameters stored from 129-th (81h) byte of ES
	Search:
		cmp word ptr [es:bx], '?/'	;In the memory, low byte is stored before high ('?' is in BL, '/' - in BH)
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
		mov di, 0
		call WriteAsHex

		;Disassemble command and write it to the result buffer
		call GetCommand
		push di

		;Write command's machine code to the result buffer
		mov cx, 2		;for WriteAsHex procedure
		mov di, 7
		@@WriteOpcodeByte:
			or bx, bx
			jz @@WriteSpace			;if bx = 0
				mov ah, [codeBuf + si]
				call WriteAsHex
				dec bx
				inc si
				jmp @@Finally
		@@WriteSpace:
			WriteWord "  "
		@@Finally:
			cmp di, 7 + 12
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
;	bx - number of bytes that make up the command
;	di - size of the buffer to write
;	ds:[resultBuf+20; resultBuf+CH) - disassembled command
;-------------------------------------------------------------------
GetCommand PROC
	push ax
	push cx
	push dx
	push bp

	push si
	mov di, 20			;pass first 20 bytes (they are for printing IP and opcode)

	;Get command template from opcode map by first byte
	xor ah, ah
	mov al, [codeBuf + si]
	inc si
	mov bx, [commadsHandle]
	call GetOpcodeLine

; Check for exception cases:

	;Check if command is in group
	cmp word ptr[commandBuf], 'RG'
	jne @@SkipGroups
		mov al, [commandBuf + 2]
		sub al, 48		;convert ASCII symbol to a number
		mov bl, [codeBuf + si]
		call GetOpcodeGroupsLine
	@@SkipGroups:

	;Check if command is unknown
	cmp word ptr[commandBuf], '--'
	jne @@CommandExists
		mov al, 7
		mov bx, offset _Unknown
		call WriteToBuf
		jmp @@End
	@@CommandExists:

; Decryption of command template:

	;Write name of a command
	mov al, 8
	mov bx, offset commandBuf
	call WriteToBuf

	;Write operands
	mov dl, [codeBuf + si]
	mov word ptr [modByteFlag], 1
	mov bx, 8
	cmp [commandBuf + bx], 0
	je @@End			;if there is first operand
		call DecryptOperands
		mov bx, 12
		cmp [commandBuf + bx], 0
		je @@End		;if there is second operand
			;Add comma between operands
			WriteWord " ,"
			call DecryptOperands

@@End:
	mov bx, si
	pop si
	sub bx, si
	;Add new line
	WriteWord 0A0Dh

	pop bp
	pop dx
	pop cx
	pop ax
	ret
GetCommand ENDP

;-------------------------------------------------------------------
; DecryptOperands - decrypts an operand using its template from
; commandBuf and subsequent bytes if needed 
; IN
;	dl - possible ModR/M byte
;	ds:[codeBuf+si] - machine code buffer
;	ds:[commandBuf+bx] - template of operands
;	ds:[resultBuf+di] - output buffer
; OUT
;	Decrypted operands stored in ds:[resultBuf+di]
;	si += number of bytes used as operand
;	di += size of output
;-------------------------------------------------------------------
DecryptOperands PROC
	push ax
	push cx
	push dx

; (_) Predefined general or segment register
	cmp [commandBuf + bx], "_"
	jne @@rs_Skip

		mov ax, word ptr [commandBuf + bx + 1]
		WriteWord ax

		jmp @@End
	@@rs_Skip:


; (E) A ModR/M byte follows the opcode and specifies the operand
	; The operand is either a general-purpose register or a memory address
	cmp [commandBuf + bx], "E"
	je @@E
		jmp @@E_Skip
	@@E:

		add si, [modByteFlag]		;increase si, if ModR/M byte hasn't been used yet
		mov [modByteFlag], 0

		;Get Mod and R/M fields from ModR/M byte (dl)
		mov dh, dl
		and dh, 11000000b	;keep only mod field (1 to 2 bites)
		shr dh, 6			;shift mod bites to the right
		and dl, 00000111b	;keep only r/m field (6 to 8 bites)

	cmp dh, 11b
	jne @@E_Memory
	;Operand is a register stored in R/M field from ModR/M byte (dl)
		xor dh, dh
		add dl, dl			;multiply by 2 (because registers are two symbols, e.g. "AX")
		cmp [commandBuf + bx + 1], "w"
		jne @@E_NotWord
			add dl, 16
		@@E_NotWord:
		mov bx, dx
		mov ax, word ptr [_registers + bx]
		WriteWord ax

		jmp @@End
	@@E_Memory:
	;Operand is a memory addres
		;Write "byte/word ptr" if needed
		cmp [commandBuf + bx + 1], "w"
		jne @@E_SkipWordPtr
			mov al, 9
			mov bx, offset _wordPtr
			call WriteToBuf
			jmp @@E_SkipBytePtr
		@@E_SkipWordPtr:
		cmp [commandBuf + bx + 2], "t"
		jne @@E_SkipBytePtr
			mov al, 9
			mov bx, offset _bytePtr
			call WriteToBuf
		@@E_SkipBytePtr:

		WriteByte "["

		;Check if it is a direct address
		cmp dl, 110b
		jne @@E_NotDirectAddress
			cmp dh, 00b
			je @@E_NoPlus
		@@E_NotDirectAddress:

		;Write corresponding register(s) into square brackets
		cmp dl, 100b
		jge @@E_AddrReg2
			mov al, dl
			mov ah, 5
			mul ah			;multiply by 5 (because there are two registers and a plus, e.g. "BX+SI")
			mov bx, ax
			mov al, 5
			add bx, offset _addrRegs1
			call WriteToBuf
			jmp @@E_AddrReg1
		@@E_AddrReg2:
			xor bh, bh
			mov bl, dl
			sub bl, 100b	;substract to start from zero
			add bl, bl		;multiply by 2 (because registers are two symbols, e.g. "AX")
			mov ax, word ptr [_addrRegs2 + bx]
			WriteWord ax
		@@E_AddrReg1:

		cmp dh, 00b
		je @@E_NoOffset		;if there is no offset
			WriteByte "+"
			@@E_NoPlus:

			cmp dh, 01b
			je @@E_OffsetByte
				mov ax, word ptr [codeBuf + si]
				add si, 2
				mov cx, 4
				jmp @@E_OffsetWord
			@@E_OffsetByte:
				mov ah, [codeBuf + si]
				inc si
				mov cx, 2
			@@E_OffsetWord:
			call WriteAsHex
		@@E_NoOffset:

		WriteByte "]"

		jmp @@End
	@@E_Skip:


; (M) The ModR/M byte may refer only to memory
	cmp [commandBuf + bx], "M"
	jne @@M_Skip

		;Get Mod field from ModR/M byte (dl)
		mov dh, dl
		and dh, 11000000b			;keep only mod field (1 to 2 bites)
		shr dh, 6					;shift mod bites to the right
		and dl, 00000111b			;keep only r/m field (6 to 8 bites)

		cmp dh, 11b
		je @@M_InvalidValue
			jmp @@E_Memory			;if ModR/M byte is valid
		@@M_InvalidValue:
			mov al, 7
			mov bx, offset _Unknown
			mov di, 20
			call WriteToBuf

		jmp @@End
	@@M_Skip:


; (O) The offset of the operand is encoded as a word in the instruction
	cmp [commandBuf + bx], "O"
	jne @@O_Skip

		WriteByte "["
		mov dh, 10b
		jmp @@E_NoPlus

	@@O_Skip:


; (G) The reg field of the ModR/M byte selects a general register
	cmp [commandBuf + bx], "G"
	jne @@G_Skip

		add si, [modByteFlag]		;increase si, if ModR/M byte hasn't been used yet
		mov [modByteFlag], 0

		;Get Reg field from ModR/M byte (dl)
		xor dh, dh
		and dl, 00111000b			;keep only reg field (3 to 5 bites)
		shr dl, 3					;shift them to the right

		;Write corresponding register to the result buffer
		add dl, dl					;multiply by 2 (because registers are two symbols, e.g. "AX")
		cmp [commandBuf + bx + 1], "w"
		jne @@G_NotWord
			add dl, 16
		@@G_NotWord:
		mov bx, dx
		mov ax, word ptr [_registers + bx]
		WriteWord ax

		jmp @@End
	@@G_Skip:


; (S) The reg field of the ModR/M byte selects a segment register
	cmp [commandBuf + bx], "S"
	jne @@S_Skip

		add si, [modByteFlag]		;increase si, if ModR/M byte hasn't been used yet
		mov [modByteFlag], 0

		;Get sReg field from ModR/M byte (dl)
		and dl, 00011000b			;keep only 4 to 5 bites
		shr dl, 3					;shift them to the right

		;Write corresponding segment register to the result buffer
		xor dh, dh
		add dl, dl					;multiply by 2 (because registers are two symbols, e.g. "DS")
		mov bx, dx
		mov ax, word ptr [_segments + bx]
		WriteWord ax

		jmp @@End
	@@S_Skip:


; (I) Immediate data. The operand value is encoded in subsequent bytes of the instruction
	cmp [commandBuf + bx], "I"
	jne @@I_Skip

		cmp [commandBuf + bx + 1], "w"
		je @@I_Word
			;Write subsequent byte
			mov ah, [codeBuf + si]
			inc si
			mov cx, 2
			jmp @@I_Byte
		@@I_Word:
			;Write subsequent word
			mov ax, word ptr [codeBuf + si]
			add si, 2
			mov cx, 4
		@@I_Byte:
		call WriteAsHex

		jmp @@End
	@@I_Skip:


; (J) The instruction contains a relative offset to be added to the address of the subsequent instruction
	cmp [commandBuf + bx], "J"
	jne @@J_Skip

		xor ah, ah
		mov al, [codeBuf + si]		;read relative offset
		inc si
		cbw							;convert al to ax
		add ax, [startIP]
		add ax, si					;add address of the subsequent instruction
		mov cx, 4
		call WriteAsHex

		jmp @@End
	@@J_Skip:


; (Ap) Absolute adress = segment:offset
	cmp word ptr [commandBuf + bx], "pA"
	jne @@A_Skip

		mov ax, word ptr [codeBuf + si]		;get offset 
		mov dx, ax
		shr ax, 4
		add ax, word ptr [codeBuf + si + 2]	;add segment
		mov cx, 1
		call WriteAsHex				;write X----h

		and dx, 000Fh				;keep only lowest nibble
		shl ax, 4
		add ax, dx
		mov cx, 4
		call WriteAsHex				;write -XXXXh
		add si, 4

		jmp @@End
	@@A_Skip:

@@End:
	pop dx
	pop cx
	pop ax
	ret
DecryptOperands ENDP

;-------------------------------------------------------------------
; GetOpcodeLine - parse a line from a file with opcodes
; IN
;	al - line number
; OUT
;	ds:commandBuf - parsed line with command template
;-------------------------------------------------------------------
GetOpcodeLine PROC
	push ax
	push bx
	push cx
	push dx

	;Calculate offset for the pointer
	mov ah, CommandSize
	mul ah				;ax = al * ah = line number * line size

	;Move file pointer to the beginning of ax line
	mov cx, 0
	mov bx, [commadsHandle]
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
	pop bx
	pop ax
	ret
GetOpcodeLine ENDP

;-------------------------------------------------------------------
; GetOpcodeGroupsLine - parse a line from the file with opcode groups
; IN
;	al - group number
;	bl - second byte of a command
; OUT
;	ds:commandBuf - parsed line with command template
;-------------------------------------------------------------------
GetOpcodeGroupsLine PROC
	push ax
	push bx
	push cx
	push dx
	push di

	;Calculate line number for opcode groups map:
	mov ah, 8
	mul ah				;multiplicate al by 8
	and bl, 00111000b	;extract only 3 to 5 bites
	shr bl, 3			;shift them to the right
	add al, bl			;al = groupNr * 8 + --XXX---

	;Calculate offset for the pointer
	mov ah, CommandSize
	mul ah				;ax = al * ah = line number * line size

	;Move file pointer to the beginning of ax line
	mov bx, [groupsHandle]
	mov cx, 0
	mov dx, ax
	mov ax, 4200h
	int 21h

	;Store line in the groups buffer
	mov ah, 3Fh
	mov cx, 16
	mov dx, offset groupsBuf
	int 21h

	;Move template from the groups buffer to the command buffer
	mov al, 8
	cmp [groupsBuf + 8], 0
	je @@NoParameters
		mov al, 16
	@@NoParameters:
	mov bx, offset groupsBuf
	mov di, offset commandBuf
	sub di, offset resultBuf		;because procedure will add it later
	call WriteToBuf

	pop di
	pop dx
	pop cx
	pop bx
	pop ax
	ret
GetOpcodeGroupsLine ENDP

;-------------------------------------------------------------------
; WriteToBuf - copy string from input buffer to result buffer,
; replacing zeroes with spaces.
; IN
;	al - number of bytes to copy
;	ds:bx - input buffer
;	ds:[resultBuf+di] - output buffer
; OUT
;	Copied string, stored in ds:[resultBuf+di]
;	di += al
;-------------------------------------------------------------------
WriteToBuf PROC
	push ax
	push bx

	@@Loop:
		mov ah, [bx]
		inc bx
		cmp ah, 0
		jne @@NotZero
			mov ah, " "
		@@NotZero:
		WriteByte ah
		dec al
		jnz @@Loop

	pop bx
	pop ax
	ret
WriteToBuf ENDP

;-------------------------------------------------------------------
; WriteAsHex - write an integer into result buffer in hexadecimal format
; IN
;	ah / ax - integer to convert
;	cx - number of nibbles to write (from the left: ->XXXXh);
;		i.e. size of the integer:
;			2(nibbles) for 1 byte integer / 4(nibbles) - for 2 bytes
;	ds:[resultBuf+di] - output buffer
; OUT
;	An ASCII string with a number converted to hex, stored in ds:[resultBuf+di]
;	di += number of symbols (0-F) written
;-------------------------------------------------------------------
WriteAsHex PROC
	push ax
	push bx
	push cx

	@@Repeat:
	rol ax, 4
	mov bx, ax
	and bx, 000Fh
	mov bl, [hex + bx]
	WriteByte bl
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
