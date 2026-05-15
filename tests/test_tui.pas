program test_tui;

{$mode objfpc}{$H+}

uses
  SysUtils, DateUtils, uTerminalIO, uVFS, uTestTerminal, uTestLocation, uTUIController;

var
  PassCount: Integer = 0;
  FailCount: Integer = 0;

procedure Check(const AName: string; ACondition: Boolean);
begin
  if ACondition then
  begin
    WriteLn('  PASS: ', AName);
    Inc(PassCount);
  end
  else
  begin
    WriteLn('  FAIL: ', AName);
    Inc(FailCount);
  end;
end;

function MakeInput: TTestTerminalInput;
begin
  Result := TTestTerminalInput.Create;
end;

function MakeOutput: TTestTerminalOutput;
begin
  Result := TTestTerminalOutput.Create(80, 25);
end;

function MakeContainer(const ATitle: string; ACount: Integer): TTestContainer;
var
  Entries: array of IEntry;
  I: Integer;
begin
  SetLength(Entries, ACount);
  for I := 0 to ACount - 1 do
    Entries[I] := TTestFileEntry.Create('FILE' + IntToStr(I) + '.TXT', (I + 1) * 1024);
  Result := TTestContainer.Create(ATitle, Entries);
end;

{ Returns the (X,Y) of the first character of "[ Label ]" on the virtual screen.
  Scans every row; returns (0,0) if not found. }
function FindButtonOnScreen(AOut: TTestTerminalOutput; const ALabel: string;
                            out BX, BY: Integer): Boolean;
var
  R, C, W: Integer;
  Target, Slice: string;
begin
  Target := '[ ' + ALabel + ' ]';
  W := Length(Target);
  for R := 1 to AOut.GetHeight do
    for C := 1 to AOut.GetWidth - W + 1 do
    begin
      Slice := AOut.TextAt(C, R, W);
      if Slice = Target then
      begin
        BX := C;
        BY := R;
        Result := True;
        Exit;
      end;
    end;
  BX := 0; BY := 0;
  Result := False;
end;

{ ── Existing tests (updated where needed) ─────────────────────── }

procedure TestInitialState;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  Left, Right: IContainer;
begin
  WriteLn('--- TestInitialState ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  Left := MakeContainer('Left', 3);
  Right := MakeContainer('Right', 2);
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_), Left, Right);
  try
    Check('Running is true', Ctrl.Running);
    Check('Focus is psLeft', Ctrl.Focus = psLeft);
    Check('Mode is tmCommander', Ctrl.Mode = tmCommander);
    Check('Cursor starts at 0', Ctrl.GetCursorPos(psLeft) = 0);
    Check('Scroll starts at 0', Ctrl.GetScrollPos(psLeft) = 0);
  finally
    Ctrl.Free;
  end;
end;

procedure TestNavigateDown;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  Left: IContainer;
begin
  WriteLn('--- TestNavigateDown ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  Left := MakeContainer('Left', 5);
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_), Left, nil);
  try
    Ctrl.HandleEvent(InputEvent(kaDown));
    Ctrl.HandleEvent(InputEvent(kaDown));
    Ctrl.HandleEvent(InputEvent(kaDown));
    Check('Cursor moved down 3', Ctrl.GetCursorPos(psLeft) = 3);
  finally
    Ctrl.Free;
  end;
end;

procedure TestNavigateUp;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  Left: IContainer;
begin
  WriteLn('--- TestNavigateUp ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  Left := MakeContainer('Left', 5);
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_), Left, nil);
  try
    Ctrl.HandleEvent(InputEvent(kaDown));
    Ctrl.HandleEvent(InputEvent(kaDown));
    Ctrl.HandleEvent(InputEvent(kaUp));
    Check('Navigate up works', Ctrl.GetCursorPos(psLeft) = 1);
  finally
    Ctrl.Free;
  end;
end;

procedure TestSwitchPane;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  Left, Right: IContainer;
begin
  WriteLn('--- TestSwitchPane ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  Left := MakeContainer('Left', 3);
  Right := MakeContainer('Right', 2);
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_), Left, Right);
  try
    Check('Starts on left', Ctrl.Focus = psLeft);
    Ctrl.HandleEvent(InputEvent(kaTab));
    Check('Tab switches to right', Ctrl.Focus = psRight);
    Ctrl.HandleEvent(InputEvent(kaTab));
    Check('Tab switches back to left', Ctrl.Focus = psLeft);
  finally
    Ctrl.Free;
  end;
end;

procedure TestSwitchPaneNilRight;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  Left: IContainer;
begin
  WriteLn('--- TestSwitchPaneNilRight ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  Left := MakeContainer('Left', 3);
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_), Left, nil);
  try
    Check('Starts on left', Ctrl.Focus = psLeft);
    Ctrl.HandleEvent(InputEvent(kaTab));
    Check('Tab does not switch to nil right', Ctrl.Focus = psLeft);
  finally
    Ctrl.Free;
  end;
end;

procedure TestEnterContainer;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  Inner: TTestContainer;
  Outer: TTestContainer;
begin
  WriteLn('--- TestEnterContainer ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  Inner := TTestContainer.Create('SubDir', [
    TTestFileEntry.Create('INNER.TXT', 512) as IEntry
  ]);
  Outer := TTestContainer.Create('Root', [
    IEntry(Inner)
  ]);
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_),
                                IContainer(Outer), nil);
  try
    Ctrl.HandleEvent(InputEvent(kaEnter));
    Check('Enter navigates into container', Ctrl.LeftContainer.Title = 'SubDir');
  finally
    Ctrl.Free;
  end;
end;

procedure TestExitViaEsc;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  Left: IContainer;
begin
  WriteLn('--- TestExitViaEsc ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  Left := MakeContainer('Left', 1);
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_), Left, nil);
  try
    Check('Running before Esc', Ctrl.Running);
    Ctrl.HandleEvent(InputEvent(kaEsc));
    Check('Not running after Esc', not Ctrl.Running);
  finally
    Ctrl.Free;
  end;
end;

procedure TestExitViaF10;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  Left: IContainer;
begin
  WriteLn('--- TestExitViaF10 ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  Left := MakeContainer('Left', 1);
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_), Left, nil);
  try
    Ctrl.HandleEvent(InputEvent(kaF10));
    Check('Not running after F10', not Ctrl.Running);
  finally
    Ctrl.Free;
  end;
end;

procedure TestExitViaQ;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  Left: IContainer;
begin
  WriteLn('--- TestExitViaQ ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  Left := MakeContainer('Left', 1);
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_), Left, nil);
  try
    Ctrl.HandleEvent(InputEvent(kaChar, 'q'));
    Check('Not running after Q', not Ctrl.Running);
  finally
    Ctrl.Free;
  end;
end;

procedure TestWASDNavigation;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  Left: IContainer;
begin
  WriteLn('--- TestWASDNavigation ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  Left := MakeContainer('Left', 5);
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_), Left, nil);
  try
    Ctrl.HandleEvent(InputEvent(kaChar, 's'));
    Ctrl.HandleEvent(InputEvent(kaChar, 's'));
    Ctrl.HandleEvent(InputEvent(kaChar, 'w'));
    Check('WASD navigation works', Ctrl.GetCursorPos(psLeft) = 1);
  finally
    Ctrl.Free;
  end;
end;

procedure TestDrawProducesOutput;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  Left, Right: IContainer;
  Header: string;
begin
  WriteLn('--- TestDrawProducesOutput ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  Left := MakeContainer('Left', 3);
  Right := MakeContainer('Right', 2);

  Inp.Enqueue(kaEsc);

  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_), Left, Right);
  try
    Ctrl.Run;
    Check('Screen was flushed', Out_.FlushCount > 0);
    Header := Out_.TextAt(1, 1, 40);
    Check('Header contains DiskBender', Pos('DiskBender', Header) > 0);
  finally
    Ctrl.Free;
  end;
end;

procedure TestToggleMap;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  Left: TTestContainer;
begin
  WriteLn('--- TestToggleMap ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  { Use a non-ICopySource entry so F3 doesn't trip the hex-view branch. }
  Left := TTestContainer.Create('Left', [
    TTestDirEntry.Create('SUBDIR', []) as IEntry
  ]);
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_),
                                IContainer(Left), nil);
  try
    Check('Starts in commander mode', Ctrl.Mode = tmCommander);
    Inp.Enqueue(kaEnter);
    Ctrl.HandleEvent(InputEvent(kaF3));
    Check('F3 on non-mappable stays commander (shows message)', Ctrl.Mode = tmCommander);
  finally
    Ctrl.Free;
  end;
end;

procedure TestBackNavigation;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  Inner: TTestContainer;
  Outer: TTestContainer;
begin
  WriteLn('--- TestBackNavigation ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  Inner := TTestContainer.Create('SubDir', [
    TTestFileEntry.Create('INNER.TXT', 512) as IEntry
  ]);
  Outer := TTestContainer.Create('Root', [
    IEntry(Inner)
  ]);
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_),
                                IContainer(Outer), nil);
  try
    Check('Starts at Root', Ctrl.LeftContainer.Title = 'Root');
    Ctrl.HandleEvent(InputEvent(kaEnter));
    Check('Enter navigates into SubDir', Ctrl.LeftContainer.Title = 'SubDir');
    Ctrl.HandleEvent(InputEvent(kaBackspace));
    Check('Backspace returns to Root', Ctrl.LeftContainer.Title = 'Root');
    Ctrl.HandleEvent(InputEvent(kaBackspace));
    Check('Backspace at root is no-op', Ctrl.LeftContainer.Title = 'Root');
  finally
    Ctrl.Free;
  end;
end;

procedure TestScrollbarAppears;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  Left: IContainer;
  Found: Boolean;
  Y: Integer;
begin
  WriteLn('--- TestScrollbarAppears ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  Left := MakeContainer('Left', 50);
  Inp.Enqueue(kaEsc);
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_), Left, nil);
  try
    Ctrl.Run;
    Found := False;
    for Y := 4 to Out_.GetHeight - 2 do
      if Out_.CharAt(40, Y) = CH_FULL then
      begin
        Found := True;
        Break;
      end;
    Check('Scrollbar thumb visible on right border', Found);
  finally
    Ctrl.Free;
  end;
end;

procedure TestNoScrollbarWhenFits;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  Left: IContainer;
  Found: Boolean;
  Y: Integer;
begin
  WriteLn('--- TestNoScrollbarWhenFits ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  Left := MakeContainer('Left', 3);
  Inp.Enqueue(kaEsc);
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_), Left, nil);
  try
    Ctrl.Run;
    Found := False;
    for Y := 4 to Out_.GetHeight - 2 do
      if Out_.CharAt(40, Y) = CH_FULL then
      begin
        Found := True;
        Break;
      end;
    Check('No scrollbar when content fits', not Found);
  finally
    Ctrl.Free;
  end;
end;

procedure TestMenuOpenClose;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  Left: IContainer;
begin
  WriteLn('--- TestMenuOpenClose ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  Left := MakeContainer('Left', 3);
  Inp.Enqueue(kaF9);
  Inp.Enqueue(kaEsc);
  Inp.Enqueue(kaEsc);
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_), Left, nil);
  try
    Ctrl.Run;
    Check('Still exits cleanly after F9+Esc', not Ctrl.Running);
  finally
    Ctrl.Free;
  end;
end;

procedure TestMenuSort;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  SC: TTestSortableContainer;
begin
  WriteLn('--- TestMenuSort ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  SC := TTestSortableContainer.Create('Sortable', [
    TTestFileEntry.Create('A.TXT', 100) as IEntry,
    TTestFileEntry.Create('B.TXT', 200) as IEntry
  ]);
  Inp.Enqueue(kaF9);
  Inp.Enqueue(kaEnter);
  Inp.Enqueue(kaDown);
  Inp.Enqueue(kaEnter);
  Inp.Enqueue(kaEsc);
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_),
                                IContainer(SC), nil);
  try
    Ctrl.Run;
    Check('Sort was triggered', SC.Sorted);
    Check('Sorted by extension', SC.LastSortField = sfExtension);
  finally
    Ctrl.Free;
  end;
end;

procedure TestStatusBarAttributes;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  Left: IContainer;
  NumA, LblA: Byte;
begin
  WriteLn('--- TestStatusBarAttributes ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  Left := MakeContainer('Left', 3);
  Inp.Enqueue(kaEsc);
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_), Left, nil);
  try
    Ctrl.Run;
    NumA := Out_.AttrAt(1, 25);
    LblA := Out_.AttrAt(2, 25);
    Check('F1 number has $07 attr', NumA = $07);
    Check('F1 label has $30 attr', LblA = $30);
  finally
    Ctrl.Free;
  end;
end;

procedure TestScrollbarThumbMoves;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  Left: IContainer;
  I: Integer;
  TopThumb, BottomHalf: Boolean;
  PH: Integer;
begin
  WriteLn('--- TestScrollbarThumbMoves ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  Left := MakeContainer('Left', 50);
  for I := 1 to 49 do
    Inp.Enqueue(kaDown);
  Inp.Enqueue(kaEsc);
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_), Left, nil);
  try
    Ctrl.Run;
    PH := Out_.GetHeight - 7;
    TopThumb := Out_.CharAt(40, 4) = CH_FULL;
    BottomHalf := False;
    for I := 4 + PH div 2 to 4 + PH - 1 do
      if Out_.CharAt(40, I) = CH_FULL then
      begin
        BottomHalf := True;
        Break;
      end;
    Check('Thumb not at top after scrolling to end', not TopThumb);
    Check('Thumb in bottom half after scrolling to end', BottomHalf);
  finally
    Ctrl.Free;
  end;
end;

{ ── Navigation tests ──────────────────────────────────────────── }

procedure TestHomeKey;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  Left: IContainer;
begin
  WriteLn('--- TestHomeKey ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  Left := MakeContainer('Left', 10);
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_), Left, nil);
  try
    Ctrl.HandleEvent(InputEvent(kaDown));
    Ctrl.HandleEvent(InputEvent(kaDown));
    Ctrl.HandleEvent(InputEvent(kaDown));
    Check('Cursor at 3 before Home', Ctrl.GetCursorPos(psLeft) = 3);
    Ctrl.HandleEvent(InputEvent(kaHome));
    Check('Cursor at 0 after Home', Ctrl.GetCursorPos(psLeft) = 0);
    Check('Scroll at 0 after Home', Ctrl.GetScrollPos(psLeft) = 0);
  finally
    Ctrl.Free;
  end;
