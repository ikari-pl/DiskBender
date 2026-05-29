# Free Pascal makefile for DiskBender
# Builds a unified binary with CLI and TUI support

CC=fpc
OPTS=-O2 -Fuunits -Futui -Mobjfpc -Sh -k-w
SRC=DiskBender.pas
BIN=../DiskBender

LAZARUS_DIR ?= ~/src/lazarus
FPC_COMPILER ?= /opt/homebrew/bin/fpc

all: build

build:
	mkdir -p ../build
	$(CC) $(OPTS) -o$(BIN) $(SRC)

build-gui:
	$(LAZARUS_DIR)/lazbuild --lazarusdir=$(LAZARUS_DIR) --compiler=$(FPC_COMPILER) gui/DiskBenderGUI.lpi

run-gui: build-gui
	open ../DiskBenderGUI.app

clean:
	rm -rf ../build
	rm -f $(BIN)
	rm -f *.o *.ppu units/*.o units/*.ppu tui/*.o tui/*.ppu