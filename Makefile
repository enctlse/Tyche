.PHONY: all clean

all: Pine

Pine: bootstrap.o
	ld bootstrap.o -o Pine

bootstrap.o: bootstrap.asm
	nasm -f elf64 bootstrap.asm -o bootstrap.o

clean:
	rm -f bootstrap.o Pine
