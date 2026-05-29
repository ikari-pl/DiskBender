# Testing Gaps

## Fix #12 — `--cwd` argument (no following value)

**Location**: `src/gui/uMainForm.pas`, `FormCreate` method, argument-parsing loop.

**Gap**: The `--cwd` flag (with no following path value) cannot be unit-tested without
instantiating the LCL `TMainForm`, which requires a full Lazarus/Cocoa application
context.  There is no standalone parsing function to call from a headless test program.

**Expected behaviour**: When `DiskBenderGUI` is launched with `--cwd` as the final
argument (i.e. no value follows), the parser falls through to the `else Inc(I)` arm
and leaves `StartDir` as `GetCurrentDir`.  The application opens normally with the
current working directory as the starting path, and does not crash.

**Manual verification steps**:

1. Build the GUI binary:
   ```
   ~/src/lazarus/lazbuild --lazarusdir=/Users/ikari/src/lazarus \
       --compiler=/opt/homebrew/bin/fpc src/gui/DiskBenderGUI.lpi
   ```
2. Run:
   ```
   open DiskBenderGUI.app --args --cwd
   ```
3. Confirm the application launches without crashing and the host pane shows
   the directory from which the `open` command was issued (i.e. `GetCurrentDir`
   at launch time).

**Why automation is not viable here**: `FormCreate` directly calls `Application`,
`ParamStr`, `GetCurrentDir`, and LCL widget constructors.  Extracting the path-parsing
logic into a pure function and testing that separately would require modifying
`uMainForm.pas` — out of scope for this test-gap document.
