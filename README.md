# Disassembler

## About the project
This project is an optional assignment for the subject "Computer Architecture" of the course "Software Engineering" at Vilnius University.

The program is written entirely in assembly language. It disassembles the machine code from a given file into instructions for the **Intel 8086 microprocessor**. The program understands only `.COM` format, which has no structure (segments), it is just a flat binary.

## Usage
To compile and link the disassembler use the following commands from `temp/` directory:
```
tasm ..\disasm.asm
tlink disasm.obj
```

Then, to run the program:
```
disasm.exe input_file output_file
```

Include `/?` to see the help message.

## Disassembling opcodes
Disassembler uses an opcode map to convert bytes into instruction with appropriate operands. The opcode map found at [link](http://www.mlsite.net/8086/) has been modified for this program.  
All instructions and types of their operators are stored in 2 files (`opc.map`, `opc-grp.com`), which can be modified if needed.

### Files
There are two files in `temp/` directory with the templates of all Intel 8086 microprocessor's instructions:
1. Each line in `opc.map` file represents an assembly instruction of the corresponding opcode (from 0x00 to 0xFF).
1. `opc-grp.com` file is for opcodes that have several variations depending on subsequent byte. For each opcode instructions are divided into groups of $8 = 2^3$ (determined by 3 bites of the next byte).

### File structure
All lines are equally long and their size is saved in the `CommandSize` constant. Each line has the following form:
- The First 8 characters are the name of an instruction;
  - `--` instead of name if no instruction specified for this opcode
  - `GRx` for instructions that are in group `x`
- The Next 4 are for the first operand;
- And 4 more are for the second one;
- New line.

### Operands
To describe the type of instructions' operands, a special designation is used:
- `_XX` - The operand is either a general-purpose or a segment register (`XX` is the name of this register).
- `E` - A ModR/M byte follows the opcode and specifies the operand. The operand is either a general-purpose register or a memory address. If it is a memory address, the address is computed from a segment register and any of the following values: a base register, an index register, an offset.
- `M` - Same as `E`, but the ModR/M byte may refer only to memory. Applicable, e.g., to LES and LDS.
- `O` - The offset of the operand is encoded as a WORD in the instruction. Applicable, e.g., to certain MOVs (opcodes A0 through A3).
- `G` - The reg field of the ModR/M byte selects a general-purpose register.
- `S` - The reg field of the ModR/M byte selects a segment register.
- `I` - Immediate data. The operand value is encoded in subsequent bytes of the instruction.
- `J` - The instruction contains a relative offset to be added to the address of the subsequent instruction. Applicable, e.g., to short JMP (opcode EB), or LOOP.
- `A` - Direct address. The address of the operand is encoded in the instruction. Applicable, e.g., to far JMP (opcode EA).
- Addition:
  - `b` - Byte argument.
  - `w` - Word argument.
  - `p` - segment:offset pointer (32-bit).
- Exceptions:
  - If the operand is missing, then all 4 characters are whitespaces.
  - In `opc-grp.com` missing operands' template means taking the general template for operands of this group (the one that follows `GRx`).
