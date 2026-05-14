unit uTUIController;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, DateUtils, uTerminalIO, uVFS, uExternalDrive,
  uExternalDriveAsync, uDSKLocation;

type
  TPaneSide = (psLeft, psRight);

  TTUIMode = (tmCommander, tmDiskMap, tmSectorMap, tmHex);

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
    FSelections: array[TPaneSide] of array of Boolean;
    FMode: TTUIMode;
    FDateKind: array[TPaneSide] of TDateKind;
    FSortField: array[TPaneSide] of TSortField;
    FSortAscending: array[TPaneSide] of Boolean;
    FDirsFirst: array[TPaneSide] of Boolean;
    FRunning: Boolean;
    FMenuOpen: Boolean;
    FNowYear: Word;
    FMapScrollX: Integer;
    FHexData: TBytes;
    FHexLines: array of string;   { Pre-formatted hex+ascii lines; built in EnterHexMode }
    FHexScroll: Integer;
    FHexTitle: string;
    FModifierState: Byte;      { Live modifier state when kitty keyboard protocol active }
    FLastModifierState: Byte;  { Previous modifier state; debounces kaModifierChange redraws }

    function ActiveContainer: IContainer;
    function ActiveCursor: Integer;
    function ActiveScroll: Integer;
    procedure SetActiveCursor(V: Integer);
    procedure SetActiveScroll(V: Integer);
    function PaneHeight: Integer;
    function ContainerForSide(ASide: TPaneSide): IContainer;
    procedure ResetSelections(ASide: TPaneSide);
    procedure EnsureSelections(ASide: TPaneSide);

    { Drawing }
    procedure DrawHeader;
    procedure DrawStatusBar;
    procedure DrawPane(ASide: TPaneSide; X1, X2: Integer);
    procedure DrawPanes;
    procedure DrawDiskMap;
    procedure DrawSectorMap;
    procedure DrawHex;
    function HexRows: Integer;
    function HexLineCount: Integer;
    function EnterHexMode: Boolean;
    procedure UpdateScreen;

    { Drawing helpers }
    procedure HLine(X1, X2, Y: Integer; AAttr: Byte);
    procedure VLine(X, Y1, Y2: Integer; AAttr: Byte);
    procedure DrawBox(X1, Y1, X2, Y2: Integer; const ATitle: string; AAttr: Byte);
    procedure SectionDivider(X1, X2, Y: Integer; AAttr: Byte);
    function DrawButton(X, Y: Integer; const ALabel: string; AFocused: Boolean; AAttr: Byte): Integer;
    function PointInButton(MX, MY, X, Y: Integer; const ALabel: string): Boolean;
    procedure FillRect(X1, Y1, X2, Y2: Integer; AAttr: Byte);
    procedure DrawScrollbar(X, YTop, YBottom, TotalItems, VisibleItems, ScrollOffset: Integer; AAttr: Byte);

    { Entry formatting }
    function FormatEntry(AEntry: IEntry; AWidth: Integer; AShowDate: Boolean; ADateKind: TDateKind): string;

    { Actions }
    procedure ActionNavigateUp;
    procedure ActionNavigateDown;
    procedure ActionHome;
    procedure ActionEnd;
    procedure ActionPageUp;
    procedure ActionPageDown;
    procedure ActionSelect;
    procedure ActionEnter;
    procedure ActionGoBack;
    procedure ActionSwitchPane;
    procedure ActionCopy;
    procedure ActionDelete;
    procedure ActionRename;
    procedure ActionToggleMap;
    procedure ActionShowBlockMap;
    procedure ActionShowSectorMap;
    procedure ActionSave;
    procedure ActionRevert;
    procedure ActionMenu;
    procedure ActionExit;
    procedure ActionMapScrollLeft;
    procedure ActionMapScrollRight;
    procedure ActionMapScrollHome;
    procedure ActionMapScrollEnd;
    procedure ActionHexScrollUp;
    procedure ActionHexScrollDown;
    procedure ActionHexPageUp;
    procedure ActionHexPageDown;
    procedure ActionHexHome;
    procedure ActionHexEnd;
    procedure ReapplySort(ASide: TPaneSide);
    procedure HandleMouse(const AEvent: TInputEvent);
    function StatusBarSlotAt(X: Integer): Integer;
    procedure InvokeStatusBarSlot(Slot: Integer; AModifiers: Byte);

    { Dialogs }
    procedure ShowMessageBox(const AMsg: string);
    function ConfirmDialog(const AMsg: string): Boolean;
    function InputDialog(const APrompt, ADefault: string; out AText: string): Boolean;

    { Drive actions (F9 menu) }
    procedure ActionDriveRead;
    procedure ActionDriveWrite;
    { Returns True on natural completion (WasOk may still be False),
      False if user pressed Esc to cancel. }
    function RunProgressModal(const ATitle: string; ATask: TGwTask): Boolean;
  public
    constructor Create(AInput: ITerminalInput; AOutput: ITerminalOutput;
                       ALeft, ARight: IContainer);
    procedure Run;
    procedure HandleEvent(const AEvent: TInputEvent);
    { Test hook: force a single screen render without entering the input loop.
      The RenderForTest call is idempotent and equivalent to one tick of Run's body.
      Production code paths never need to call this. }
    procedure RenderForTest;

    function GetCursorPos(ASide: TPaneSide): Integer;
    function GetScrollPos(ASide: TPaneSide): Integer;
    function GetSelected(ASide: TPaneSide; AIndex: Integer): Boolean;
    function HasAnySelection(ASide: TPaneSide): Boolean;

    property Running: Boolean read FRunning;
    property Focus: TPaneSide read FFocus;
    property Mode: TTUIMode read FMode;
    property MapScrollX: Integer read FMapScrollX;
    property LeftContainer: IContainer read FLeft write FLeft;
    property RightContainer: IContainer read FRight write FRight;

    { Test hook: exposes InputDialog for unit tests so they can drive it with
      a scripted key queue without going through a menu action. }
    function RunInputDialogForTest(const APrompt, ADefault: string;
                                   out AText: string): Boolean;
  end;

implementation

{ ── Helpers ──────────────────────────────────────────────────── }

function TTUIController.ActiveContainer: IContainer;
begin
  Result := ContainerForSide(FFocus);
end;

function TTUIController.ContainerForSide(ASide: TPaneSide): IContainer;
begin
  case ASide of
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

procedure TTUIController.ResetSelections(ASide: TPaneSide);
begin
  SetLength(FSelections[ASide], 0);
end;

procedure TTUIController.EnsureSelections(ASide: TPaneSide);
var
  Cont: IContainer;
  OldLen, I: Integer;
begin
  Cont := ContainerForSide(ASide);
  if Cont = nil then
  begin
    SetLength(FSelections[ASide], 0);
    Exit;
  end;
  OldLen := Length(FSelections[ASide]);
  if OldLen <> Cont.EntryCount then
  begin
    SetLength(FSelections[ASide], Cont.EntryCount);
    for I := OldLen to Cont.EntryCount - 1 do
      FSelections[ASide][I] := False;
  end;
end;

function TTUIController.GetCursorPos(ASide: TPaneSide): Integer;
begin
  Result := FCursors[ASide];
end;

function TTUIController.GetScrollPos(ASide: TPaneSide): Integer;
begin
  Result := FScrolls[ASide];
end;

function TTUIController.GetSelected(ASide: TPaneSide; AIndex: Integer): Boolean;
begin
  if (AIndex >= 0) and (AIndex < Length(FSelections[ASide])) then
    Result := FSelections[ASide][AIndex]
  else
    Result := False;
end;

function TTUIController.HasAnySelection(ASide: TPaneSide): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 0 to Length(FSelections[ASide]) - 1 do
    if FSelections[ASide][I] then
    begin
      Result := True;
      Exit;
    end;
end;

{ ── Drawing Primitives ───────────────────────────────────────── }

procedure TTUIController.HLine(X1, X2, Y: Integer; AAttr: Byte);
begin
  FOutput.PutText(X1, Y, RepeatUTF8Char(CH_HLINE, X2 - X1 + 1), AAttr);
end;

procedure TTUIController.VLine(X, Y1, Y2: Integer; AAttr: Byte);
var
  I: Integer;
begin
  for I := Y1 to Y2 do
    FOutput.PutText(X, I, CH_VLINE, AAttr);
end;

{ Double-line frame, NC-style. Single-line HLine/VLine remain available for
  dividers *between sections inside* such a frame (use SectionDivider). }
procedure TTUIController.DrawBox(X1, Y1, X2, Y2: Integer; const ATitle: string; AAttr: Byte);
var
  I: Integer;
begin
  FOutput.PutText(X1 + 1, Y1, RepeatUTF8Char(CH_DHLINE, X2 - X1 - 1), AAttr);
  FOutput.PutText(X1 + 1, Y2, RepeatUTF8Char(CH_DHLINE, X2 - X1 - 1), AAttr);
  for I := Y1 + 1 to Y2 - 1 do
  begin
    FOutput.PutText(X1, I, CH_DVLINE, AAttr);
    FOutput.PutText(X2, I, CH_DVLINE, AAttr);
  end;
  FOutput.PutText(X1, Y1, CH_DTLCORNER, AAttr);
  FOutput.PutText(X2, Y1, CH_DTRCORNER, AAttr);
  FOutput.PutText(X1, Y2, CH_DBLCORNER, AAttr);
  FOutput.PutText(X2, Y2, CH_DBRCORNER, AAttr);
  if ATitle <> '' then
    FOutput.PutText(X1 + (X2 - X1 - Length(ATitle) - 2) div 2 + 1, Y1,
                    ' ' + ATitle + ' ', AAttr);
end;

{ A single-line horizontal divider that joins the double-line frame walls at
  X1/X2 with ╟ ╢ junction glyphs. Y is the absolute row of the divider. }
procedure TTUIController.SectionDivider(X1, X2, Y: Integer; AAttr: Byte);
begin
  HLine(X1 + 1, X2 - 1, Y, AAttr);
  FOutput.PutText(X1, Y, CH_DLTEE, AAttr);
  FOutput.PutText(X2, Y, CH_DRTEE, AAttr);
end;

{ Render a clickable button "[ Label ]" at (X,Y); returns the column just past
  it. AFocused inverts the colours so keyboard focus is visible. }
function TTUIController.DrawButton(X, Y: Integer; const ALabel: string;
  AFocused: Boolean; AAttr: Byte): Integer;
var
  S: string;
  A: Byte;
begin
  S := '[ ' + ALabel + ' ]';
  if AFocused then A := (AAttr shl 4) or (AAttr shr 4) else A := AAttr;
  FOutput.PutText(X, Y, S, A);
  Result := X + Length(S);
end;

{ True when (MX,MY) falls on the "[ Label ]" span starting at (X,Y). }
function TTUIController.PointInButton(MX, MY, X, Y: Integer; const ALabel: string): Boolean;
begin
  Result := (MY = Y) and (MX >= X) and (MX < X + Length('[ ' + ALabel + ' ]'));
end;

procedure TTUIController.FillRect(X1, Y1, X2, Y2: Integer; AAttr: Byte);
var
  Y: Integer;
begin
  for Y := Y1 to Y2 do
    FOutput.PutText(X1, Y, StringOfChar(' ', X2 - X1 + 1), AAttr);
end;

procedure TTUIController.DrawScrollbar(X, YTop, YBottom, TotalItems, VisibleItems,
  ScrollOffset: Integer; AAttr: Byte);
var
  TrackH, ThumbH, ScrollRange, TrackRange, ThumbY, Y: Integer;
begin
  if TotalItems <= VisibleItems then Exit;
  TrackH := YBottom - YTop + 1;
  ThumbH := Round(TrackH * VisibleItems / TotalItems);
  if ThumbH < 1 then ThumbH := 1;
  ScrollRange := TotalItems - VisibleItems;
  if ScrollRange < 1 then ScrollRange := 1;
  TrackRange := TrackH - ThumbH;
  ThumbY := YTop + Round(ScrollOffset / ScrollRange * TrackRange);
  if ThumbY + ThumbH - 1 > YBottom then
    ThumbY := YBottom - ThumbH + 1;
  for Y := ThumbY to ThumbY + ThumbH - 1 do
    FOutput.PutText(X, Y, CH_FULL, AAttr);
