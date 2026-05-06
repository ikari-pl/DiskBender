unit uTUI_Custom;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Keyboard, Video, uDSK, uCPM, uLocalFS, uInterfaces, Classes;

type
  TPaneType = (ptLocal, ptDSK);
  TTUIMode = (tmCommander, tmDiskMap);
  TMenuActionProc = procedure of object;

  TMenuItem = record
    Title: string;
    Shortcut: string;
    KeyCode: LongWord;
    Action: TMenuActionProc;
  end;

  TMenuCategory = record
    Title: string;
    Items: array of TMenuItem;
  end;

  TDiskBenderTUI = class
  private
    FDisk: IVirtualDisk;
    FFS: IFilesystem;
    FLocal: TLocalFS;
    FMode: TTUIMode;
    FFocusedPane: TPaneType;
    FLCursor, FRCursor: Integer;
    FLScroll, FRScroll: Integer;
    FRunning: Boolean;
    FLastKey: LongWord;
    FDSKPath: string;
    FMenu: array of TMenuCategory;

    procedure TextOut(X, Y: Integer; const S: string; Color: Byte = $07);
    procedure DrawBox(X1, Y1, X2, Y2: Integer; const Title: string; Attr: Byte);
    procedure ClearScreen;
    procedure DrawHeader;
    procedure DrawMenuBar;
    procedure DrawPanes;
    procedure DrawDiskMap;
    procedure DrawStatusBar;
    procedure UpdateScreen;
    procedure HandleAction(KeyCode: LongWord);
    procedure ShowMessage(const Msg: string);
    function ConfirmDialog(const Msg: string): Boolean;

    { Menu Actions }
    procedure ActionSave;
    procedure ActionCopy;
    procedure ActionToggleDelete;
    procedure ActionRevert;
    procedure ActionExit;
    procedure ActionAbout;
    procedure ActionChangeDir;
    procedure ActionToggleMap;

    procedure InitMenu;
  public
    constructor Create(const ADSKPath: string; ADisk: IVirtualDisk);
    destructor Destroy; override;
    procedure Run;
  end;

implementation

procedure TDiskBenderTUI.TextOut(X, Y: Integer; const S: string; Color: Byte = $07);
var
  I: Integer;
begin
  if (Y < 1) or (Y > ScreenHeight) then Exit;
  for I := 1 to Length(S) do
  begin
    if (X + I - 1 <= ScreenWidth) then
      VideoBuf^[(Y - 1) * ScreenWidth + (X + I - 2)] := ord(S[I]) or (Color shl 8);
  end;
end;

procedure TDiskBenderTUI.DrawBox(X1, Y1, X2, Y2: Integer; const Title: string; Attr: Byte);
var
  I: Integer;
