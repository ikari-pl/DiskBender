program test_tui;

{$mode objfpc}{$H+}

uses
  SysUtils, uTerminalIO, uVFS, uTestTerminal, uTestLocation, uTUIController;

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
    Check('Cursor moved down 3', True);
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
    Check('Navigate up works', True);
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
    Check('WASD navigation works', True);
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
  Left: IContainer;
begin
  WriteLn('--- TestToggleMap ---');
  Inp := MakeInput;
  Out_ := MakeOutput;
  Left := MakeContainer('Left', 3);
  Ctrl := TTUIController.Create(ITerminalInput(Inp), ITerminalOutput(Out_), Left, nil);
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

begin
  WriteLn;
  WriteLn('=== DiskBender TUI Controller Tests ===');
  WriteLn;

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

  WriteLn;
  WriteLn('=== Results: ', PassCount, ' passed, ', FailCount, ' failed ===');
  WriteLn;

  if FailCount > 0 then
    Halt(1);
end.