end;

{ ── Entry Formatting ─────────────────────────────────────────── }

function FormatHumanSize(ASize: Int64): string;
begin
  if ASize < 100000 then
    Result := IntToStr(ASize)
  else if ASize < 1024 * 1024 then
    Result := IntToStr((ASize + 512) div 1024) + 'K'
  else if ASize < Int64(1024) * 1024 * 1024 then
    Result := IntToStr((ASize + 524288) div (1024 * 1024)) + 'M'
  else
    Result := IntToStr(ASize div (Int64(1024) * 1024 * 1024)) + 'G';
end;

function FormatEntryDate(DT: TDateTime; ANowYear: Word): string;
const
  MonthNames: array[1..12] of string = (
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec');
var
  Y, M, D, H, Mi, S, Ms: Word;
begin
  if DT = 0 then begin Result := StringOfChar(' ', 12); Exit; end;
  DecodeDate(DT, Y, M, D);
  DecodeTime(DT, H, Mi, S, Ms);
  if Y = ANowYear then
    Result := Format('%s %2d %2d:%02d', [MonthNames[M], D, H, Mi])
  else
    Result := Format('%s %2d  %4d', [MonthNames[M], D, Y]);
end;

function TTUIController.FormatEntry(AEntry: IEntry; AWidth: Integer;
  AShowDate: Boolean; ADateKind: TDateKind): string;
var
  Sz: ISizeable;
  Del: IDeletable;
  UA: IUserArea;
  Dt: IDated;
  Name, SizeStr, DateStr, Prefix: string;
  DateW, NameW: Integer;
begin
  Name := AEntry.DisplayName;
  SizeStr := '';
  DateStr := '';
  Prefix := '';
  DateW := 0;

  if Supports(AEntry, ISizeable, Sz) then
  begin
    case Sz.SizeUnit of
      suBytes: SizeStr := FormatHumanSize(Sz.Size);
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

  if AShowDate then
    DateW := 13;

  NameW := AWidth - 9 - DateW;
  if (NameW > 1) and (Length(Name) > NameW) then
    Name := Copy(Name, 1, NameW - 1) + '~';

  if AShowDate then
  begin
    if Supports(AEntry, IDated, Dt) and (ADateKind in Dt.GetAvailableDates) then
      DateStr := ' ' + FormatEntryDate(Dt.GetDate(ADateKind), FNowYear)
    else
      DateStr := StringOfChar(' ', DateW);
  end;

  if NameW > 0 then
    Result := Format(' %-' + IntToStr(NameW) + 's %7s', [Name, SizeStr]) + DateStr
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
  if FMenuOpen then Exit;
  S := ' DiskBender Commander v0.2 ';
  FOutput.PutText(1, 1, StringOfChar(' ', W), $70);
  FOutput.PutText((W - Length(S)) div 2 + 1, 1, S, $70);
end;

procedure TTUIController.DrawStatusBar;
const
  NumAttr = $07;
  LblAttr = $30;
  GapAttr = $00;
var
  Labels: array[1..10] of string;
  Cont, OtherCont: IContainer;
  Entry: IEntry;
  SlotW, X, I: Integer;
  NumStr: string;
begin
  for I := 1 to 10 do
    Labels[I] := '';

  Cont := ActiveContainer;
  case FFocus of
    psLeft: OtherCont := FRight;
    psRight: OtherCont := FLeft;
  end;

  Labels[1] := 'Help';
  Labels[10] := 'Quit';
  Labels[9] := 'Menu';

  if (Cont <> nil) and Supports(Cont, IWritable) then
    Labels[2] := 'Save';
  { Slot 3: F3 cycles through Hex view (on a file), Block map, and Sector
    map. While a modifier is held (kitty keyboard protocol only) the label
    short-circuits to the modifier's target view; otherwise we show the
    generic "View/Map" label to signal that F3 is a cycle key. }
  if Cont <> nil then
  begin
    if ((FModifierState and KM_SHIFT) <> 0) and Supports(Cont, ISectorMappable) then
      Labels[3] := 'Sec'
    else if ((FModifierState and KM_CTRL) <> 0) and Supports(Cont, IBlockMappable) then
      Labels[3] := 'Blk'
    else
    begin
      Entry := nil;
      if (FCursors[FFocus] >= 0) and (FCursors[FFocus] < Cont.EntryCount) then
        Entry := Cont.GetEntry(FCursors[FFocus]);
      if (Entry <> nil) and (not Supports(Entry, IContainer)) and
         Supports(Entry, ICopySource) and
         (Supports(Cont, IBlockMappable) or Supports(Cont, ISectorMappable)) then
        Labels[3] := 'Vw/Map'
      else if (Entry <> nil) and (not Supports(Entry, IContainer)) and
              Supports(Entry, ICopySource) then
        Labels[3] := 'View'
      else if Supports(Cont, IBlockMappable) or Supports(Cont, ISectorMappable) then
        Labels[3] := 'Map';
    end;
  end;

  if Cont <> nil then
  begin
    Entry := nil;
    if (FCursors[FFocus] >= 0) and (FCursors[FFocus] < Cont.EntryCount) then
      Entry := Cont.GetEntry(FCursors[FFocus]);
    if (Entry <> nil) and Supports(Entry, ICopySource) and
       (OtherCont <> nil) and Supports(OtherCont, ICopyTarget) then
      Labels[5] := 'Copy';
    if (Entry <> nil) and Supports(Entry, IRenameable) then
      Labels[6] := 'Ren';
    if (Entry <> nil) and Supports(Entry, IDeletable) then
      Labels[8] := 'Del';
  end;

  FOutput.PutText(1, FOutput.Height, StringOfChar(' ', FOutput.Width), GapAttr);
  SlotW := FOutput.Width div 10;
  for I := 1 to 10 do
  begin
    if Labels[I] = '' then Continue;
    X := (I - 1) * SlotW + 1;
    NumStr := IntToStr(I);
    FOutput.PutText(X, FOutput.Height, NumStr, NumAttr);
    FOutput.PutText(X + Length(NumStr), FOutput.Height,
      Copy(Labels[I] + StringOfChar(' ', SlotW), 1, SlotW - Length(NumStr)), LblAttr);
  end;
end;

procedure TTUIController.DrawPane(ASide: TPaneSide; X1, X2: Integer);
var
  Cont: IContainer;
  Writable: IWritable;
  BoxAttr, ItemAttr: Byte;
  Title: string;
  Y, I, Idx, MaxVisible: Integer;
  Entry, SampleEntry: IEntry;
  LineStr: string;
  PW: Integer;
  IsFocused, IsCursor, IsSelected, ShowDate: Boolean;
begin
  Cont := ContainerForSide(ASide);

  if FFocus = ASide then BoxAttr := $1F else BoxAttr := $17;
  PW := X2 - X1 - 1;

  if Cont = nil then
  begin
    DrawBox(X1, 3, X2, FOutput.Height - 1, '(empty)', BoxAttr);
    FillRect(X1 + 1, 4, X2 - 1, FOutput.Height - 2, BoxAttr);
    FOutput.PutText(X1 + 2, FOutput.Height div 2, 'No container loaded', $18);
    Exit;
  end;

  ShowDate := False;
  if Cont.EntryCount > 0 then
  begin
    SampleEntry := Cont.GetEntry(0);
    if (SampleEntry <> nil) and (SampleEntry.GetName = '..') and (Cont.EntryCount > 1) then
      SampleEntry := Cont.GetEntry(1);
    if (SampleEntry <> nil) and Supports(SampleEntry, IDated) then
      ShowDate := True;
  end;

  Title := Cont.Title;
  if Supports(Cont, IWritable, Writable) and Writable.Modified then
    Title := Title + ' [MOD]';

  DrawBox(X1, 3, X2, FOutput.Height - 1, Title, BoxAttr);
  FillRect(X1 + 1, 4, X2 - 1, FOutput.Height - 2, BoxAttr);

  EnsureSelections(ASide);
  IsFocused := (FFocus = ASide);
  MaxVisible := PaneHeight;
  for I := 0 to MaxVisible - 1 do
  begin
    Idx := FScrolls[ASide] + I;
    if Idx >= Cont.EntryCount then Break;
    Entry := Cont.GetEntry(Idx);
    if Entry = nil then Continue;
    Y := 4 + I;

    LineStr := FormatEntry(Entry, PW, ShowDate, FDateKind[ASide]);
    if Length(LineStr) > PW then
      LineStr := Copy(LineStr, 1, PW);
    LineStr := LineStr + StringOfChar(' ', PW - Length(LineStr));

    IsCursor := IsFocused and (Idx = FCursors[ASide]);
    IsSelected := GetSelected(ASide, Idx);

    if IsCursor and IsSelected then
      ItemAttr := $3E
    else if IsCursor then
      ItemAttr := $30
    else if IsSelected and IsFocused then
      ItemAttr := $1E
    else if IsSelected then
      ItemAttr := $16
    else
      ItemAttr := BoxAttr;

    FOutput.PutText(X1 + 1, Y, LineStr, ItemAttr);
  end;

  if Cont.EntryCount > PaneHeight then
    DrawScrollbar(X2, 4, 4 + PaneHeight - 1,
                  Cont.EntryCount, PaneHeight, FScrolls[ASide], BoxAttr);
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
const
  BoxAttr     = $1F;  { white on blue, the panel background }
  DimAttr     = $18;  { dark grey labels }
  AddrAttr    = $1B;  { cyan offset labels }
  HeaderAttr  = $1F;  { white text }
  FreeAttr    = $18;  { dark grey ░ }
  DirAttr     = $1E;  { yellow █ }
  UsedAttr    = $1B;  { cyan █ }
  DelAttr     = $1C;  { red █ }
var
  Mappable: IBlockMappable;
  Cont: IContainer;
  Map: TBytes;
  Total, FreeC, DirC, UsedC, DelC: Integer;
  UsedPct, FreePct: Integer;
  I, X, Y, ColIdx, RowIdx: Integer;
  GroupSize, GroupsPerRow, BlocksPerRow: Integer;
  ContentW, RowsAvail, FirstRowY, FooterY: Integer;
  Ch: string;
  Attr: Byte;
  S, MarginPad: string;
  LegendX: Integer;
  LeftPad: Integer;
begin
  Cont := ActiveContainer;
  DrawBox(1, 3, FOutput.Width, FOutput.Height - 1, ' Block Allocation Map ', BoxAttr);
  FillRect(2, 4, FOutput.Width - 1, FOutput.Height - 2, BoxAttr);

  if (Cont = nil) or not Supports(Cont, IBlockMappable, Mappable) then
  begin
    FOutput.PutText(3, FOutput.Height div 2, 'No block map available.', DimAttr);
    Exit;
  end;

  Map := Mappable.GetBlockMap;
  Total := Length(Map);
  if Total = 0 then
  begin
    FOutput.PutText(3, FOutput.Height div 2, 'Empty block map.', DimAttr);
    Exit;
  end;

  FreeC := 0; DirC := 0; UsedC := 0; DelC := 0;
  for I := 0 to Total - 1 do
    case Map[I] of
      0: Inc(FreeC);
      1: Inc(DirC);
      2: Inc(UsedC);
      3: Inc(DelC);
    end;
  UsedPct := ((UsedC + DirC) * 100) div Total;
  FreePct := 100 - UsedPct;

  { Header: summary counts. Each colored swatch is 2 chars wide so it visually
    matches the 2-char-per-block grid below. }
  S := Format(' %d blocks  ', [Total]);
  FOutput.PutText(3, 4, S, HeaderAttr);
  X := 3 + Length(S);

  FOutput.PutText(X, 4, CH_FULL + CH_FULL, UsedAttr);
  S := Format(' Used %d (%d%%)  ', [UsedC, (UsedC * 100) div Total]);
  FOutput.PutText(X + 2, 4, S, HeaderAttr);
  X := X + 2 + Length(S);

  FOutput.PutText(X, 4, CH_FULL + CH_FULL, DirAttr);
  S := Format(' Dir %d  ', [DirC]);
  FOutput.PutText(X + 2, 4, S, HeaderAttr);
  X := X + 2 + Length(S);

  FOutput.PutText(X, 4, CH_FULL + CH_FULL, DelAttr);
  S := Format(' Del %d  ', [DelC]);
  FOutput.PutText(X + 2, 4, S, HeaderAttr);
  X := X + 2 + Length(S);

  FOutput.PutText(X, 4, CH_SHADE_LIGHT + CH_SHADE_LIGHT, FreeAttr);
  S := Format(' Free %d (%d%%)', [FreeC, FreePct]);
  FOutput.PutText(X + 2, 4, S, HeaderAttr);

  { Layout: each block = 2 chars. Groups of 8 blocks (16 chars) separated by
    2 spaces. Row label is "BBBB:  " = 7 chars; LeftPad is 7. Compute groups
    per row from the available width. }
  LeftPad := 7;
  ContentW := FOutput.Width - 4 - LeftPad;
  GroupSize := 8;
  { Each group uses (GroupSize * 2) chars for blocks + 2 chars separator
    (the separator after the last group is unused). }
  GroupsPerRow := (ContentW + 2) div (GroupSize * 2 + 2);
  if GroupsPerRow < 1 then GroupsPerRow := 1;
  if GroupsPerRow > 6 then GroupsPerRow := 6;
  BlocksPerRow := GroupsPerRow * GroupSize;

  { Column ruler — group-start indices aligned to the first byte of each group }
  for I := 0 to GroupsPerRow - 1 do
  begin
    X := 3 + LeftPad + I * (GroupSize * 2 + 2);
    FOutput.PutText(X, 6, IntToStr(I * GroupSize), DimAttr);
  end;

  { Block grid — two cells per block, groups separated by two spaces }
  FirstRowY := 7;
  FooterY := FOutput.Height - 2;
  RowsAvail := FooterY - 1 - FirstRowY;
  RowIdx := 0;
  while (RowIdx * BlocksPerRow < Total) and (RowIdx < RowsAvail) do
  begin
    Y := FirstRowY + RowIdx;
    FOutput.PutText(3, Y, Format('%4.4d:', [RowIdx * BlocksPerRow]), AddrAttr);
    MarginPad := ' ';
    FOutput.PutText(3 + 5, Y, MarginPad, BoxAttr);

    for ColIdx := 0 to BlocksPerRow - 1 do
    begin
      I := RowIdx * BlocksPerRow + ColIdx;
      if I >= Total then Break;
      X := 3 + LeftPad + (ColIdx * 2) + (ColIdx div GroupSize) * 2;
      case Map[I] of
        0: begin Ch := CH_SHADE_LIGHT + CH_SHADE_LIGHT; Attr := FreeAttr; end;
        1: begin Ch := CH_FULL + CH_FULL;               Attr := DirAttr; end;
        2: begin Ch := CH_FULL + CH_FULL;               Attr := UsedAttr; end;
        3: begin Ch := CH_FULL + CH_FULL;               Attr := DelAttr; end;
      else
        begin Ch := '??';                                Attr := HeaderAttr; end;
      end;
      FOutput.PutText(X, Y, Ch, Attr);
    end;
    Inc(RowIdx);
  end;

  { If the map didn't fit, hint at truncation }
  if RowIdx * BlocksPerRow < Total then
    FOutput.PutText(3, FooterY - 1,
      Format('... %d blocks beyond visible area', [Total - RowIdx * BlocksPerRow]),
      DimAttr);

  { Legend at bottom — 2-char colored swatches with labels }
  LegendX := 3;
  FOutput.PutText(LegendX, FooterY, CH_SHADE_LIGHT + CH_SHADE_LIGHT, FreeAttr);
  FOutput.PutText(LegendX + 2, FooterY, ' Free    ', HeaderAttr);
  LegendX := LegendX + 11;
  FOutput.PutText(LegendX, FooterY, CH_FULL + CH_FULL, DirAttr);
  FOutput.PutText(LegendX + 2, FooterY, ' Dir     ', HeaderAttr);
  LegendX := LegendX + 11;
  FOutput.PutText(LegendX, FooterY, CH_FULL + CH_FULL, UsedAttr);
  FOutput.PutText(LegendX + 2, FooterY, ' Used    ', HeaderAttr);
  LegendX := LegendX + 11;
  FOutput.PutText(LegendX, FooterY, CH_FULL + CH_FULL, DelAttr);
  FOutput.PutText(LegendX + 2, FooterY, ' Deleted', HeaderAttr);
end;

procedure TTUIController.DrawSectorMap;
const
  BoxBG = $01;
var
  Mappable: ISectorMappable;
  Cont: IContainer;
  Tracks: TTrackColumnArray;
  NTracks, MaxChunks, MaxSec: Integer;
  TrackChunks: array of array of Byte;
  TrackTops: array of array of Boolean;
  TrackSecIDs: array of array of Byte;
  GroupStart, TrackColX, IDColX: array of Integer;
  NGroups, CurX, G: Integer;
  ScrollX, StartG, VisFirst, VisLast, VisG: Integer;
  IsDiff: Boolean;
  I, J, K, T, Row, NumChunks, ChunksInSec: Integer;
  DataY, LabelY, ColX: Integer;
  Attr: Byte;
  Title: string;

  function SectorColor(AState: TSectorState): Byte;
  const
    Colors: array[TSectorState] of Byte = ($08, $0A, $0E, $0B, $0D, $0C);
  begin
    Result := Colors[AState];
  end;

begin
  Cont := ActiveContainer;
  DrawBox(1, 3, FOutput.Width, FOutput.Height - 1, ' Sector Map ', $1F);
  FillRect(2, 4, FOutput.Width - 1, FOutput.Height - 2, $1F);

  if (Cont = nil) or not Supports(Cont, ISectorMappable, Mappable) then
  begin
    FOutput.PutText(3, FOutput.Height div 2, 'No sector map available.', $18);
    Exit;
  end;

  Tracks := Mappable.GetSectorMap;
  NTracks := Length(Tracks);
  if NTracks = 0 then Exit;

  SetLength(TrackChunks, NTracks);
  SetLength(TrackTops, NTracks);
  SetLength(TrackSecIDs, NTracks);
  MaxChunks := 0;
  MaxSec := 0;
  for T := 0 to NTracks - 1 do
  begin
    if Length(Tracks[T].Sectors) > MaxSec then
      MaxSec := Length(Tracks[T].Sectors);
    NumChunks := 0;
    for J := 0 to Length(Tracks[T].Sectors) - 1 do
      NumChunks := NumChunks + Tracks[T].Sectors[J].SizeBytes div 256;
    SetLength(TrackChunks[T], NumChunks);
    SetLength(TrackTops[T], NumChunks);
    SetLength(TrackSecIDs[T], NumChunks);
    K := 0;
    for J := 0 to Length(Tracks[T].Sectors) - 1 do
    begin
      ChunksInSec := Tracks[T].Sectors[J].SizeBytes div 256;
      for I := 0 to ChunksInSec - 1 do
      begin
        TrackChunks[T][K] := SectorColor(Tracks[T].Sectors[J].State);
        TrackTops[T][K] := (I = 0) and (J > 0);
        TrackSecIDs[T][K] := Tracks[T].Sectors[J].SectorID;
        Inc(K);
      end;
    end;
    if NumChunks > MaxChunks then MaxChunks := NumChunks;
  end;

  SetLength(GroupStart, NTracks);
  NGroups := 1;
  GroupStart[0] := 0;
  for T := 1 to NTracks - 1 do
  begin
    IsDiff := Length(TrackSecIDs[T]) <> Length(TrackSecIDs[T - 1]);
    if not IsDiff then
      for K := 0 to Length(TrackSecIDs[T]) - 1 do
        if TrackSecIDs[T][K] <> TrackSecIDs[T - 1][K] then
        begin
          IsDiff := True;
          Break;
        end;
    if IsDiff then
    begin
      GroupStart[NGroups] := T;
      Inc(NGroups);
    end;
  end;
  SetLength(GroupStart, NGroups);

  ScrollX := FMapScrollX;
  if ScrollX >= NTracks then ScrollX := NTracks - 1;
  if ScrollX < 0 then ScrollX := 0;
  FMapScrollX := ScrollX;

  StartG := 0;
  for G := 1 to NGroups - 1 do
    if GroupStart[G] <= ScrollX then StartG := G;

  SetLength(TrackColX, NTracks);
  SetLength(IDColX, NGroups);
  CurX := 3;
  G := StartG;
  IDColX[StartG] := CurX;
  CurX := CurX + 3;
  VisFirst := ScrollX;
  VisLast := ScrollX - 1;
  VisG := StartG;
  for T := ScrollX to NTracks - 1 do
  begin
    if (G + 1 < NGroups) and (T = GroupStart[G + 1]) then
    begin
      Inc(G);
      IDColX[G] := CurX;
      CurX := CurX + 3;
      VisG := G;
    end;
    if CurX > FOutput.Width - 2 then Break;
    TrackColX[T] := CurX;
    CurX := CurX + 2;
    VisLast := T;
  end;
  if VisLast < VisFirst then Exit;

  LabelY := 5;
  DataY := LabelY + 2;

  Title := Format('%d trk x %d sec', [Length(Tracks), MaxSec]);
  if NGroups > 1 then
    Title := Title + Format('  (%d layouts)', [NGroups]);
  if ScrollX > 0 then
    Title := Title + Format('  [%d..%d]', [ScrollX, VisLast]);
  FOutput.PutText(3, 4, Title, $1F);

  for G := StartG to VisG do
    FOutput.PutText(IDColX[G], LabelY, 'id', $17);
  for T := VisFirst to VisLast do
  begin
    ColX := TrackColX[T];
    if T >= 10 then
      FOutput.PutText(ColX, LabelY, Chr(Ord('0') + (T div 10)), $17)
    else
      FOutput.PutText(ColX, LabelY, ' ', $17);
    FOutput.PutText(ColX, LabelY + 1, Chr(Ord('0') + (T mod 10)), $17);
  end;

  for Row := 0 to MaxChunks - 1 do
  begin
    if DataY + Row >= FOutput.Height - 3 then Break;
    for G := StartG to VisG do
    begin
      T := GroupStart[G];
      if (Row < Length(TrackSecIDs[T])) and
         ((Row = 0) or TrackTops[T][Row]) then
        FOutput.PutText(IDColX[G], DataY + Row,
          IntToHex(TrackSecIDs[T][Row], 2), $17);
    end;
    for T := VisFirst to VisLast do
    begin
      ColX := TrackColX[T];
      if Row >= Length(TrackChunks[T]) then
        Continue
      else if TrackTops[T][Row] then
      begin
        Attr := (BoxBG shl 4) or TrackChunks[T][Row];
        FOutput.PutText(ColX, DataY + Row, CH_BLK7, Attr);
      end
      else
        FOutput.PutText(ColX, DataY + Row, CH_FULL, TrackChunks[T][Row]);
    end;
  end;

  FOutput.PutText(3, FOutput.Height - 2,
    ' [' + CH_FULL + '] Data  [' + CH_FULL + '] Dir  [' + CH_FULL + '] Boot  [' + CH_FULL + '] N/S  [' + CH_FULL + '] Err  [' + CH_FULL + '] Free ', $07);
  FOutput.PutText(5, FOutput.Height - 2, CH_FULL, $0A);
  FOutput.PutText(15, FOutput.Height - 2, CH_FULL, $0E);
  FOutput.PutText(24, FOutput.Height - 2, CH_FULL, $0B);
  FOutput.PutText(34, FOutput.Height - 2, CH_FULL, $0D);
  FOutput.PutText(43, FOutput.Height - 2, CH_FULL, $0C);
  FOutput.PutText(52, FOutput.Height - 2, CH_FULL, $08);
end;

function TTUIController.HexRows: Integer;
begin
  Result := FOutput.Height - 5;
  if Result < 1 then Result := 1;
end;

function TTUIController.HexLineCount: Integer;
begin
  Result := Length(FHexLines);
end;

function TTUIController.EnterHexMode: Boolean;
const
  HEX_MAX = 4 * 1024 * 1024;   { 4 MB cap — larger files are truncated }
var
  Cont: IContainer;
  Entry: IEntry;
  Src: ICopySource;
  MS: TMemoryStream;
  RawSz: Int64;
  Sz: Integer;
  Truncated: Boolean;
  NLines, LIdx, Off, I, ByteVal: Integer;
  HexPart, AscPart: string;
  C: Char;
begin
  Result := False;
  Cont := ActiveContainer;
  if Cont = nil then Exit;
  if (ActiveCursor < 0) or (ActiveCursor >= Cont.EntryCount) then Exit;
  Entry := Cont.GetEntry(ActiveCursor);
  if Entry = nil then Exit;
  if Supports(Entry, IContainer) then Exit;
  if not Supports(Entry, ICopySource, Src) then Exit;

  MS := TMemoryStream.Create;
  try
    try
      Src.CopyTo(MS);
    except
      { Caller reports the failure to the user (avoids a double message box). }
      SetLength(FHexData, 0);
      SetLength(FHexLines, 0);
      Exit;
    end;
    RawSz := MS.Size;
    Truncated := RawSz > HEX_MAX;
    if Truncated then
      Sz := HEX_MAX
    else
      Sz := Integer(RawSz);
    SetLength(FHexData, Sz);
    if Sz > 0 then
    begin
      MS.Position := 0;
      MS.ReadBuffer(FHexData[0], Sz);
    end;
  finally
    MS.Free;
  end;

  if Truncated then
    FHexTitle := ' Hex: ' + Entry.GetName + ' (' + IntToStr(RawSz) + ' bytes, truncated) '
  else
    FHexTitle := ' Hex: ' + Entry.GetName + ' (' + IntToStr(Sz) + ' bytes) ';

  { Pre-format all hex+ascii lines so DrawHex only indexes, never recomputes. }
  NLines := (Sz + 15) div 16;
  if Sz = 0 then NLines := 0;
  SetLength(FHexLines, NLines);
  for LIdx := 0 to NLines - 1 do
  begin
    Off := LIdx * 16;
    HexPart := '';
    AscPart := '';
    for I := 0 to 15 do
    begin
      if Off + I < Sz then
      begin
        ByteVal := FHexData[Off + I];
        HexPart := HexPart + IntToHex(ByteVal, 2);
        if (ByteVal >= 32) and (ByteVal < 127) then
          C := Chr(ByteVal)
        else
          C := '.';
        AscPart := AscPart + C;
      end
      else
      begin
        HexPart := HexPart + '  ';
        AscPart := AscPart + ' ';
      end;
      if I = 7 then HexPart := HexPart + ' ';
      if I < 15 then HexPart := HexPart + ' ';
    end;
    FHexLines[LIdx] := HexPart + '|' + AscPart;
  end;

  FHexScroll := 0;
  FMode := tmHex;
  Result := True;
end;

procedure TTUIController.DrawHex;
const
  BoxAttr  = $1F;
  AddrAttr = $1B;
  HexAttr  = $1F;
  AsciiAttr= $1E;
  { FHexLines format: "<49-char hex part>|<16-char ascii part>"
    Separator '|' is at index 50 (1-based). }
  HEX_PART_LEN = 49;   { 16 × 3 bytes + 1 extra space between groups }
var
  Rows, Lines, ScreenY, LineIdx, Off: Integer;
  AddrPart, HexPart, AscPart: string;
  Footer, Line: string;
  Sep: Integer;
begin
  DrawBox(1, 3, FOutput.Width, FOutput.Height - 1, FHexTitle, BoxAttr);
  FillRect(2, 4, FOutput.Width - 1, FOutput.Height - 2, BoxAttr);

  if Length(FHexLines) = 0 then
  begin
    FOutput.PutText(3, FOutput.Height div 2, '(empty file)', $18);
    Exit;
  end;

  Rows := HexRows;
  Lines := HexLineCount;
  if FHexScroll < 0 then FHexScroll := 0;
  if (Lines > Rows) and (FHexScroll > Lines - Rows) then
    FHexScroll := Lines - Rows;
  if Lines <= Rows then FHexScroll := 0;

  for ScreenY := 0 to Rows - 1 do
  begin
    LineIdx := FHexScroll + ScreenY;
    if LineIdx >= Lines then Break;
    Off := LineIdx * 16;
    AddrPart := IntToHex(Off, 8);

    Line := FHexLines[LineIdx];
    Sep := Pos('|', Line);
    if Sep > 0 then
    begin
      HexPart := Copy(Line, 1, Sep - 1);
      AscPart := Copy(Line, Sep + 1, MaxInt);
    end
    else
    begin
      HexPart := Line;
      AscPart := '';
    end;

    FOutput.PutText(3, 4 + ScreenY, AddrPart, AddrAttr);
    FOutput.PutText(3 + 9, 4 + ScreenY, HexPart, HexAttr);
    FOutput.PutText(3 + 9 + HEX_PART_LEN + 2, 4 + ScreenY, AscPart, AsciiAttr);
  end;

  if Lines > Rows then
    DrawScrollbar(FOutput.Width - 1, 4, 4 + Rows - 1, Lines, Rows, FHexScroll, BoxAttr);

  Footer := ' Esc/F3/F10/Q exit  PgUp/PgDn  Home/End ';
  if Length(Footer) < FOutput.Width - 4 then
    FOutput.PutText(3, FOutput.Height - 1, Footer, $30);
end;

procedure TTUIController.ActionHexScrollUp;
begin
  if FHexScroll > 0 then Dec(FHexScroll);
end;

procedure TTUIController.ActionHexScrollDown;
var
  Lines, Rows: Integer;
begin
  Lines := HexLineCount;
  Rows := HexRows;
  if (Lines > Rows) and (FHexScroll < Lines - Rows) then Inc(FHexScroll);
end;

procedure TTUIController.ActionHexPageUp;
var
  Rows: Integer;
begin
  Rows := HexRows;
  Dec(FHexScroll, Rows);
  if FHexScroll < 0 then FHexScroll := 0;
end;

procedure TTUIController.ActionHexPageDown;
var
  Lines, Rows, Max: Integer;
begin
  Lines := HexLineCount;
  Rows := HexRows;
  if Lines <= Rows then Exit;
  Max := Lines - Rows;
  Inc(FHexScroll, Rows);
  if FHexScroll > Max then FHexScroll := Max;
end;

procedure TTUIController.ActionHexHome;
begin
  FHexScroll := 0;
end;

procedure TTUIController.ActionHexEnd;
var
  Lines, Rows: Integer;
begin
  Lines := HexLineCount;
  Rows := HexRows;
  if Lines > Rows then FHexScroll := Lines - Rows
  else FHexScroll := 0;
end;

procedure TTUIController.UpdateScreen;
var
  M, D: Word;
begin
  DecodeDate(Now, FNowYear, M, D);
  FOutput.Clear;
  DrawHeader;
  case FMode of
    tmCommander: DrawPanes;
    tmDiskMap:   DrawDiskMap;
    tmSectorMap: DrawSectorMap;
    tmHex:       DrawHex;
  end;
  DrawStatusBar;
  FOutput.Flush;
end;

{ ── Dialogs ──────────────────────────────────────────────────── }

const
  DLG_HPAD = 2;   { horizontal columns of padding inside box frame walls }

procedure TTUIController.ShowMessageBox(const AMsg: string);
const
  OK_LBL = 'OK';
var
  BW, BH, BX, BY, OkX: Integer;
begin
  BW := Length(AMsg) + 2 + 2 * DLG_HPAD;
  if BW < 14 + 2 * DLG_HPAD then BW := 14 + 2 * DLG_HPAD;  { room for the [ OK ] button }
  if BW > FOutput.Width - 4 then BW := FOutput.Width - 4;
  BH := 7;   { border / blank / msg / blank / [OK] / blank / border — 1-row pad around the button }
  BX := (FOutput.Width - BW) div 2 + 1;
  if BX < 1 then BX := 1;
  BY := (FOutput.Height - BH) div 2 + 1;
  DrawBox(BX, BY, BX + BW - 1, BY + BH - 1, '', $4F);
  FillRect(BX + 1, BY + 1, BX + BW - 2, BY + BH - 2, $4F);
  FOutput.PutText(BX + 1 + DLG_HPAD, BY + 2, Copy(AMsg, 1, BW - 2 - 2 * DLG_HPAD), $4F);
  OkX := BX + (BW - Length('[ ' + OK_LBL + ' ]')) div 2;
  DrawButton(OkX, BY + BH - 3, OK_LBL, True, $4F);
  FOutput.Flush;
  { Any key, or any mouse click, dismisses. }
  FInput.WaitForKey;
end;

function TTUIController.ConfirmDialog(const AMsg: string): Boolean;
const
  YES_LBL = 'Yes';
  NO_LBL  = 'No';
var
  BW, BH, BX, BY, ContentW, YesX, NoX, BtnSel: Integer;
  Prompt: string;
  E: TInputEvent;

  procedure Redraw;
  begin
    DrawBox(BX, BY, BX + BW - 1, BY + BH - 1, '', $4F);
    FillRect(BX + 1, BY + 1, BX + BW - 2, BY + BH - 2, $4F);
    FOutput.PutText(BX + 1 + DLG_HPAD, BY + 2, Copy(Prompt, 1, BW - 2 - 2 * DLG_HPAD), $4F);
    DrawButton(YesX, BY + BH - 3, YES_LBL, BtnSel = 0, $4F);
    DrawButton(NoX,  BY + BH - 3, NO_LBL,  BtnSel = 1, $4F);
    FOutput.Flush;
  end;

begin
  Prompt := AMsg + '?';
  BW := Length(Prompt) + 2 + 2 * DLG_HPAD;
  ContentW := Length('[ ' + YES_LBL + ' ]') + 6 + Length('[ ' + NO_LBL + ' ]'); { Yes  gap(6)  No }
  if BW < ContentW + 2 * DLG_HPAD + 2 then BW := ContentW + 2 * DLG_HPAD + 2;
  if BW > FOutput.Width - 4 then BW := FOutput.Width - 4;
  BH := 7;   { border / blank / prompt / blank / buttons / blank / border }
  BX := (FOutput.Width - BW) div 2 + 1;
  if BX < 1 then BX := 1;
  BY := (FOutput.Height - BH) div 2 + 1;
  YesX := BX + (BW - ContentW) div 2;
  NoX  := YesX + Length('[ ' + YES_LBL + ' ]') + 6;
  BtnSel := 0;
  Redraw;
  repeat
    E := FInput.WaitForKey;
    case E.Action of
      kaEsc: Exit(False);
      kaTab, kaLeft, kaRight: begin BtnSel := 1 - BtnSel; Redraw; end;
      kaEnter: Exit(BtnSel = 0);
      kaChar:
        case UpCase(E.CharValue) of
          'Y': Exit(True);
          'N': Exit(False);
        end;
      kaMouse:
        if E.MouseButton = mbLeft then
        begin
          if PointInButton(E.MouseX, E.MouseY, YesX, BY + BH - 3, YES_LBL) then Exit(True)
          else if PointInButton(E.MouseX, E.MouseY, NoX, BY + BH - 3, NO_LBL) then Exit(False);
        end;
    end;
  until False;
end;

function TTUIController.InputDialog(const APrompt, ADefault: string;
                                    out AText: string): Boolean;
const
  OK_LBL     = 'OK';
  CANCEL_LBL = 'Cancel';
var
  BW, BH, BX, BY: Integer;
  ContentW, OkX, CancelX: Integer;
  MaxTextW: Integer;
  BtnFocus: Integer;  { 0 = OK, 1 = Cancel }
  E: TInputEvent;

  procedure Redraw;
  var
    FieldStr: string;
    TruncText: string;
  begin
    DrawBox(BX, BY, BX + BW - 1, BY + BH - 1, '', $4F);
    FillRect(BX + 1, BY + 1, BX + BW - 2, BY + BH - 2, $4F);
    FOutput.PutText(BX + 1 + DLG_HPAD, BY + 2, Copy(APrompt, 1, BW - 2 - 2 * DLG_HPAD), $4F);
    { Text field: show last MaxTextW chars of AText with trailing cursor bar }
    TruncText := AText;
    if Length(TruncText) > MaxTextW then
      TruncText := Copy(TruncText, Length(TruncText) - MaxTextW + 1, MaxTextW);
    FieldStr := TruncText + '_';
    FieldStr := FieldStr + StringOfChar(' ', MaxTextW + 1 - Length(FieldStr));
    FOutput.PutText(BX + 1 + DLG_HPAD, BY + 3, FieldStr, $70);
    DrawButton(OkX,     BY + BH - 3, OK_LBL,     BtnFocus = 0, $4F);
    DrawButton(CancelX, BY + BH - 3, CANCEL_LBL, BtnFocus = 1, $4F);
    FOutput.Flush;
  end;

begin
  AText := ADefault;
  BW := Length(APrompt) + 2 + 2 * DLG_HPAD;
  ContentW := Length('[ ' + OK_LBL + ' ]') + 6 + Length('[ ' + CANCEL_LBL + ' ]');
  if BW < ContentW + 2 + 2 * DLG_HPAD then BW := ContentW + 2 + 2 * DLG_HPAD;
  if BW < 44 then BW := 44;
  if BW > FOutput.Width - 4 then BW := FOutput.Width - 4;
  { box: border/blank/prompt/field/blank/buttons/blank/border = 8 rows }
  BH := 8;
  BX := (FOutput.Width - BW) div 2 + 1;
  if BX < 1 then BX := 1;
  BY := (FOutput.Height - BH) div 2 + 1;
  OkX     := BX + (BW - ContentW) div 2;
  CancelX := OkX + Length('[ ' + OK_LBL + ' ]') + 6;
  MaxTextW := BW - 2 - 2 * DLG_HPAD;
  BtnFocus := 0;
  Redraw;
  repeat
    E := FInput.WaitForKey;
    case E.Action of
      kaEsc:
        begin
          AText := '';
          Result := False;
          Exit;
        end;
      kaEnter:
        begin
          if BtnFocus = 1 then
          begin
            AText := '';
            Result := False;
          end
          else
            Result := True;
          Exit;
        end;
      kaTab:
        begin
          BtnFocus := 1 - BtnFocus;
          Redraw;
        end;
      kaBackspace:
        begin
          if Length(AText) > 0 then
            Delete(AText, Length(AText), 1);
          Redraw;
        end;
      kaChar:
        begin
          if (E.CharValue >= ' ') and (Length(AText) < 255) then
          begin
            AText := AText + E.CharValue;
            BtnFocus := 0;
            Redraw;
          end;
        end;
      kaMouse:
        if E.MouseButton = mbLeft then
        begin
          if PointInButton(E.MouseX, E.MouseY, OkX, BY + BH - 3, OK_LBL) then
          begin
            Result := True;
            Exit;
          end
          else if PointInButton(E.MouseX, E.MouseY, CancelX, BY + BH - 3, CANCEL_LBL) then
          begin
            AText := '';
            Result := False;
            Exit;
          end;
        end;
    end;
  until False;
end;

function TTUIController.RunProgressModal(const ATitle: string;
                                         ATask: TGwTask): Boolean;
const
  BoxW  = 52;
  BoxH  = 8;
  Spinners: array[0..3] of Char = ('|', '/', '-', '\');
var
  BX, BY, SpinIdx: Integer;
  LastLog, CurLog, LogLine: string;
  Cancelled: Boolean;
begin
  BX := (FOutput.Width  - BoxW) div 2 + 1;
  BY := (FOutput.Height - BoxH) div 2 + 1;
  if BX < 1 then BX := 1;
  if BY < 1 then BY := 1;

  SpinIdx   := 0;
  LastLog   := '';
  Cancelled := False;

  repeat
    { Draw the modal frame. }
    DrawBox(BX, BY, BX + BoxW - 1, BY + BoxH - 1, '', $4E);
    FillRect(BX + 1, BY + 1, BX + BoxW - 2, BY + BoxH - 2, $4E);

    { Title row. }
    FOutput.PutText(BX + 2, BY + 1,
      Copy(ATitle, 1, BoxW - 4), $4F);

    { Cancel hint. }
    if not Cancelled then
      FOutput.PutText(BX + 2, BY + 3, 'Press Esc to cancel.', $4E)
    else
      FOutput.PutText(BX + 2, BY + 3, 'Cancelling...       ', $4E);

    { Spinner. }
    FOutput.PutText(BX + 2, BY + 5, Spinners[SpinIdx] + ' Working...', $4E);
    SpinIdx := (SpinIdx + 1) mod 4;

    { Last line of log output. }
    CurLog := ATask.GetLogSnapshot;
    if CurLog <> LastLog then
      LastLog := CurLog;
    { Pick the last non-empty line. }
    LogLine := '';
    if LastLog <> '' then
    begin
      LogLine := LastLog;
      while (Length(LogLine) > 0) and
            (LogLine[Length(LogLine)] in [#10, #13]) do
        Delete(LogLine, Length(LogLine), 1);
      { Find last newline. }
      if Pos(#10, LogLine) > 0 then
        LogLine := Copy(LogLine, LastDelimiter(#10, LogLine) + 1, MaxInt);
    end;
    FOutput.PutText(BX + 2, BY + 6,
      Copy(LogLine + StringOfChar(' ', BoxW - 4), 1, BoxW - 4), $4E);

    FOutput.Flush;

    { Non-blocking key check: Sleep 100ms then poll. }
    Sleep(100);

    { Check for Esc without blocking — peek at the input queue if available.
      Since ITerminalInput only has blocking WaitForKey, we check finished
      state first and only call WaitForKey when done. }
    if ATask.IsFinished then
      Break;

    { On non-cancelled runs, we cannot non-blockingly poll ITerminalInput
      (it has no TryWaitForKey).  Use a simple approach: the user's only
      feedback is that they must wait.  We do a short sleep loop so the
      spinner animates and log updates, and the UI doesn't freeze.
      Esc-cancellation is left for a follow-up when TryWaitForKey is added. }

  until ATask.IsFinished;

  { If somehow we got here without finishing (shouldn't happen), wait. }
  while not ATask.IsFinished do
    Sleep(50);

  if Cancelled then
    Result := False
  else
    Result := True;

  { Restore the screen. }
  UpdateScreen;
end;

procedure TTUIController.ActionDriveRead;
var
  DriveStr, ImagePath, GwPath, Log: string;
  NewCont: IContainer;
  Cont: IContainer;
  DiskInfo: string;
  Task: TGwTask;
begin
  if not InputDialog('Drive letter (a/b):', 'a', DriveStr) then Exit;
  if DriveStr = '' then DriveStr := 'a';
  { Validate drive letter — only 'a' or 'b' accepted. }
  if not ((Length(DriveStr) = 1) and (LowerCase(DriveStr)[1] in ['a', 'b'])) then
  begin
    ShowMessageBox('Error: --drive must be ''a'' or ''b'' (got ''' + DriveStr + ''').');
    Exit;
  end;

  ImagePath := GetCurrentDir + PathDelim + 'disc-' +
               FormatDateTime('yyyymmdd-hhnnss', Now) + '.dsk';
  if not InputDialog('Save image as:', ImagePath, ImagePath) then Exit;
  if ImagePath = '' then Exit;

  GwPath := FindGwExecutable;
  if GwPath = '' then
  begin
    ShowMessageBox(GW_NOT_FOUND_HINT);
    Exit;
  end;

  Task := TGwTask.Create(gopRead, GwPath, DriveStr, ImagePath);
  try
    Task.Start;
    RunProgressModal('Reading disc from drive ' + DriveStr + '...', Task);
    Log := Task.GetLogSnapshot;
    if not Task.WasOk then
    begin
      ShowMessageBox('Read failed: ' + Copy(Log, 1, 200));
      Exit;
    end;
  finally
    Task.Free;
  end;

  { Open the resulting DSK in the active pane. }
  try
    NewCont := TDSKContainer.Create(ImagePath);
  except
    on E: Exception do
    begin
      ShowMessageBox('Read OK but cannot open DSK: ' + E.Message);
      Exit;
    end;
  end;

  { Push current container onto history and navigate into the new one. }
  Cont := ActiveContainer;
  if Cont <> nil then
  begin
    SetLength(FHistory[FFocus], Length(FHistory[FFocus]) + 1);
    FHistory[FFocus][High(FHistory[FFocus])] := Cont;
  end;
  case FFocus of
    psLeft:  FLeft  := NewCont;
    psRight: FRight := NewCont;
  end;
  ResetSelections(FFocus);
  SetActiveCursor(0);
  SetActiveScroll(0);
  FMapScrollX := 0;

  DiskInfo := IntToStr(NewCont.EntryCount) + ' entries';
  ShowMessageBox('Read OK — ' + DiskInfo + '.  Image: ' +
                 ExtractFileName(ImagePath));
end;

procedure TTUIController.ActionDriveWrite;
var
  DriveStr, GwPath, Log: string;
  Cont: IContainer;
  Writable: IWritable;
  PathProv: IPathProvider;
  ImagePath: string;
  Task: TGwTask;
begin
  Cont := ActiveContainer;
  if Cont = nil then
  begin
    ShowMessageBox('Active pane is not a disc image.');
    Exit;
  end;

  { Require the pane to expose its host path (i.e. implement IPathProvider). }
  if not Supports(Cont, IPathProvider, PathProv) then
  begin
    ShowMessageBox('Active pane is not a disc image.');
    Exit;
  end;
  ImagePath := PathProv.Path;

  { Warn about unsaved changes. }
  if Supports(Cont, IWritable, Writable) and Writable.Modified then
  begin
    if not ConfirmDialog('Disc has unsaved changes — save first') then Exit;
    try
      Writable.Save;
    except
      on E: Exception do begin ShowMessageBox('Save failed: ' + E.Message); Exit; end;
    end;
  end;

  if not InputDialog('Drive letter (a/b):', 'a', DriveStr) then Exit;
  if DriveStr = '' then DriveStr := 'a';
  { Validate drive letter — only 'a' or 'b' accepted. }
  if not ((Length(DriveStr) = 1) and (LowerCase(DriveStr)[1] in ['a', 'b'])) then
  begin
    ShowMessageBox('Error: --drive must be ''a'' or ''b'' (got ''' + DriveStr + ''').');
    Exit;
  end;

  if not ConfirmDialog('Write ' + ExtractFileName(ImagePath) +
                       ' to drive ' + DriveStr + '? This ERASES the disc') then Exit;

  GwPath := FindGwExecutable;
  if GwPath = '' then
  begin
    ShowMessageBox(GW_NOT_FOUND_HINT);
    Exit;
  end;

  Task := TGwTask.Create(gopWrite, GwPath, DriveStr, ImagePath);
  try
    Task.Start;
    RunProgressModal('Writing disc to drive ' + DriveStr + '...', Task);
    Log := Task.GetLogSnapshot;
    if not Task.WasOk then
    begin
      ShowMessageBox('Write failed: ' + Copy(Log, 1, 200));
      Exit;
    end;
  finally
    Task.Free;
  end;

  ShowMessageBox('Write complete.');
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

procedure TTUIController.ActionHome;
begin
  SetActiveCursor(0);
  SetActiveScroll(0);
end;

procedure TTUIController.ActionEnd;
var
  Cont: IContainer;
  MaxScroll: Integer;
begin
  Cont := ActiveContainer;
  if Cont = nil then Exit;
  SetActiveCursor(Cont.EntryCount - 1);
  MaxScroll := Cont.EntryCount - PaneHeight;
  if MaxScroll < 0 then MaxScroll := 0;
  SetActiveScroll(MaxScroll);
end;

procedure TTUIController.ActionMapScrollLeft;
begin
  if FMapScrollX > 0 then
    Dec(FMapScrollX);
end;

procedure TTUIController.ActionMapScrollRight;
var
  Cont: IContainer;
  Mappable: ISectorMappable;
  Tracks: TTrackColumnArray;
  MaxScroll: Integer;
begin
  Inc(FMapScrollX);
  { Clamp immediately so state is consistent without requiring a render.
    We need the track count from the current sector map. }
  Cont := ActiveContainer;
  if (Cont <> nil) and Supports(Cont, ISectorMappable, Mappable) then
  begin
    Tracks := Mappable.GetSectorMap;
    MaxScroll := Length(Tracks) - 1;
    if MaxScroll < 0 then MaxScroll := 0;
    if FMapScrollX > MaxScroll then FMapScrollX := MaxScroll;
  end;
end;

procedure TTUIController.ActionMapScrollHome;
begin
  FMapScrollX := 0;
end;

procedure TTUIController.ActionMapScrollEnd;
begin
  FMapScrollX := MaxInt;
end;

procedure TTUIController.ActionPageUp;
var
  PH: Integer;
begin
  PH := PaneHeight;
  SetActiveCursor(ActiveCursor - PH);
  if ActiveCursor < 0 then SetActiveCursor(0);
  SetActiveScroll(ActiveScroll - PH);
  if ActiveScroll < 0 then SetActiveScroll(0);
end;

procedure TTUIController.ActionPageDown;
var
  Cont: IContainer;
  PH, MaxScroll: Integer;
begin
  Cont := ActiveContainer;
  if Cont = nil then Exit;
  PH := PaneHeight;
  SetActiveCursor(ActiveCursor + PH);
  if ActiveCursor >= Cont.EntryCount then
    SetActiveCursor(Cont.EntryCount - 1);
  SetActiveScroll(ActiveScroll + PH);
  MaxScroll := Cont.EntryCount - PH;
  if MaxScroll < 0 then MaxScroll := 0;
  if ActiveScroll > MaxScroll then
    SetActiveScroll(MaxScroll);
end;

procedure TTUIController.ActionSelect;
begin
  EnsureSelections(FFocus);
  if (ActiveCursor >= 0) and (ActiveCursor < Length(FSelections[FFocus])) then
    FSelections[FFocus][ActiveCursor] := not FSelections[FFocus][ActiveCursor];
  ActionNavigateDown;
end;

procedure TTUIController.ActionEnter;
var
  Cont: IContainer;
  Entry: IEntry;
  SubCont: IContainer;
  Exp: IExpandable;
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
    ReapplySort(FFocus);
    ResetSelections(FFocus);
    SetActiveCursor(0);
    SetActiveScroll(0);
    FMapScrollX := 0;
  end
  else if Supports(Entry, IExpandable, Exp) then
  begin
    try
      SubCont := Exp.Expand;
    except
      on E: Exception do begin ShowMessageBox(E.Message); Exit; end;
    end;
    if SubCont = nil then Exit;
    SetLength(FHistory[FFocus], Length(FHistory[FFocus]) + 1);
    FHistory[FFocus][High(FHistory[FFocus])] := ActiveContainer;
    case FFocus of
      psLeft: FLeft := SubCont;
      psRight: FRight := SubCont;
    end;
    ReapplySort(FFocus);
    ResetSelections(FFocus);
    SetActiveCursor(0);
    SetActiveScroll(0);
    FMapScrollX := 0;
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
  ReapplySort(FFocus);
  ResetSelections(FFocus);
  SetActiveCursor(0);
  SetActiveScroll(0);
  FMapScrollX := 0;
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
  I, CopyCount: Integer;
  BatchMode: Boolean;
begin
  Cont := ActiveContainer;
  if Cont = nil then Exit;

  case FFocus of
    psLeft: OtherCont := FRight;
    psRight: OtherCont := FLeft;
  end;

  if (OtherCont = nil) or not Supports(OtherCont, ICopyTarget, Tgt) then
  begin
    ShowMessageBox('Cannot copy: target does not accept imports.');
    Exit;
  end;

  EnsureSelections(FFocus);
  BatchMode := HasAnySelection(FFocus);

  if BatchMode then
  begin
    if not ConfirmDialog('Copy selected files to ' + OtherCont.Title) then Exit;
    CopyCount := 0;
    for I := 0 to Cont.EntryCount - 1 do
    begin
      if not FSelections[FFocus][I] then Continue;
      Entry := Cont.GetEntry(I);
      if (Entry = nil) or not Supports(Entry, ICopySource, Src) then Continue;
      if Tgt.Import(Src, Entry.Name) then
        Inc(CopyCount);
    end;
    OtherCont.Refresh;
    if FFocus = psLeft then ReapplySort(psRight) else ReapplySort(psLeft);
    ResetSelections(FFocus);
    ShowMessageBox('Copied ' + IntToStr(CopyCount) + ' file(s).');
  end
  else
  begin
    if (ActiveCursor < 0) or (ActiveCursor >= Cont.EntryCount) then Exit;
    Entry := Cont.GetEntry(ActiveCursor);
    if Entry = nil then Exit;
    if not Supports(Entry, ICopySource, Src) then
    begin
      ShowMessageBox('Cannot copy: source does not support extraction.');
      Exit;
    end;
    if ConfirmDialog('Copy ' + Entry.Name + ' to ' + OtherCont.Title) then
    begin
      if Tgt.Import(Src, Entry.Name) then
      begin
        OtherCont.Refresh;
        if FFocus = psLeft then ReapplySort(psRight) else ReapplySort(psLeft);
        ShowMessageBox('Copied successfully.');
      end
      else
        ShowMessageBox('Copy failed.');
    end;
  end;
end;

procedure TTUIController.ActionDelete;
var
  Cont: IContainer;
  Entry: IEntry;
  Del: IDeletable;
  Restorable: IRestorable;
  I, DelCount: Integer;
  BatchMode: Boolean;
begin
  Cont := ActiveContainer;
  if Cont = nil then Exit;

  EnsureSelections(FFocus);
  BatchMode := HasAnySelection(FFocus);

  if BatchMode then
  begin
    if not ConfirmDialog('Delete selected files') then Exit;
    DelCount := 0;
    for I := 0 to Cont.EntryCount - 1 do
    begin
      if not FSelections[FFocus][I] then Continue;
      Entry := Cont.GetEntry(I);
      if (Entry = nil) or not Supports(Entry, IDeletable, Del) then Continue;
      if not Del.IsDeleted then
      begin
        Del.Delete;
        Inc(DelCount);
      end;
    end;
    Cont.Refresh;
    ReapplySort(FFocus);
    ResetSelections(FFocus);
    ShowMessageBox('Deleted ' + IntToStr(DelCount) + ' file(s).');
  end
  else
  begin
    if (ActiveCursor < 0) or (ActiveCursor >= Cont.EntryCount) then Exit;
    Entry := Cont.GetEntry(ActiveCursor);
    if Entry = nil then Exit;

    if not Supports(Entry, IDeletable, Del) then
    begin
      ShowMessageBox('This entry cannot be deleted.');
      Exit;
    end;

    if Del.IsDeleted then
    begin
      if Supports(Entry, IRestorable, Restorable) then
      begin
        Restorable.Restore;
        Cont.Refresh;
        ReapplySort(FFocus);
      end
      else
        ShowMessageBox('Cannot restore this entry.');
    end
    else
    begin
      if ConfirmDialog('Delete ' + Entry.Name) then
      begin
        Del.Delete;
        Cont.Refresh;
        ReapplySort(FFocus);
      end;
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
    ShowMessageBox('This entry cannot be renamed.')
  else
    ShowMessageBox('Rename: not yet implemented in TUI.');
end;

procedure TTUIController.ActionToggleMap;
var
  Cont: IContainer;
  Entry: IEntry;
  HasBlocks, HasSectors, EntryIsFile: Boolean;
begin
  Cont := ActiveContainer;
  HasBlocks := (Cont <> nil) and Supports(Cont, IBlockMappable);
  HasSectors := (Cont <> nil) and Supports(Cont, ISectorMappable);

  EntryIsFile := False;
  if (Cont <> nil) and (ActiveCursor >= 0) and (ActiveCursor < Cont.EntryCount) then
  begin
    Entry := Cont.GetEntry(ActiveCursor);
    if (Entry <> nil) and (not Supports(Entry, IContainer)) and Supports(Entry, ICopySource) then
      EntryIsFile := True;
  end;

  { F3 cycles through every view the current pane offers, NC-style:
      commander → hex (if file) → blockmap (if any) → sectormap (if any) → commander.
    Esc / Backspace short-circuit back to commander from any view. }
  case FMode of
    tmCommander:
      begin
        FMapScrollX := 0;
        if EntryIsFile then
        begin
          if not EnterHexMode then
          begin
            if HasBlocks then FMode := tmDiskMap
            else if HasSectors then FMode := tmSectorMap
            else ShowMessageBox('Hex view: cannot read this entry.');
          end;
        end
        else if HasBlocks then FMode := tmDiskMap
        else if HasSectors then FMode := tmSectorMap
        else ShowMessageBox('No view available here.');
      end;
    tmHex:
      begin
        SetLength(FHexData, 0);
        SetLength(FHexLines, 0);
        if HasBlocks then FMode := tmDiskMap
        else if HasSectors then FMode := tmSectorMap
        else FMode := tmCommander;
      end;
    tmDiskMap:
      if HasSectors then FMode := tmSectorMap
      else FMode := tmCommander;
    tmSectorMap:
      begin FMapScrollX := 0; FMode := tmCommander; end;
  end;
end;

procedure TTUIController.ActionShowBlockMap;
var Cont: IContainer;
begin
  Cont := ActiveContainer;
  if (Cont = nil) or not Supports(Cont, IBlockMappable) then
  begin
    ShowMessageBox('No block map available here.');
    Exit;
  end;
  if FMode = tmHex then begin SetLength(FHexData, 0); SetLength(FHexLines, 0); end;
  FMapScrollX := 0;
  FMode := tmDiskMap;
end;

procedure TTUIController.ActionShowSectorMap;
var Cont: IContainer;
begin
  Cont := ActiveContainer;
  if (Cont = nil) or not Supports(Cont, ISectorMappable) then
  begin
    ShowMessageBox('No sector map available here.');
    Exit;
  end;
  if FMode = tmHex then begin SetLength(FHexData, 0); SetLength(FHexLines, 0); end;
  FMapScrollX := 0;
  FMode := tmSectorMap;
end;

procedure TTUIController.ActionSave;
var
  Cont: IContainer;
  Writable: IWritable;
begin
  Cont := ActiveContainer;
  if (Cont = nil) or not Supports(Cont, IWritable, Writable) then
  begin
    ShowMessageBox('Nothing to save.');
    Exit;
  end;
  if Writable.Modified then
  begin
    if ConfirmDialog('Save changes') then
    begin
      try
        Writable.Save;
        ShowMessageBox('Saved.');
      except
        on E: Exception do
          ShowMessageBox('Save failed: ' + E.Message);
      end;
    end;
  end
  else
    ShowMessageBox('No changes to save.');
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
      try
        Writable.Revert;
        ActiveContainer.Refresh;
        ReapplySort(FFocus);
        ShowMessageBox('Changes reverted.');
      except
        on E: Exception do
          ShowMessageBox('Revert failed: ' + E.Message);
      end;
    end;
  end;
end;

procedure TTUIController.ActionMenu;
const
  maSort = 0; maSave = 1; maRevert = 2; maBlockMap = 3; maDiskInfo = 4; maSectorMap = 5;
  maHexView = 6; maDriveRead = 7; maDriveWrite = 8;
  BarAttr = $70; BarActiveAttr = $0F;
  MenuAttr = $30; SelAttr = $70;
type
  TMenuItem = record
    Lbl: string;
    IsSep: Boolean;
    Tag: Integer;
  end;
var
  Items: array of TMenuItem;
  Cont: IContainer;
  Sortable: ISortable;
  Summary: ISummary;
  ActiveSide: Integer;
  Sel, I, Count: Integer;
  BoxH, BX, BY, BoxW: Integer;
  E: TInputEvent;
  SortSel, SortCount: Integer;
  SortBoxW, SortBoxH, SBX, SBY: Integer;
  SortLabels: array of string;
  SortFields_: array of TSortField;

  procedure AddItem(const ALbl: string; ATag: Integer; ASep: Boolean = False);
  begin
    SetLength(Items, Length(Items) + 1);
    Items[High(Items)].Lbl := ALbl;
    Items[High(Items)].Tag := ATag;
    Items[High(Items)].IsSep := ASep;
  end;

  procedure BuildItems;
  var
    EntryUnderCursor: IEntry;
  begin
    SetLength(Items, 0);
    Cont := ActiveContainer;
    if Cont = nil then Exit;

    if Supports(Cont, ISortable, Sortable) then
      AddItem('Sort...', maSort);

    if (ActiveCursor >= 0) and (ActiveCursor < Cont.EntryCount) then
    begin
      EntryUnderCursor := Cont.GetEntry(ActiveCursor);
      if (EntryUnderCursor <> nil) and
         (not Supports(EntryUnderCursor, IContainer)) and
         Supports(EntryUnderCursor, ICopySource) then
        AddItem('Hex view     F3', maHexView);
    end;

    if Supports(Cont, IBlockMappable) then
      AddItem('Block map    F3', maBlockMap);

    if Supports(Cont, ISectorMappable) then
      AddItem('Sector map   F3', maSectorMap);

    if Supports(Cont, ISummary) then
      AddItem('Disk info', maDiskInfo);

    if (Length(Items) > 0) and Supports(Cont, IWritable) then
      AddItem('', -1, True);

    if Supports(Cont, IWritable) then
    begin
      AddItem('Save         F2', maSave);
      AddItem('Revert', maRevert);
    end;

    { Greaseweazle drive actions — always shown so the user can read a disc
      into any pane regardless of what is currently open. }
    AddItem('', -1, True);
    AddItem('Read disc from drive...', maDriveRead);
    { Write is only meaningful when the active pane holds a DSK image. }
    if (Cont <> nil) and Supports(Cont, IPathProvider) then
      AddItem('Write disc to drive...', maDriveWrite);
  end;

  procedure DrawMenuBar;
  var
    LeftLbl, RightLbl: string;
    LeftAttr, RightAttr: Byte;
  begin
    LeftLbl := ' Left ';
    RightLbl := ' Right ';
    FOutput.PutText(1, 1, StringOfChar(' ', FOutput.Width), BarAttr);
    if ActiveSide = 0 then LeftAttr := BarActiveAttr else LeftAttr := BarAttr;
    if ActiveSide = 1 then RightAttr := BarActiveAttr else RightAttr := BarAttr;
    FOutput.PutText(2, 1, LeftLbl, LeftAttr);
    FOutput.PutText(2 + Length(LeftLbl) + 2, 1, RightLbl, RightAttr);
  end;

  procedure DrawDropdown;
  var
    J: Integer;
    Attr: Byte;
  begin
    UpdateScreen;
    FMenuOpen := True;
    DrawMenuBar;
    if Count = 0 then
    begin
      DrawBox(BX, BY, BX + BoxW - 1, BY + 2, '', MenuAttr);
      FillRect(BX + 1, BY + 1, BX + BoxW - 2, BY + 1, MenuAttr);
      FOutput.PutText(BX + 2, BY + 1, '(no options)', MenuAttr);
      FOutput.Flush;
      Exit;
    end;
    DrawBox(BX, BY, BX + BoxW - 1, BY + BoxH - 1, '', MenuAttr);
    FillRect(BX + 1, BY + 1, BX + BoxW - 2, BY + BoxH - 2, MenuAttr);
    for J := 0 to High(Items) do
    begin
      if Items[J].IsSep then
      begin
        HLine(BX + 1, BX + BoxW - 2, BY + 1 + J, MenuAttr);
        FOutput.PutText(BX, BY + 1 + J, CH_LTEE, MenuAttr);
        FOutput.PutText(BX + BoxW - 1, BY + 1 + J, CH_RTEE, MenuAttr);
      end
      else
      begin
        if J = Sel then Attr := SelAttr else Attr := MenuAttr;
        FOutput.PutText(BX + 1, BY + 1 + J,
          ' ' + Items[J].Lbl + StringOfChar(' ', BoxW - 3 - Length(Items[J].Lbl)),
          Attr);
      end;
    end;
    FOutput.Flush;
  end;

  procedure RunSortDialog;
  var
    FirstEntry: IEntry;
    Dated: IDated;
    DirsFirst: Boolean;
    ChkLbl: string;
    DividerY, ChkY, BtnY, OkX, CancelX: Integer;

    procedure AddSortOption(const ALbl: string; AField: TSortField);
    begin
      SetLength(SortLabels, Length(SortLabels) + 1);
      SetLength(SortFields_, Length(SortFields_) + 1);
      SortLabels[High(SortLabels)] := ALbl;
      SortFields_[High(SortFields_)] := AField;
    end;

    procedure ApplySort;
    var
      ChosenField: TSortField;
    begin
      ChosenField := SortFields_[SortSel];
      FSortField[FFocus] := ChosenField;
      FSortAscending[FFocus] := True;
      FDirsFirst[FFocus] := DirsFirst;
      Sortable.Sort(ChosenField, True, DirsFirst);
      SetActiveCursor(0);
      SetActiveScroll(0);
      case ChosenField of
        sfDateCreated:  FDateKind[FFocus] := dkCreation;
        sfDateModified: FDateKind[FFocus] := dkModification;
      end;
    end;

    procedure DrawSortBox;
    var
      J: Integer;
      Attr: Byte;
    begin
      DrawBox(SBX, SBY, SBX + SortBoxW - 1, SBY + SortBoxH - 1, ' Sort by ', $4F);
      FillRect(SBX + 1, SBY + 1, SBX + SortBoxW - 2, SBY + SortBoxH - 2, $4F);
      for J := 0 to SortCount - 1 do
      begin
        if J = SortSel then Attr := $70 else Attr := $4F;
        FOutput.PutText(SBX + 1, SBY + 1 + J,
          ' ' + SortLabels[J] + StringOfChar(' ', SortBoxW - 3 - Length(SortLabels[J])),
          Attr);
      end;
      SectionDivider(SBX, SBX + SortBoxW - 1, DividerY, $4F);
      if DirsFirst then ChkLbl := '[x] Dirs first' else ChkLbl := '[ ] Dirs first';
      FOutput.PutText(SBX + 1, ChkY,
        ' ' + ChkLbl + StringOfChar(' ', SortBoxW - 3 - Length(ChkLbl)), $4F);
      DrawButton(OkX,     BtnY, 'OK',     True,  $4F);
      DrawButton(CancelX, BtnY, 'Cancel', False, $4F);
      FOutput.Flush;
    end;

    function ContentW: Integer;
    begin
      Result := Length('[ OK ]') + 3 + Length('[ Cancel ]');
    end;

  begin
    SetLength(SortLabels, 0);
    SetLength(SortFields_, 0);
    AddSortOption('Name', sfName);
    AddSortOption('Extension', sfExtension);
    AddSortOption('Size', sfSize);

    if (Cont <> nil) and (Cont.EntryCount > 0) then
    begin
      FirstEntry := Cont.GetEntry(0);
      if (FirstEntry <> nil) and (FirstEntry.GetName = '..') and
         (Cont.EntryCount > 1) then
        FirstEntry := Cont.GetEntry(1);
      if (FirstEntry <> nil) and Supports(FirstEntry, IUserArea) then
        AddSortOption('User', sfUser);
      if (FirstEntry <> nil) and Supports(FirstEntry, IDated, Dated) then
      begin
        if dkModification in Dated.GetAvailableDates then
          AddSortOption('Modified', sfDateModified);
        if dkCreation in Dated.GetAvailableDates then
          AddSortOption('Created', sfDateCreated);
      end;
    end;

    SortCount := Length(SortLabels);
    if SortCount = 0 then Exit;
    DirsFirst := FDirsFirst[FFocus];
    SortBoxW := 22;
    SortBoxH := SortCount + 7;     { options + divider + checkbox + blank + buttons + blank + 2 borders }
    SBX := (FOutput.Width - SortBoxW) div 2;
    SBY := (FOutput.Height - SortBoxH) div 2;
    DividerY := SBY + 1 + SortCount;
    ChkY     := SBY + 2 + SortCount;
    BtnY     := SBY + 4 + SortCount;   { one blank row (SBY+3+SortCount) above the buttons }
    OkX      := SBX + (SortBoxW - ContentW) div 2;
    CancelX  := OkX + Length('[ OK ]') + 3;
    SortSel := 0;
    DrawSortBox;
    repeat
      E := FInput.WaitForKey;
      case E.Action of
        kaUp: if SortSel > 0 then Dec(SortSel);
        kaDown: if SortSel < SortCount - 1 then Inc(SortSel);
        kaEnter: begin ApplySort; Exit; end;
        kaEsc: Exit;
        kaChar:
          case UpCase(E.CharValue) of
            'Q': Exit;
            ' ': DirsFirst := not DirsFirst;
          end;
        kaMouse:
          if E.MouseButton = mbLeft then
          begin
            if PointInButton(E.MouseX, E.MouseY, OkX, BtnY, 'OK') then
              begin ApplySort; Exit; end
            else if PointInButton(E.MouseX, E.MouseY, CancelX, BtnY, 'Cancel') then
              Exit
            else if (E.MouseX > SBX) and (E.MouseX < SBX + SortBoxW - 1) then
            begin
              if (E.MouseY >= SBY + 1) and (E.MouseY <= SBY + SortCount) then
                SortSel := E.MouseY - (SBY + 1)
              else if E.MouseY = ChkY then
                DirsFirst := not DirsFirst;
            end;
          end;
      end;
      DrawSortBox;
    until False;
  end;

  procedure ComputeBoxW;
  var
    J, MaxW: Integer;
  begin
    MaxW := 0;
    for J := 0 to High(Items) do
      if not Items[J].IsSep and (Length(Items[J].Lbl) > MaxW) then
        MaxW := Length(Items[J].Lbl);
    if MaxW < 20 then MaxW := 20;  { minimum sensible width }
    BoxW := MaxW + 4;  { 1 left border + 1 left pad + content + 1 right pad + 1 right border }
    if BoxW > FOutput.Width - BX then BoxW := FOutput.Width - BX;
  end;

  procedure SwitchMenuSide;
  begin
    if ActiveSide = 0 then
    begin
      ActiveSide := 1;
      if FRight <> nil then FFocus := psRight;
    end
    else
    begin
      ActiveSide := 0;
      if FLeft <> nil then FFocus := psLeft;
    end;
    BuildItems;
    Count := Length(Items);
    if ActiveSide = 0 then
      BX := 2
    else
      BX := 2 + Length(' Left ') + 2;
    BoxH := Count + 2;
    ComputeBoxW;
    Sel := 0;
    if Count > 0 then
      while (Sel < Count) and Items[Sel].IsSep do Inc(Sel);
  end;

  { Dispatch a menu item by its tag value.  Extracted so both the keyboard
    Enter path and the mouse-click path share exactly one copy of this logic. }
  procedure ExecuteMenuItemByTag(Tag: Integer);
  begin
    case Tag of
      maSort:     RunSortDialog;
      maSave:     ActionSave;
      maRevert:   ActionRevert;
      maBlockMap: ActionToggleMap;
      maSectorMap: FMode := tmSectorMap;
      maHexView:
        begin
          if not EnterHexMode then
            ShowMessageBox('Hex view: cannot read this entry.');
        end;
      maDiskInfo:
        begin
          if Supports(Cont, ISummary, Summary) then
            ShowMessageBox(Summary.GetSummaryInfo);
        end;
      maDriveRead:  ActionDriveRead;
      maDriveWrite: ActionDriveWrite;
    end;
  end;

begin
  if FFocus = psLeft then ActiveSide := 0 else ActiveSide := 1;

  BuildItems;
  Count := Length(Items);

  if ActiveSide = 0 then
    BX := 2
  else
    BX := 2 + Length(' Left ') + 2;
  BY := 2;
  BoxH := Count + 2;
  ComputeBoxW;

  Sel := 0;
  if Count > 0 then
    while (Sel < Count) and Items[Sel].IsSep do Inc(Sel);

  DrawDropdown;
  repeat
    E := FInput.WaitForKey;
    case E.Action of
      kaUp:
        begin
          I := Sel;
          repeat Dec(I) until (I < 0) or not Items[I].IsSep;
          if I >= 0 then Sel := I;
        end;
      kaDown:
        begin
          I := Sel;
          repeat Inc(I) until (I >= Count) or not Items[I].IsSep;
          if I < Count then Sel := I;
        end;
      kaLeft:
        begin
          SwitchMenuSide;
        end;
      kaRight:
        begin
          SwitchMenuSide;
        end;
      kaEnter:
        begin
          if Count > 0 then
            ExecuteMenuItemByTag(Items[Sel].Tag);
          Break;
        end;
      kaEsc: Break;
      kaChar:
        if UpCase(E.CharValue) = 'Q' then Break;
      kaMouse:
        if E.MouseButton = mbLeft then
        begin
          { Click inside the dropdown rect → select + execute the item at that
            row. Click on a separator: ignore. Click outside: close menu. }
          if (E.MouseX >= BX) and (E.MouseX <= BX + BoxW - 1) and
             (E.MouseY >= BY + 1) and (E.MouseY <= BY + BoxH - 2) then
          begin
            I := E.MouseY - (BY + 1);
            if (I >= 0) and (I <= High(Items)) and not Items[I].IsSep then
            begin
              Sel := I;
              ExecuteMenuItemByTag(Items[Sel].Tag);
              Break;
            end;
          end
          else
            Break; { click outside the dropdown closes it }
        end;
    end;
    DrawDropdown;
  until False;
  FMenuOpen := False;
end;

procedure TTUIController.ActionExit;

  function HasUnsaved(ASide: TPaneSide): Boolean;
  var
    Cont: IContainer;
    Writable: IWritable;
    I: Integer;
  begin
    Result := False;
    Cont := ContainerForSide(ASide);
    if (Cont <> nil) and Supports(Cont, IWritable, Writable) and Writable.Modified then
      Exit(True);
    for I := 0 to Length(FHistory[ASide]) - 1 do
      if Supports(FHistory[ASide][I], IWritable, Writable) and Writable.Modified then
        Exit(True);
  end;

begin
  if HasUnsaved(psLeft) or HasUnsaved(psRight) then
    if not ConfirmDialog('Unsaved changes. Exit anyway') then Exit;
  FRunning := False;
end;

procedure TTUIController.ReapplySort(ASide: TPaneSide);
var
  C: IContainer;
  S: ISortable;
begin
  C := ContainerForSide(ASide);
  if (C <> nil) and Supports(C, ISortable, S) then
    S.Sort(FSortField[ASide], FSortAscending[ASide], FDirsFirst[ASide]);
end;

procedure TTUIController.HandleMouse(const AEvent: TInputEvent);
var
  Side: TPaneSide;
  HalfW, Row, NewCursor: Integer;
  Cont: IContainer;
  I: Integer;
begin
  HalfW := FOutput.Width div 2;
  if AEvent.MouseX <= HalfW then
    Side := psLeft
  else
    Side := psRight;

  if AEvent.MouseWheel <> 0 then
  begin
    if FMode = tmSectorMap then
    begin
      if AEvent.MouseWheel > 0 then
        for I := 1 to 3 do ActionMapScrollRight
      else
        for I := 1 to 3 do ActionMapScrollLeft;
      Exit;
    end;
    if ContainerForSide(Side) = nil then Exit;
    if FFocus <> Side then
      FFocus := Side;
    if AEvent.MouseWheel > 0 then
      for I := 1 to 3 do ActionNavigateDown
    else
      for I := 1 to 3 do ActionNavigateUp;
    Exit;
  end;

  if AEvent.MouseButton = mbLeft then
  begin
    { Status bar (bottom row): treat as click on the F-key shortcut. }
    if AEvent.MouseY = FOutput.Height then
    begin
      if StatusBarSlotAt(AEvent.MouseX) >= 0 then
        InvokeStatusBarSlot(StatusBarSlotAt(AEvent.MouseX), AEvent.Modifiers);
      Exit;
    end;
    if (AEvent.MouseY >= 4) and (AEvent.MouseY <= FOutput.Height - 2) then
    begin
      if ContainerForSide(Side) = nil then Exit;
      if FFocus <> Side then
        FFocus := Side;
      Cont := ActiveContainer;
      if (Cont = nil) or (Cont.EntryCount = 0) then Exit;
      Row := AEvent.MouseY - 4;
      NewCursor := ActiveScroll + Row;
      if NewCursor >= Cont.EntryCount then
        NewCursor := Cont.EntryCount - 1;
      if NewCursor < 0 then NewCursor := 0;
      SetActiveCursor(NewCursor);
    end;
  end;
end;

function TTUIController.StatusBarSlotAt(X: Integer): Integer;
var
  SlotW: Integer;
begin
  SlotW := FOutput.Width div 10;
  if (SlotW <= 0) or (X < 1) or (X > FOutput.Width) then Exit(-1);
  Result := ((X - 1) div SlotW) + 1;
  if (Result < 1) or (Result > 10) then Result := -1;
end;

procedure TTUIController.InvokeStatusBarSlot(Slot: Integer; AModifiers: Byte);
begin
  case Slot of
    1: ShowMessageBox('DiskBender Commander v0.2 -- Tab to switch panes, Enter to open');
    2: ActionSave;
    3:
      if (AModifiers and KM_SHIFT) <> 0 then ActionShowSectorMap
      else if (AModifiers and KM_CTRL) <> 0 then ActionShowBlockMap
      else ActionToggleMap;
    5: ActionCopy;
    6: ActionRename;
    8: ActionDelete;
    9: ActionMenu;
    10: ActionExit;
  end;
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
  FDateKind[psLeft] := dkModification;
  FDateKind[psRight] := dkModification;
  FSortField[psLeft] := sfName;
  FSortField[psRight] := sfName;
  FSortAscending[psLeft] := True;
  FSortAscending[psRight] := True;
  FDirsFirst[psLeft] := True;
  FDirsFirst[psRight] := True;
  FRunning := True;
  FMenuOpen := False;
  FMapScrollX := 0;
  FModifierState := 0;
  FLastModifierState := $FF;  { sentinel: force redraw on first real event }
end;

procedure TTUIController.HandleEvent(const AEvent: TInputEvent);
begin
  { Every event carries the modifier state at event time (kitty keyboard
    protocol or xterm CSI parameters). Tracking it here means DrawStatusBar
    can show modifier-aware labels reactively on terminals that emit
    standalone modifier press/release events (kitty / wezterm / iTerm2 with
    CSI-u enabled). On Terminal.app the state only changes when a chord key
    arrives, so labels appear briefly during the chord. }
  FModifierState := AEvent.Modifiers;
  if AEvent.Action = kaModifierChange then
  begin
    if AEvent.Modifiers <> FLastModifierState then
    begin
      FLastModifierState := AEvent.Modifiers;
      DrawStatusBar;
      FOutput.Flush;
    end;
    Exit;
  end;

  if FMode = tmHex then
  begin
    case AEvent.Action of
      kaUp:       ActionHexScrollUp;
      kaDown:     ActionHexScrollDown;
      kaPageUp:   ActionHexPageUp;
      kaPageDown: ActionHexPageDown;
      kaHome:     ActionHexHome;
      kaEnd:      ActionHexEnd;
      { Esc/F10/Backspace close the hex view back to the commander panes.
        F10 used to exit the app — that surprised users who expected the
        usual "exit-the-current-view" semantics from NC-style TUIs. }
      kaEsc, kaF10, kaBackspace:
        begin SetLength(FHexData, 0); SetLength(FHexLines, 0); FMode := tmCommander; end;
      kaF3:
        if (AEvent.Modifiers and KM_SHIFT) <> 0 then ActionShowSectorMap
        else if (AEvent.Modifiers and KM_CTRL) <> 0 then ActionShowBlockMap
        else ActionToggleMap;
      kaModifierChange: { redraw handled by main loop };
      kaChar:
        case UpCase(AEvent.CharValue) of
          'W': ActionHexScrollUp;
          'S': ActionHexScrollDown;
          'Q':
            begin SetLength(FHexData, 0); SetLength(FHexLines, 0); FMode := tmCommander; end;
        end;
    end;
    Exit;
  end;

  { In the disk-block / sector-map views, Esc and F10 close the view rather
    than exiting the app. (F10/Esc in the commander panes still exit the app
    after the unsaved-changes confirmation.) }
  if FMode in [tmDiskMap, tmSectorMap] then
  begin
    case AEvent.Action of
      kaEsc, kaF10, kaBackspace:
        begin FMapScrollX := 0; FMode := tmCommander; Exit; end;
      kaChar:
        if UpCase(AEvent.CharValue) = 'Q' then
        begin FMapScrollX := 0; FMode := tmCommander; Exit; end;
    end;
  end;

  case AEvent.Action of
    kaLeft:      if FMode = tmSectorMap then ActionMapScrollLeft;
    kaRight:     if FMode = tmSectorMap then ActionMapScrollRight;
    kaUp:        if FMode <> tmSectorMap then ActionNavigateUp;
    kaDown:      if FMode <> tmSectorMap then ActionNavigateDown;
    kaHome:      if FMode = tmSectorMap then ActionMapScrollHome else ActionHome;
    kaEnd:       if FMode = tmSectorMap then ActionMapScrollEnd else ActionEnd;
    kaPageUp:    if FMode <> tmSectorMap then ActionPageUp;
    kaPageDown:  if FMode <> tmSectorMap then ActionPageDown;
    kaEnter:     ActionEnter;
    kaBackspace: ActionGoBack;
    kaTab:       ActionSwitchPane;
    kaEsc:       ActionExit;
    kaF1:        ShowMessageBox('DiskBender Commander v0.2 -- Tab to switch panes, Enter to open');
    kaF2:        ActionSave;
    kaF3:
      if (AEvent.Modifiers and KM_SHIFT) <> 0 then ActionShowSectorMap
      else if (AEvent.Modifiers and KM_CTRL) <> 0 then ActionShowBlockMap
      else ActionToggleMap;
    kaF5:        ActionCopy;
    kaF6:        ActionRename;
    kaF8:        ActionDelete;
    kaF9:        ActionMenu;
    kaF10:       ActionExit;
    kaMouse:     HandleMouse(AEvent);
    kaChar:
      case UpCase(AEvent.CharValue) of
        'W': ActionNavigateUp;
        'S': ActionNavigateDown;
        'Q': ActionExit;
        'M': ActionToggleMap;
        ' ': ActionSelect;
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

procedure TTUIController.RenderForTest;
begin
  UpdateScreen;
end;

function TTUIController.RunInputDialogForTest(const APrompt, ADefault: string;
                                              out AText: string): Boolean;
begin
  Result := InputDialog(APrompt, ADefault, AText);
end;

end.