begin
  for I := X1 + 1 to X2 - 1 do
  begin
    TextOut(I, Y1, #196, Attr);
    TextOut(I, Y2, #196, Attr);
  end;
  for I := Y1 + 1 to Y2 - 1 do
  begin
    TextOut(X1, I, #179, Attr);
    TextOut(X2, I, #179, Attr);
  end;
  TextOut(X1, Y1, #218, Attr);
  TextOut(X2, Y1, #191, Attr);
  TextOut(X1, Y2, #192, Attr);
  TextOut(X2, Y2, #217, Attr);
  
  if Title <> '' then
    TextOut(X1 + (X2 - X1 - (Length(Title)+2)) div 2, Y1, ' ' + Title + ' ', Attr);
end;

procedure TDiskBenderTUI.ClearScreen;
var
  I: Integer;
begin
  for I := 0 to ScreenWidth * ScreenHeight - 1 do
    VideoBuf^[I] := ord(' ') or ($07 shl 8);
end;

constructor TDiskBenderTUI.Create(const ADSKPath: string; ADisk: IVirtualDisk);
begin
  inherited Create;
  FDisk := ADisk;
  FDSKPath := ADSKPath;
  FFS := TDiskBenderCPM.Create(FDisk);
  (FFS as TDiskBenderCPM).AutoDetectFormat;
  FFS.ScanDirectory;
  FLocal := TLocalFS.Create('.');
  FMode := tmCommander;
  FFocusedPane := ptDSK;
  FLCursor := 0; FRCursor := 0;
  FLScroll := 0; FRScroll := 0;
  FRunning := True;
  InitVideo;
  InitKeyboard;
  InitMenu;
end;

destructor TDiskBenderTUI.Destroy;
begin
  DoneKeyboard;
  DoneVideo;
  FFS := nil;
  FLocal.Free;
  inherited Destroy;
end;

procedure TDiskBenderTUI.InitMenu;
begin
  SetLength(FMenu, 3);
  
  FMenu[0].Title := 'File';
  SetLength(FMenu[0].Items, 3);
  FMenu[0].Items[0].Title := 'Save'; FMenu[0].Items[0].Shortcut := 'F2'; FMenu[0].Items[0].KeyCode := $3C00; FMenu[0].Items[0].Action := @ActionSave;
  FMenu[0].Items[1].Title := 'Revert'; FMenu[0].Items[1].Shortcut := 'F9'; FMenu[0].Items[1].KeyCode := $4300; FMenu[0].Items[1].Action := @ActionRevert;
  FMenu[0].Items[2].Title := 'Exit'; FMenu[0].Items[2].Shortcut := 'F10'; FMenu[0].Items[2].KeyCode := $4400; FMenu[0].Items[2].Action := @ActionExit;

  FMenu[1].Title := 'Disk';
  SetLength(FMenu[1].Items, 3);
  FMenu[1].Items[0].Title := 'Copy'; FMenu[1].Items[0].Shortcut := 'F5'; FMenu[1].Items[0].KeyCode := $3F00; FMenu[1].Items[0].Action := @ActionCopy;
  FMenu[1].Items[1].Title := 'Del/Undel'; FMenu[1].Items[1].Shortcut := 'F8'; FMenu[1].Items[1].KeyCode := $4200; FMenu[1].Items[1].Action := @ActionToggleDelete;
  FMenu[1].Items[2].Title := 'Map'; FMenu[1].Items[2].Shortcut := 'F3'; FMenu[1].Items[2].KeyCode := $3D00; FMenu[1].Items[2].Action := @ActionToggleMap;

  FMenu[2].Title := 'Help';
  SetLength(FMenu[2].Items, 1);
  FMenu[2].Items[0].Title := 'About'; FMenu[2].Items[0].Shortcut := 'F1'; FMenu[2].Items[0].KeyCode := $3B00; FMenu[2].Items[0].Action := @ActionAbout;
end;

procedure TDiskBenderTUI.DrawHeader;
var
  S: string;
begin
  S := ' DiskBender Commander v0.1 ';
  TextOut(1, 1, StringOfChar(' ', ScreenWidth), $70);
  TextOut((ScreenWidth - Length(S)) div 2, 1, S, $70);
end;

procedure TDiskBenderTUI.DrawMenuBar;
var
  I, XPos: Integer;
begin
  TextOut(1, 2, StringOfChar(' ', ScreenWidth), $07);
  XPos := 2;
  for I := 0 to High(FMenu) do
  begin
    TextOut(XPos, 2, ' ' + FMenu[I].Title + ' ', $07);
    XPos := XPos + Length(FMenu[I].Title) + 4;
  end;
end;

procedure TDiskBenderTUI.DrawPanes;
var
  I, J, MaxY, PaneWidth: Integer;
  S, ModStr: string;
  VFile: IVirtualFile;
  LFile: TLocalFile;
  Attr, BoxAttr, GrayAttr: Byte;
begin
  PaneWidth := ScreenWidth div 2;
  MaxY := ScreenHeight - 1;
  GrayAttr := $18; 

  { LEFT Pane: DSK Image }
  if FFocusedPane = ptDSK then BoxAttr := $1F else BoxAttr := $17;
  if FDisk.Modified then ModStr := ' [MOD]' else ModStr := '';
  DrawBox(1, 3, PaneWidth, MaxY - 1, ExtractFileName(FDSKPath) + ModStr, BoxAttr);
  for J := 4 to MaxY - 2 do for I := 2 to PaneWidth - 1 do TextOut(I, J, ' ', BoxAttr);
  
  S := ' Format: ' + FFS.GetSummaryInfo;
  TextOut(2, 4, S, GrayAttr);

  for I := 0 to MaxY - 8 do
  begin
    if I + FRScroll < FFS.GetFileCount then
    begin
      VFile := FFS.GetFile(I + FRScroll);
      S := Format(' %-12s %-4s %8d', [VFile.Name, VFile.Extension, VFile.SizeKB]);
      if VFile.IsDeleted then S := '[DEL] ' + S else S := '      ' + S;
      if (FFocusedPane = ptDSK) and (I + FRScroll = FRCursor) then Attr := $30 else Attr := BoxAttr;
      TextOut(2, 5 + I, S, Attr);
    end;
  end;

  { RIGHT Pane: Local FS }
  if FFocusedPane = ptLocal then BoxAttr := $1F else BoxAttr := $17;
  DrawBox(PaneWidth + 1, 3, ScreenWidth, MaxY - 1, ' Host File System ', BoxAttr);
  for J := 4 to MaxY - 2 do for I := PaneWidth + 2 to ScreenWidth - 1 do TextOut(I, J, ' ', BoxAttr);
  TextOut(PaneWidth + 2, 4, ' ' + FLocal.CurrentDir, GrayAttr);

  for I := 0 to MaxY - 8 do
  begin
    if I + FLScroll < FLocal.Count then
    begin
      LFile := FLocal.GetFile(I + FLScroll);
      if LFile.IsDir then S := Format(' [%-12s] ', [LFile.Name]) else S := Format(' %-14s ', [LFile.Name]);
      S := S + Format('%8d', [LFile.Size]);
      if (FFocusedPane = ptLocal) and (I + FLScroll = FLCursor) then Attr := $30 else Attr := BoxAttr;
      TextOut(PaneWidth + 2, 5 + I, S, Attr);
    end;
  end;
end;

procedure TDiskBenderTUI.DrawDiskMap;
var
  I, X, Y, W: Integer;
  Map: TBytes;
  Attr: Byte;
  Legend: string;
begin
  DrawBox(1, 3, ScreenWidth, ScreenHeight - 1, ' Allocation Block Map ', $1F);
  Map := FFS.GetBlockMap;
  
  W := ScreenWidth - 4;
  for I := 0 to Length(Map) - 1 do
  begin
    X := (I mod W) + 3;
    Y := (I div W) + 5;
    if Y >= ScreenHeight - 3 then Break;
    
    case Map[I] of
      0: Attr := $07;
      1: Attr := $0E;
      2: Attr := $0A;
      3: Attr := $0C;
    end;
    TextOut(X, Y, #219, Attr);
  end;

  Legend := ' [ ] Free  ['#219'] Dir  ['#219'] Used  ['#219'] Deleted ';
  TextOut(3, ScreenHeight - 2, Legend, $07);
  TextOut(4, ScreenHeight - 2, #219, $07);
  TextOut(14, ScreenHeight - 2, #219, $0E);
  TextOut(23, ScreenHeight - 2, #219, $0A);
  TextOut(33, ScreenHeight - 2, #219, $0C);
end;

procedure TDiskBenderTUI.DrawStatusBar;
begin
  TextOut(1, ScreenHeight, ' [F2] Save  [F3] Map  [F5] Copy  [F8] Del/Undel  [F10] Exit  [Tab] Pane ', $70);
end;

procedure TDiskBenderTUI.ShowMessage(const Msg: string);
var
  X, Y: Integer;
begin
  X := (ScreenWidth - Length(Msg) - 4) div 2;
  Y := ScreenHeight div 2;
  TextOut(X, Y, '  ' + Msg + '  ', $4F);
  Video.UpdateScreen(False);
  GetKeyEvent;
end;

function TDiskBenderTUI.ConfirmDialog(const Msg: string): Boolean;
var
  X, Y: Integer;
  K: TKeyEvent;
begin
  X := (ScreenWidth - Length(Msg) - 10) div 2;
  Y := ScreenHeight div 2;
  TextOut(X, Y, '  ' + Msg + ' (Y/N)?  ', $4F);
  Video.UpdateScreen(False);
  repeat
    K := GetKeyEvent;
    K := TranslateKeyEvent(K);
    case UpCase(Char(GetKeyEventCode(K) and $FF)) of
      'Y': Exit(True);
      'N': Exit(False);
    end;
  until False;
end;

procedure TDiskBenderTUI.ActionSave;
begin
  if FDisk.Modified then
  begin
    if ConfirmDialog('Save changes to file') then
    begin
      FDisk.Save;
      ShowMessage('Disk saved successfully.');
    end;
  end else ShowMessage('No changes to save.');
end;

procedure TDiskBenderTUI.ActionCopy;
var
  VFile: IVirtualFile;
  LStream: TFileStream;
  DestPath: string;
begin
  if FFocusedPane = ptDSK then
  begin
    if (FRCursor < 0) or (FRCursor >= FFS.GetFileCount) then Exit;
    VFile := FFS.GetFile(FRCursor);
    DestPath := FLocal.CurrentDir + '/' + VFile.Name;
    if VFile.Extension <> '' then DestPath := DestPath + '.' + VFile.Extension;
    
    if ConfirmDialog('Extract ' + VFile.Name + ' to ' + FLocal.CurrentDir) then
    begin
      LStream := TFileStream.Create(DestPath, fmCreate);
      try
        FFS.GetFileContent(FRCursor, LStream);
        ShowMessage('File extracted successfully.');
        FLocal.SetDir(FLocal.CurrentDir);
      finally
        LStream.Free;
      end;
    end;
  end else ShowMessage('Injection not yet implemented!');
end;

procedure TDiskBenderTUI.ActionToggleDelete;
begin
  if FFocusedPane = ptDSK then
  begin
    FFS.ToggleDelete(FRCursor);
    FFS.ScanDirectory;
  end;
end;

procedure TDiskBenderTUI.ActionToggleMap;
begin
  if FMode = tmCommander then FMode := tmDiskMap else FMode := tmCommander;
end;

procedure TDiskBenderTUI.ActionRevert;
begin
  if FDisk.Modified then
  begin
    if ConfirmDialog('Revert all changes') then
    begin
      FDisk.Revert;
      FFS.ScanDirectory;
      ShowMessage('Changes reverted.');
    end;
  end;
end;

procedure TDiskBenderTUI.ActionExit;
begin
  if FDisk.Modified then
  begin
    if ConfirmDialog('Disk is modified. Exit anyway') then FRunning := False;
  end else FRunning := False;
end;

procedure TDiskBenderTUI.ActionAbout;
begin
  ShowMessage('DiskBender Commander v0.1 - (c) 2026 Futurama Fans');
end;

procedure TDiskBenderTUI.ActionChangeDir;
var
  LFile: TLocalFile;
  NewDir: string;
begin
  LFile := FLocal.GetFile(FLCursor);
  if LFile.IsDir then
  begin
    if LFile.Name = '..' then
      NewDir := ExtractFileDir(FLocal.CurrentDir)
    else
      NewDir := FLocal.CurrentDir + '/' + LFile.Name;
    
    FLocal.SetDir(NewDir);
    FLCursor := 0;
    FLScroll := 0;
  end;
end;

procedure TDiskBenderTUI.UpdateScreen;
begin
  ClearScreen;
  DrawHeader;
  DrawMenuBar;
  if FMode = tmCommander then DrawPanes else DrawDiskMap;
  DrawStatusBar;
  Video.UpdateScreen(False);
end;

procedure TDiskBenderTUI.HandleAction(KeyCode: LongWord);
var
  I, J: Integer;
begin
  for I := 0 to High(FMenu) do
    for J := 0 to High(FMenu[I].Items) do
      if (KeyCode shr 8 = FMenu[I].Items[J].KeyCode shr 8) then
      begin
        FMenu[I].Items[J].Action();
        Exit;
      end;

  case KeyCode shr 8 of
    $01: ActionExit; { ESC }
    $0F: if FFocusedPane = ptLocal then FFocusedPane := ptDSK else FFocusedPane := ptLocal; { Tab }
    $1C: if FFocusedPane = ptLocal then ActionChangeDir; { Enter }
    $48, $FF21: { Up }
      if FFocusedPane = ptLocal then
        begin if FLCursor > 0 then Dec(FLCursor); if FLCursor < FLScroll then FLScroll := FLCursor; end
      else
        begin if FRCursor > 0 then Dec(FRCursor); if FRCursor < FRScroll then FRScroll := FRCursor; end;
    $50, $FF27: { Down }
      if FFocusedPane = ptLocal then
        begin if FLCursor < FLocal.Count - 1 then Inc(FLCursor); if FLCursor >= FLScroll + (ScreenHeight - 8) then Inc(FLScroll); end
      else
        begin if FRCursor < FFS.GetFileCount - 1 then Inc(FRCursor); if FRCursor >= FRScroll + (ScreenHeight - 8) then Inc(FRScroll); end;
  end;

  case KeyCode and $FF of
    ord('w'), ord('W'): HandleAction($4800);
    ord('s'), ord('S'): HandleAction($5000);
    ord('u'), ord('U'): ActionToggleDelete;
    ord('m'), ord('M'): ActionToggleMap;
  end;
end;

procedure TDiskBenderTUI.Run;
var
  K: TKeyEvent;
begin
  while FRunning do
  begin
    UpdateScreen;
    K := GetKeyEvent;
    K := TranslateKeyEvent(K);
    FLastKey := GetKeyEventCode(K);
    HandleAction(FLastKey);
  end;
end;

end.