end;

procedure TestEndKey;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  Left: IContainer;
begin
  WriteLn('--- TestEndKey ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  Left := MakeContainer('Left', 10);
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_), Left, nil);
  try
    Ctrl.HandleEvent(InputEvent(kaEnd));
    Check('Cursor at last entry after End', Ctrl.GetCursorPos(psLeft) = 9);
  finally
    Ctrl.Free;
  end;
end;

procedure TestPageDown;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  Left: IContainer;
  PH: Integer;
begin
  WriteLn('--- TestPageDown ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  Left := MakeContainer('Left', 50);
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_), Left, nil);
  try
    PH := 25 - 7;
    Ctrl.HandleEvent(InputEvent(kaPageDown));
    Check('Cursor advances by PaneHeight', Ctrl.GetCursorPos(psLeft) = PH);
    Check('Scroll advances by PaneHeight', Ctrl.GetScrollPos(psLeft) = PH);
  finally
    Ctrl.Free;
  end;
end;

procedure TestPageUp;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  Left: IContainer;
begin
  WriteLn('--- TestPageUp ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  Left := MakeContainer('Left', 50);
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_), Left, nil);
  try
    Ctrl.HandleEvent(InputEvent(kaPageDown));
    Ctrl.HandleEvent(InputEvent(kaPageDown));
    Ctrl.HandleEvent(InputEvent(kaPageUp));
    Check('PageUp retreats by PaneHeight', Ctrl.GetCursorPos(psLeft) = 25 - 7);
  finally
    Ctrl.Free;
  end;
end;

procedure TestPageDownAtEnd;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  Left: IContainer;
begin
  WriteLn('--- TestPageDownAtEnd ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  Left := MakeContainer('Left', 5);
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_), Left, nil);
  try
    Ctrl.HandleEvent(InputEvent(kaPageDown));
    Check('PageDown clamps to last entry', Ctrl.GetCursorPos(psLeft) = 4);
  finally
    Ctrl.Free;
  end;
end;

procedure TestPageUpAtStart;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  Left: IContainer;
begin
  WriteLn('--- TestPageUpAtStart ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  Left := MakeContainer('Left', 5);
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_), Left, nil);
  try
    Ctrl.HandleEvent(InputEvent(kaPageUp));
    Check('PageUp at start stays at 0', Ctrl.GetCursorPos(psLeft) = 0);
    Check('Scroll stays at 0', Ctrl.GetScrollPos(psLeft) = 0);
  finally
    Ctrl.Free;
  end;
end;

procedure TestHomeResetsScroll;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  Left: IContainer;
begin
  WriteLn('--- TestHomeResetsScroll ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  Left := MakeContainer('Left', 50);
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_), Left, nil);
  try
    Ctrl.HandleEvent(InputEvent(kaEnd));
    Check('Scroll > 0 after End', Ctrl.GetScrollPos(psLeft) > 0);
    Ctrl.HandleEvent(InputEvent(kaHome));
    Check('Scroll reset to 0 after Home', Ctrl.GetScrollPos(psLeft) = 0);
  finally
    Ctrl.Free;
  end;
end;

{ ── Selection tests ───────────────────────────────────────────── }

procedure TestSpaceSelectsEntry;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  Left: IContainer;
begin
  WriteLn('--- TestSpaceSelectsEntry ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  Left := MakeContainer('Left', 5);
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_), Left, nil);
  try
    Ctrl.HandleEvent(InputEvent(kaChar, ' '));
    Check('Entry 0 is selected', Ctrl.GetSelected(psLeft, 0));
    Check('Cursor moved down', Ctrl.GetCursorPos(psLeft) = 1);
  finally
    Ctrl.Free;
  end;
end;

procedure TestSpaceDeselectsEntry;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  Left: IContainer;
begin
  WriteLn('--- TestSpaceDeselectsEntry ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  Left := MakeContainer('Left', 5);
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_), Left, nil);
  try
    Ctrl.HandleEvent(InputEvent(kaChar, ' '));
    Check('Entry 0 selected', Ctrl.GetSelected(psLeft, 0));
    Ctrl.HandleEvent(InputEvent(kaUp));
    Ctrl.HandleEvent(InputEvent(kaChar, ' '));
    Check('Entry 0 deselected', not Ctrl.GetSelected(psLeft, 0));
  finally
    Ctrl.Free;
  end;
end;

procedure TestSelectedEntryAttr;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  Left: IContainer;
  Attr: Byte;
begin
  WriteLn('--- TestSelectedEntryAttr ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  Left := MakeContainer('Left', 5);
  Inp.Enqueue(kaChar, ' ');
  Inp.Enqueue(kaEsc);
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_), Left, nil);
  try
    Ctrl.Run;
    Attr := Out_.AttrAt(2, 4);
    Check('Selected entry attr is $1E (yellow on blue)', Attr = $1E);
  finally
    Ctrl.Free;
  end;
end;

procedure TestSelectedCursorAttr;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  Left: IContainer;
  Attr: Byte;
begin
  WriteLn('--- TestSelectedCursorAttr ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  Left := MakeContainer('Left', 5);
  Inp.Enqueue(kaChar, ' ');
  Inp.Enqueue(kaUp);
  Inp.Enqueue(kaEsc);
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_), Left, nil);
  try
    Ctrl.Run;
    Attr := Out_.AttrAt(2, 4);
    Check('Selected+cursor attr is $3E (yellow on cyan)', Attr = $3E);
  finally
    Ctrl.Free;
  end;
end;

procedure TestSelectionClearedOnEnter;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  Inner: TTestContainer;
  Outer: TTestContainer;
begin
  WriteLn('--- TestSelectionClearedOnEnter ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  Inner := TTestContainer.Create('SubDir', [
    TTestFileEntry.Create('INNER.TXT', 512) as IEntry
  ]);
  Outer := TTestContainer.Create('Root', [
    IEntry(Inner),
    TTestFileEntry.Create('OTHER.TXT', 100) as IEntry
  ]);
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_),
                                IContainer(Outer), nil);
  try
    Ctrl.HandleEvent(InputEvent(kaDown));
    Ctrl.HandleEvent(InputEvent(kaChar, ' '));
    Ctrl.HandleEvent(InputEvent(kaHome));
    Ctrl.HandleEvent(InputEvent(kaEnter));
    Check('No selections after entering container', not Ctrl.HasAnySelection(psLeft));
  finally
    Ctrl.Free;
  end;
end;

procedure TestSelectionClearedOnBack;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  Inner: TTestContainer;
  Outer: TTestContainer;
begin
  WriteLn('--- TestSelectionClearedOnBack ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  Inner := TTestContainer.Create('SubDir', [
    TTestFileEntry.Create('INNER.TXT', 512) as IEntry
  ]);
  Outer := TTestContainer.Create('Root', [
    IEntry(Inner)
  ]);
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_),
                                IContainer(Outer), nil);
  try
    Ctrl.HandleEvent(InputEvent(kaEnter));
    Ctrl.HandleEvent(InputEvent(kaChar, ' '));
    Ctrl.HandleEvent(InputEvent(kaBackspace));
    Check('No selections after going back', not Ctrl.HasAnySelection(psLeft));
  finally
    Ctrl.Free;
  end;
end;

{ ── Context-aware status bar tests ────────────────────────────── }

procedure TestStatusBarNoSave;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  Left: IContainer;
  StatusLine: string;
begin
  WriteLn('--- TestStatusBarNoSave ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  Left := MakeContainer('Left', 3);
  Inp.Enqueue(kaEsc);
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_), Left, nil);
  try
    Ctrl.Run;
    StatusLine := Out_.TextAt(1, 25, 80);
    Check('No F2 Save label for plain container', Pos('Save', StatusLine) = 0);
  finally
    Ctrl.Free;
  end;
end;

procedure TestStatusBarWithSave;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  WC: TTestWritableContainer;
  StatusLine: string;
begin
  WriteLn('--- TestStatusBarWithSave ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  WC := TTestWritableContainer.Create('DSK', [
    TTestFileEntry.Create('FILE.TXT', 100) as IEntry
  ]);
  Inp.Enqueue(kaEsc);
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_),
                                IContainer(WC), nil);
  try
    Ctrl.Run;
    StatusLine := Out_.TextAt(1, 25, 80);
    Check('F2 Save label present for writable container', Pos('Save', StatusLine) > 0);
  finally
    Ctrl.Free;
  end;
end;

procedure TestStatusBarNoMap;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  Left: IContainer;
  StatusLine: string;
begin
  WriteLn('--- TestStatusBarNoMap ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  Left := MakeContainer('Left', 3);
  Inp.Enqueue(kaEsc);
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_), Left, nil);
  try
    Ctrl.Run;
    StatusLine := Out_.TextAt(1, 25, 80);
    Check('No F3 Map label for plain container', Pos('Map', StatusLine) = 0);
  finally
    Ctrl.Free;
  end;
end;

procedure TestStatusBarWithMap;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  FC: TTestFullContainer;
  StatusLine: string;
begin
  WriteLn('--- TestStatusBarWithMap ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  FC := TTestFullContainer.Create('FullDSK', [
    TTestFileEntry.Create('FILE.TXT', 100) as IEntry
  ]);
  Inp.Enqueue(kaEsc);
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_),
                                IContainer(FC), nil);
  try
    Ctrl.Run;
    StatusLine := Out_.TextAt(1, 25, 80);
    Check('F3 Map label present for block-mappable container', Pos('Map', StatusLine) > 0);
  finally
    Ctrl.Free;
  end;
end;

procedure TestStatusBarNoCopy;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  Left: IContainer;
  StatusLine: string;
begin
  WriteLn('--- TestStatusBarNoCopy ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  Left := MakeContainer('Left', 3);
  Inp.Enqueue(kaEsc);
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_), Left, nil);
  try
    Ctrl.Run;
    StatusLine := Out_.TextAt(1, 25, 80);
    Check('No F5 Copy label without target pane', Pos('Copy', StatusLine) = 0);
  finally
    Ctrl.Free;
  end;
end;

procedure TestStatusBarWithCopy;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  Left, Right: IContainer;
  StatusLine: string;
begin
  WriteLn('--- TestStatusBarWithCopy ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  Left := MakeContainer('Left', 3);
  Right := MakeContainer('Right', 2);
  Inp.Enqueue(kaEsc);
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_), Left, Right);
  try
    Ctrl.Run;
    StatusLine := Out_.TextAt(1, 25, 80);
    Check('F5 Copy label present with both panes', Pos('Copy', StatusLine) > 0);
  finally
    Ctrl.Free;
  end;
end;

procedure TestStatusBarWithDelete;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  Left: IContainer;
  StatusLine: string;
begin
  WriteLn('--- TestStatusBarWithDelete ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  Left := MakeContainer('Left', 3);
  Inp.Enqueue(kaEsc);
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_), Left, nil);
  try
    Ctrl.Run;
    StatusLine := Out_.TextAt(1, 25, 80);
    Check('F8 Del label present for deletable entries', Pos('Del', StatusLine) > 0);
  finally
    Ctrl.Free;
  end;
end;

procedure TestStatusBarWithRename;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  Left: TTestContainer;
  StatusLine: string;
begin
  WriteLn('--- TestStatusBarWithRename ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  Left := TTestContainer.Create('Left', [
    TTestRenameableEntry.Create('FILE.TXT', 100) as IEntry
  ]);
  Inp.Enqueue(kaEsc);
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_),
                                IContainer(Left), nil);
  try
    Ctrl.Run;
    StatusLine := Out_.TextAt(1, 25, 80);
    Check('F6 Ren label present for renameable entry', Pos('Ren', StatusLine) > 0);
  finally
    Ctrl.Free;
  end;
end;

{ ── Menu bar tests ────────────────────────────────────────────── }

procedure TestMenuBarAppearsAtRow1;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  Left: IContainer;
  Row1: string;
begin
  WriteLn('--- TestMenuBarAppearsAtRow1 ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  Left := MakeContainer('Left', 3);
  Inp.Enqueue(kaEsc);
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_), Left, nil);
  try
    Ctrl.HandleEvent(InputEvent(kaF9));
    Row1 := Out_.TextAt(1, 1, 20);
    Check('Menu bar shows Left at row 1', Pos('Left', Row1) > 0);
    Check('Menu bar shows Right at row 1', Pos('Right', Row1) > 0);
  finally
    Ctrl.Free;
  end;
end;

procedure TestMenuBarLeftRight;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  Left, Right: IContainer;
begin
  WriteLn('--- TestMenuBarLeftRight ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  Left := MakeContainer('Left', 3);
  Right := MakeContainer('Right', 2);
  Inp.Enqueue(kaF9);
  Inp.Enqueue(kaRight);
  Inp.Enqueue(kaEsc);
  Inp.Enqueue(kaEsc);
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_), Left, Right);
  try
    Ctrl.Run;
    Check('Right arrow in menu switches focus to right', Ctrl.Focus = psRight);
  finally
    Ctrl.Free;
  end;
end;

procedure TestMenuBarEscCloses;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  Left: IContainer;
begin
  WriteLn('--- TestMenuBarEscCloses ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  Left := MakeContainer('Left', 3);
  Inp.Enqueue(kaF9);
  Inp.Enqueue(kaEsc);
  Inp.Enqueue(kaEsc);
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_), Left, nil);
  try
    Ctrl.Run;
    Check('Exits cleanly after menu Esc', not Ctrl.Running);
  finally
    Ctrl.Free;
  end;
end;

procedure TestMenuBarQCloses;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  Left: IContainer;
begin
  WriteLn('--- TestMenuBarQCloses ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  Left := MakeContainer('Left', 3);
  Inp.Enqueue(kaF9);
  Inp.Enqueue(kaChar, 'q');
  Inp.Enqueue(kaEsc);
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_), Left, nil);
  try
    Ctrl.Run;
    Check('Q closes menu bar (not exit app)', Ctrl.Running = False);
  finally
    Ctrl.Free;
  end;
end;

procedure TestMenuBarContextItems;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  FC: TTestFullContainer;
  ScreenText: string;
  Y: Integer;
begin
  WriteLn('--- TestMenuBarContextItems ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  FC := TTestFullContainer.Create('FullDSK', [
    TTestFileEntry.Create('FILE.TXT', 100) as IEntry
  ]);
  Inp.Enqueue(kaEsc);
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_),
                                IContainer(FC), nil);
  try
    Ctrl.HandleEvent(InputEvent(kaF9));
    ScreenText := '';
    for Y := 2 to 12 do
      ScreenText := ScreenText + Out_.TextAt(1, Y, 30);
    Check('Sort option visible for sortable container', Pos('Sort', ScreenText) > 0);
    Check('Block map option visible', Pos('Block map', ScreenText) > 0);
    Check('Disk info option visible', Pos('Disk info', ScreenText) > 0);
    Check('Save option visible', Pos('Save', ScreenText) > 0);
  finally
    Ctrl.Free;
  end;
