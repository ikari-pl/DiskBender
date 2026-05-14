# Manual TUI/CLI test recipe

Quick interactive smoke checks for the UI polish pass that landed
2026-05-14 (button padding, dropdown sizing, modifier debouncing,
status-bar bounds, background-thread `gw` with Esc-cancel). Pair these
with the automated suites (`test_tui`, `test_cpm_write`, `test_drive`)
which cover the same surface programmatically.

All commands assume cwd = repo root.

## 1. Visual baseline

```sh
./DiskBender "Batman Forever (UK) (128K) (Face 1A) (2011) [Original] [DEMO].dsk"
```

Verify:

- Both panes have **double-line frames** (`╔ ═ ╗ ║ ╚ ╝`).
- Local-FS pane shows directories as `<name>`; the CP/M pane shows
  GUARD pseudo-entries as `[GUARD#00]`...`[GUARD#10]`. Square brackets
  are non-navigable; angle brackets are navigable.
- Bottom F-key bar has at least one column of breathing room around
  each label.

## 2. Dialog padding

- Press **F8** on a deletable file. The confirmation box has 2 columns
  of padding inside the frame walls; `[ Yes ]` / `[ No ]` buttons sit
  on their own row with a blank above and below; Tab toggles focus;
  mouse clicks fire either action.
- **F9** → **Sort by...** → same padding, plus `[ OK ]` / `[ Cancel ]`
  on a padded button row.

## 3. Dropdown width fits the longest item

- **F9**. The menu must show `Read disc from drive...` (24 chars) in
  full — no truncation. The width is `Max(label_length) + 4` clamped
  to the screen width (`ComputeBoxW` in `uTUIController.ActionMenu`).
- Automated coverage: `TestF9MenuFitsLongLabels` in `tests/test_tui.pas`.

## 4. F3 view-cycle and modifier shortcuts

- Cursor on a CP/M file → **F3** cycles: hex view → block-allocation
  map → sector map → commander.
- **Shift+F3** jumps straight to sector map; **Ctrl+F3** jumps to
  block-allocation map. Both require a terminal that supports the
  kitty keyboard protocol (iTerm2 with CSI-u enabled, kitty,
  wezterm). On a non-kitty terminal those keys fall back to plain F3.

## 5. Modifier debouncing

In a kitty terminal: hold and release Shift several times rapidly.
The `View/Map` label in the bottom status bar should update on actual
state transitions only, not on every modifier event. (`kaModifierChange`
arm checks `FLastModifierState != AEvent.Modifiers` before redrawing.)

## 6. Greaseweazle progress modal with Esc-cancel

The async path uses `TGwTask` (TThread) so the TUI stays responsive
during a real disc read (typically 30–90 s on hardware). To exercise
it without a real Greaseweazle, drop in a slow stub:

```sh
cat > tests/slow_gw.sh <<'EOF'
#!/bin/sh
# Slow gw stub: prints a "track" every second for 30s so the progress
# modal is visible and Esc-cancel is feelable. Falls back to fake_gw.sh
# to actually synthesize a valid DSK when the read completes.
HERE="$(dirname "$0")"
case "$1" in
  info)
    echo "Slow fake gw"
    echo "firmware: slow-1.0"
    exit 0
    ;;
  read)
    OUT="$3"
    [ "$2" = "--drive" ] && OUT="$5"
    echo "Slow read starting..."
    i=0
    while [ $i -lt 30 ]; do
      echo "Track $i.0: reading..."
      sleep 1
      i=$((i+1))
    done
    "$HERE/fake_gw.sh" read --drive a "$OUT"
    ;;
  write)
    echo "Slow write..."
    sleep 5
    echo "fake_gw: write complete"
    ;;
esac
EOF
chmod +x tests/slow_gw.sh

DISKBENDER_GW="$PWD/tests/slow_gw.sh" ./DiskBender
```

In the TUI: **F9 → Read disc from drive...** → drive `a` → output
path `/tmp/test.dsk`.

Expected:

- A modal opens with the title `Reading disc from drive a...` and
  shows the gw log streaming.
- **Press Esc.** The modal closes within ~1 second; the underlying
  child process is SIGTERM'd via `TProcess.Terminate(143)`. Without
  this fix the TUI would freeze for the full 30 s.

If `Esc` does nothing on your terminal, check whether kitty mode is
detected — only kitty-capable terminals deliver the press cleanly.

## 7. CLI safety smoke

```sh
# Destructive write refuses without --yes in non-interactive contexts.
echo "" | ./DiskBender disk write --drive a \
    "Batman Forever (UK) (128K) (Face 1A) (2011) [Original] [DEMO].dsk"
# → Error: 'disk write' is destructive. Pass --yes to confirm in non-interactive contexts.

# Interactive TTY prompts for YES; anything else aborts.
./DiskBender disk write --drive a \
    "Batman Forever (UK) (128K) (Face 1A) (2011) [Original] [DEMO].dsk"
# → Type anything except YES → Aborted.

# --drive whitelist rejects non-a/b values.
./DiskBender disk write --yes --drive zz \
    "Batman Forever (UK) (128K) (Face 1A) (2011) [Original] [DEMO].dsk"
# → Error: --drive must be 'a' or 'b' (got 'zz').
```

## 8. Sector-size column and Discology-style oddities

```sh
./DiskBender disk sectormap \
    "Batman Forever (UK) (128K) (Face 2A) (2011) [Original] [DEMO].dsk" \
  | head -20
```

The size column should show entries like `25x128B+1x4K+2x0B+1x8K` —
this face has the variable-sector copy-protection payload, and the
sector-map formatter now distinguishes those sizes per track and lists
them by frequency.

## When to update this file

Add a section here when a UI behavior changes in a way the automated
suites can't fully cover (visual layout, terminal-protocol-dependent
input, long-running async UX). Keep it terse — commands and what to
look for, not exposition.

Cross-refs in this repo:

- `CLAUDE.md` — project conventions and build instructions.
- `tests/test_tui.pas` — automated TUI controller tests.
- `tests/fake_gw.sh` — fast `gw` stub for unit tests.
- `src/units/uExternalDriveAsync.pas` — `TGwTask` thread implementation.
- `src/tui/uTUIController.pas` — `RunProgressModal`,
  `ActionDriveRead`/`ActionDriveWrite`, `ComputeBoxW`, `DLG_HPAD`,
  `FLastModifierState`, `StatusBarSlotAt`.
