# DiskBender - Development Notes

## What is DiskBender?

A Free Pascal tool for managing Amstrad CPC DSK disk images. Three modes:

- **TUI** — Norton Commander-style dual-pane terminal UI (default)
- **CLI** — Scriptable command-line interface (`diskbender files list image.dsk`)
- **GUI** — Lazarus LCL Cocoa app (separate binary)

## Build

### TUI + CLI (single binary)

```bash
cd /Users/ikari/src/cpc/DiskBender/src && make
```

### GUI

```bash
~/src/lazarus/lazbuild --lazarusdir=/Users/ikari/src/lazarus --compiler=/opt/homebrew/bin/fpc src/gui/DiskBenderGUI.lpi
```

### Tests

```bash
cd /Users/ikari/src/cpc/DiskBender && fpc -Fu./src/units -Fu./src/tui -Fu./src tests/test_tui.pas -otests/test_tui && ./tests/test_tui
```

## Run

```bash
# TUI with DSK in left pane, local dir in right:
./DiskBender path/to/image.dsk

# TUI with local dirs in both panes (file browser):
./DiskBender

# CLI:
./DiskBender files list image.dsk
./DiskBender disk info image.dsk

# GUI:
./DiskBender gui image.dsk
# or directly:
open DiskBenderGUI.app --args /path/to/image.dsk
```

## Architecture

### VFS (Virtual File System) — capability-based model

Everything is an `IEntry`. Entries that contain children also implement `IContainer`.
Capabilities are expressed as orthogonal interfaces checked at runtime via `Supports()`.
The TUI never casts to concrete types — it discovers what an entry can do.

Core interfaces (in `uVFS.pas`):

| Interface | Purpose |
|---|---|
| `IEntry` | Name + DisplayName — the fundamental unit |
| `IContainer` | Holds child entries, navigable |
| `ISizeable` | Has a size (bytes/KB/blocks) |
| `ICopySource` | Content extractable to a stream |
| `ICopyTarget` | Can receive/import an entry |
| `IDeletable` | Can be deleted |
| `IRestorable` | Can restore deleted entries |
| `IRenameable` | Can be renamed |
| `IWritable` | Can save/revert changes |
| `IBlockMappable` | Has block-level allocation map |
| `IAttributed` | Has metadata flags (R/O, System, Archive) |
| `ISortable` | Entries can be reordered |
| `ISummary` | Provides summary text |
| `IPhysicalLayout` | Has physical geometry info |
| `IUserArea` | Has a CP/M user number |

### Terminal I/O abstraction

`ITerminalInput` / `ITerminalOutput` interfaces decouple the TUI controller from
FPC's Video/Keyboard units. This makes the controller fully testable with mock
implementations (`TTestTerminalInput` / `TTestTerminalOutput`).

### TUI Controller

`TTUIController` is a pure-logic class that depends only on `uTerminalIO` and `uVFS`.
It has no `uses Keyboard, Video`. Navigation uses a per-pane history stack (Backspace
pops back). Enter on any `IContainer` pushes and navigates in. All actions check
capabilities via `Supports()`.

## TUI Key Bindings

| Key | Action |
|---|---|
| Up/Down, W/S | Navigate entries |
| Enter | Open container (dir, .dsk) |
| Backspace | Go back (history stack) |
| Tab | Switch pane focus |
| F2 | Save modified DSK |
| F3 | Toggle block allocation map |
| F5 | Copy between panes |
| F6 | Rename (DSK entries) |
| F8 | Delete / Undelete |
| F9 | Revert DSK changes |
| Esc, F10, Q | Exit |

## Key Files

### VFS + Locations
- `src/units/uVFS.pas` — All VFS interfaces and shared types
- `src/units/uLocalLocation.pas` — Host filesystem: `TLocalContainer`, `TLocalDirEntry`, `TLocalFileEntry`
- `src/units/uDSKLocation.pas` — DSK images: `TDSKContainer`, `TCPMFileEntry`

### TUI
- `src/tui/uTerminalIO.pas` — `ITerminalInput`, `ITerminalOutput`, `TKeyAction`
- `src/tui/uFPCTerminal.pas` — Real terminal implementation (FPC Video + Keyboard)
- `src/tui/uTUIController.pas` — Pure-logic TUI controller

