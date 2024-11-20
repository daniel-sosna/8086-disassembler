;*******************************************************;
; Author: Daniel Sosna                                  ;
; Info: The program disassembles machine code into      ;
;       instructions for the Intel 8086 microprocessor. ;
;*******************************************************;

LOCALS @@
.MODEL small
.STACK 100h

FileNameSize = 10h	;Max size of the names of the entered files
CodeBufSize = 100h	;Size of the machine code block to read at a time (minimum 6)
CommandSize = 16	;Size of each line in commands file
ResultBufSize = 30	;Max size of assembly instruction we possibly will get
CommandsFile EQU "opc.map", "$"
GroupsFile EQU "opc-grp.map", "$"

JumpIfZero MACRO label
	LOCAL skip
	jnz skip
	jmp PrintHelpAndCloseFiles
	skip:
ENDM

.DATA
	;Files
	inFileName	db FileNameSize dup(0), "$"
	inHandle	dw 0
	outFileName	db FileNameSize dup(0), "$"
	outHandle	dw 0
	commandsFileName	db CommandsFile
	commahdsHandle		dw 0
	groupsFileName		db GroupsFile
	groupsHandle		dw 0
	;Messages
	newLine		db 13, 10, "$"
	msgFilesSuccess	db "Successfully opened files.", 13, 10, "$"
	msgErrOpenFile	db "[ERROR] Cannot open file ", "$"
	msgHelp		db "The program disassembles machine code into instructions for the Intel 8086 microprocessor. See README.md for more information.", 13, 10
				db "Usage: disasm.exe [options] input_file output_file", 13, 10
				db "  *Also, there have to be 'opc.map' and 'opc-grp.map' files with opcodes in the same directory.", 13, 10
				db "  options:", 13, 10
				db "    /?  Print this message.", 13, 10
				db "$"
	;Other

.DATA?	;Uninitialized data
	codeBuf		db CodeBufSize dup(?)
	commandBuf	db CommandSize dup(?)
	resultBuf	db ResultBufSize dup(?)

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
	cmp [es:bx], '?/'		;In the memory, low byte is stored before high ('?' is in BL, '/' - in BH)
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
	jc ErrOpenInFile
	mov [inHandle], ax

	;Create output file
	mov ah, 3Ch
	mov cx, 00000000b
	mov dx, offset outFileName
	int 21h
	jc ErrOpenOutFile
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
	; Call proc passing ax and dx
	jmp @@Loop

;-------------------------------------------------------------------

Exit: ;Close all opened files and exit
	mov bx, [inHandle]
	call CloseFile
	mov bx, [outHandle]
	call CloseFile
	mov bx, [commahdsHandle]
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
; PrintMsg - print message (that ends by '$') to the screen
; IN
; 	dx - message
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
; 	dx - filename
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
;	inFileName - first filename
;	outFileName - second filename
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
