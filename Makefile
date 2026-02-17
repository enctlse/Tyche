.PHONY: all clean

all: Pine

Pine: Pinecompiler.o
	ld Pinecompiler.o -o Pine

Pinecompiler.o: Pinecompiler.asm
	nasm -f elf64 Pinecompiler.asm -o Pinecompiler.o

clean:
	rm -f Pinecompiler.o Pine
