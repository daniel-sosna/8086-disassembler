# Disassembler

## About the project
This project is an optional assignment for the subject "Computer Architecture" of the course "Software Engineering" at Vilnius University.

The program is written entirely in assembler. It disassembles the machine code from a given file into instructions for the Intel 8086 microprocessor. The program understands only .COM format, which has no structure, it is just a flat binary.

## Instructions' opcodes
Opcode map found at [link](http://www.mlsite.net/8086/) has been modified for this program.

### How to customize commands/groups:
- Open `commands.txt`/`groups.txt` file
- Edit commands/groups if you need and make sure each line is 16 characters long
- Delete all _`\n`_ (0x0D, 0x0A)
- Replace all _spaces_ (0x20) with _`\0`_ (0x00)
- Save file as `opc.map`/`opc-grp.map`