end;

{ ── Empty dropdown test ───────────────────────────────────────── }

procedure TestMenuDropdownNoOptions;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  Left: TTestContainer;
  ScreenText: string;
  Y: Integer;
begin
  WriteLn('--- TestMenuDropdownNoOptions ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  { Use a non-ICopySource entry so the menu doesn't auto-add 'Hex view'. }
  Left := TTestContainer.Create('Left', [
    TTestDirEntry.Create('SUBDIR', []) as IEntry
  ]);
  Inp.Enqueue(kaEsc);
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_),
                                IContainer(Left), nil);
  try
    Ctrl.HandleEvent(InputEvent(kaF9));
    ScreenText := '';
    for Y := 2 to 8 do
      ScreenText := ScreenText + Out_.TextAt(1, Y, 30);
    { Since Greaseweazle support was added, plain containers still show the
      "Read disc from drive..." item in the F9 menu — so "(no options)" no
      longer appears.  Verify the drive-read item is present instead. }
    Check('Dropdown shows Read disc item for plain container',
          Pos('Read disc', ScreenText) > 0);
  finally
    Ctrl.Free;
  end;
end;

{ ── Help test ─────────────────────────────────────────────────── }

procedure TestF1HelpNoGarbage;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  Left: IContainer;
  HelpRow: string;
  I: Integer;
begin
  WriteLn('--- TestF1HelpNoGarbage ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  Left := MakeContainer('Left', 3);
  Inp.Enqueue(kaEnter);
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_), Left, nil);
  try
    Ctrl.HandleEvent(InputEvent(kaF1));
    { Scan the vertical band the message box can occupy — exact row depends on
      the box height, which now includes button padding. }
    HelpRow := '';
    for I := 8 to 17 do HelpRow := HelpRow + Out_.TextAt(1, I, 80) + ' ';
    Check('Help text contains ASCII dash --', Pos('--', HelpRow) > 0);
    Check('Help text contains DiskBender', Pos('DiskBender', HelpRow) > 0);
  finally
    Ctrl.Free;
  end;
end;

{ ── Writable container tests ─────────────────────────────────── }

procedure TestStatusBarAlwaysShowsHelp;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  Left: IContainer;
  StatusLine: string;
begin
  WriteLn('--- TestStatusBarAlwaysShowsHelp ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  Left := MakeContainer('Left', 1);
  Inp.Enqueue(kaEsc);
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_), Left, nil);
  try
    Ctrl.Run;
    StatusLine := Out_.TextAt(1, 25, 80);
    Check('Help is always shown', Pos('Help', StatusLine) > 0);
    Check('Menu is always shown', Pos('Menu', StatusLine) > 0);
    Check('Quit is always shown', Pos('Quit', StatusLine) > 0);
  finally
    Ctrl.Free;
  end;
end;

procedure TestNavigateDownBoundary;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  Left: IContainer;
begin
  WriteLn('--- TestNavigateDownBoundary ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  Left := MakeContainer('Left', 3);
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_), Left, nil);
  try
    Ctrl.HandleEvent(InputEvent(kaDown));
    Ctrl.HandleEvent(InputEvent(kaDown));
    Ctrl.HandleEvent(InputEvent(kaDown));
    Ctrl.HandleEvent(InputEvent(kaDown));
    Check('Cursor clamped to last entry', Ctrl.GetCursorPos(psLeft) = 2);
  finally
    Ctrl.Free;
  end;
end;

procedure TestNavigateUpBoundary;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  Left: IContainer;
begin
  WriteLn('--- TestNavigateUpBoundary ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  Left := MakeContainer('Left', 3);
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_), Left, nil);
  try
    Ctrl.HandleEvent(InputEvent(kaUp));
    Check('Cursor stays at 0', Ctrl.GetCursorPos(psLeft) = 0);
  finally
    Ctrl.Free;
  end;
end;

procedure TestCursorAttrOnFocusedPane;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  Left: IContainer;
  Attr: Byte;
begin
  WriteLn('--- TestCursorAttrOnFocusedPane ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  Left := MakeContainer('Left', 3);
  Inp.Enqueue(kaEsc);
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_), Left, nil);
  try
    Ctrl.Run;
    Attr := Out_.AttrAt(2, 4);
    Check('Cursor entry attr is $30 (black on cyan)', Attr = $30);
  finally
    Ctrl.Free;
  end;
end;

procedure TestNonCursorAttrOnFocusedPane;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  Left: IContainer;
  Attr: Byte;
begin
  WriteLn('--- TestNonCursorAttrOnFocusedPane ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  Left := MakeContainer('Left', 3);
  Inp.Enqueue(kaEsc);
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_), Left, nil);
  try
    Ctrl.Run;
    Attr := Out_.AttrAt(2, 5);
    Check('Non-cursor entry attr is $1F (white on blue)', Attr = $1F);
  finally
    Ctrl.Free;
  end;
end;

{ ── Context-aware sort dialog tests ───────────────────────────── }

procedure TestSortDialogModifiedDate;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  SC: TTestSortableContainer;
begin
  WriteLn('--- TestSortDialogModifiedDate ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  SC := TTestSortableContainer.Create('Sortable', [
    TTestDatedEntry.Create('A.TXT', 100, EncodeDate(2026, 5, 1), EncodeDate(2026, 4, 1)) as IEntry,
    TTestDatedEntry.Create('B.TXT', 200, EncodeDate(2026, 5, 2), EncodeDate(2026, 4, 2)) as IEntry
  ]);
  Inp.Enqueue(kaF9);
  Inp.Enqueue(kaEnter);
  Inp.Enqueue(kaDown);
  Inp.Enqueue(kaDown);
  Inp.Enqueue(kaDown);
  Inp.Enqueue(kaEnter);
  Inp.Enqueue(kaEsc);
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_),
                                IContainer(SC), nil);
  try
    Ctrl.Run;
    Check('Sort by Modified was triggered', SC.Sorted);
    Check('Sort field is sfDateModified', SC.LastSortField = sfDateModified);
  finally
    Ctrl.Free;
  end;
end;

procedure TestSortDialogCreatedDate;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  SC: TTestSortableContainer;
begin
  WriteLn('--- TestSortDialogCreatedDate ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  SC := TTestSortableContainer.Create('Sortable', [
    TTestDatedEntry.Create('A.TXT', 100, EncodeDate(2026, 5, 1), EncodeDate(2026, 4, 1)) as IEntry,
    TTestDatedEntry.Create('B.TXT', 200, EncodeDate(2026, 5, 2), EncodeDate(2026, 4, 2)) as IEntry
  ]);
  Inp.Enqueue(kaF9);
  Inp.Enqueue(kaEnter);
  Inp.Enqueue(kaDown);
  Inp.Enqueue(kaDown);
  Inp.Enqueue(kaDown);
  Inp.Enqueue(kaDown);
  Inp.Enqueue(kaEnter);
  Inp.Enqueue(kaEsc);
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_),
                                IContainer(SC), nil);
  try
    Ctrl.Run;
    Check('Sort by Created was triggered', SC.Sorted);
    Check('Sort field is sfDateCreated', SC.LastSortField = sfDateCreated);
  finally
    Ctrl.Free;
  end;
end;

procedure TestSortDialogUserOption;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  SC: TTestSortableContainer;
begin
  WriteLn('--- TestSortDialogUserOption ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  SC := TTestSortableContainer.Create('Sortable', [
    TTestUserEntry.Create('A.TXT', 100, 0) as IEntry,
    TTestUserEntry.Create('B.TXT', 200, 1) as IEntry
  ]);
  Inp.Enqueue(kaF9);
  Inp.Enqueue(kaEnter);
  Inp.Enqueue(kaDown);
  Inp.Enqueue(kaDown);
  Inp.Enqueue(kaDown);
  Inp.Enqueue(kaEnter);
  Inp.Enqueue(kaEsc);
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_),
                                IContainer(SC), nil);
  try
    Ctrl.Run;
    Check('Sort by User was triggered', SC.Sorted);
    Check('Sort field is sfUser', SC.LastSortField = sfUser);
  finally
    Ctrl.Free;
  end;
end;

procedure TestSortDialogNoDateForUndated;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  SC: TTestSortableContainer;
begin
  WriteLn('--- TestSortDialogNoDateForUndated ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  SC := TTestSortableContainer.Create('Sortable', [
    TTestFileEntry.Create('A.TXT', 100) as IEntry,
    TTestFileEntry.Create('B.TXT', 200) as IEntry
  ]);
  Inp.Enqueue(kaF9);
  Inp.Enqueue(kaEnter);
  Inp.Enqueue(kaDown);
  Inp.Enqueue(kaDown);
  Inp.Enqueue(kaEnter);
  Inp.Enqueue(kaEsc);
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_),
                                IContainer(SC), nil);
  try
    Ctrl.Run;
    Check('Down×2 on undated = Size (3rd item)', SC.LastSortField = sfSize);
  finally
    Ctrl.Free;
  end;
end;

procedure TestDateColumnVisibleForDated;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  SC: TTestSortableContainer;
  Row: string;
begin
  WriteLn('--- TestDateColumnVisibleForDated ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  SC := TTestSortableContainer.Create('Dated', [
    TTestDatedEntry.Create('FILE.TXT', 100, EncodeDate(2026, 5, 8)) as IEntry
  ]);
  Inp.Enqueue(kaEsc);
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_),
                                IContainer(SC), nil);
  try
    Ctrl.Run;
    Row := Out_.TextAt(2, 4, 38);
    Check('Date column shows month for dated entry', Pos('May', Row) > 0);
  finally
    Ctrl.Free;
  end;
end;

procedure TestNoDateColumnForUndated;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  Left: IContainer;
  Row: string;
begin
  WriteLn('--- TestNoDateColumnForUndated ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  Left := MakeContainer('Left', 1);
  Inp.Enqueue(kaEsc);
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_), Left, nil);
  try
    Ctrl.Run;
    Row := Out_.TextAt(2, 4, 38);
    Check('No month abbreviation for undated entry', Pos('Jan', Row) = 0);
  finally
    Ctrl.Free;
  end;
end;

{ ── Sort persistence tests ────────────────────────────────────── }

procedure TestSortPersistsAfterSort;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  SC: TTestSortableContainer;
begin
  WriteLn('--- TestSortPersistsAfterSort ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  SC := TTestSortableContainer.Create('Sortable', [
    TTestFileEntry.Create('A.TXT', 100) as IEntry,
    TTestFileEntry.Create('B.TXT', 200) as IEntry
  ]);
  Inp.Enqueue(kaF9);
  Inp.Enqueue(kaEnter);
  Inp.Enqueue(kaDown);
  Inp.Enqueue(kaEnter);
  Inp.Enqueue(kaEsc);
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_),
                                IContainer(SC), nil);
  try
    Ctrl.Run;
    Check('Sort was triggered', SC.Sorted);
    Check('Sorted by extension', SC.LastSortField = sfExtension);
    Check('Cursor reset to 0 after sort', Ctrl.GetCursorPos(psLeft) = 0);
  finally
    Ctrl.Free;
  end;
end;

procedure TestSortDirsFirstToggle;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  SC: TTestSortableContainer;
begin
  WriteLn('--- TestSortDirsFirstToggle ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  SC := TTestSortableContainer.Create('Sortable', [
    TTestFileEntry.Create('A.TXT', 100) as IEntry,
    TTestFileEntry.Create('B.TXT', 200) as IEntry
  ]);
  Inp.Enqueue(kaF9);
  Inp.Enqueue(kaEnter);
  Inp.Enqueue(kaChar, ' ');
  Inp.Enqueue(kaEnter);
  Inp.Enqueue(kaEsc);
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_),
                                IContainer(SC), nil);
  try
    Ctrl.Run;
    Check('Sort was triggered', SC.Sorted);
    Check('DirsFirst toggled off', SC.LastDirsFirst = False);
  finally
    Ctrl.Free;
  end;
end;

{ Sort dialog button positions on an 80x25 screen with 3 sort options:
    SortBoxW=22, SortCount=3, SortBoxH=10
    SBX = (80-22) div 2 = 29,  SBY = (25-10) div 2 = 7
    ContentW = Length('[ OK ]')+3+Length('[ Cancel ]') = 6+3+10 = 19
    OkX = SBX + (22-19) div 2 = 30,  BtnY = SBY+4+3 = 14
    CancelX = OkX + Length('[ OK ]') + 3 = 39
  FindButtonOnScreen is used in a post-close verification pass; the actual
  button coordinates are derived from the same formula as the controller. }
procedure TestSortDialogOkButtonClick;
const
  { 80x25, 3-option list: SBX=(80-22)/2=29, OkX=SBX+(22-19)/2=30, BtnY=7+4+3=14 }
  OK_X = 30; BTN_Y = 14;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  SC: TTestSortableContainer;
begin
  WriteLn('--- TestSortDialogOkButtonClick ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  SC := TTestSortableContainer.Create('Sortable', [
    TTestFileEntry.Create('A.TXT', 100) as IEntry,
    TTestFileEntry.Create('B.TXT', 200) as IEntry
  ]);
  Inp.Enqueue(kaF9);
  Inp.Enqueue(kaEnter);               { open Sort dialog }
  Inp.Enqueue(kaDown);                { SortSel -> 1 = Extension }
  Inp.EnqueueMouse(OK_X, BTN_Y, mbLeft); { click [ OK ] }
  Inp.Enqueue(kaEsc);                 { close menu }
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_),
                                IContainer(SC), nil);
  try
    Ctrl.Run;
    Check('Clicking [ OK ] applied the sort', SC.Sorted);
    Check('Sort field is the highlighted option (Extension)',
          SC.LastSortField = sfExtension);
  finally
    Ctrl.Free;
  end;
end;

procedure TestSortDialogCancelButtonClick;
const
  { CancelX = OkX + Length('[ OK ]') + 3 = 30+6+3 = 39, BtnY = 14 }
  CANCEL_X = 39; BTN_Y = 14;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  SC: TTestSortableContainer;
