# DiskBender

A disk image manager for Amstrad CPC `.dsk` files, written in Free Pascal.
Inspect, extract, and manipulate CP/M filesystems — from the command line,
a Norton Commander-style terminal UI, or a native macOS GUI.

```
diskbender files list myDisk.dsk
diskbender disk sectormap myDisk.dsk
diskbender disk info myDisk.dsk -o json
```

---

## Features

- **Three interfaces** — CLI, TUI, and Lazarus/Cocoa GUI sharing the same backend
- **CP/M filesystem** — list, extract, add, rename, delete, and undelete files across user areas 0–15
- **Sector map** — physical layout of every track; detects copy-protection fingerprints (twin sectors, suspicious IDs, DataLength mismatches, short-read anomalies)
- **Block map** — CP/M allocation view, colour-coded by file; highlights blocks owned by the selected file
- **Hex viewer** — scrollable hex/ASCII dump of any file on the image
- **Truecolor TUI** — 24-bit truecolor terminal, NC-style dual-pane layout, host filesystem browser
- **Greaseweazle** — read real 3" discs to `.dsk` or write an image back to floppy
- **Standard & Extended DSK** — both format variants supported, including copy-protected discs

---

## Installation

### Prerequisites

- [Free Pascal Compiler](https://www.freepascal.org/) 3.2+
- [Lazarus IDE](https://www.lazarus-ide.org/) 3.x (GUI only)
- macOS (Cocoa backend for GUI); TUI/CLI work on any Unix terminal

### Build — CLI + TUI (single binary)

```bash
cd src && make
# produces ../DiskBender
```

### Build — GUI

```bash
~/src/lazarus/lazbuild \
  --lazarusdir=/path/to/lazarus \
  --compiler=/opt/homebrew/bin/fpc \
  src/gui/DiskBenderGUI.lpi
```

### Tests

```bash
cd /path/to/DiskBender
fpc -Fu./src/units -Fu./src/tui -Fu./src tests/test_tui.pas -o tests/test_tui && ./tests/test_tui
fpc -Fu./src/units -Fu./src/tui -Fu./src tests/test_cpm_write.pas -o tests/test_cpm_write && ./tests/test_cpm_write
```

---

## Usage

### CLI

```
diskbender <noun> <verb> [options] [target] <dsk_path> [-o table|json]
```

**File commands**

| Command | Description |
|---------|-------------|
| `files list myDisk.dsk` | List all files |
| `files get NAME.EXT myDisk.dsk` | Extract a file to the current directory |
| `files get --stdout NAME.EXT myDisk.dsk` | Extract to stdout (pipe-friendly) |
| `files add myfile.bas myDisk.dsk` | Import a host file onto the DSK |
| `files rename OLD.BAS NEW.BAS myDisk.dsk` | Rename a file |
| `files delete NAME.EXT myDisk.dsk` | Mark a file deleted |
| `files undelete NAME.EXT myDisk.dsk` | Restore a deleted file |

**Disk commands**

| Command | Description |
|---------|-------------|
| `disk info myDisk.dsk` | Geometry, DPB parameters, free space |
| `disk map myDisk.dsk` | CP/M block allocation map |
| `disk sectormap myDisk.dsk` | Physical sector layout with protection detection |

**Greaseweazle**

```bash
diskbender gw read --drive a out.dsk          # read disc → DSK file
diskbender gw write --drive a image.dsk       # write DSK file → disc
diskbender gw write --drive a --yes image.dsk # skip confirmation
```

Requires `gw` on `PATH`, or set `DISKBENDER_GW=/path/to/gw`.

**Output format**

Append `-o json` to any `files` or `disk` command for machine-readable output.

### TUI

```bash
diskbender myDisk.dsk      # DSK in left pane, host filesystem in right
diskbender                 # host filesystem browser (both panes)
```

Norton Commander-style dual-pane interface. Navigate with arrow keys or
mouse. The active DSK is shown on one side; the host filesystem (with
full date and size columns) is on the other.

#### Key bindings

| Key | Action |
|-----|--------|
| Up/Down, W/S | Navigate entries |
| Enter | Open container (directory, `.dsk`) |
| Backspace | Go back (history stack, cursor restored by name) |
| Tab | Switch pane focus |
| F2 | Save modified DSK |
| F3 | Toggle block map (on DSK); open hex viewer (on file) |
| Shift+F3 | Open full-screen sector map |
| F5 | Copy between panes |
| F6 | Rename |
| F8 | Delete / Undelete |
| F9 | Menu (sort, save, revert, sector map, disk info…) |
| Esc / F10 / Q | Exit (or close current view) |
| Alt+B | Toggle block map pane (companion panel) |
| Alt+M | Toggle sector map pane (companion panel) |
| Mouse wheel | Scroll list / sector map |

#### Sector map

The full-screen and pane sector maps show the physical track layout of the
disk, with protection-aware coloring:

| Glyph / color | Meaning |
|---------------|---------|
| `█` green | CP/M data sector |
| `█` cyan | Boot / system track |
| `░` dark | Free (filler bytes only) |
| `X` red | FDC error flag set |
| `L` yellow | Actual read length ≠ nominal size |
| `W` orange | Declared DataLength ≠ nominal size |
| `X` magenta | Suspicious sector ID (outside standard CPC ranges) |
| Magenta background | Twin sector (duplicate ID on same track) |

Sectors owned by the currently selected file are highlighted. In the pane
view the display autoscrolls to keep the selected file's tracks visible as
you navigate.

### GUI

```bash
open DiskBenderGUI.app --args /path/to/image.dsk
```

Full LCL/Cocoa interface with sortable columns, drag & drop between panes,
hex viewer, disk map dialog, and disk info dialog.

---

## Architecture

DiskBender uses a capability-based VFS model. Everything is an `IEntry`;
containers also implement `IContainer`. Capabilities are orthogonal
interfaces discovered at runtime via `Supports()`:

| Interface | Capability |
|-----------|------------|
| `IEntry` | Name + display name |
| `IContainer` | Holds child entries, navigable |
| `ISizeable` | Has a byte/block size |
| `ICopySource` | Content extractable to a stream |
| `ICopyTarget` | Can receive / import an entry |
| `IDeletable` | Can be deleted |
| `IRestorable` | Can restore deleted entries |
| `IRenameable` | Can be renamed |
| `IWritable` | Can save / revert changes |
| `IBlockMappable` | Block-level allocation map |
| `ISectorMappable` | Physical sector layout map |
| `ISectorOwning` | Knows which sectors it occupies |
| `IAttributed` | CP/M R/O, System, Archive flags |
| `IDated` | Modified / created timestamps |
| `IPhysicalLayout` | Track/sector geometry |
| `IUserArea` | CP/M user number |

The TUI never casts to concrete types — it queries capabilities and enables
or disables UI actions accordingly.

```
┌────────────────────────────────────────────┐
│   CLI   │        TUI        │     GUI       │
└─────────┴────────┬──────────┴───────┬───────┘
                   │                  │
           ┌───────▼──────────────────▼───────┐
           │            CoreAPI.pas            │
           └──────────────────┬────────────────┘
                              │
           ┌──────────────────▼────────────────┐
           │      VFS capability interfaces     │
           │  IContainer / IEntry / IWritable…  │
           └──────┬────────────────────┬────────┘
                  │                    │
         ┌────────▼────────┐  ┌────────▼────────┐
         │  TDSKContainer  │  │ TLocalContainer  │
         │  TCPMFileEntry  │  │ TLocalFileEntry  │
         └────────┬────────┘  └─────────────────┘
                  │
         ┌────────▼────────┐  ┌─────────────────┐
         │   uDSK.pas      │  │   uCPM.pas       │
         │ (disk I/O)      │  │ (CP/M filesystem)│
         └─────────────────┘  └─────────────────┘
```

---

## Project layout

```
src/
├── DiskBender.pas           # Mode dispatch: TUI / CLI / GUI / gw
├── CoreAPI.pas              # CLI command dispatch
├── units/
│   ├── uVFS.pas             # All VFS interfaces and shared types
│   ├── uDSK.pas             # DSK image I/O (standard & extended)
│   ├── uCPM.pas             # CP/M filesystem (TCPMFile, TCPMFileView)
│   ├── uCPMTypes.pas        # Shared types: TCPMFileName, TRowTag
│   ├── uInterfaces.pas      # IVirtualDisk / IFilesystem / IVirtualFile
│   ├── uDSKLocation.pas     # VFS DSK adapter: TDSKContainer, TCPMFileEntry
│   ├── uLocalLocation.pas   # VFS host-FS adapter: TLocalContainer, TLocalFileEntry
│   ├── uFormatters.pas      # Table / JSON / sector-map output formatters
│   └── uExternalDrive.pas   # Greaseweazle integration
├── tui/
│   ├── uTerminalIO.pas      # ITerminalInput / ITerminalOutput interfaces
│   ├── uFPCTerminal.pas     # Real terminal (FPC Video + Keyboard, truecolor SGR)
│   └── uTUIController.pas   # Pure-logic TUI controller (testable with mock terminal)
└── gui/
    ├── DiskBenderGUI.lpr    # Lazarus entry point
    ├── DiskBenderGUI.lpi    # Lazarus project file
    ├── uMainForm.pas        # Dual-pane form, F-key handlers, drag & drop, sorting
    └── uViewers.pas         # Hex viewer, disk map, disk info dialogs
tests/
├── test_tui.pas             # 275 TUI controller tests (mock terminal)
├── test_cpm_write.pas       # CP/M write-path tests (round-trip, extents, skew)
├── uTestTerminal.pas        # Mock terminal (scripted key queue, virtual screen)
├── uTestLocation.pas        # Mock VFS containers and entries
└── uTestVirtualDisk.pas     # Mock IVirtualDisk implementations
```

---

## CP/M notes

- CP/M has no subdirectories — organisation is by **user area** (0–15)
- Filenames are 8.3 format, stored uppercase; deleted entries have `0xE5` in byte 0
- DiskBender can toggle the deleted flag; blocks remain intact until overwritten
- **GUARD entries** — Discology copy-protection uses directory entries with all-space filenames to pre-allocate blocks without creating real files; these appear as `[GUARD#00]`, `[GUARD#01]` etc. and their blocks are counted as live in the allocation map

---

## License

MIT
