# DiskBender GUI - Development Notes

## What is DiskBender?

A Lazarus LCL Cocoa GUI application for managing CPC DSK disk images with Norton Commander-style dual-panel file operations.

## Build

```bash
cd /Users/ikari/src/cpc/DiskBender
~/src/lazarus/lazbuild --lazarusdir=/Users/ikari/src/lazarus --compiler=/opt/homebrew/bin/fpc src/gui/DiskBenderGUI.lpi
```

## Run

```bash
open /Users/ikari/src/cpc/DiskBender/DiskBenderGUI.app --args /path/to/image.dsk
```

## Kill

```bash
pkill -f DiskBenderGUI
```

## Implemented Features

### F-Key Operations (work on focused panel)
- **F1 Help** - Shows help message
- **F2 Rename** - Rename DSK file via `FFS.RenameFile()`; host shows message to use Finder
- **F3 View** - Hex viewer for DSK files; host shows file info message
- **F4 Edit** - Same as F3 View (hex editor placeholder)
- **F5 Copy** - Copy between DSK and Host (based on focused pane)
- **F6 Move** - Rename file on DSK; host shows message to use Finder
- **F7 NewDir** - Shows "CP/M has no subdirectories" message
- **F8 Delete** - Toggle delete flag on DSK files; host shows message
- **F9 Menu** - Shows hint about left/right arrows to switch panels
- **F10 Quit** - Exit application

### Panel Operations
- **Left/Right arrows** - Switch between DSK and Host panels
- **Enter** - On DSK: enter "directory" (user area); On Host: open folder
- **Column sorting** - Click header to sort (stub implemented)
- **Drag & Drop** - Between panes (stub implemented)

### File Operations
- **Copy to DSK** - Add host file to DSK via `FFS.AddFile()`
- **Copy to Host** - Extract DSK file to host filesystem
- **Undelete** - Restore first character of deleted file via `FFS.UndeleteFile()`

### Backend (uCPM.pas)
- `RenameFile(Idx: Integer; const NewName: string)`
- `UndeleteFile(Idx: Integer)`
- `AddFile(const HostPath: string): Boolean`

## Recently Completed (Apr 2026 refactor pass)

- **Column sorting** - Click any header to sort; click again to flip direction.
  DSK sort is delegated to `IFilesystem.SortFiles` (stable), host sort runs
  in-memory over `FHostEntries`.
- **Drag & Drop between panes** - Drop a host file on DSK to copy, drop a DSK
  file on Host to extract.
- **Hex viewer** - Dedicated modal `ShowHexViewer` in `uViewers` with a real
  `TMemo` (scrollable, fixed-width font) instead of `ShowMessage`.
- **Disk map** - Paint-box colour grid via `uViewers.ShowDiskMap` with legend.
- **Disk info** - Scrollable text modal via `uViewers.ShowTextViewer`.
- **Host details panel** - `LabelDetails` updated on select via
  `ListViewHost.OnSelectItem`.
- **F-key shortcuts** - Wired centrally via `FormKeyDownHandler` with
  `KeyPreview=True`; no LFM hand-editing required.
- **Row metadata** - Parallel `FDSKRowTags` / `FHostRowTags` arrays of
  `TRowTag` replace `Pointer(PtrInt())` smuggling in `TListItem.Data`.
- **Reference counting** - `TCPMFile` is a plain `TObject` owned by a
  `TFPGObjectList`; `TCPMFileView` (`TInterfacedObject`) wraps it for the
  `IVirtualFile` surface. No more `TNonRefCountedObject` hack.
- **Shared types unit** - `uCPMTypes.pas` owns `TCPMFileName` (advanced
  record), `TRowTag`, `TCPMAttr` and the magic constants.

## Still Missing / TODO Features

1. **File icons** - `SetupFileIcons`, `GetIconIndexForExt`, `GetIconIndexForHostItem` are stubs (no icons)
2. **F5 Copy** - Basic implementation, needs progress indicator for large files
3. **User area navigation** - CP/M has no dirs but user areas (0-15) need proper UI
4. **Menu accelerators** - Menu items could use more keyboard shortcuts
5. **Hex viewer search** - Hex dump is scrollable but has no Find/Goto
6. **Hex editor (F4)** - Currently same as F3 View; real edit-and-write-back not implemented
7. **Smoke-test** - End-to-end test with a real DSK image

## Key Files

- `src/gui/uMainForm.pas` - Main form, F-key handlers, sort, drag&drop
- `src/gui/uMainForm.lfm` - Form layout (Lazarus designer)
- `src/gui/uViewers.pas` - Programmatic hex/text/disk-map modal dialogs
- `src/units/uCPM.pas` - CP/M filesystem implementation (`TCPMFile` + `TCPMFileView`)
- `src/units/uInterfaces.pas` - `IFilesystem` / `IVirtualFile` / `IVirtualDisk`
- `src/units/uCPMTypes.pas` - Shared CP/M constants, `TCPMFileName`, `TRowTag`

## CP/M Notes

- CP/M has no directories, only user areas (0-15)
- Filenames: 8 chars + 3 char extension
- Files with `?` in first byte are deleted
- User number is stored in directory entry (not in filename)