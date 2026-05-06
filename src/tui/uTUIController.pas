unit uTUIController;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, uTerminalIO, uVFS;

type
  TPaneSide = (psLeft, psRight);

  TTUIMode = (tmCommander, tmDiskMap);

  TTUIController = class
  strict private
    FInput: ITerminalInput;
    FOutput: ITerminalOutput;
    FLeft: IContainer;
    FRight: IContainer;
    FFocus: TPaneSide;
    FCursors: array[TPaneSide] of Integer;
    FScrolls: array[TPaneSide] of Integer;
    FHistory: array[TPaneSide] of array of IContainer;
    FMode: TTUIMode;
    FRunning: Boolean;

    function ActiveContainer: IContainer;
    function ActiveCursor: Integer;
    function ActiveScroll: Integer;
    procedure SetActiveCursor(V: Integer);
    procedure SetActiveScroll(V: Integer);
    function PaneHeight: Integer;

    { Drawing }
    procedure DrawHeader;
    procedure DrawStatusBar;
    procedure DrawPane(ASide: TPaneSide; X1, X2: Integer);
    procedure DrawPanes;
    procedure DrawDiskMap;
    procedure UpdateScreen;

    { Drawing helpers }
    procedure HLine(X1, X2, Y: Integer; AAttr: Byte);
    procedure VLine(X, Y1, Y2: Integer; AAttr: Byte);
    procedure DrawBox(X1, Y1, X2, Y2: Integer; const ATitle: string; AAttr: Byte);
    procedure FillRect(X1, Y1, X2, Y2: Integer; AAttr: Byte);

    { Entry formatting }
    function FormatEntry(AEntry: IEntry; AWidth: Integer): string;

    { Actions }
    procedure ActionNavigateUp;
    procedure ActionNavigateDown;
    procedure ActionEnter;
    procedure ActionGoBack;
    procedure ActionSwitchPane;
    procedure ActionCopy;
    procedure ActionDelete;
    procedure ActionRename;
    procedure ActionToggleMap;
    procedure ActionSave;
    procedure ActionRevert;
    procedure ActionExit;

    { Dialogs }
    procedure ShowMessage(const AMsg: string);
    function ConfirmDialog(const AMsg: string): Boolean;
  public
    constructor Create(AInput: ITerminalInput; AOutput: ITerminalOutput;
                       ALeft, ARight: IContainer);
    procedure Run;
    procedure HandleEvent(const AEvent: TInputEvent);

    property Running: Boolean read FRunning;
    property Focus: TPaneSide read FFocus;
    property Mode: TTUIMode read FMode;
    property LeftContainer: IContainer read FLeft write FLeft;
    property RightContainer: IContainer read FRight write FRight;
  end;

implementation

{ ── Helpers ──────────────────────────────────────────────────── }

function TTUIController.ActiveContainer: IContainer;
begin
  case FFocus of
    psLeft: Result := FLeft;
    psRight: Result := FRight;
  end;
end;

function TTUIController.ActiveCursor: Integer;
begin
  Result := FCursors[FFocus];
end;

function TTUIController.ActiveScroll: Integer;
begin
  Result := FScrolls[FFocus];
end;

procedure TTUIController.SetActiveCursor(V: Integer);
begin
  FCursors[FFocus] := V;
end;

procedure TTUIController.SetActiveScroll(V: Integer);
begin
  FScrolls[FFocus] := V;
end;

function TTUIController.PaneHeight: Integer;
begin
  Result := FOutput.Height - 7;
  if Result < 1 then Result := 1;
end;

{ ── Drawing Primitives ───────────────────────────────────────── }