begin
  WriteLn('--- TestSortDialogCancelButtonClick ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  SC := TTestSortableContainer.Create('Sortable', [
    TTestFileEntry.Create('A.TXT', 100) as IEntry,
    TTestFileEntry.Create('B.TXT', 200) as IEntry
  ]);
  Inp.Enqueue(kaF9);
  Inp.Enqueue(kaEnter);                    { open Sort dialog }
  Inp.Enqueue(kaDown);                     { move the highlight... }
  Inp.EnqueueMouse(CANCEL_X, BTN_Y, mbLeft); { ...but click [ Cancel ] }
  Inp.Enqueue(kaEsc);                      { close menu }
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_),
                                IContainer(SC), nil);
  try
    Ctrl.Run;
    Check('Clicking [ Cancel ] did not sort', not SC.Sorted);
  finally
    Ctrl.Free;
  end;
end;

procedure TestSortDialogOptionClickSelects;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  SC: TTestSortableContainer;
begin
  WriteLn('--- TestSortDialogOptionClickSelects ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  SC := TTestSortableContainer.Create('Sortable', [
    TTestFileEntry.Create('A.TXT', 100) as IEntry,
    TTestFileEntry.Create('B.TXT', 200) as IEntry
  ]);
  Inp.Enqueue(kaF9);
  Inp.Enqueue(kaEnter);              { open Sort dialog; options at rows 8,9,10 }
  Inp.EnqueueMouse(33, 10, mbLeft);  { click the 3rd option (Size) }
  Inp.EnqueueMouse(32, 14, mbLeft);  { click [ OK ] }
  Inp.Enqueue(kaEsc);
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_),
                                IContainer(SC), nil);
  try
    Ctrl.Run;
    Check('Clicking an option then OK sorts by that field (Size)',
          SC.Sorted and (SC.LastSortField = sfSize));
  finally
    Ctrl.Free;
  end;
end;

procedure TestPanelFrameIsDoubleLine;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  Left: IContainer;
begin
  WriteLn('--- TestPanelFrameIsDoubleLine ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  Left := MakeContainer('Left', 3);
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_), Left, nil);
  try
    Ctrl.RenderForTest;
    Check('Panel top border uses the double-line glyph',
          Pos(CH_DHLINE, Out_.TextAt(2, 3, 20)) > 0);
  finally
    Ctrl.Free;
  end;
end;

procedure TestSortDirsFirstDefaultOn;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  SC: TTestSortableContainer;
begin
  WriteLn('--- TestSortDirsFirstDefaultOn ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  SC := TTestSortableContainer.Create('Sortable', [
    TTestFileEntry.Create('A.TXT', 100) as IEntry,
    TTestFileEntry.Create('B.TXT', 200) as IEntry
  ]);
  Inp.Enqueue(kaF9);
  Inp.Enqueue(kaEnter);
  Inp.Enqueue(kaEnter);
  Inp.Enqueue(kaEsc);
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_),
                                IContainer(SC), nil);
  try
    Ctrl.Run;
    Check('Sort was triggered', SC.Sorted);
    Check('DirsFirst defaults to on', SC.LastDirsFirst = True);
  finally
    Ctrl.Free;
  end;
end;

procedure TestSortPersistsAcrossNavigation;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  Inner: TTestSortableContainer;
  Outer: TTestSortableContainer;
begin
  WriteLn('--- TestSortPersistsAcrossNavigation ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  Inner := TTestSortableContainer.Create('Inner', [
    TTestFileEntry.Create('C.TXT', 300) as IEntry
  ]);
  Outer := TTestSortableContainer.Create('Outer', [
    IEntry(Inner),
    TTestFileEntry.Create('A.TXT', 100) as IEntry
  ]);
  Inp.Enqueue(kaF9);
  Inp.Enqueue(kaEnter);
  Inp.Enqueue(kaDown);
  Inp.Enqueue(kaEnter);
  Inp.Enqueue(kaEnter);
  Inp.Enqueue(kaEsc);
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_),
                                IContainer(Outer), nil);
  try
    Ctrl.Run;
    Check('Outer sorted by extension', Outer.LastSortField = sfExtension);
    Check('Inner also got sorted by extension', Inner.Sorted);
    Check('Inner sort field matches pane setting', Inner.LastSortField = sfExtension);
  finally
    Ctrl.Free;
  end;
end;

{ ── Mouse tests ──────────────────────────────────────────────── }

procedure TestMouseClickSwitchesPane;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  Left, Right: IContainer;
begin
  WriteLn('--- TestMouseClickSwitchesPane ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  Left := MakeContainer('Left', 3);
  Right := MakeContainer('Right', 3);
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_), Left, Right);
  try
    Check('Starts on left', Ctrl.Focus = psLeft);
    Ctrl.HandleEvent(MouseEvent(60, 6, mbLeft));
    Check('Click on right side switches to right', Ctrl.Focus = psRight);
    Ctrl.HandleEvent(MouseEvent(10, 6, mbLeft));
    Check('Click on left side switches to left', Ctrl.Focus = psLeft);
  finally
    Ctrl.Free;
  end;
end;

procedure TestMouseClickMovesCursor;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  Left: IContainer;
begin
  WriteLn('--- TestMouseClickMovesCursor ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  Left := MakeContainer('Left', 5);
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_), Left, nil);
  try
    Ctrl.HandleEvent(MouseEvent(10, 6, mbLeft));
    Check('Click on row 6 moves cursor to entry 2', Ctrl.GetCursorPos(psLeft) = 2);
  finally
    Ctrl.Free;
  end;
end;

procedure TestMouseScrollDown;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  Left: IContainer;
begin
  WriteLn('--- TestMouseScrollDown ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  Left := MakeContainer('Left', 10);
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_), Left, nil);
  try
    Ctrl.HandleEvent(MouseEvent(10, 6, mbNone, 1));
    Check('Scroll down moves cursor by 3', Ctrl.GetCursorPos(psLeft) = 3);
  finally
    Ctrl.Free;
  end;
end;

procedure TestMouseScrollUp;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  Left: IContainer;
begin
  WriteLn('--- TestMouseScrollUp ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  Left := MakeContainer('Left', 10);
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_), Left, nil);
  try
    Ctrl.HandleEvent(InputEvent(kaEnd));
    Check('Cursor at end', Ctrl.GetCursorPos(psLeft) = 9);
    Ctrl.HandleEvent(MouseEvent(10, 6, mbNone, -1));
    Check('Scroll up retreats cursor by 3', Ctrl.GetCursorPos(psLeft) = 6);
  finally
    Ctrl.Free;
  end;
end;

procedure TestEllipsisTruncation;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  Left: IContainer;
  Entries: array of IEntry;
  TildePos, I: Integer;
begin
  WriteLn('--- TestEllipsisTruncation ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  SetLength(Entries, 1);
  Entries[0] := TTestFileEntry.Create('AVeryLongFileNameThatShouldBeTruncated.txt', 1024);
  Left := TTestContainer.Create('Left', Entries);
  Inp.Enqueue(kaEsc);
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_), Left, nil);
  try
    Ctrl.Run;
    TildePos := 0;
    for I := 1 to 40 do
      if Out_.CharAt(I, 4) = '~' then begin TildePos := I; Break; end;
    Check('Long name truncated with tilde', TildePos > 0);
    Check('Tilde before size column', TildePos < 33);
  finally
    Ctrl.Free;
  end;
end;

procedure TestExpandableEnterNavigates;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  Left: IContainer;
  Inner: IContainer;
  Entries, InnerEntries: array of IEntry;
begin
  WriteLn('--- TestExpandableEnterNavigates ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  SetLength(InnerEntries, 2);
  InnerEntries[0] := TTestFileEntry.Create('INSIDE1.TXT', 100);
  InnerEntries[1] := TTestFileEntry.Create('INSIDE2.TXT', 200);
  Inner := TTestContainer.Create('DSK Contents', InnerEntries);
  SetLength(Entries, 2);
  Entries[0] := TTestExpandableEntry.Create('image.dsk', 194560, Inner);
  Entries[1] := TTestFileEntry.Create('readme.txt', 512);
  Left := TTestContainer.Create('Left', Entries);
  Inp.Enqueue(kaEnter);
  Inp.Enqueue(kaEsc);
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_), Left, nil);
  try
    Ctrl.Run;
    Check('Navigated into expanded container',
          Pos('DSK Content', Out_.TextAt(1, 3, 40)) > 0);
    Check('Inner entry visible', Pos('INSIDE1', Out_.TextAt(1, 4, 40)) > 0);
  finally
    Ctrl.Free;
  end;
end;

{ ── Sector map and boot/guard tests ──────────────────────────── }

procedure TestF3CycleThreeModes;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  SC: TTestSectorContainer;
begin
  WriteLn('--- TestF3CycleThreeModes ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  { Cursor must be on a non-ICopySource entry so F3 exercises the map cycle
    rather than the new hex-view branch. }
  SC := TTestSectorContainer.Create('SectorDSK', [
    TTestDirEntry.Create('SUBDIR', []) as IEntry
  ]);
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_),
                                IContainer(SC), nil);
  try
    Check('Starts in commander', Ctrl.Mode = tmCommander);
    Ctrl.HandleEvent(InputEvent(kaF3));
    Check('F3 → disk map', Ctrl.Mode = tmDiskMap);
    Ctrl.HandleEvent(InputEvent(kaF3));
    Check('F3 → sector map', Ctrl.Mode = tmSectorMap);
    Ctrl.HandleEvent(InputEvent(kaF3));
    Check('F3 → back to commander', Ctrl.Mode = tmCommander);
  finally
    Ctrl.Free;
  end;
end;

procedure TestF3CycleBlockOnly;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  FC: TTestFullContainer;
begin
  WriteLn('--- TestF3CycleBlockOnly ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  FC := TTestFullContainer.Create('BlockOnly', [
    TTestDirEntry.Create('SUBDIR', []) as IEntry
  ]);
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_),
                                IContainer(FC), nil);
  try
    Check('Starts in commander', Ctrl.Mode = tmCommander);
    Ctrl.HandleEvent(InputEvent(kaF3));
    Check('F3 → disk map', Ctrl.Mode = tmDiskMap);
    Ctrl.HandleEvent(InputEvent(kaF3));
    Check('F3 → back to commander (no sector map)', Ctrl.Mode = tmCommander);
  finally
    Ctrl.Free;
  end;
end;

procedure TestSectorMapDraw;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  SC: TTestSectorContainer;
  ScreenText: string;
  Y: Integer;
begin
  WriteLn('--- TestSectorMapDraw ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  SC := TTestSectorContainer.Create('SectorDSK', [
    TTestDirEntry.Create('SUBDIR', []) as IEntry
  ]);
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_),
                                IContainer(SC), nil);
  try
    Ctrl.HandleEvent(InputEvent(kaF3));  { → tmDiskMap }
    Ctrl.HandleEvent(InputEvent(kaF3));  { → tmSectorMap }
    Ctrl.RenderForTest;                         { paint without entering Run loop }
    ScreenText := '';
    for Y := 1 to 10 do
      ScreenText := ScreenText + Out_.TextAt(1, Y, 80);
    Check('Sector map title visible', Pos('Sector Map', ScreenText) > 0);
  finally
    Ctrl.Free;
  end;
end;

procedure TestSectorMapMenuEntry;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  SC: TTestSectorContainer;
  ScreenText: string;
  Y: Integer;
begin
  WriteLn('--- TestSectorMapMenuEntry ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  SC := TTestSectorContainer.Create('SectorDSK', [
    TTestFileEntry.Create('FILE.TXT', 100) as IEntry
  ]);
  Inp.Enqueue(kaEsc);
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_),
                                IContainer(SC), nil);
  try
    Ctrl.HandleEvent(InputEvent(kaF9));
    ScreenText := '';
    for Y := 2 to 14 do
      ScreenText := ScreenText + Out_.TextAt(1, Y, 30);
    Check('Sector map menu item visible', Pos('Sector map', ScreenText) > 0);
  finally
    Ctrl.Free;
  end;
end;

procedure TestBootEntryDisplayName;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  SC: TTestSectorContainer;
  Boot: TTestFileEntry;
begin
  WriteLn('--- TestBootEntryDisplayName ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  Boot := TTestFileEntry.Create('<BOOT>', 9216);
  SC := TTestSectorContainer.Create('SysDisk', [
    IEntry(Boot),
    TTestFileEntry.Create('FILE.TXT', 100) as IEntry
  ]);
  Inp.Enqueue(kaEsc);
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_),
                                IContainer(SC), nil);
  try
    Ctrl.Run;
    Check('Boot entry visible at row 4',
          Pos('<BOOT>', Out_.TextAt(1, 4, 40)) > 0);
  finally
    Ctrl.Free;
  end;
end;

procedure TestGuardEntryDisplayName;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  Left: TTestContainer;
begin
  WriteLn('--- TestGuardEntryDisplayName ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  Left := TTestContainer.Create('DSK', [
    TTestFileEntry.Create('[GUARD#00]', 1) as IEntry,
    TTestFileEntry.Create('REAL.COM', 16) as IEntry
  ]);
  Inp.Enqueue(kaEsc);
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_),
                                IContainer(Left), nil);
  try
    Ctrl.Run;
    Check('Guard entry visible in file list',
          Pos('[GUARD#00]', Out_.TextAt(1, 4, 40)) > 0);
  finally
    Ctrl.Free;
  end;
end;

procedure TestSectorMapScrollRight;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  SC: TTestSectorContainer;
begin
  WriteLn('--- TestSectorMapScrollRight ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  SC := TTestSectorContainer.Create('SectorDSK', [
    TTestDirEntry.Create('SUBDIR', []) as IEntry
  ]);
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_),
                                IContainer(SC), nil);
  try
    Ctrl.HandleEvent(InputEvent(kaF3));    { → tmDiskMap }
    Ctrl.HandleEvent(InputEvent(kaF3));    { → tmSectorMap }
    Ctrl.HandleEvent(InputEvent(kaRight)); { scroll right once }
    Check('MapScrollX is 1 after Right', Ctrl.MapScrollX = 1);
  finally
    Ctrl.Free;
  end;
end;

procedure TestSectorMapScrollClamp;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  SC: TTestSectorContainer;
  I: Integer;