### Backend
- `src/units/uDSK.pas` — Low-level DSK image I/O
- `src/units/uCPM.pas` — CP/M filesystem (`TCPMFile` + `TCPMFileView`)
- `src/units/uCPMTypes.pas` — Shared CP/M constants, `TCPMFileName`, `TRowTag`
- `src/units/uInterfaces.pas` — `IFilesystem` / `IVirtualFile` / `IVirtualDisk` (used by uDSK/uCPM and GUI)
- `src/CoreAPI.pas` — CLI command dispatch

### GUI (separate binary)
- `src/gui/uMainForm.pas` — Main form, F-key handlers, sort, drag&drop
- `src/gui/uViewers.pas` — Hex/text/disk-map modal dialogs

### Tests
- `tests/test_tui.pas` — 24 TUI controller tests
- `tests/uTestTerminal.pas` — Mock terminal (scripted key queue, virtual screen buffer)
- `tests/uTestLocation.pas` — Mock VFS containers and entries

### Entry point
- `src/DiskBender.pas` — Mode dispatch: no args → TUI file browser, one arg → TUI with DSK, `gui <path>` → launches GUI app, `<noun> <verb>` → CLI

## CP/M Notes

- CP/M has no directories, only user areas (0-15)
- Filenames: 8 chars + 3 char extension
- Files with `?` in first byte are deleted
- User number is stored in directory entry (not in filename)
- Max file size for import: 64 KB (CP/M constraint)

## GUI-Specific Features (Apr 2026)

- Column sorting — click header to sort/flip direction
- Drag & drop between panes
- Hex viewer — scrollable `TMemo` modal
- Disk map — paint-box colour grid with legend
- Disk info — scrollable text modal
- F-key shortcuts via `FormKeyDownHandler` with `KeyPreview=True`

## TODO

1. **GUI: File icons** — icon stubs not implemented
2. **GUI: F5 Copy progress** — needs indicator for large files
3. **TUI: User area navigation** — user areas 0-15 need proper UI
4. **TUI: Hex viewer (F3 on file)** — not yet wired
5. **GUI: Hex editor (F4)** — read-only, no write-back
6. **End-to-end smoke test** — with a real DSK image
7. **TUI: View mode switching** — Brief (name only) / Full (name+size+date) panel modes; `TViewMode` enum and `FViewMode` state already stubbed in `uTUIController.pas`
8. **TUI: Directory size calculation** — recursive size for local dirs, shown in Full view mode; may need an async/background approach for large trees
9. ~~**TUI: Date column**~~ — Done. Local entries implement `IDated` (mtime + birthtime on Darwin via `fpstat`). `FormatEntry` shows NC-style 12-char date column. `FDateKind` per pane tracks which date kind to display.
10. ~~**TUI: Context-aware sort dialog**~~ — Done. `RunSortDialog` dynamically probes first entry for `IUserArea`/`IDated` to build option list. Local dirs get Modified/Created, DSK gets User.

<!-- BEGIN BEADS INTEGRATION v:1 profile:minimal hash:ca08a54f -->
## Beads Issue Tracker

This project uses **bd (beads)** for issue tracking. Run `bd prime` to see full workflow context and commands.

### Quick Reference

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --claim  # Claim work
bd close <id>         # Complete work
```

### Rules

- Use `bd` for ALL task tracking — do NOT use TodoWrite, TaskCreate, or markdown TODO lists
- Run `bd prime` for detailed command reference and session close protocol
- Use `bd remember` for persistent knowledge — do NOT use MEMORY.md files

## Session Completion

**When ending a work session**, you MUST complete ALL steps below. Work is NOT complete until `git push` succeeds.

**MANDATORY WORKFLOW:**

1. **File issues for remaining work** - Create issues for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **PUSH TO REMOTE** - This is MANDATORY:
   ```bash
   git pull --rebase
   bd dolt push
   git push
   git status  # MUST show "up to date with origin"
   ```
5. **Clean up** - Clear stashes, prune remote branches
6. **Verify** - All changes committed AND pushed
7. **Hand off** - Provide context for next session

**CRITICAL RULES:**
- Work is NOT complete until `git push` succeeds
- NEVER stop before pushing - that leaves work stranded locally
- NEVER say "ready to push when you are" - YOU must push
- If push fails, resolve and retry until it succeeds
<!-- END BEADS INTEGRATION -->