procedure TTUIController.HLine(X1, X2, Y: Integer; AAttr: Byte);
begin
  FOutput.PutText(X1, Y, StringOfChar(#196, X2 - X1 + 1), AAttr);
end;

procedure TTUIController.VLine(X, Y1, Y2: Integer; AAttr: Byte);
var
  I: Integer;
begin
  for I := Y1 to Y2 do
    FOutput.PutText(X, I, #179, AAttr);
end;

procedure TTUIController.DrawBox(X1, Y1, X2, Y2: Integer; const ATitle: string; AAttr: Byte);
begin
  HLine(X1 + 1, X2 - 1, Y1, AAttr);
  HLine(X1 + 1, X2 - 1, Y2, AAttr);
  VLine(X1, Y1 + 1, Y2 - 1, AAttr);
  VLine(X2, Y1 + 1, Y2 - 1, AAttr);
  FOutput.PutText(X1, Y1, #218, AAttr);
  FOutput.PutText(X2, Y1, #191, AAttr);
  FOutput.PutText(X1, Y2, #192, AAttr);
  FOutput.PutText(X2, Y2, #217, AAttr);
  if ATitle <> '' then
    FOutput.PutText(X1 + (X2 - X1 - Length(ATitle) - 2) div 2 + 1, Y1,
                    ' ' + ATitle + ' ', AAttr);
end;

procedure TTUIController.FillRect(X1, Y1, X2, Y2: Integer; AAttr: Byte);
var
  Y: Integer;
begin
  for Y := Y1 to Y2 do
    FOutput.PutText(X1, Y, StringOfChar(' ', X2 - X1 + 1), AAttr);
end;

{ ── Entry Formatting ─────────────────────────────────────────── }

function TTUIController.FormatEntry(AEntry: IEntry; AWidth: Integer): string;
var
  Sz: ISizeable;
  Del: IDeletable;
  UA: IUserArea;
  Name: string;
  SizeStr: string;
  Prefix: string;
begin
  Name := AEntry.DisplayName;
  SizeStr := '';
  Prefix := '';

  if Supports(AEntry, ISizeable, Sz) then
  begin
    case Sz.SizeUnit of
      suBytes: SizeStr := IntToStr(Sz.Size);
      suKB: SizeStr := IntToStr(Sz.Size) + 'K';
      suBlocks: SizeStr := IntToStr(Sz.Size) + 'B';
      suRecords: SizeStr := IntToStr(Sz.Size) + 'R';
      suSectors: SizeStr := IntToStr(Sz.Size) + 'S';
    end;
  end;

  if Supports(AEntry, IDeletable, Del) and Del.IsDeleted then
    Prefix := '*';

  if Supports(AEntry, IUserArea, UA) then
    Prefix := Prefix + IntToStr(UA.User) + ':';

  Name := Prefix + Name;

  if AWidth > 10 then
    Result := Format(' %-' + IntToStr(AWidth - 9) + 's %7s ', [Name, SizeStr])
  else
    Result := ' ' + Name;
end;

{ ── Screen Drawing ───────────────────────────────────────────── }

procedure TTUIController.DrawHeader;
var
  S: string;
  W: Integer;
begin
  W := FOutput.Width;
  S := ' DiskBender Commander v0.2 ';
  FOutput.PutText(1, 1, StringOfChar(' ', W), $70);
  FOutput.PutText((W - Length(S)) div 2 + 1, 1, S, $70);
end;

procedure TTUIController.DrawStatusBar;
begin
  FOutput.PutText(1, FOutput.Height,
    ' F2 Save  F3 Map  F5 Copy  F8 Del  F10 Exit  Tab Pane ' +
    StringOfChar(' ', FOutput.Width), $70);
end;

procedure TTUIController.DrawPane(ASide: TPaneSide; X1, X2: Integer);
var
  Cont: IContainer;
  Writable: IWritable;
  BoxAttr, ItemAttr: Byte;
  Title: string;
  Y, I, Idx, MaxVisible: Integer;
  Entry: IEntry;
  LineStr: string;
  PW: Integer;
begin
  Cont := nil;
  case ASide of
    psLeft: Cont := FLeft;
    psRight: Cont := FRight;
  end;

  if FFocus = ASide then BoxAttr := $1F else BoxAttr := $17;
  PW := X2 - X1 - 1;

  if Cont = nil then
  begin
    DrawBox(X1, 3, X2, FOutput.Height - 1, '(empty)', BoxAttr);
    FillRect(X1 + 1, 4, X2 - 1, FOutput.Height - 2, BoxAttr);
    FOutput.PutText(X1 + 2, FOutput.Height div 2, 'No container loaded', $18);
    Exit;
  end;

  Title := Cont.Title;
  if Supports(Cont, IWritable, Writable) and Writable.Modified then
    Title := Title + ' [MOD]';

  DrawBox(X1, 3, X2, FOutput.Height - 1, Title, BoxAttr);
  FillRect(X1 + 1, 4, X2 - 1, FOutput.Height - 2, BoxAttr);

  MaxVisible := PaneHeight;
  for I := 0 to MaxVisible - 1 do
  begin
    Idx := FScrolls[ASide] + I;
    if Idx >= Cont.EntryCount then Break;
    Entry := Cont.GetEntry(Idx);
    if Entry = nil then Continue;
    Y := 4 + I;

    LineStr := FormatEntry(Entry, PW);
    if Length(LineStr) > PW then
      LineStr := Copy(LineStr, 1, PW);
    LineStr := LineStr + StringOfChar(' ', PW - Length(LineStr));

    if (FFocus = ASide) and (Idx = FCursors[ASide]) then
      ItemAttr := $30
    else
      ItemAttr := BoxAttr;

    FOutput.PutText(X1 + 1, Y, LineStr, ItemAttr);
  end;
end;

procedure TTUIController.DrawPanes;
var
  PaneWidth: Integer;
begin
  PaneWidth := FOutput.Width div 2;
  DrawPane(psLeft, 1, PaneWidth);
  DrawPane(psRight, PaneWidth + 1, FOutput.Width);
end;

procedure TTUIController.DrawDiskMap;
var
  Mappable: IBlockMappable;
  Cont: IContainer;
  Map: TBytes;
  I, X, Y, W: Integer;
  Attr: Byte;
begin
  Cont := ActiveContainer;
  DrawBox(1, 3, FOutput.Width, FOutput.Height - 1, ' Allocation Block Map ', $1F);
  FillRect(2, 4, FOutput.Width - 1, FOutput.Height - 2, $1F);

  if (Cont = nil) or not Supports(Cont, IBlockMappable, Mappable) then
  begin
    FOutput.PutText(3, FOutput.Height div 2, 'No block map available.', $18);
    Exit;
  end;

  Map := Mappable.GetBlockMap;
  W := FOutput.Width - 4;

  for I := 0 to Length(Map) - 1 do
  begin
    X := (I mod W) + 3;
    Y := (I div W) + 5;
    if Y >= FOutput.Height - 3 then Break;

    case Map[I] of
      0: Attr := $07;
      1: Attr := $0E;
      2: Attr := $0A;
      3: Attr := $0C;
    else
      Attr := $08;
    end;
    FOutput.PutText(X, Y, #219, Attr);
  end;

  FOutput.PutText(3, FOutput.Height - 2,
    ' [ ] Free  ['#219'] Dir  ['#219'] Used  ['#219'] Deleted ', $07);
end;

procedure TTUIController.UpdateScreen;
begin
  FOutput.Clear;
  DrawHeader;
  if FMode = tmCommander then
    DrawPanes
  else
    DrawDiskMap;
  DrawStatusBar;
  FOutput.Flush;
end;

{ ── Dialogs ──────────────────────────────────────────────────── }

procedure TTUIController.ShowMessage(const AMsg: string);
var
  X, Y: Integer;
begin
  X := (FOutput.Width - Length(AMsg) - 4) div 2;
  Y := FOutput.Height div 2;
  FOutput.PutText(X, Y, '  ' + AMsg + '  ', $4F);
  FOutput.Flush;
  FInput.WaitForKey;
end;

function TTUIController.ConfirmDialog(const AMsg: string): Boolean;
var
  X, Y: Integer;
  E: TInputEvent;
begin
  X := (FOutput.Width - Length(AMsg) - 10) div 2;
  Y := FOutput.Height div 2;
  FOutput.PutText(X, Y, '  ' + AMsg + ' (Y/N)?  ', $4F);
  FOutput.Flush;
  repeat
    E := FInput.WaitForKey;
    if E.Action = kaChar then
    begin
      case UpCase(E.CharValue) of
        'Y': Exit(True);
        'N': Exit(False);
      end;
    end;
  until False;
end;

{ ── Actions ──────────────────────────────────────────────────── }

procedure TTUIController.ActionNavigateUp;
begin
  if ActiveCursor > 0 then
  begin
    SetActiveCursor(ActiveCursor - 1);
    if ActiveCursor < ActiveScroll then
      SetActiveScroll(ActiveCursor);
  end;
end;

procedure TTUIController.ActionNavigateDown;
var
  Cont: IContainer;
begin
  Cont := ActiveContainer;
  if Cont = nil then Exit;
  if ActiveCursor < Cont.EntryCount - 1 then
  begin
    SetActiveCursor(ActiveCursor + 1);
    if ActiveCursor >= ActiveScroll + PaneHeight then
      SetActiveScroll(ActiveScroll + 1);
  end;
end;

procedure TTUIController.ActionEnter;
var
  Cont: IContainer;
  Entry: IEntry;
  SubCont: IContainer;
begin
  Cont := ActiveContainer;
  if Cont = nil then Exit;
  if (ActiveCursor < 0) or (ActiveCursor >= Cont.EntryCount) then Exit;
  Entry := Cont.GetEntry(ActiveCursor);
  if Entry = nil then Exit;

  if Supports(Entry, IContainer, SubCont) then
  begin
    SetLength(FHistory[FFocus], Length(FHistory[FFocus]) + 1);
    FHistory[FFocus][High(FHistory[FFocus])] := ActiveContainer;
    case FFocus of
      psLeft: FLeft := SubCont;
      psRight: FRight := SubCont;
    end;
    SetActiveCursor(0);
    SetActiveScroll(0);
  end;
end;

procedure TTUIController.ActionGoBack;
var
  Prev: IContainer;
  N: Integer;
begin
  N := Length(FHistory[FFocus]);
  if N = 0 then Exit;
  Prev := FHistory[FFocus][N - 1];
  SetLength(FHistory[FFocus], N - 1);
  Prev.Refresh;
  case FFocus of
    psLeft: FLeft := Prev;
    psRight: FRight := Prev;
  end;
  SetActiveCursor(0);
  SetActiveScroll(0);
end;

procedure TTUIController.ActionSwitchPane;
begin
  if FFocus = psLeft then
  begin
    if FRight <> nil then FFocus := psRight;
  end
  else
  begin
    if FLeft <> nil then FFocus := psLeft;
  end;
end;

procedure TTUIController.ActionCopy;
var
  Cont, OtherCont: IContainer;
  Entry: IEntry;
  Src: ICopySource;
  Tgt: ICopyTarget;
begin
  Cont := ActiveContainer;
  if Cont = nil then Exit;
  if (ActiveCursor < 0) or (ActiveCursor >= Cont.EntryCount) then Exit;
  Entry := Cont.GetEntry(ActiveCursor);
  if Entry = nil then Exit;

  case FFocus of
    psLeft: OtherCont := FRight;
    psRight: OtherCont := FLeft;
  end;

  if not Supports(Entry, ICopySource, Src) then
  begin
    ShowMessage('Cannot copy: source does not support extraction.');
    Exit;
  end;
  if (OtherCont = nil) or not Supports(OtherCont, ICopyTarget, Tgt) then
  begin
    ShowMessage('Cannot copy: target does not accept imports.');
    Exit;
  end;

  if ConfirmDialog('Copy ' + Entry.Name + ' to ' + OtherCont.Title) then
  begin
    if Tgt.Import(Src, Entry.Name) then
    begin
      OtherCont.Refresh;
      ShowMessage('Copied successfully.');
    end
    else
      ShowMessage('Copy failed.');
  end;
end;

procedure TTUIController.ActionDelete;
var
  Cont: IContainer;
  Entry: IEntry;
  Del: IDeletable;
  Restorable: IRestorable;
begin
  Cont := ActiveContainer;
  if Cont = nil then Exit;
  if (ActiveCursor < 0) or (ActiveCursor >= Cont.EntryCount) then Exit;
  Entry := Cont.GetEntry(ActiveCursor);
  if Entry = nil then Exit;

  if not Supports(Entry, IDeletable, Del) then
  begin
    ShowMessage('This entry cannot be deleted.');
    Exit;
  end;

  if Del.IsDeleted then
  begin
    if Supports(Entry, IRestorable, Restorable) then
    begin
      Restorable.Restore;
      Cont.Refresh;
    end
    else
      ShowMessage('Cannot restore this entry.');
  end
  else
  begin
    if ConfirmDialog('Delete ' + Entry.Name) then
    begin
      Del.Delete;
      Cont.Refresh;
    end;
  end;
end;

procedure TTUIController.ActionRename;
var
  Cont: IContainer;
  Entry: IEntry;
  Ren: IRenameable;
begin
  Cont := ActiveContainer;
  if Cont = nil then Exit;
  if (ActiveCursor < 0) or (ActiveCursor >= Cont.EntryCount) then Exit;
  Entry := Cont.GetEntry(ActiveCursor);
  if Entry = nil then Exit;

  if not Supports(Entry, IRenameable, Ren) then
    ShowMessage('This entry cannot be renamed.')
  else
    ShowMessage('Rename: not yet implemented in TUI.');
end;

procedure TTUIController.ActionToggleMap;
var
  Cont: IContainer;
begin
  if FMode = tmDiskMap then
  begin
    FMode := tmCommander;
    Exit;
  end;
  Cont := ActiveContainer;
  if (Cont = nil) or not Supports(Cont, IBlockMappable) then
  begin
    ShowMessage('No block map available for this container.');
    Exit;
  end;
  FMode := tmDiskMap;
end;

procedure TTUIController.ActionSave;
var
  Cont: IContainer;
  Writable: IWritable;
begin
  Cont := ActiveContainer;
  if (Cont = nil) or not Supports(Cont, IWritable, Writable) then
  begin
    ShowMessage('Nothing to save.');
    Exit;
  end;
  if Writable.Modified then
  begin
    if ConfirmDialog('Save changes') then
    begin
      Writable.Save;
      ShowMessage('Saved.');
    end;
  end
  else
    ShowMessage('No changes to save.');
end;

procedure TTUIController.ActionRevert;
var
  Cont: IContainer;
  Writable: IWritable;
begin
  Cont := ActiveContainer;
  if (Cont = nil) or not Supports(Cont, IWritable, Writable) then
    Exit;
  if Writable.Modified then
  begin
    if ConfirmDialog('Revert all changes') then
    begin
      Writable.Revert;
      ActiveContainer.Refresh;
      ShowMessage('Changes reverted.');
    end;
  end;
end;

procedure TTUIController.ActionExit;
var
  Writable: IWritable;
  Cont: IContainer;
begin
  Cont := FLeft;
  if (Cont <> nil) and Supports(Cont, IWritable, Writable) and Writable.Modified then
  begin
    if not ConfirmDialog('Left pane has unsaved changes. Exit anyway') then Exit;
  end;
  Cont := FRight;
  if (Cont <> nil) and Supports(Cont, IWritable, Writable) and Writable.Modified then
  begin
    if not ConfirmDialog('Right pane has unsaved changes. Exit anyway') then Exit;
  end;
  FRunning := False;
end;

{ ── Public ───────────────────────────────────────────────────── }

constructor TTUIController.Create(AInput: ITerminalInput; AOutput: ITerminalOutput;
                                  ALeft, ARight: IContainer);
begin
  inherited Create;
  FInput := AInput;
  FOutput := AOutput;
  FLeft := ALeft;
  FRight := ARight;
  if FLeft <> nil then
    FFocus := psLeft
  else
    FFocus := psRight;
  FCursors[psLeft] := 0;
  FCursors[psRight] := 0;
  FScrolls[psLeft] := 0;
  FScrolls[psRight] := 0;
  FMode := tmCommander;
  FRunning := True;
end;

procedure TTUIController.HandleEvent(const AEvent: TInputEvent);
begin
  case AEvent.Action of
    kaUp:        ActionNavigateUp;
    kaDown:      ActionNavigateDown;
    kaEnter:     ActionEnter;
    kaBackspace: ActionGoBack;
    kaTab:       ActionSwitchPane;
    kaEsc:       ActionExit;
    kaF1:        ShowMessage('DiskBender Commander v0.2 — Tab to switch panes, Enter to open');
    kaF2:        ActionSave;
    kaF3:        ActionToggleMap;
    kaF5:        ActionCopy;
    kaF6:        ActionRename;
    kaF8:        ActionDelete;
    kaF9:        ActionRevert;
    kaF10:       ActionExit;
    kaChar:
      case UpCase(AEvent.CharValue) of
        'W': ActionNavigateUp;
        'S': ActionNavigateDown;
        'Q': ActionExit;
        'M': ActionToggleMap;
      end;
  else
    { Ignore unknown keys }
  end;
end;

procedure TTUIController.Run;
var
  E: TInputEvent;
begin
  FOutput.Init;
  try
    while FRunning do
    begin
      UpdateScreen;
      E := FInput.WaitForKey;
      HandleEvent(E);
    end;
  finally
    FOutput.Done;
  end;
end;

end.