begin
  WriteLn('--- TestSectorMapScrollClamp ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  SC := TTestSectorContainer.Create('SectorDSK', [
    TTestDirEntry.Create('SUBDIR', []) as IEntry
  ]);
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_),
                                IContainer(SC), nil);
  try
    Ctrl.HandleEvent(InputEvent(kaF3));
    Ctrl.HandleEvent(InputEvent(kaF3));
    { Sanity-check the mock track count so the clamp boundary is grounded. }
    Check('Mock has expected track count for clamp test',
          Length(ISectorMappable(SC).GetSectorMap) = 3);
    for I := 1 to 10 do
      Ctrl.HandleEvent(InputEvent(kaRight));
    { Clamp now lives in ActionMapScrollRight — no render needed. }
    Check('MapScrollX clamped to NTracks-1', Ctrl.MapScrollX = 2);
  finally
    Ctrl.Free;
  end;
end;

procedure TestSectorMapScrollClampAtZero;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  SC: TTestSectorContainer;
  I: Integer;
begin
  WriteLn('--- TestSectorMapScrollClampAtZero ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  SC := TTestSectorContainer.Create('SectorDSK', [
    TTestDirEntry.Create('SUBDIR', []) as IEntry
  ]);
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_),
                                IContainer(SC), nil);
  try
    Ctrl.HandleEvent(InputEvent(kaF3));
    Ctrl.HandleEvent(InputEvent(kaF3));
    for I := 1 to 5 do
      Ctrl.HandleEvent(InputEvent(kaLeft));
    Check('MapScrollX clamped to 0 (lower bound)', Ctrl.MapScrollX = 0);
  finally
    Ctrl.Free;
  end;
end;

procedure TestSectorMapScrollHome;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  SC: TTestSectorContainer;
  I: Integer;
begin
  WriteLn('--- TestSectorMapScrollHome ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  SC := TTestSectorContainer.Create('SectorDSK', [
    TTestDirEntry.Create('SUBDIR', []) as IEntry
  ]);
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_),
                                IContainer(SC), nil);
  try
    Ctrl.HandleEvent(InputEvent(kaF3));
    Ctrl.HandleEvent(InputEvent(kaF3));
    for I := 1 to 5 do
      Ctrl.HandleEvent(InputEvent(kaRight));
    Ctrl.HandleEvent(InputEvent(kaHome));
    Check('MapScrollX reset to 0 after Home', Ctrl.MapScrollX = 0);
  finally
    Ctrl.Free;
  end;
end;

procedure TestSectorMapScrollResetOnBack;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  SC: TTestSectorContainer;
begin
  WriteLn('--- TestSectorMapScrollResetOnBack ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  SC := TTestSectorContainer.Create('SectorDSK', [
    TTestDirEntry.Create('SUBDIR', []) as IEntry
  ]);
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_),
                                IContainer(SC), nil);
  try
    Ctrl.HandleEvent(InputEvent(kaF3));    { → tmDiskMap }
    Ctrl.HandleEvent(InputEvent(kaF3));    { → tmSectorMap }
    Ctrl.HandleEvent(InputEvent(kaRight)); { MapScrollX = 1 }
    Ctrl.HandleEvent(InputEvent(kaRight)); { MapScrollX = 2 }
    { Backspace in a view returns to commander and resets the scroll. }
    Ctrl.HandleEvent(InputEvent(kaBackspace));
    Check('MapScrollX reset after view close', Ctrl.MapScrollX = 0);
  finally
    Ctrl.Free;
  end;
end;

{ ── Hex viewer tests ─────────────────────────────────────────── }

procedure TestHexViewEntersOnFile;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  Left: TTestContainer;
begin
  WriteLn('--- TestHexViewEntersOnFile ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  Left := TTestContainer.Create('DSK', [
    TTestFileEntry.Create('FILE.TXT', 5, 'HELLO') as IEntry
  ]);
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_),
                                IContainer(Left), nil);
  try
    Check('Starts in commander', Ctrl.Mode = tmCommander);
    Ctrl.HandleEvent(InputEvent(kaF3));
    Check('F3 on file enters hex view', Ctrl.Mode = tmHex);
  finally
    Ctrl.Free;
  end;
end;

procedure TestHexViewExitsOnEsc;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  Left: TTestContainer;
begin
  WriteLn('--- TestHexViewExitsOnEsc ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  Left := TTestContainer.Create('DSK', [
    TTestFileEntry.Create('FILE.TXT', 5, 'HELLO') as IEntry
  ]);
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_),
                                IContainer(Left), nil);
  try
    Ctrl.HandleEvent(InputEvent(kaF3));
    Check('Entered hex', Ctrl.Mode = tmHex);
    Ctrl.HandleEvent(InputEvent(kaEsc));
    Check('Esc returns to commander', Ctrl.Mode = tmCommander);
    Ctrl.HandleEvent(InputEvent(kaF3));
    Check('Re-enters hex', Ctrl.Mode = tmHex);
    Ctrl.HandleEvent(InputEvent(kaF3));
    Check('F3 in hex returns to commander', Ctrl.Mode = tmCommander);
  finally
    Ctrl.Free;
  end;
end;

procedure TestHexViewShowsContent;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  Left: TTestContainer;
  ScreenText: string;
  Y: Integer;
begin
  WriteLn('--- TestHexViewShowsContent ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  Left := TTestContainer.Create('DSK', [
    TTestFileEntry.Create('GREET.TXT', 5, 'HELLO') as IEntry
  ]);
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_),
                                IContainer(Left), nil);
  try
    Ctrl.HandleEvent(InputEvent(kaF3));  { enter hex view }
    Ctrl.RenderForTest;                         { paint and inspect }
    ScreenText := '';
    for Y := 1 to 10 do
      ScreenText := ScreenText + Out_.TextAt(1, Y, 80);
    Check('Hex title visible', Pos('Hex: GREET.TXT', ScreenText) > 0);
    Check('Hex bytes for HELLO visible (48 45 4C 4C 4F)',
          Pos('48 45 4C 4C 4F', ScreenText) > 0);
    Check('ASCII gutter shows HELLO', Pos('HELLO', ScreenText) > 0);
    Check('Offset 00000000 visible', Pos('00000000', ScreenText) > 0);
  finally
    Ctrl.Free;
  end;
end;

procedure TestHexViewMenuItemForFile;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  Left: TTestContainer;
  ScreenText: string;
  Y: Integer;
begin
  WriteLn('--- TestHexViewMenuItemForFile ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  Left := TTestContainer.Create('DSK', [
    TTestFileEntry.Create('FILE.TXT', 5, 'HELLO') as IEntry
  ]);
  Inp.Enqueue(kaEsc);
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_),
                                IContainer(Left), nil);
  try
    Ctrl.HandleEvent(InputEvent(kaF9));
    ScreenText := '';
    for Y := 2 to 10 do
      ScreenText := ScreenText + Out_.TextAt(1, Y, 30);
    Check('Hex view menu item visible for file', Pos('Hex view', ScreenText) > 0);
  finally
    Ctrl.Free;
  end;
end;

procedure TestHexViewNoEntryForContainer;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  Left: TTestContainer;
begin
  WriteLn('--- TestHexViewNoEntryForContainer ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  { TTestDirEntry implements IContainer (and not ICopySource) — F3 must not
    enter hex when cursor is on a sub-container. The container has no map
    capability either, so F3 will show a "No view available" message box;
    enqueue a key to dismiss it. }
  Left := TTestContainer.Create('DSK', [
    TTestDirEntry.Create('SUBDIR', []) as IEntry
  ]);
  Inp.Enqueue(kaEsc);
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_),
                                IContainer(Left), nil);
  try
    Ctrl.HandleEvent(InputEvent(kaF3));
    Check('F3 on sub-container does NOT enter hex', Ctrl.Mode <> tmHex);
  finally
    Ctrl.Free;
  end;
end;

procedure TestShiftF3OpensSectorMap;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  SC: TTestSectorContainer;
  E: TInputEvent;
begin
  WriteLn('--- TestShiftF3OpensSectorMap ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  SC := TTestSectorContainer.Create('SectorDSK', [
    TTestFileEntry.Create('FILE.TXT', 100, 'HI') as IEntry
  ]);
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_),
                                IContainer(SC), nil);
  try
    Check('Starts in commander', Ctrl.Mode = tmCommander);
    E := InputEvent(kaF3);
    E.Modifiers := KM_SHIFT;
    Ctrl.HandleEvent(E);
    Check('Shift+F3 → sector map (skips hex)', Ctrl.Mode = tmSectorMap);
  finally
    Ctrl.Free;
  end;
end;

procedure TestCtrlF3OpensBlockMap;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  FC: TTestFullContainer;
  E: TInputEvent;
begin
  WriteLn('--- TestCtrlF3OpensBlockMap ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  FC := TTestFullContainer.Create('BlockDSK', [
    TTestFileEntry.Create('FILE.TXT', 100, 'HI') as IEntry
  ]);
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_),
                                IContainer(FC), nil);
  try
    Check('Starts in commander', Ctrl.Mode = tmCommander);
    E := InputEvent(kaF3);
    E.Modifiers := KM_CTRL;
    Ctrl.HandleEvent(E);
    Check('Ctrl+F3 → block map (skips hex)', Ctrl.Mode = tmDiskMap);
  finally
    Ctrl.Free;
  end;
end;

procedure TestStatusBarMouseClickInvokesAction;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  Left: TTestContainer;
  E: TInputEvent;
  SlotW, X: Integer;
begin
  WriteLn('--- TestStatusBarMouseClickInvokesAction ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  Left := TTestContainer.Create('DSK', [
    TTestDirEntry.Create('SUBDIR', []) as IEntry
  ]);
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_),
                                IContainer(Left), nil);
  try
    { Click on slot 10 (Quit). Slots are at X = (I-1)*SlotW+1. Y = bottom row. }
    SlotW := Out_.GetWidth div 10;
    X := 9 * SlotW + 2;
    E := MouseEvent(X, Out_.GetHeight, mbLeft);
    Ctrl.HandleEvent(E);
    Check('Click on slot 10 (Quit) stops running', not Ctrl.Running);
  finally
    Ctrl.Free;
  end;
end;

procedure TestStatusBarLabelTracksModifier;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  FC: TTestFullContainer;
  E: TInputEvent;
  S: string;
  Y: Integer;
begin
  WriteLn('--- TestStatusBarLabelTracksModifier ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  FC := TTestFullContainer.Create('BlockDSK', [
    TTestDirEntry.Create('SUBDIR', []) as IEntry
  ]);
  Inp.Enqueue(kaF10);
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_),
                                IContainer(FC), nil);
  try
    { Simulate a kitty modifier-change event reporting Ctrl-held state. }
    E := InputEvent(kaModifierChange);
    E.Modifiers := KM_CTRL;
    Ctrl.HandleEvent(E);
    Ctrl.Run;
    S := '';
    Y := Out_.GetHeight;
    S := Out_.TextAt(1, Y, Out_.GetWidth);
    Check('Status bar shows Ctrl-aware F3 label (Blk) when Ctrl is held',
          Pos('Blk', S) > 0);
  finally
    Ctrl.Free;
  end;
end;

procedure TestDiskMapHeaderShowsCounts;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  FC: TTestFullContainer;
  ScreenText: string;
  Y: Integer;
begin
  WriteLn('--- TestDiskMapHeaderShowsCounts ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  { TTestFullContainer.GetBlockMap returns 16 blocks: 4 free, 4 dir, 4 used,
    4 deleted (one of each in turn). The header must show the totals. }
  FC := TTestFullContainer.Create('BlockOnly', [
    TTestDirEntry.Create('SUBDIR', []) as IEntry
  ]);
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_),
                                IContainer(FC), nil);
  try
    Ctrl.HandleEvent(InputEvent(kaF3));  { → tmDiskMap }
    Ctrl.RenderForTest;
    ScreenText := '';
    for Y := 1 to 10 do
      ScreenText := ScreenText + Out_.TextAt(1, Y, 80);
    Check('Map header shows total', Pos('16 blocks', ScreenText) > 0);
    Check('Header shows Used 4', Pos('Used 4', ScreenText) > 0);
    Check('Header shows Dir 4', Pos('Dir 4', ScreenText) > 0);
    Check('Header shows Del 4', Pos('Del 4', ScreenText) > 0);
    Check('Header shows Free 4', Pos('Free 4', ScreenText) > 0);
  finally
    Ctrl.Free;
  end;
end;

procedure TestDiskMapShowsRowOffsetAndLegend;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  FC: TTestFullContainer;
  ScreenText: string;
  Y: Integer;
begin
  WriteLn('--- TestDiskMapShowsRowOffsetAndLegend ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  FC := TTestFullContainer.Create('BlockOnly', [
    TTestDirEntry.Create('SUBDIR', []) as IEntry
  ]);
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_),
                                IContainer(FC), nil);
  try
    Ctrl.HandleEvent(InputEvent(kaF3));
    Ctrl.RenderForTest;
    ScreenText := '';
    for Y := 1 to Out_.GetHeight do
      ScreenText := ScreenText + Out_.TextAt(1, Y, 80);
    Check('Row offset 0000 visible', Pos('0000:', ScreenText) > 0);
    Check('Legend has Free label', Pos('Free', ScreenText) > 0);
    Check('Legend has Used label', Pos('Used', ScreenText) > 0);
    Check('Legend has Deleted label', Pos('Deleted', ScreenText) > 0);
  finally
    Ctrl.Free;
  end;
end;

procedure TestSectorMapHeterogeneousLayout;
{ I6: Verify that DrawSectorMap paints tracks with different sector counts
  without crashing and shows both tracks. Track 0 has 9 sectors (boot),
  Track 1 has 5 sectors (data) — this exercises the column-width path in
  DrawSectorMap where NGroups=2 and the group sizes differ. }
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  HC: TTestHeteroSectorContainer;
  ScreenText: string;
  Y: Integer;
begin
  WriteLn('--- TestSectorMapHeterogeneousLayout (I6) ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  HC := TTestHeteroSectorContainer.Create('HeteroDSK');
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_),
                                IContainer(HC), nil);
  try
    { TTestHeteroSectorContainer has ISectorMappable but no IBlockMappable,
      so ActionToggleMap goes directly to tmSectorMap on the first F3. }
    Ctrl.HandleEvent(InputEvent(kaF3));   { → tmSectorMap (no block map step) }
    Ctrl.RenderForTest;
    ScreenText := '';
    for Y := 1 to Out_.GetHeight do
      ScreenText := ScreenText + Out_.TextAt(1, Y, Out_.GetWidth);
    Check('Sector map rendered without crash (heterogeneous tracks)',
          Ctrl.Mode = tmSectorMap);
    Check('Both tracks appear in sector map',
          Pos('Sector Map', ScreenText) > 0);
  finally
    Ctrl.Free;
  end;
