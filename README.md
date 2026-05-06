# DiskBender

A vintage disk image manager for Amstrad CPC DSK files, written in Free Pascal.
Inspect, extract, and manipulate CP/M filesystems stored in `.dsk` images —
from the command line, a terminal UI, or a full graphical interface.

```
diskbender files list myDisk.dsk
diskbender disk map myDisk.dsk
diskbender disk info myDisk.dsk -o json
```

---

## Features

- **Three interfaces** — CLI, TUI, and Lazarus LCL GUI, all sharing the same backend
- **CP/M filesystem** — list, extract, delete, and undelete files across user areas 0–15
- **Disk map** — colour-coded visual block map showing free, used, and directory sectors
- **Hex viewer** — scrollable hex/ASCII dump of any file on the image
- **Norton Commander layout** — dual-pane view with DSK on one side, host filesystem on the other
- **Drag & drop** — move files between DSK and host by dragging between panes
- **Standard & Extended DSK** — both format variants supported

---

## Screenshots

_GUI (Lazarus LCL / Cocoa):_

```
┌─────────────────────────────────────────┬──────────────────────────────────────────┐
│  DSK: myDisk.dsk                        │  Host: ~/Documents/CPC                   │
├──────────┬──────┬────┬──────────────────┼──────────────────────┬──────┬────────────┤
│ Name     │ Ext  │ KB │ User             │ Name                 │ Size │ Date       │
├──────────┼──────┼────┼──────────────────┼──────────────────────┼──────┼────────────┤
│ BASIC    │ COM  │  4 │ 0                │ games/               │  —   │ 2024-01-10 │
│ LOADER   │ BAS  │  2 │ 0                │ tools/               │  —   │ 2024-01-10 │
│ HELLO    │ BAS  │  1 │ 1                │ myDisk.dsk           │ 180K │ 2024-01-15 │
└──────────┴──────┴────┴──────────────────┴──────────────────────┴──────┴────────────┘
 F1 Help  F2 Rename  F3 View  F5 Copy  F6 Move  F8 Delete  F10 Quit
```

---

## Installation

### Prerequisites

- [Free Pascal Compiler](https://www.freepascal.org/) (FPC) 3.2+
- [Lazarus IDE](https://www.lazarus-ide.org/) 3.x (GUI only)
- macOS (Cocoa backend); Linux support is untested

### Build — CLI / TUI

```bash
fpc -Fu src/units src/DiskBender.pas -o DiskBender_bin
```

### Build — GUI

```bash
~/src/lazarus/lazbuild \
  --lazarusdir=/path/to/lazarus \
  --compiler=/opt/homebrew/bin/fpc \
  src/gui/DiskBenderGUI.lpi
```

---

## Usage

### CLI

```
diskbender <noun> <verb> [target] <dsk_path> [-o table|json]
```

| Noun | Verb | Description |
|------|------|-------------|
| `files` | `list` | List all files on the disk |
| `files` | `get <name>` | Extract a file to the current directory |
| `files` | `delete <name>` | Mark a file as deleted |
| `files` | `undelete <name>` | Restore a deleted file |
| `disk` | `info` | Show disk geometry and filesystem parameters |
| `disk` | `map` | Render a block allocation map |

**Examples**

```bash
# List files, JSON output
diskbender files list myDisk.dsk -o json

# Extract a file
diskbender files get LOADER.BAS myDisk.dsk

# Show disk block map
diskbender disk map myDisk.dsk
```

### TUI (interactive terminal)

```bash
diskbender myDisk.dsk
```

Launches a Norton Commander-style terminal interface. Use arrow keys to navigate,
Enter to select, and the F1–F10 row for operations.

### GUI

```bash
open DiskBenderGUI.app --args /path/to/image.dsk
```

---

## F-Key Reference (TUI & GUI)

| Key | Action |
|-----|--------|
| F1 | Help |
| F2 | Rename file |
| F3 | View (hex dump) |
| F4 | Edit (hex viewer placeholder) |
| F5 | Copy between panes |
| F6 | Move / rename |
| F7 | New directory (not supported in CP/M) |
| F8 | Delete / toggle deleted flag |
| F9 | Panel switch hint |
| F10 | Quit |

---

## Project Layout

```
src/
├── DiskBender.pas          # CLI + TUI entry point
├── units/
│   ├── uDSK.pas            # DSK image parser (standard & extended)
│   ├── uCPM.pas            # CP/M filesystem (TCPMFile, TCPMFileView)
│   ├── uCPMTypes.pas       # Shared types: TCPMFileName, TRowTag, TCPMAttr
│   ├── uInterfaces.pas     # IVirtualDisk / IFilesystem / IVirtualFile
│   ├── uLocalFS.pas        # Host filesystem adapter
│   └── uFormatters.pas     # Table / JSON output formatters
├── tui/
│   └── uTUI_Custom.pas     # Terminal UI (Video/Keyboard units)
├── gui/
│   ├── DiskBenderGUI.lpr   # Lazarus program entry point
│   ├── DiskBenderGUI.lpi   # Lazarus project file
│   ├── uMainForm.pas       # Dual-pane main form, F-key handlers, drag & drop
│   ├── uMainForm.lfm       # Lazarus form layout
│   └── uViewers.pas        # Hex viewer, text viewer, disk map dialogs
└── CoreAPI.pas             # Shared command dispatch (CLI ↔ GUI)
tests/
├── test_dsk.pas            # DSK format tests
└── test_cpm.pas            # CP/M filesystem tests
resources/
├── DiskBender.svg          # App icon (source)
└── DiskBender.icns         # macOS icon bundle
```

---

## Architecture

```
┌────────────────────────────────────────────┐
│  CLI  │      TUI      │        GUI          │  ← user interfaces
└───────┴───────┬───────┴──────────┬──────────┘
                │                  │
         ┌──────▼──────────────────▼──────┐
         │         CoreAPI.pas            │  ← command dispatch
         └──────────────┬─────────────────┘
                        │
         ┌──────────────▼─────────────────┐
         │  IVirtualDisk / IFilesystem    │  ← interface layer
         │         IVirtualFile           │
         └──────┬───────────────┬─────────┘
                │               │
         ┌──────▼──────┐  ┌─────▼──────┐
         │  uDSK.pas   │  │  uCPM.pas  │  ← implementations
         │ (disk I/O)  │  │ (CP/M FS)  │
         └─────────────┘  └────────────┘
```

All three interfaces share the same `IVirtualDisk` / `IFilesystem` interface layer.
Adding support for a new disk format (e.g. `.img`, `.hfe`) means implementing
`IVirtualDisk` — no changes needed in the UI layer.

---

## CP/M Notes

- CP/M has no subdirectories — organisation is by **user area** (0–15)
- Filenames are 8.3 format; characters are stored uppercase
- A deleted file has `0xE5` in the first byte of its directory entry —
  DiskBender can toggle this flag to undelete files when the blocks are still intact
- The Disk Parameter Block (DPB) stored in `uCPM.pas` targets the standard
  Amstrad CPC 3" compact cassette disk geometry (9 sectors × 40 tracks × 2 sides)

---

## License

MIT
