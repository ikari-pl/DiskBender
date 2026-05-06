# Free Pascal makefile for DiskBender
# Builds a unified binary with CLI and TUI support

CC=fpc
OPTS=-O2 -Fuunits -Futui -Mobjfpc -Sh
SRC=DiskBender.pas
BIN=../DiskBender

all: build

build:
	mkdir -p ../build
	$(CC) $(OPTS) -o$(BIN) $(SRC)

clean:
	rm -rf ../build
	rm -f $(BIN)
	rm -f *.o *.ppu units/*.o units/*.ppu tui/*.o tui/*.ppu