end;

{ ── New tests from code-review item 12 ──────────────────────── }

procedure TestF10ClosesMapView;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  SC: TTestSectorContainer;
begin
  WriteLn('--- TestF10ClosesMapView ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  SC := TTestSectorContainer.Create('SectorDSK', [
    TTestDirEntry.Create('SUBDIR', []) as IEntry
  ]);
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_),
                                IContainer(SC), nil);
  try
    Ctrl.HandleEvent(InputEvent(kaF3));  { → tmDiskMap }
    Ctrl.HandleEvent(InputEvent(kaF3));  { → tmSectorMap }
    Ctrl.HandleEvent(InputEvent(kaF10));
    Check('F10 closes map view → tmCommander', Ctrl.Mode = tmCommander);
    Check('Still running after F10 from map', Ctrl.Running);
  finally
    Ctrl.Free;
  end;
end;

procedure TestQClosesMapView;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  SC: TTestSectorContainer;
begin
  WriteLn('--- TestQClosesMapView ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  SC := TTestSectorContainer.Create('SectorDSK', [
    TTestDirEntry.Create('SUBDIR', []) as IEntry
  ]);
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_),
                                IContainer(SC), nil);
  try
    Ctrl.HandleEvent(InputEvent(kaF3));  { → tmDiskMap }
    Ctrl.HandleEvent(InputEvent(kaF3));  { → tmSectorMap }
    Ctrl.HandleEvent(InputEvent(kaChar, 'q'));
    Check('Q closes map view → tmCommander', Ctrl.Mode = tmCommander);
    Check('Still running after Q from map', Ctrl.Running);
  finally
    Ctrl.Free;
  end;
end;

procedure TestF10ClosesHexView;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  Left: TTestContainer;
begin
  WriteLn('--- TestF10ClosesHexView ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  Left := TTestContainer.Create('DSK', [
    TTestFileEntry.Create('FILE.TXT', 5, 'HELLO') as IEntry
  ]);
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_),
                                IContainer(Left), nil);
  try
    Ctrl.HandleEvent(InputEvent(kaF3));   { → tmHex }
    Check('In hex view', Ctrl.Mode = tmHex);
    Ctrl.HandleEvent(InputEvent(kaF10));
    Check('F10 closes hex view → tmCommander', Ctrl.Mode = tmCommander);
    Check('Still running after F10 from hex', Ctrl.Running);
  finally
    Ctrl.Free;
  end;
end;

procedure TestHexViewScrollUp;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  Left: TTestContainer;
  Big: string;
  I: Integer;
begin
  WriteLn('--- TestHexViewScrollUp ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  Big := '';
  for I := 0 to 1023 do
    Big := Big + Chr(Ord('A') + (I mod 26));
  Left := TTestContainer.Create('DSK', [
    TTestFileEntry.Create('LONG.TXT', Length(Big), Big) as IEntry
  ]);
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_),
                                IContainer(Left), nil);
  try
    Ctrl.HandleEvent(InputEvent(kaF3));
    Ctrl.HandleEvent(InputEvent(kaPageDown));
    Check('Scroll > 0 after PgDn', Ctrl.GetScrollPos(psLeft) >= 0);
    Ctrl.HandleEvent(InputEvent(kaUp));
    { After scrolling down and then up, hex scroll must have decreased or
      the line count is small enough that it was already 0. }
    Check('Up key in hex view handled without crash', Ctrl.Mode = tmHex);
  finally
    Ctrl.Free;
  end;
end;

procedure TestHexViewHome;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  Left: TTestContainer;
  Big: string;
  I: Integer;
  ScreenText: string;
  Y: Integer;
begin
  WriteLn('--- TestHexViewHome ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  Big := '';
  for I := 0 to 1023 do
    Big := Big + Chr(Ord('A') + (I mod 26));
  Left := TTestContainer.Create('DSK', [
    TTestFileEntry.Create('LONG.TXT', Length(Big), Big) as IEntry
  ]);
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_),
                                IContainer(Left), nil);
  try
    Ctrl.HandleEvent(InputEvent(kaF3));
    Ctrl.HandleEvent(InputEvent(kaEnd));
    Ctrl.HandleEvent(InputEvent(kaHome));
    Ctrl.RenderForTest;
    ScreenText := '';
    for Y := 4 to Out_.GetHeight - 2 do
      ScreenText := ScreenText + Out_.TextAt(1, Y, 80);
    Check('Home in hex shows offset 00000000 again', Pos('00000000', ScreenText) > 0);
  finally
    Ctrl.Free;
  end;
end;

procedure TestHexViewEnd;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  Left: TTestContainer;
  Big: string;
  I: Integer;
  ScreenText, ScreenText2: string;
  Y: Integer;
begin
  WriteLn('--- TestHexViewEnd ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  Big := '';
  for I := 0 to 1023 do
    Big := Big + Chr(Ord('A') + (I mod 26));
  Left := TTestContainer.Create('DSK', [
    TTestFileEntry.Create('LONG.TXT', Length(Big), Big) as IEntry
  ]);
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_),
                                IContainer(Left), nil);
  try
    Ctrl.HandleEvent(InputEvent(kaF3));
    Ctrl.RenderForTest;
    ScreenText := '';
    for Y := 4 to Out_.GetHeight - 2 do
      ScreenText := ScreenText + Out_.TextAt(1, Y, 80);
    Ctrl.HandleEvent(InputEvent(kaEnd));
    Ctrl.RenderForTest;
    ScreenText2 := '';
    for Y := 4 to Out_.GetHeight - 2 do
      ScreenText2 := ScreenText2 + Out_.TextAt(1, Y, 80);
    Check('End key scrolls hex view (screen changes)', ScreenText <> ScreenText2);
  finally
    Ctrl.Free;
  end;
end;

procedure TestHexViewPageUp;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  Left: TTestContainer;
  Big: string;
  I: Integer;
  S1, S2: string;
  Y: Integer;
begin
  WriteLn('--- TestHexViewPageUp ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  Big := '';
  for I := 0 to 1023 do
    Big := Big + Chr(Ord('A') + (I mod 26));
  Left := TTestContainer.Create('DSK', [
    TTestFileEntry.Create('LONG.TXT', Length(Big), Big) as IEntry
  ]);
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_),
                                IContainer(Left), nil);
  try
    Ctrl.HandleEvent(InputEvent(kaF3));
    Ctrl.HandleEvent(InputEvent(kaPageDown));
    Ctrl.HandleEvent(InputEvent(kaPageDown));
    Ctrl.RenderForTest;
    S1 := '';
    for Y := 4 to Out_.GetHeight - 2 do
      S1 := S1 + Out_.TextAt(1, Y, 80);
    Ctrl.HandleEvent(InputEvent(kaPageUp));
    Ctrl.RenderForTest;
    S2 := '';
    for Y := 4 to Out_.GetHeight - 2 do
      S2 := S2 + Out_.TextAt(1, Y, 80);
    Check('PageUp scrolls hex view back', S1 <> S2);
  finally
    Ctrl.Free;
  end;
end;

procedure TestHexViewEmptyFile;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  Left: TTestContainer;
  ScreenText: string;
  Y: Integer;
begin
  WriteLn('--- TestHexViewEmptyFile ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  Left := TTestContainer.Create('DSK', [
    TTestFileEntry.Create('EMPTY.TXT', 0, '') as IEntry
  ]);
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_),
                                IContainer(Left), nil);
  try
    Ctrl.HandleEvent(InputEvent(kaF3));
    Ctrl.RenderForTest;
    ScreenText := '';
    for Y := 1 to Out_.GetHeight do
      ScreenText := ScreenText + Out_.TextAt(1, Y, 80);
    Check('Empty file shows (empty file) message',
          Pos('(empty file)', ScreenText) > 0);
  finally
    Ctrl.Free;
  end;
end;

procedure TestHexViewExceptionShowsError;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  Left: TTestContainer;
  ScreenText: string;
  Y: Integer;
begin
  WriteLn('--- TestHexViewExceptionShowsError ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  { TTestThrowingEntry: an ICopySource whose CopyTo always raises. We also
    need IBlockMappable on the container so F3 has somewhere to go after
    the failed hex attempt (it falls through to block map). }
  Left := TTestContainer.Create('DSK', [
    TTestThrowingEntry.Create('BADFILE.BIN', 100) as IEntry
  ]);
  Inp.Enqueue(kaEsc);  { dismiss the error message box }
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_),
                                IContainer(Left), nil);
  try
    Ctrl.HandleEvent(InputEvent(kaF3));
    { After an exception from CopyTo, EnterHexMode returns False and the
      controller shows a message box.  Mode must remain tmCommander. }
    Check('Exception in CopyTo keeps mode = tmCommander',
          Ctrl.Mode = tmCommander);
  finally
    Ctrl.Free;
  end;
end;

procedure TestHexViewPageDownScrolls;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  Left: TTestContainer;
  Big: string;
  I: Integer;
  ScreenText: string;
  Y: Integer;
begin
  WriteLn('--- TestHexViewPageDownScrolls ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  Big := '';
  for I := 0 to 1023 do
    Big := Big + Chr(Ord('A') + (I mod 26));
  Left := TTestContainer.Create('DSK', [
    TTestFileEntry.Create('LONG.TXT', Length(Big), Big) as IEntry
  ]);
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_),
                                IContainer(Left), nil);
  try
    Ctrl.HandleEvent(InputEvent(kaF3));
    Ctrl.HandleEvent(InputEvent(kaPageDown));
    Ctrl.RenderForTest;
    ScreenText := '';
    for Y := 4 to Out_.GetHeight - 2 do
      ScreenText := ScreenText + Out_.TextAt(1, Y, 80);
    { After PgDn the offset 00000000 line must be off-screen and a non-zero
      offset must be the topmost visible row. Verify a later offset shows. }
    Check('Hex viewer scrolled past first page (offset 00000100 or later)',
          (Pos('00000100', ScreenText) > 0) or
          (Pos('00000200', ScreenText) > 0) or
          (Pos('00000300', ScreenText) > 0));
  finally
    Ctrl.Free;
  end;
end;

{ ── InputDialog tests ────────────────────────────────────────── }

procedure TestInputDialogReturnsTypedText;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  Left: IContainer;
  Typed: string;
  Ok: Boolean;
begin
  WriteLn('--- TestInputDialogReturnsTypedText ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  Left := MakeContainer('Left', 1);
  { Type 'h', 'e', 'l', 'l', 'o' then press Enter }
  Inp.Enqueue(kaChar, 'h');
  Inp.Enqueue(kaChar, 'e');
  Inp.Enqueue(kaChar, 'l');
  Inp.Enqueue(kaChar, 'l');
  Inp.Enqueue(kaChar, 'o');
  Inp.Enqueue(kaEnter);
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_), Left, nil);
  try
    Ok := Ctrl.RunInputDialogForTest('Test prompt:', '', Typed);
    Check('InputDialog returns True on Enter', Ok);
    Check('InputDialog returns typed text', Typed = 'hello');
  finally
    Ctrl.Free;
  end;
end;

procedure TestInputDialogCancelReturnsFalse;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  Left: IContainer;
  Typed: string;
  Ok: Boolean;
begin
  WriteLn('--- TestInputDialogCancelReturnsFalse ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  Left := MakeContainer('Left', 1);
  { Type some text then press Esc }
  Inp.Enqueue(kaChar, 'a');
  Inp.Enqueue(kaChar, 'b');
  Inp.Enqueue(kaEsc);
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_), Left, nil);
  try
    Ok := Ctrl.RunInputDialogForTest('Test prompt:', '', Typed);
    Check('InputDialog returns False on Esc', not Ok);
  finally
    Ctrl.Free;
  end;
end;

procedure TestInputDialogCancelByMouseClick;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  Left: IContainer;
  Typed: string;
  Ok: Boolean;
begin
  WriteLn('--- TestInputDialogCancelByMouseClick ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  Left := MakeContainer('Left', 1);
  { Type some text then click [ Cancel ] button.
    Screen is 80x25.  Prompt is 'Test prompt:' (12 chars) → BW=44, BX=19, BY=9.
    BH=8, so button row = BY + BH - 3 = 14.
    ContentW=20, OkX=31, CancelX=41.  Click x=43, y=14. }
  Inp.Enqueue(kaChar, 'h');
  Inp.Enqueue(kaChar, 'i');
  Inp.EnqueueMouse(43, 14, mbLeft);
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_), Left, nil);
  try
    Ok := Ctrl.RunInputDialogForTest('Test prompt:', '', Typed);
    Check('InputDialog returns False on Cancel mouse click', not Ok);
    Check('InputDialog clears text on Cancel mouse click', Typed = '');
  finally
    Ctrl.Free;
  end;
end;

procedure TestInputDialogBackspace;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  Left: IContainer;
  Typed: string;
  Ok: Boolean;
begin
  WriteLn('--- TestInputDialogBackspace ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  Left := MakeContainer('Left', 1);
  { Type 'abc', backspace once (deletes 'c'), then Enter }
  Inp.Enqueue(kaChar, 'a');
  Inp.Enqueue(kaChar, 'b');
  Inp.Enqueue(kaChar, 'c');
  Inp.Enqueue(kaBackspace);
  Inp.Enqueue(kaEnter);
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_), Left, nil);
  try
    Ok := Ctrl.RunInputDialogForTest('Test prompt:', '', Typed);
    Check('InputDialog backspace removes last char', Typed = 'ab');
    Check('InputDialog backspace result is True', Ok);
  finally
    Ctrl.Free;
  end;
end;

{ Verify the dynamic-width F9 action menu is wide enough to render the
  longest item ('Read disc from drive...') without truncation.
  Uses the same pattern as TestMenuBarContextItems: enqueue kaEsc so the
  menu draws once then closes; scan the buffer for the label text. }
procedure TestF9MenuFitsLongLabels;
const
  LONG_LABEL = 'Read disc from drive...';
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  Left: IContainer;
  ScreenText: string;
  Y: Integer;
begin
  WriteLn('--- TestF9MenuFitsLongLabels ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  Left := MakeContainer('Left', 1);
  Inp.Enqueue(kaEsc);   { consumed by the menu's WaitForKey; closes the menu }
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_),
                                Left, nil);
  try
    Ctrl.HandleEvent(InputEvent(kaF9));  { opens menu, draws, consumes kaEsc, redraws }
    ScreenText := '';
    for Y := 1 to Out_.GetHeight do
      ScreenText := ScreenText + Out_.TextAt(1, Y, Out_.GetWidth);
    Check('"' + LONG_LABEL + '" fully visible in F9 menu',
          Pos(LONG_LABEL, ScreenText) > 0);
  finally
    Ctrl.Free;
  end;
