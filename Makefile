.PHONY: all clean

all: tyche

tyche: bootstrap.o
	ld bootstrap.o -o tyche

bootstrap.o: bootstrap.asm
	nasm -f elf64 bootstrap.asm -o bootstrap.o

clean:
	rm -f bootstrap.o tyche