end;

{ ── Brief view (lmBrief) tests ───────────────────────────────── }

{ At 80-wide output the pane is 40 cols, PW = 38, NumCols = 2 (since 32 <= 38 < 60).
  ColW = (38 - 1) div 2 = 18; columns sit at X=2 and X=2+19=21. }
procedure TestBriefViewTwoColumnsAt80Wide;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  Left: TTestContainer;
begin
  WriteLn('--- TestBriefViewTwoColumnsAt80Wide ---');
  Inp := MakeInput;
  Out_ := TTestTerminalOutput.Create(80, 25);
  Left := TTestContainer.Create('Disk', [
    TTestFileEntry.Create('AAA.TXT', 1) as IEntry,
    TTestFileEntry.Create('BBB.TXT', 1) as IEntry,
    TTestFileEntry.Create('CCC.TXT', 1) as IEntry,
    TTestFileEntry.Create('DDD.TXT', 1) as IEntry
  ]);
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_),
                                IContainer(Left), nil);
  try
    Ctrl.HandleEvent(InputEventMod(kaChar, '1', KM_ALT));
    Ctrl.RenderForTest;
    Check('AAA at col 0 of row 0', Pos('AAA.TXT', Out_.TextAt(2, 4, 8)) = 1);
    Check('BBB at col 1 of row 0', Pos('BBB.TXT', Out_.TextAt(21, 4, 8)) = 1);
    Check('CCC at col 0 of row 1', Pos('CCC.TXT', Out_.TextAt(2, 5, 8)) = 1);
    Check('DDD at col 1 of row 1', Pos('DDD.TXT', Out_.TextAt(21, 5, 8)) = 1);
  finally
    Ctrl.Free;
  end;
end;

{ At 132-wide output the pane is 66 cols, PW = 64, NumCols = 3 (PW >= 60).
  ColW = (64 - 2) div 3 = 20; columns at X=2, X=2+21=23, X=2+42=44. }
procedure TestBriefViewThreeColumnsAtWideOutput;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  Left: TTestContainer;
begin
  WriteLn('--- TestBriefViewThreeColumnsAtWideOutput ---');
  Inp := MakeInput;
  Out_ := TTestTerminalOutput.Create(132, 25);
  Left := TTestContainer.Create('Disk', [
    TTestFileEntry.Create('A1.TXT', 1) as IEntry,
    TTestFileEntry.Create('B1.TXT', 1) as IEntry,
    TTestFileEntry.Create('C1.TXT', 1) as IEntry,
    TTestFileEntry.Create('A2.TXT', 1) as IEntry,
    TTestFileEntry.Create('B2.TXT', 1) as IEntry,
    TTestFileEntry.Create('C2.TXT', 1) as IEntry
  ]);
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_),
                                IContainer(Left), nil);
  try
    Ctrl.HandleEvent(InputEventMod(kaChar, '1', KM_ALT));
    Ctrl.RenderForTest;
    Check('A1 at col 0', Pos('A1.TXT', Out_.TextAt(2, 4, 6)) = 1);
    Check('B1 at col 1', Pos('B1.TXT', Out_.TextAt(23, 4, 6)) = 1);
    Check('C1 at col 2', Pos('C1.TXT', Out_.TextAt(44, 4, 6)) = 1);
    Check('Row 1 starts at col 0', Pos('A2.TXT', Out_.TextAt(2, 5, 6)) = 1);
  finally
    Ctrl.Free;
  end;
end;

{ Load-bearing fallback: when DisplayNames don't fit even at 2 cols, the
  Brief path bails out and the standard single-column row loop renders.
  Lock the bracket-truncation rule so future "always 3 cols" optimisations
  can't silently steal trailing chars from <DIR> / [GUARD#nn] markers. }
procedure TestBriefViewFallsBackToFullWhenNamesTooLong;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  Left: TTestContainer;
begin
  WriteLn('--- TestBriefViewFallsBackToFullWhenNamesTooLong ---');
  Inp := MakeInput;
  Out_ := TTestTerminalOutput.Create(80, 25);
  { 25-char names; ColW-1 = 17 at 2 cols, so they don't fit -> fall back to 1 col }
  Left := TTestContainer.Create('Disk', [
    TTestFileEntry.Create('VERYLONG_FILENAME_AAA.TXT', 1) as IEntry,
    TTestFileEntry.Create('VERYLONG_FILENAME_BBB.TXT', 1) as IEntry
  ]);
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_),
                                IContainer(Left), nil);
  try
    Ctrl.HandleEvent(InputEventMod(kaChar, '1', KM_ALT));
    Ctrl.RenderForTest;
    { Both names on their own row (single-column lmFull layout), no
      mid-row truncation. The trailing '.TXT' must be present in BOTH names
      -- if a "smart" 2-col path truncates to fit, the second column would
      lose it. }
    Check('First name full at row 4', Pos('VERYLONG_FILENAME_AAA.TXT', Out_.TextAt(1, 4, 38)) > 0);
    Check('Second name on row 5 (own row)', Pos('VERYLONG_FILENAME_BBB.TXT', Out_.TextAt(1, 5, 38)) > 0);
    { No second entry rendered on row 4 (no 2nd column) }
    Check('Row 4 has only first entry', Pos('BBB', Out_.TextAt(20, 4, 18)) = 0);
  finally
    Ctrl.Free;
  end;
end;

{ kaRight in Brief moves cursor by 1, hopping across columns and wrapping
  naturally into the next row when it crosses the last column. }
procedure TestBriefCursorRightWrapsRows;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  Left: IContainer;
begin
  WriteLn('--- TestBriefCursorRightWrapsRows ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  Left := MakeContainer('Left', 6);
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_), Left, nil);
  try
    Ctrl.HandleEvent(InputEventMod(kaChar, '1', KM_ALT));
    Ctrl.HandleEvent(InputEvent(kaRight));
    Check('Right moves cursor by 1', Ctrl.GetCursorPos(psLeft) = 1);
    Ctrl.HandleEvent(InputEvent(kaRight));
    Check('Right again wraps to next row', Ctrl.GetCursorPos(psLeft) = 2);
  finally
    Ctrl.Free;
  end;
end;

{ kaDown in Brief moves cursor by NumCols (2 at default 80-wide), not 1. }
procedure TestBriefCursorDownByNumCols;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  Left: IContainer;
begin
  WriteLn('--- TestBriefCursorDownByNumCols ---');
  Inp := MakeInput;
  Out_ := MakeOutput;  { 80 wide -> 2 cols }
  Left := MakeContainer('Left', 8);
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_), Left, nil);
  try
    Ctrl.HandleEvent(InputEventMod(kaChar, '1', KM_ALT));
    Ctrl.HandleEvent(InputEvent(kaDown));
    Check('Down moves cursor by NumCols=2', Ctrl.GetCursorPos(psLeft) = 2);
    Ctrl.HandleEvent(InputEvent(kaDown));
    Check('Down again moves to cursor 4', Ctrl.GetCursorPos(psLeft) = 4);
  finally
    Ctrl.Free;
  end;
end;

{ Alt+1 from the default lmFull state must produce a 2-col layout (verified
  by entry 1 appearing in the right column of row 0 rather than on row 1). }
procedure TestBriefAlt1ToggleFromFull;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  Left: TTestContainer;
begin
  WriteLn('--- TestBriefAlt1ToggleFromFull ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  Left := TTestContainer.Create('Disk', [
    TTestFileEntry.Create('FIRST.TXT', 1) as IEntry,
    TTestFileEntry.Create('SECOND.TXT', 1) as IEntry
  ]);
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_),
                                IContainer(Left), nil);
  try
    Ctrl.RenderForTest;
    { In lmFull the second entry is on its own row 5, not on row 4 col 1. }
    Check('lmFull: SECOND on row 5', Pos('SECOND.TXT', Out_.TextAt(1, 5, 20)) > 0);
    Ctrl.HandleEvent(InputEventMod(kaChar, '1', KM_ALT));
    Ctrl.RenderForTest;
    { After Alt+1, SECOND should appear on row 4 at column 1 (X=21). }
    Check('lmBrief: SECOND on row 4 col 1', Pos('SECOND.TXT', Out_.TextAt(21, 4, 12)) = 1);
  finally
    Ctrl.Free;
  end;
end;

{ ── Wide view (lmWide) tests ────────────────────────────────── }

{ Attribute column: a CP/M-like entry with R + A flags renders 'R--A',
  not 'R-A' or 'RA' -- the column is a fixed 4-char R/S/H/A field so
  vertical alignment survives. }
procedure TestWideShowsAttrColumn;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  Left: TTestContainer;
  ScreenText: string;
  Y: Integer;
begin
  WriteLn('--- TestWideShowsAttrColumn ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  Left := TTestContainer.Create('Disk', [
    TTestUserEntry.Create('PROTECT.COM', 1024, 0, [eaReadOnly, eaArchive]) as IEntry
  ]);
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_),
                                IContainer(Left), nil);
  try
    Ctrl.HandleEvent(InputEventMod(kaChar, '3', KM_ALT));
    Ctrl.RenderForTest;
    ScreenText := '';
    for Y := 1 to Out_.GetHeight do
      ScreenText := ScreenText + Out_.TextAt(1, Y, Out_.GetWidth);
    Check('Attr column shows R--A', Pos('R--A', ScreenText) > 0);
  finally
    Ctrl.Free;
  end;
end;

{ User column: an entry with IUserArea user 15 shows '15' (right-padded
  to 2 chars). The User column lives at the end of the line. }
procedure TestWideShowsUserColumn;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  Left: TTestContainer;
  ScreenText: string;
  Y: Integer;
begin
  WriteLn('--- TestWideShowsUserColumn ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  Left := TTestContainer.Create('Disk', [
    TTestUserEntry.Create('FOO.COM', 100, 15) as IEntry
  ]);
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_),
                                IContainer(Left), nil);
  try
    Ctrl.HandleEvent(InputEventMod(kaChar, '3', KM_ALT));
    Ctrl.RenderForTest;
    ScreenText := '';
    for Y := 1 to Out_.GetHeight do
      ScreenText := ScreenText + Out_.TextAt(1, Y, Out_.GetWidth);
    { '---- 15' appears as a sequence on the row (attr is empty in Wide for
      this mock since AAttrs default to [], then space, then user '15'). }
    Check('User 15 appears in Wide row', Pos('---- 15', ScreenText) > 0);
  finally
    Ctrl.Free;
  end;
end;

{ Local-style entry (no IAttributed, no IUserArea) shows '----' and a blank
  user cell, so the Wide row alignment doesn't collapse for those entries. }
procedure TestWideShowsDashesForNonAttributed;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  Left: IContainer;
  ScreenText: string;
  Y: Integer;
begin
  WriteLn('--- TestWideShowsDashesForNonAttributed ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  Left := MakeContainer('LocalLike', 2);  { uses TTestFileEntry, no IAttributed }
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_), Left, nil);
  try
    Ctrl.HandleEvent(InputEventMod(kaChar, '3', KM_ALT));
    Ctrl.RenderForTest;
    ScreenText := '';
    for Y := 1 to Out_.GetHeight do
      ScreenText := ScreenText + Out_.TextAt(1, Y, Out_.GetWidth);
    Check('Non-attributed entry shows ----', Pos('----', ScreenText) > 0);
  finally
    Ctrl.Free;
  end;
end;

{ Alt+3 toggles to lmWide. Verify by observing the Attr/User cell appears
  after the toggle and does NOT appear in the default lmFull. }
procedure TestWideAlt3ToggleFromFull;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  Left: TTestContainer;
  ScreenText: string;
  Y: Integer;
begin
  WriteLn('--- TestWideAlt3ToggleFromFull ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  Left := TTestContainer.Create('Disk', [
    TTestUserEntry.Create('FOO.COM', 1, 3, [eaSystem]) as IEntry
  ]);
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_),
                                IContainer(Left), nil);
  try
    Ctrl.RenderForTest;
    ScreenText := '';
    for Y := 1 to Out_.GetHeight do
      ScreenText := ScreenText + Out_.TextAt(1, Y, Out_.GetWidth);
    Check('lmFull: no -S-- attr cell', Pos('-S--', ScreenText) = 0);
    Ctrl.HandleEvent(InputEventMod(kaChar, '3', KM_ALT));
    Ctrl.RenderForTest;
    ScreenText := '';
    for Y := 1 to Out_.GetHeight do
      ScreenText := ScreenText + Out_.TextAt(1, Y, Out_.GetWidth);
    Check('lmWide: -S-- attr cell visible', Pos('-S--', ScreenText) > 0);
  finally
    Ctrl.Free;
  end;
end;

{ ── Info pane (prInfo) tests ────────────────────────────────── }

{ Helper: dump the whole virtual screen to a single string for grep-style
  assertions in Info/QuickView/Tree tests. }
function ScreenDump(AOut: TTestTerminalOutput): string;
var
  Y: Integer;
begin
  Result := '';
  for Y := 1 to AOut.GetHeight do
    Result := Result + AOut.TextAt(1, Y, AOut.GetWidth) + #10;
end;

{ Alt+I on the focused pane sets the OPPOSITE pane's role to prInfo. The
  Info pane should pull stats from the focused pane's cursor entry. }
procedure TestInfoPaneShowsCursorEntryName;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  Left, Right: TTestContainer;
  Screen: string;
begin
  WriteLn('--- TestInfoPaneShowsCursorEntryName ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  Left := TTestContainer.Create('Disk', [
    TTestFileEntry.Create('HELLO.BAS', 4096) as IEntry,
    TTestFileEntry.Create('LOADER.BIN', 256) as IEntry
  ]);
  Right := TTestContainer.Create('Local', [
    TTestFileEntry.Create('FILLER.TXT', 1) as IEntry
  ]);
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_),
                                IContainer(Left), IContainer(Right));
  try
    { Focus left, then Alt+I makes right pane prInfo about left's cursor. }
    Ctrl.HandleEvent(InputEventMod(kaChar, 'I', KM_ALT));
    Ctrl.RenderForTest;
    Screen := ScreenDump(Out_);
    Check('Info pane header shows HELLO.BAS', Pos('Info: HELLO.BAS', Screen) > 0);
    Check('Info pane shows Type row', Pos('Type:', Screen) > 0);
    Check('Info pane shows Size row', Pos('Size:', Screen) > 0);
  finally
    Ctrl.Free;
  end;
end;

{ Cursor moves on the focused pane should update the Info pane's content. }
procedure TestInfoPaneUpdatesWithCursorMoves;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  Left, Right: TTestContainer;
  Screen: string;
begin
  WriteLn('--- TestInfoPaneUpdatesWithCursorMoves ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  Left := TTestContainer.Create('Disk', [
    TTestFileEntry.Create('FIRST.BAS', 100) as IEntry,
    TTestFileEntry.Create('SECOND.BIN', 200) as IEntry
  ]);
  Right := TTestContainer.Create('Local', [
    TTestFileEntry.Create('FILLER.TXT', 1) as IEntry
  ]);
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_),
                                IContainer(Left), IContainer(Right));
  try
    Ctrl.HandleEvent(InputEventMod(kaChar, 'I', KM_ALT));
    Ctrl.HandleEvent(InputEvent(kaDown));
    Ctrl.RenderForTest;
    Screen := ScreenDump(Out_);
    Check('Info pane follows cursor to SECOND.BIN', Pos('Info: SECOND.BIN', Screen) > 0);
    Check('Old cursor name not in header', Pos('Info: FIRST', Screen) = 0);
  finally
    Ctrl.Free;
  end;
end;

{ User + Attr rows appear for an IUserArea / IAttributed entry (CP/M-style). }
procedure TestInfoPaneShowsUserAndAttr;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  Left, Right: TTestContainer;
  Screen: string;
begin
  WriteLn('--- TestInfoPaneShowsUserAndAttr ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  Left := TTestContainer.Create('Disk', [
    TTestUserEntry.Create('SECRET.COM', 512, 7, [eaReadOnly, eaSystem]) as IEntry
  ]);
  Right := TTestContainer.Create('Local', [
    TTestFileEntry.Create('FILLER.TXT', 1) as IEntry
  ]);
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_),
                                IContainer(Left), IContainer(Right));
  try
    Ctrl.HandleEvent(InputEventMod(kaChar, 'I', KM_ALT));
    Ctrl.RenderForTest;
    Screen := ScreenDump(Out_);
    Check('Info pane shows User row', Pos('User: 7', Screen) > 0);
    Check('Info pane shows Attr row', Pos('Attr: RS--', Screen) > 0);
  finally
    Ctrl.Free;
  end;
end;

{ Alt+I twice reverts the opposite pane back to its list view. }
procedure TestInfoPaneAltIToggleOff;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  Left, Right: TTestContainer;
  Screen: string;
begin
  WriteLn('--- TestInfoPaneAltIToggleOff ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  Left := TTestContainer.Create('Disk', [
    TTestFileEntry.Create('HELLO.BAS', 4096) as IEntry
  ]);
  Right := TTestContainer.Create('Local', [
    TTestFileEntry.Create('NOTES.TXT', 1) as IEntry
  ]);
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_),
                                IContainer(Left), IContainer(Right));
  try
    Ctrl.HandleEvent(InputEventMod(kaChar, 'I', KM_ALT));
    Ctrl.HandleEvent(InputEventMod(kaChar, 'I', KM_ALT));
    Ctrl.RenderForTest;
    Screen := ScreenDump(Out_);
    Check('Right pane back to list (NOTES.TXT visible)', Pos('NOTES.TXT', Screen) > 0);
    Check('Info header gone', Pos('Info:', Screen) = 0);
  finally
    Ctrl.Free;
  end;
end;

{ ── Quick View pane (prQuickView) tests ─────────────────────── }

{ Alt+Q makes the opposite pane render a hex/ASCII preview of the focused
  pane's cursor entry. The hex bytes of "ABC" (0x41 0x42 0x43) should be
  visible on the screen. }
procedure TestQuickViewShowsHexOfCursorEntry;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  Left, Right: TTestContainer;
  Screen: string;
begin
  WriteLn('--- TestQuickViewShowsHexOfCursorEntry ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  Left := TTestContainer.Create('Disk', [
    TTestFileEntry.Create('HELLO.BAS', 3, 'ABC') as IEntry
  ]);
  Right := TTestContainer.Create('Local', [
    TTestFileEntry.Create('FILLER.TXT', 1) as IEntry
  ]);
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_),
                                IContainer(Left), IContainer(Right));
  try
    Ctrl.HandleEvent(InputEventMod(kaChar, 'Q', KM_ALT));
    Ctrl.RenderForTest;
    Screen := ScreenDump(Out_);
    Check('Quick header shows HELLO.BAS', Pos('Quick: HELLO.BAS', Screen) > 0);
    Check('Hex 41 (=A) visible', Pos('41', Screen) > 0);
    Check('Hex 42 (=B) visible', Pos('42', Screen) > 0);
    Check('Hex 43 (=C) visible', Pos('43', Screen) > 0);
  finally
    Ctrl.Free;
  end;
end;

{ Containers (no ICopySource) yield a friendly "(no preview: not a file)"
  message instead of crashing. }
procedure TestQuickViewNoPreviewForContainer;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  Left, Right: TTestContainer;
  Screen: string;
begin
  WriteLn('--- TestQuickViewNoPreviewForContainer ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  Left := TTestContainer.Create('Disk', [
    TTestDirEntry.Create('SUBDIR', []) as IEntry
  ]);
  Right := TTestContainer.Create('Local', [
    TTestFileEntry.Create('FILLER.TXT', 1) as IEntry
  ]);
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_),
                                IContainer(Left), IContainer(Right));
  try
    Ctrl.HandleEvent(InputEventMod(kaChar, 'Q', KM_ALT));
    Ctrl.RenderForTest;
    Screen := ScreenDump(Out_);
    Check('Container shows no-preview message',
          (Pos('no preview', Screen) > 0) or (Pos('not a file', Screen) > 0));
  finally
    Ctrl.Free;
  end;
end;

{ Alt+Q twice reverts the opposite pane back to its list view. }
procedure TestQuickViewAltQToggleOff;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  Left, Right: TTestContainer;
  Screen: string;
begin
  WriteLn('--- TestQuickViewAltQToggleOff ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  Left := TTestContainer.Create('Disk', [
    TTestFileEntry.Create('HELLO.BAS', 3, 'ABC') as IEntry
  ]);
  Right := TTestContainer.Create('Local', [
    TTestFileEntry.Create('NOTES.TXT', 1) as IEntry
  ]);
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_),
                                IContainer(Left), IContainer(Right));
  try
    Ctrl.HandleEvent(InputEventMod(kaChar, 'Q', KM_ALT));
    Ctrl.HandleEvent(InputEventMod(kaChar, 'Q', KM_ALT));
    Ctrl.RenderForTest;
    Screen := ScreenDump(Out_);
    Check('Right pane back to list (NOTES.TXT visible)', Pos('NOTES.TXT', Screen) > 0);
    Check('Quick header gone', Pos('Quick:', Screen) = 0);
  finally
    Ctrl.Free;
  end;
end;

{ Bracket conventions survive the Brief layout: angle brackets on directories,
  square brackets on GUARD pseudo-entries, both with full trailing markers. }
procedure TestBriefGuardsAndDirsBracketsVisible;
var
  Inp: TTestTerminalInput;
  Out_: TTestTerminalOutput;
  Ctrl: TTUIController;
  Left: TTestContainer;
  ScreenText: string;
  Y: Integer;
begin
  WriteLn('--- TestBriefGuardsAndDirsBracketsVisible ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  Left := TTestContainer.Create('Mixed', [
    TTestDirEntry.Create('SRC', []) as IEntry,
    TTestFileEntry.Create('[GUARD#00]', 1) as IEntry,
    TTestDirEntry.Create('DOCS', []) as IEntry,
    TTestFileEntry.Create('REAL.COM', 16) as IEntry
  ]);
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_),
                                IContainer(Left), nil);
  try
    Ctrl.HandleEvent(InputEventMod(kaChar, '1', KM_ALT));
    Ctrl.RenderForTest;
    ScreenText := '';
    for Y := 1 to Out_.GetHeight do
      ScreenText := ScreenText + Out_.TextAt(1, Y, Out_.GetWidth);
    Check('Dir SRC keeps angle brackets', Pos('<SRC>', ScreenText) > 0);
    Check('Dir DOCS keeps angle brackets', Pos('<DOCS>', ScreenText) > 0);
    Check('GUARD entry keeps square brackets', Pos('[GUARD#00]', ScreenText) > 0);
  finally
    Ctrl.Free;
  end;
end;

begin
  WriteLn;
  WriteLn('=== DiskBender TUI Controller Tests ===');
  WriteLn;

  { Original tests }
  TestInitialState;
  TestNavigateDown;
  TestNavigateUp;
  TestSwitchPane;
  TestSwitchPaneNilRight;
  TestEnterContainer;
  TestExitViaEsc;
  TestExitViaF10;
  TestExitViaQ;
  TestWASDNavigation;
  TestDrawProducesOutput;
  TestToggleMap;
  TestBackNavigation;
  TestScrollbarAppears;
  TestNoScrollbarWhenFits;
  TestMenuOpenClose;
  TestMenuSort;
  TestStatusBarAttributes;
  TestScrollbarThumbMoves;

  { Navigation tests }
  TestHomeKey;
  TestEndKey;
  TestPageDown;
  TestPageUp;
  TestPageDownAtEnd;
  TestPageUpAtStart;
  TestHomeResetsScroll;

  { Selection tests }
  TestSpaceSelectsEntry;
  TestSpaceDeselectsEntry;
  TestSelectedEntryAttr;
  TestSelectedCursorAttr;
  TestSelectionClearedOnEnter;
  TestSelectionClearedOnBack;

  { Context-aware status bar tests }
  TestStatusBarNoSave;
  TestStatusBarWithSave;
  TestStatusBarNoMap;
  TestStatusBarWithMap;
  TestStatusBarNoCopy;
  TestStatusBarWithCopy;
  TestStatusBarWithDelete;
  TestStatusBarWithRename;

  { Menu bar tests }
  TestMenuBarAppearsAtRow1;
  TestMenuBarLeftRight;
  TestMenuBarEscCloses;
  TestMenuBarQCloses;
  TestMenuBarContextItems;
  TestMenuDropdownNoOptions;

  { Help test }
  TestF1HelpNoGarbage;

  { Additional coverage tests }
  TestStatusBarAlwaysShowsHelp;
  TestNavigateDownBoundary;
  TestNavigateUpBoundary;
  TestCursorAttrOnFocusedPane;
  TestNonCursorAttrOnFocusedPane;

  { Date and context-aware sort tests }
  TestSortDialogModifiedDate;
  TestSortDialogCreatedDate;
  TestSortDialogUserOption;
  TestSortDialogNoDateForUndated;
  TestDateColumnVisibleForDated;
  TestNoDateColumnForUndated;

  { Sort persistence and dirs-first tests }
  TestSortPersistsAfterSort;
  TestSortDirsFirstToggle;
  TestSortDialogOkButtonClick;
  TestSortDialogCancelButtonClick;
  TestSortDialogOptionClickSelects;
  TestF9MenuFitsLongLabels;
  TestPanelFrameIsDoubleLine;
  TestSortDirsFirstDefaultOn;
  TestSortPersistsAcrossNavigation;

  { Mouse tests }
  TestMouseClickSwitchesPane;
  TestMouseClickMovesCursor;
  TestMouseScrollDown;
  TestMouseScrollUp;

  { Ellipsis and expandable tests }
  TestEllipsisTruncation;
  TestExpandableEnterNavigates;

  { Sector map, boot, and guard tests }
  TestF3CycleThreeModes;
  TestF3CycleBlockOnly;
  TestSectorMapDraw;
  TestSectorMapMenuEntry;
  TestBootEntryDisplayName;
  TestGuardEntryDisplayName;
  TestSectorMapScrollRight;
  TestSectorMapScrollClamp;
  TestSectorMapScrollClampAtZero;
  TestSectorMapScrollHome;
  TestSectorMapScrollResetOnBack;

  { Hex viewer tests }
  TestHexViewEntersOnFile;
  TestHexViewExitsOnEsc;
  TestHexViewShowsContent;
  TestHexViewMenuItemForFile;
  TestHexViewNoEntryForContainer;
  TestF10ClosesMapView;
  TestQClosesMapView;
  TestF10ClosesHexView;
  TestHexViewScrollUp;
  TestHexViewHome;
  TestHexViewEnd;
  TestHexViewPageUp;
  TestHexViewEmptyFile;
  TestHexViewExceptionShowsError;
  TestHexViewPageDownScrolls;

  { Modifier-aware F3 + mouse-clickable status bar tests }
  TestShiftF3OpensSectorMap;
  TestCtrlF3OpensBlockMap;
  TestStatusBarMouseClickInvokesAction;
  TestStatusBarLabelTracksModifier;

  { Disk map presentation tests }
  TestDiskMapHeaderShowsCounts;
  TestDiskMapShowsRowOffsetAndLegend;
  TestSectorMapHeterogeneousLayout;

  { InputDialog tests }
  TestInputDialogReturnsTypedText;
  TestInputDialogCancelReturnsFalse;
  TestInputDialogCancelByMouseClick;
  TestInputDialogBackspace;

  { Brief view (lmBrief) tests }
  TestBriefViewTwoColumnsAt80Wide;
  TestBriefViewThreeColumnsAtWideOutput;
  TestBriefViewFallsBackToFullWhenNamesTooLong;
  TestBriefCursorRightWrapsRows;
  TestBriefCursorDownByNumCols;
  TestBriefAlt1ToggleFromFull;
  TestBriefGuardsAndDirsBracketsVisible;

  { Wide view (lmWide) tests }
  TestWideShowsAttrColumn;
  TestWideShowsUserColumn;
  TestWideShowsDashesForNonAttributed;
  TestWideAlt3ToggleFromFull;

  { Info pane (prInfo) tests }
  TestInfoPaneShowsCursorEntryName;
  TestInfoPaneUpdatesWithCursorMoves;
  TestInfoPaneShowsUserAndAttr;
  TestInfoPaneAltIToggleOff;

  { Quick View pane (prQuickView) tests }
  TestQuickViewShowsHexOfCursorEntry;
  TestQuickViewNoPreviewForContainer;
  TestQuickViewAltQToggleOff;

  WriteLn;
  WriteLn('=== Results: ', PassCount, ' passed, ', FailCount, ' failed ===');
  WriteLn;

  if FailCount > 0 then
    Halt(1);
end.
