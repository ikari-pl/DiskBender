unit uViewers;

{ Programmatic helper forms (created without LFM):
    - ShowHexViewer(Title, Data)            — TPaintBox hex/ASCII grid with byte selection
    - ShowTextViewer(Title, Text)           — monospace text viewer
    - ShowDiskMap(Title, Map, ...)          — colour-coded block map grid
    - ShowSectorMap(Title, Tracks, Owned)   — protection-aware sector map
    - ShowGWReadDialog(GwPath, Path)        — unified Greaseweazle read dialog
    - ShowGWWriteDialog(GwPath, Path)       — unified Greaseweazle write dialog
  Each helper creates a modal form on demand and frees it on close. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Graphics, Controls, Forms, StdCtrls, ComCtrls, ExtCtrls,
  Dialogs, LCLType, uVFS, uInterfaces, uExternalDrive;

type
  { Base for all non-modal viewer windows.
    - Frees itself on close (caFree) after firing OnViewerClosed.
    - Subclasses that show selection-dependent data override UpdateSelection.
    - Subclasses that support docking override DockTo / Undock.
      TMainForm sets OnDockRequest so the viewer can show a dock button. }
  TViewerForm = class(TForm)
  public
    OnViewerClosed: TNotifyEvent;  { fired before caFree }
    OnDockRequest:  TNotifyEvent;  { set by TMainForm; signals that docking is available }
    procedure FormClose(Sender: TObject; var CloseAction: TCloseAction);
    procedure UpdateSelection(const AOwnedSectors: TPhysicalSectorArray;
                              const AHighlight: TBlockNumberArray); virtual;
    { Docking — only TDiskPlatterForm overrides; others are silent no-ops. }
    procedure DockTo(AHost: TWinControl); virtual;
    procedure Undock; virtual;
  end;

{ Show* — modeless, self-freeing.
  ShowDiskMap / ShowSectorMap / ShowDiskPlatter return the live TViewerForm so
  TMainForm can register it for selection-change notifications. }
procedure ShowHexViewer(const Title: string; const Data: TBytes);
procedure ShowTextViewer(const Title, Body: string);
function  ShowDiskMap(const Title: string; const Map: TBytes;
                      BlocksPerRow: Integer = 32;
                      const HighlightBlocks: TBlockNumberArray = nil): TViewerForm;
function  ShowSectorMap(const Title: string;
                        const Tracks: TTrackColumnArray;
                        const OwnedSectors: TPhysicalSectorArray): TViewerForm;
function ShowGWReadDialog(const AGwPath: string; out AImagePath: string): Boolean;
function ShowGWWriteDialog(const AGwPath, AImagePath: string): Boolean;
function  ShowDiskPlatter(const ATitle: string;
                          const ATracks: TTrackColumnArray;
                          const AOwnedSectors: TPhysicalSectorArray;
                          ADisk: IVirtualDisk): TViewerForm;

implementation

type
  { Plain scrollable text viewer — internal, no selection tracking. }
  TTextViewerForm = class(TViewerForm)
  public
    constructor CreateWithText(const ATitle, ABody: string);
  end;

  { TPaintBox-based hex/ASCII viewer with clickable byte selection. }
  THexViewerForm = class(TViewerForm)
  private
    FData: TBytes;
    FPB: TPaintBox;
    FStatusLabel: TLabel;
    FSelectedByte: Integer;
    FCharW: Integer;
    FLineH: Integer;
    procedure DoPaint(Sender: TObject);
    procedure DoMouseDown(Sender: TObject; Button: TMouseButton;
                          Shift: TShiftState; X, Y: Integer);
  public
    constructor CreateWithData(const ATitle: string; const AData: TBytes);
  end;

  { Block map dialog — colour-coded grid with optional per-file highlighting. }
  TDiskMapForm = class(TViewerForm)
  private
    FMap: TBytes;
    FBlocksPerRow: Integer;
    FHighlightBlocks: TBlockNumberArray;
    FPB: TPaintBox;
    function IsHighlighted(AIdx: Integer): Boolean;
    procedure DoPaint(Sender: TObject);
  public
    constructor CreateWithMap(const ATitle: string; const AMap: TBytes;
                              ABlocksPerRow: Integer;
                              const AHighlight: TBlockNumberArray);
    procedure UpdateSelection(const AOwnedSectors: TPhysicalSectorArray;
                              const AHighlight: TBlockNumberArray); override;
  end;

  { Sector map dialog — protection-aware visual grid. }
  TSectorMapForm = class(TViewerForm)
  private
    FTracks: TTrackColumnArray;
    FOwnedSectors: TPhysicalSectorArray;
    FPB: TPaintBox;
    FStatusLabel: TLabel;
    function CellColor(const Cell: TSectorCell): TColor;
    function IsSectorOwned(ATrackIdx: Integer; ASectorID: Byte): Boolean;
    procedure DoPaint(Sender: TObject);
    procedure DoMouseDown(Sender: TObject; Button: TMouseButton;
                          Shift: TShiftState; X, Y: Integer);
  public
    constructor CreateWithMap(const ATitle: string;
                              const ATracks: TTrackColumnArray;
                              const AOwnedSectors: TPhysicalSectorArray);
    procedure UpdateSelection(const AOwnedSectors: TPhysicalSectorArray;
                              const AHighlight: TBlockNumberArray); override;
  end;

  { Unified Greaseweazle dialog — read or write mode. }
  TGWMode = (gwmRead, gwmWrite);

  TGWForm = class(TForm)
  private
    FMode: TGWMode;
    FGwPath: string;
    FImagePath: string;
    FSucceeded: Boolean;
    CbDrive: TComboBox;
    EditPath: TEdit;
    LogMemo: TMemo;
    BtnRun: TButton;
    BtnClose: TButton;
    procedure BtnRunClick(Sender: TObject);
    procedure BtnBrowseClick(Sender: TObject);
  public
    constructor CreateForRead(const AGwPath: string);
    constructor CreateForWrite(const AGwPath, AImagePath: string);
    property Succeeded: Boolean read FSucceeded;
    property ImagePath: string read FImagePath;
  end;

  { Physical platter view — concentric rings, proportional sectors, luminance-
    modulated by actual byte values from IVirtualDisk.GetSectorData. }
  TDiskPlatterForm = class(TViewerForm)
  private
    FDisk: IVirtualDisk;
    FTracks: TTrackColumnArray;
    FOwnedSectors: TPhysicalSectorArray;
    FPB: TPaintBox;
    FStatusLabel: TLabel;
    FBitmapCache: TBitmap;
    FBitmapValid: Boolean;
    FCX, FCY: Integer;
    FR_max, FR_min, FRingH: Double;
    FDockHost: TWinControl;  { non-nil while docked into the main-form pane }
    procedure DoPaint(Sender: TObject);
    procedure DoMouseDown(Sender: TObject; Button: TMouseButton;
                          Shift: TShiftState; X, Y: Integer);
    procedure DoResize(Sender: TObject);
    procedure RenderToCache;
    procedure HitTest(AX, AY: Integer; out TrackIdx, SectorIdx: Integer);
    function PlatterCellColor(const ACell: TSectorCell): TColor;
    function PlatterSectorOwned(ATrackIdx: Integer; ASectorID: Byte): Boolean;
    procedure DockBtnClick(Sender: TObject);
  public
    constructor CreateWithData(const ATitle: string;
                               const ATracks: TTrackColumnArray;
                               const AOwnedSectors: TPhysicalSectorArray;
                               ADisk: IVirtualDisk);
    destructor Destroy; override;
    procedure UpdateSelection(const AOwnedSectors: TPhysicalSectorArray;
                              const AHighlight: TBlockNumberArray); override;
    procedure DockTo(AHost: TWinControl); override;
    procedure Undock; override;
  end;

{ ── TViewerForm / TTextViewerForm ──────────────────────────────────────────── }

procedure TViewerForm.FormClose(Sender: TObject; var CloseAction: TCloseAction);
begin
  { Fire first so the owner can nil its tracked reference BEFORE the object dies. }
  if Assigned(OnViewerClosed) then OnViewerClosed(Self);
  CloseAction := caFree;
end;

procedure TViewerForm.UpdateSelection(const AOwnedSectors: TPhysicalSectorArray;
                                      const AHighlight: TBlockNumberArray);
begin
  { Default: do nothing — hex/text viewers are read-only snapshots. }
end;

procedure TViewerForm.DockTo(AHost: TWinControl);
begin { Base no-op: only TDiskPlatterForm overrides. } end;

procedure TViewerForm.Undock;
begin { Base no-op: only TDiskPlatterForm overrides. } end;

{ ── TDiskMapForm.UpdateSelection ──────────────────────────────────────────── }

procedure TDiskMapForm.UpdateSelection(const AOwnedSectors: TPhysicalSectorArray;
                                       const AHighlight: TBlockNumberArray);
begin
  FHighlightBlocks := AHighlight;
  FPB.Invalidate;
end;

{ ── TSectorMapForm.UpdateSelection ─────────────────────────────────────────── }

procedure TSectorMapForm.UpdateSelection(const AOwnedSectors: TPhysicalSectorArray;
                                         const AHighlight: TBlockNumberArray);
begin
  FOwnedSectors := AOwnedSectors;
  FPB.Invalidate;
end;

{ ── TDiskPlatterForm.UpdateSelection ───────────────────────────────────────── }

procedure TDiskPlatterForm.UpdateSelection(const AOwnedSectors: TPhysicalSectorArray;
                                           const AHighlight: TBlockNumberArray);
begin
  FOwnedSectors := AOwnedSectors;
  FBitmapValid  := False;   { force full re-render with new ownership rings }
  FPB.Invalidate;
end;

constructor TTextViewerForm.CreateWithText(const ATitle, ABody: string);
var
  M: TMemo;
begin
  CreateNew(nil);
  Caption      := ATitle;
  Width        := 760;
  Height       := 540;
  Position     := poScreenCenter;
  BorderStyle  := bsSizeable;
  OnClose      := @FormClose;

  M            := TMemo.Create(Self);
  M.Parent     := Self;
  M.Align      := alClient;
  M.ReadOnly   := True;
  M.ScrollBars := ssAutoBoth;
  M.WordWrap   := False;
  M.Font.Name  := 'Menlo';
  M.Font.Size  := 11;
  M.Text       := ABody;
end;

{ ── THexViewerForm ────────────────────────────────────────────────────────── }

{ Layout per row (all monospace chars, PAD pixel offset):
    XXXXXXXX: xx xx xx xx xx xx xx xx  xx xx xx xx xx xx xx xx  |................|
    ^10 chars ^-- 8x3 = 24 chars --^1 ^-- 8x3 = 24 chars --^sp ^|^--16 chars--^^|^
    Total = 10+24+1+24+1+1+16+1 = 78 chars                       60             77 }

constructor THexViewerForm.CreateWithData(const ATitle: string; const AData: TBytes);
const
  PAD = 6;
var
  SB: TScrollBox;
  BMP: TBitmap;
  NumRows, PBW, PBH: Integer;
begin
  CreateNew(nil);
  FData := AData;
  FSelectedByte := -1;

  Caption := ATitle;
  Width := 820;
  Height := 580;
  Position := poScreenCenter;
  BorderStyle := bsSizeable;
  OnClose := @FormClose;

  BMP := TBitmap.Create;
  try
    BMP.Canvas.Font.Name := 'Menlo';
    BMP.Canvas.Font.Size := 11;
    FCharW := BMP.Canvas.TextWidth('0');
    FLineH := BMP.Canvas.TextHeight('Mg') + 2;
  finally
    BMP.Free;
  end;

  FStatusLabel := TLabel.Create(Self);
  FStatusLabel.Parent := Self;
  FStatusLabel.Align := alBottom;
  FStatusLabel.AutoSize := False;
  FStatusLabel.Height := 24;
  FStatusLabel.Caption := '  Click a byte to inspect it.';

  SB := TScrollBox.Create(Self);
  SB.Parent := Self;
  SB.Align := alClient;
  SB.AutoScroll := True;
  SB.HorzScrollBar.Tracking := True;
  SB.VertScrollBar.Tracking := True;

  NumRows := (Length(FData) + 15) div 16;
  PBW := 78 * FCharW + 2 * PAD;
  PBH := NumRows * FLineH + 2 * PAD;

  FPB := TPaintBox.Create(SB);
  FPB.Parent := SB;
  FPB.Left := 0;
  FPB.Top := 0;
  FPB.Width := PBW;
  FPB.Height := PBH;
  FPB.OnPaint := @DoPaint;
  FPB.OnMouseDown := @DoMouseDown;
end;

procedure THexViewerForm.DoPaint(Sender: TObject);
const
  PAD = 6;
var
  Row, Col, Offset, N, HexX, AscX: Integer;
  Y: Integer;
  B: Byte;
begin
  N := Length(FData);
  if N = 0 then Exit;
  with FPB.Canvas do
  begin
    Brush.Color := clWindow;
    FillRect(0, 0, FPB.Width, FPB.Height);
    Font.Name := 'Menlo';
    Font.Size := 11;
    Brush.Style := bsClear;

    for Row := 0 to (N + 15) div 16 - 1 do
    begin
      Offset := Row * 16;
      Y := PAD + Row * FLineH;

      Font.Color := clGrayText;
      TextOut(PAD, Y, Format('%8.8x: ', [Offset]));

      for Col := 0 to 15 do
      begin
        if Offset + Col >= N then Break;
        B := FData[Offset + Col];

        HexX := PAD + (10 + Col * 3) * FCharW;
        if Col >= 8 then Inc(HexX, FCharW);
        AscX := PAD + (61 + Col) * FCharW;

        if FSelectedByte = Offset + Col then
        begin
          Brush.Style := bsSolid;
          Brush.Color := clHighlight;
          FillRect(HexX, Y, HexX + 2 * FCharW, Y + FLineH);
          FillRect(AscX, Y, AscX + FCharW, Y + FLineH);
          Brush.Style := bsClear;
          Font.Color := clHighlightText;
        end
        else
          Font.Color := clWindowText;

        TextOut(HexX, Y, Format('%2.2x', [B]));
        if (B >= 32) and (B < 127) then
          TextOut(AscX, Y, Chr(B))
        else
          TextOut(AscX, Y, '.');
      end;

      Font.Color := clGrayText;
      TextOut(PAD + 60 * FCharW, Y, '|');
      TextOut(PAD + 77 * FCharW, Y, '|');
    end;
  end;
end;

procedure THexViewerForm.DoMouseDown(Sender: TObject; Button: TMouseButton;
                                      Shift: TShiftState; X, Y: Integer);
const
  PAD = 6;
var
  Row, Col, ByteIdx, N, HexX, AscX0: Integer;
  B: Byte;
  AscCh: string;
begin
  N := Length(FData);
  if N = 0 then Exit;

  Row := (Y - PAD) div FLineH;
  if (Row < 0) or (Row >= (N + 15) div 16) then Exit;

  { Check hex area }
  for Col := 0 to 15 do
  begin
    HexX := PAD + (10 + Col * 3) * FCharW;
    if Col >= 8 then Inc(HexX, FCharW);
    if (X >= HexX) and (X < HexX + 2 * FCharW) then
    begin
      ByteIdx := Row * 16 + Col;
      if ByteIdx < N then
      begin
        FSelectedByte := ByteIdx;
        B := FData[ByteIdx];
        if (B >= 32) and (B < 127) then AscCh := Chr(B) else AscCh := '.';
        FStatusLabel.Caption := Format(
          '  Offset: $%8.8x  (%d)    Value: $%2.2x  (%d)    ASCII: %s',
          [ByteIdx, ByteIdx, B, B, AscCh]);
        FPB.Invalidate;
      end;
      Exit;
    end;
  end;

  { Check ASCII area }
  AscX0 := PAD + 61 * FCharW;
  if (X >= AscX0) and (X < AscX0 + 16 * FCharW) then
  begin
    Col := (X - AscX0) div FCharW;
    if (Col >= 0) and (Col < 16) then
    begin
      ByteIdx := Row * 16 + Col;
      if ByteIdx < N then
      begin
        FSelectedByte := ByteIdx;
        B := FData[ByteIdx];
        if (B >= 32) and (B < 127) then AscCh := Chr(B) else AscCh := '.';
        FStatusLabel.Caption := Format(
          '  Offset: $%8.8x  (%d)    Value: $%2.2x  (%d)    ASCII: %s',
          [ByteIdx, ByteIdx, B, B, AscCh]);
        FPB.Invalidate;
      end;
    end;
  end;
end;

{ ── TGWForm ──────────────────────────────────────────────────────────────── }

constructor TGWForm.CreateForRead(const AGwPath: string);
var
  LDrive, LSave, LLog: TLabel;
  BtnBrowse: TButton;
begin
  CreateNew(nil);
  FMode    := gwmRead;
  FGwPath  := AGwPath;
  FSucceeded := False;

  Caption := 'Read Disc — Greaseweazle';
  Width := 540;
  Height := 420;
  Position := poScreenCenter;
  BorderStyle := bsSizeable;

  LDrive := TLabel.Create(Self);
  LDrive.Parent := Self;
  LDrive.Caption := 'Drive:';
  LDrive.SetBounds(12, 15, 60, 20);

  CbDrive := TComboBox.Create(Self);
  CbDrive.Parent := Self;
  CbDrive.Style := csDropDownList;
  CbDrive.SetBounds(80, 12, 80, 22);
  CbDrive.Items.Add('a');
  CbDrive.Items.Add('b');
  CbDrive.ItemIndex := 0;

  LSave := TLabel.Create(Self);
  LSave.Parent := Self;
  LSave.Caption := 'Save as:';
  LSave.SetBounds(12, 47, 62, 20);

  EditPath := TEdit.Create(Self);
  EditPath.Parent := Self;
  EditPath.SetBounds(80, 44, 322, 22);
  EditPath.Anchors := [akLeft, akTop, akRight];

  BtnBrowse := TButton.Create(Self);
  BtnBrowse.Parent := Self;
  BtnBrowse.Caption := 'Browse...';
  BtnBrowse.SetBounds(410, 43, 80, 24);
  BtnBrowse.Anchors := [akTop, akRight];
  BtnBrowse.OnClick := @BtnBrowseClick;

  LLog := TLabel.Create(Self);
  LLog.Parent := Self;
  LLog.Caption := 'Output:';
  LLog.SetBounds(12, 76, 60, 20);

  LogMemo := TMemo.Create(Self);
  LogMemo.Parent := Self;
  LogMemo.SetBounds(12, 96, 516, 265);
  LogMemo.ReadOnly := True;
  LogMemo.ScrollBars := ssAutoBoth;
  LogMemo.Font.Name := 'Menlo';
  LogMemo.Font.Size := 10;
  LogMemo.Anchors := [akLeft, akTop, akRight, akBottom];

  BtnRun := TButton.Create(Self);
  BtnRun.Parent := Self;
  BtnRun.Caption := 'Read Disc';
  BtnRun.SetBounds(308, 374, 100, 28);
  BtnRun.Default := True;
  BtnRun.Anchors := [akRight, akBottom];
  BtnRun.OnClick := @BtnRunClick;

  BtnClose := TButton.Create(Self);
  BtnClose.Parent := Self;
  BtnClose.Caption := 'Cancel';
  BtnClose.SetBounds(418, 374, 80, 28);
  BtnClose.Cancel := True;
  BtnClose.ModalResult := mrCancel;
  BtnClose.Anchors := [akRight, akBottom];
end;

constructor TGWForm.CreateForWrite(const AGwPath, AImagePath: string);
var
  LDrive, LImgCaption, LImgName, LWarn, LLog: TLabel;
begin
  CreateNew(nil);
  FMode      := gwmWrite;
  FGwPath    := AGwPath;
  FImagePath := AImagePath;
  FSucceeded := False;

  Caption := 'Write Disc — Greaseweazle';
  Width := 540;
  Height := 390;
  Position := poScreenCenter;
  BorderStyle := bsSizeable;

  LDrive := TLabel.Create(Self);
  LDrive.Parent := Self;
  LDrive.Caption := 'Drive:';
  LDrive.SetBounds(12, 15, 60, 20);

  CbDrive := TComboBox.Create(Self);
  CbDrive.Parent := Self;
  CbDrive.Style := csDropDownList;
  CbDrive.SetBounds(80, 12, 80, 22);
  CbDrive.Items.Add('a');
  CbDrive.Items.Add('b');
  CbDrive.ItemIndex := 0;

  LImgCaption := TLabel.Create(Self);
  LImgCaption.Parent := Self;
  LImgCaption.Caption := 'Image:';
  LImgCaption.SetBounds(12, 47, 60, 20);

  LImgName := TLabel.Create(Self);
  LImgName.Parent := Self;
  LImgName.Caption := ExtractFileName(AImagePath);
  LImgName.Font.Style := [fsBold];
  LImgName.SetBounds(80, 47, 420, 20);

  LWarn := TLabel.Create(Self);
  LWarn.Parent := Self;
  LWarn.Caption := 'Warning: writing will permanently erase the physical disc.';
  LWarn.Font.Color := clMaroon;
  LWarn.SetBounds(12, 72, 516, 20);

  LLog := TLabel.Create(Self);
  LLog.Parent := Self;
  LLog.Caption := 'Output:';
  LLog.SetBounds(12, 100, 60, 20);

  LogMemo := TMemo.Create(Self);
  LogMemo.Parent := Self;
  LogMemo.SetBounds(12, 120, 516, 218);
  LogMemo.ReadOnly := True;
  LogMemo.ScrollBars := ssAutoBoth;
  LogMemo.Font.Name := 'Menlo';
  LogMemo.Font.Size := 10;
  LogMemo.Anchors := [akLeft, akTop, akRight, akBottom];

  BtnRun := TButton.Create(Self);
  BtnRun.Parent := Self;
  BtnRun.Caption := 'Write to Disc';
  BtnRun.SetBounds(296, 348, 110, 28);
  BtnRun.Default := True;
  BtnRun.Anchors := [akRight, akBottom];
  BtnRun.OnClick := @BtnRunClick;

  BtnClose := TButton.Create(Self);
  BtnClose.Parent := Self;
  BtnClose.Caption := 'Cancel';
  BtnClose.SetBounds(416, 348, 80, 28);
  BtnClose.Cancel := True;
  BtnClose.ModalResult := mrCancel;
  BtnClose.Anchors := [akRight, akBottom];
end;

procedure TGWForm.BtnBrowseClick(Sender: TObject);
var
  SD: TSaveDialog;
begin
  SD := TSaveDialog.Create(Self);
  try
    SD.Title := 'Save disc image as...';
    SD.Filter := 'DSK images (*.dsk)|*.dsk|All files (*.*)|*.*';
    SD.DefaultExt := 'dsk';
    if SD.Execute then
      EditPath.Text := SD.FileName;
  finally
    SD.Free;
  end;
end;

procedure TGWForm.BtnRunClick(Sender: TObject);
var
  Log, Drive: string;
  OK: Boolean;
begin
  Drive := Trim(LowerCase(CbDrive.Text));
  if Drive = '' then Drive := 'a';

  BtnRun.Enabled := False;
  LogMemo.Lines.Clear;
  LogMemo.Lines.Add('Running gw...');
  Application.ProcessMessages;

  if FMode = gwmRead then
  begin
    FImagePath := Trim(EditPath.Text);
    if FImagePath = '' then
    begin
      LogMemo.Lines.Clear;
      LogMemo.Lines.Add('Error: please specify an output file path.');
      BtnRun.Enabled := True;
      Exit;
    end;
    OK := GwReadDisc(FGwPath, Drive, FImagePath, Log);
  end
  else
    OK := GwWriteDisc(FGwPath, Drive, FImagePath, Log);

  LogMemo.Lines.Clear;
  if Log <> '' then
    LogMemo.Lines.Add(Log);

  if OK then
  begin
    LogMemo.Lines.Add('');
    LogMemo.Lines.Add('=== Completed successfully ===');
    FSucceeded := True;
    BtnClose.Caption := 'Close';
    BtnClose.ModalResult := mrOK;
    BtnClose.SetFocus;
  end
  else
  begin
    LogMemo.Lines.Add('');
    LogMemo.Lines.Add('=== FAILED ===');
    BtnRun.Enabled := True;
  end;
end;

function ShowGWReadDialog(const AGwPath: string; out AImagePath: string): Boolean;
var
  F: TGWForm;
begin
  AImagePath := '';
  F := TGWForm.CreateForRead(AGwPath);
  try
    F.ShowModal;
    Result := F.Succeeded;
    AImagePath := F.ImagePath;
  finally
    F.Free;
  end;
end;

function ShowGWWriteDialog(const AGwPath, AImagePath: string): Boolean;
var
  F: TGWForm;
begin
  F := TGWForm.CreateForWrite(AGwPath, AImagePath);
  try
    F.ShowModal;
    Result := F.Succeeded;
  finally
    F.Free;
  end;
end;

{ ── Text / Hex helpers ────────────────────────────────────────────────────── }

procedure ShowTextViewer(const Title, Body: string);
var F: TTextViewerForm;
begin
  F := TTextViewerForm.CreateWithText(Title, Body);
  F.Show;
end;

procedure ShowHexViewer(const Title: string; const Data: TBytes);
var F: THexViewerForm;
begin
  F := THexViewerForm.CreateWithData('Hex View — ' + Title, Data);
  F.Show;
end;

{ ── TDiskMapForm ──────────────────────────────────────────────────────────── }

function TDiskMapForm.IsHighlighted(AIdx: Integer): Boolean;
var
  I: Integer;
begin
  for I := 0 to High(FHighlightBlocks) do
    if FHighlightBlocks[I] = AIdx then
      Exit(True);
  Result := False;
end;

constructor TDiskMapForm.CreateWithMap(const ATitle: string; const AMap: TBytes;
                                       ABlocksPerRow: Integer;
                                       const AHighlight: TBlockNumberArray);
const
  CELL = 14;
  GAP  = 2;
var
  Legend: TPanel;
  LegendBody: TLabel;
  Rows: Integer;
begin
  CreateNew(nil);
  FMap := AMap;
  FBlocksPerRow := ABlocksPerRow;
  FHighlightBlocks := AHighlight;

  Caption := ATitle;
  Position := poScreenCenter;
  OnClose := @FormClose;

  Rows := (Length(FMap) + FBlocksPerRow - 1) div FBlocksPerRow;
  Width  := FBlocksPerRow * (CELL + GAP) + 40;
  Height := Rows * (CELL + GAP) + 120;
  if Width  < 520 then Width  := 520;
  if Height > 760 then Height := 760;

  Legend := TPanel.Create(Self);
  Legend.Parent := Self;
  Legend.Align := alBottom;
  Legend.Height := 48;
  Legend.BevelOuter := bvNone;

  LegendBody := TLabel.Create(Legend);
  LegendBody.Parent := Legend;
  LegendBody.Align := alClient;
  LegendBody.Alignment := taCenter;
  LegendBody.Layout := tlCenter;
  if Length(AHighlight) > 0 then
    LegendBody.Caption :=
      'Grey=Free   Navy=Directory   Teal=Used   Green=Deleted   Yellow=Selected file'
  else
    LegendBody.Caption :=
      'Grey=Free   Navy=Directory   Teal=Used   Green=Deleted (recoverable)';

  FPB := TPaintBox.Create(Self);
  FPB.Parent := Self;
  FPB.Align := alClient;
  FPB.OnPaint := @DoPaint;
end;

procedure TDiskMapForm.DoPaint(Sender: TObject);
const
  CELL = 14;
  GAP  = 2;
var
  I, X, Y: Integer;
  C: TColor;
begin
  FPB.Canvas.Brush.Color := clBtnFace;
  FPB.Canvas.FillRect(0, 0, FPB.Width, FPB.Height);
  for I := 0 to High(FMap) do
  begin
    X := (I mod FBlocksPerRow) * (CELL + GAP) + 8;
    Y := (I div FBlocksPerRow) * (CELL + GAP) + 8;
    if IsHighlighted(I) then
      C := $0000FFFF
    else
      case FMap[I] of
        0: C := clGray;
        1: C := clNavy;
        2: C := clTeal;
        3: C := $00408040;
      else
        C := clMaroon;
      end;
    FPB.Canvas.Brush.Color := C;
    FPB.Canvas.Pen.Color := clBlack;
    FPB.Canvas.Rectangle(X, Y, X + CELL, Y + CELL);
  end;
end;

function ShowDiskMap(const Title: string; const Map: TBytes;
                     BlocksPerRow: Integer;
                     const HighlightBlocks: TBlockNumberArray): TViewerForm;
var F: TDiskMapForm;
begin
  F := TDiskMapForm.CreateWithMap(Title, Map, BlocksPerRow, HighlightBlocks);
  F.Show;
  Result := F;
end;

{ ── TSectorMapForm ────────────────────────────────────────────────────────── }

const
  SM_CELL    = 20;
  SM_GAP     = 2;
  SM_CELL_W  = SM_CELL + SM_GAP;   { 22 px per column }
  SM_CELL_H  = SM_CELL + SM_GAP;   { 22 px per row    }
  SM_LABEL_W = 46;                  { left margin for track labels }

function TSectorMapForm.CellColor(const Cell: TSectorCell): TColor;
begin
  if Cell.State = ssFDCError then
    Exit(clRed);
  if (Cell.ActualLen >= 0) and (Cell.ActualLen <> Cell.SizeBytes) then
    Exit($0000FFFF);   { yellow }
  if (Cell.DeclaredLen > 0) and (Cell.DeclaredLen <> Cell.SizeBytes) then
    Exit($000080FF);   { orange }
  if Cell.IsSuspiciousID then
    Exit($00FF00FF);   { magenta }
  if Cell.IsTwin then
    Exit($00FF80FF);   { light magenta }
  case Cell.State of
    ssData:   Result := $0000FF00;   { lime }
    ssBoot:   Result := $00FFFF00;   { cyan }
    ssSystem: Result := $00808000;   { teal }
    ssEmpty:  Result := $00404040;
  else
    Result := clGray;
  end;
end;

function TSectorMapForm.IsSectorOwned(ATrackIdx: Integer; ASectorID: Byte): Boolean;
var
  I: Integer;
begin
  for I := 0 to High(FOwnedSectors) do
    if (Integer(FOwnedSectors[I].TrackIdx) = ATrackIdx) and
       (FOwnedSectors[I].SectorID = ASectorID) then
      Exit(True);
  Result := False;
end;

constructor TSectorMapForm.CreateWithMap(const ATitle: string;
                                         const ATracks: TTrackColumnArray;
                                         const AOwnedSectors: TPhysicalSectorArray);
var
  MaxSectors, I, PBW, PBH: Integer;
  ScrollBox: TScrollBox;
  LegendPanel: TPanel;
  LegendLabel: TLabel;
begin
  CreateNew(nil);
  FTracks := ATracks;
  FOwnedSectors := AOwnedSectors;

  Caption := ATitle;
  Width := 920;
  Height := 620;
  Position := poScreenCenter;
  BorderStyle := bsSizeable;
  OnClose := @FormClose;

  LegendPanel := TPanel.Create(Self);
  LegendPanel.Parent := Self;
  LegendPanel.Align := alBottom;
  LegendPanel.Height := 52;
  LegendPanel.BevelOuter := bvNone;

  LegendLabel := TLabel.Create(LegendPanel);
  LegendLabel.Parent := LegendPanel;
  LegendLabel.Align := alClient;
  LegendLabel.Alignment := taCenter;
  LegendLabel.Layout := tlCenter;
  LegendLabel.WordWrap := True;
  LegendLabel.Caption :=
    'Green=Data   Cyan=Boot   Teal=Dir   Dark=Empty   ' +
    'Red/X=FDC error   Yellow/L=Length mismatch   Orange/W=DataLen mismatch   ' +
    'Magenta/X=Suspicious ID   Pink=Twin   Yellow border=Selected file sectors';

  FStatusLabel := TLabel.Create(Self);
  FStatusLabel.Parent := Self;
  FStatusLabel.Align := alBottom;
  FStatusLabel.Height := 22;
  FStatusLabel.Caption := '  Click a sector cell to inspect it.';
  FStatusLabel.Color := clBtnFace;

  ScrollBox := TScrollBox.Create(Self);
  ScrollBox.Parent := Self;
  ScrollBox.Align := alClient;
  ScrollBox.AutoScroll := True;
  ScrollBox.HorzScrollBar.Tracking := True;
  ScrollBox.VertScrollBar.Tracking := True;

  MaxSectors := 0;
  for I := 0 to High(FTracks) do
    if Length(FTracks[I].Sectors) > MaxSectors then
      MaxSectors := Length(FTracks[I].Sectors);

  PBW := SM_LABEL_W + MaxSectors * SM_CELL_W + SM_GAP + 20;
  PBH := Length(FTracks) * SM_CELL_H + SM_GAP + 20;

  FPB := TPaintBox.Create(ScrollBox);
  FPB.Parent := ScrollBox;
  FPB.Left := 0;
  FPB.Top  := 0;
  FPB.Width  := PBW;
  FPB.Height := PBH;
  FPB.OnPaint     := @DoPaint;
  FPB.OnMouseDown := @DoMouseDown;
end;

procedure TSectorMapForm.DoPaint(Sender: TObject);
var
  I, J, CX, CY: Integer;
  Cell: TSectorCell;
  C: TColor;
  Owned: Boolean;
  Lbl: string;
begin
  FPB.Canvas.Brush.Color := $00202020;
  FPB.Canvas.FillRect(0, 0, FPB.Width, FPB.Height);
  FPB.Canvas.Font.Size := 8;
  FPB.Canvas.Font.Style := [];

  for I := 0 to High(FTracks) do
  begin
    CY := SM_GAP + I * SM_CELL_H;

    FPB.Canvas.Brush.Style := bsClear;
    FPB.Canvas.Font.Color := $00A0A0A0;
    FPB.Canvas.TextOut(2, CY + 4, Format('T%d', [FTracks[I].TrackNum]));
    FPB.Canvas.Brush.Style := bsSolid;

    for J := 0 to High(FTracks[I].Sectors) do
    begin
      Cell := FTracks[I].Sectors[J];
      CX := SM_LABEL_W + J * SM_CELL_W;
      C := CellColor(Cell);
      Owned := IsSectorOwned(I, Cell.SectorID);

      FPB.Canvas.Brush.Color := C;
      if Owned then
      begin
        FPB.Canvas.Pen.Color := $0000FFFF;
        FPB.Canvas.Pen.Width := 2;
      end
      else
      begin
        FPB.Canvas.Pen.Color := $00303030;
        FPB.Canvas.Pen.Width := 1;
      end;
      FPB.Canvas.Rectangle(CX, CY, CX + SM_CELL, CY + SM_CELL);

      Lbl := '';
      if Cell.State = ssFDCError then
        Lbl := 'X'
      else if (Cell.ActualLen >= 0) and (Cell.ActualLen <> Cell.SizeBytes) then
        Lbl := 'L'
      else if (Cell.DeclaredLen > 0) and (Cell.DeclaredLen <> Cell.SizeBytes) then
        Lbl := 'W'
      else if Cell.IsSuspiciousID then
        Lbl := 'X';

      if Lbl <> '' then
      begin
        FPB.Canvas.Brush.Style := bsClear;
        FPB.Canvas.Font.Color := clBlack;
        FPB.Canvas.TextOut(CX + 6, CY + 4, Lbl);
        FPB.Canvas.Brush.Style := bsSolid;
      end;
    end;
  end;

  FPB.Canvas.Pen.Width := 1;
end;

procedure TSectorMapForm.DoMouseDown(Sender: TObject; Button: TMouseButton;
                                      Shift: TShiftState; X, Y: Integer);
var
  TrackIdx, SectorIdx: Integer;
  Cell: TSectorCell;
  StateName, Flags: string;
begin
  TrackIdx  := (Y - SM_GAP) div SM_CELL_H;
  SectorIdx := (X - SM_LABEL_W) div SM_CELL_W;
  if (TrackIdx < 0) or (TrackIdx >= Length(FTracks)) then Exit;
  if (SectorIdx < 0) or (SectorIdx >= Length(FTracks[TrackIdx].Sectors)) then Exit;

  Cell := FTracks[TrackIdx].Sectors[SectorIdx];

  case Cell.State of
    ssEmpty:       StateName := 'Empty';
    ssData:        StateName := 'Data';
    ssSystem:      StateName := 'Dir/System';
    ssBoot:        StateName := 'Boot';
    ssFDCError:    StateName := 'FDC Error';
    ssNonStandard: StateName := 'Non-standard';
  else
    StateName := '?';
  end;

  Flags := '';
  if Cell.IsTwin         then Flags := Flags + ' Twin';
  if Cell.IsSuspiciousID then Flags := Flags + ' SuspID';
  if (Cell.ActualLen >= 0) and (Cell.ActualLen <> Cell.SizeBytes) then
    Flags := Flags + Format(' L(%d≠%d)', [Cell.ActualLen, Cell.SizeBytes]);
  if (Cell.DeclaredLen > 0) and (Cell.DeclaredLen <> Cell.SizeBytes) then
    Flags := Flags + Format(' W(%d≠%d)', [Cell.DeclaredLen, Cell.SizeBytes]);
  if IsSectorOwned(TrackIdx, Cell.SectorID) then
    Flags := Flags + ' [owned]';

  FStatusLabel.Caption := Format(
    '  Track %d   Sector $%2.2x   Nominal %d B   State: %s%s',
    [FTracks[TrackIdx].TrackNum, Cell.SectorID, Cell.SizeBytes, StateName, Flags]);
end;

function ShowSectorMap(const Title: string;
                       const Tracks: TTrackColumnArray;
                       const OwnedSectors: TPhysicalSectorArray): TViewerForm;
var F: TSectorMapForm;
begin
  F := TSectorMapForm.CreateWithMap(Title, Tracks, OwnedSectors);
  F.Show;
  Result := F;
end;

{ ── TDiskPlatterForm ──────────────────────────────────────────────────────── }

const
  PL_BASE_ANGLE  = -1.5707963267948966; { -Pi/2: sectors start at 12 o'clock }
  PL_GAP_FRAC    = 0.08;   { inter-track gap as fraction of ring height }
  PL_SECT_GAP    = 0.025;  { angular gap between adjacent sectors (radians) }
  PL_CENTER_FRAC = 0.18;   { centre hole radius as fraction of FR_max }
  PL_LUM_MIN     = 0.28;   { minimum luminance multiplier for byte=0 }
  PL_LUM_MAX     = 0.92;   { maximum luminance multiplier for byte=255 }
  PL_MAX_LUMSEGS = 48;     { max luminance sub-segments per sector arc }
  PL_OWNED_COLOR = $0000CCFF; { warm gold base colour for owned-file sectors }

function AdjustLuminance(C: TColor; Factor: Double): TColor;
var
  R, G, B: Integer;
begin
  C := ColorToRGB(C);
  R := Round((C and $FF) * Factor);
  G := Round(((C shr 8) and $FF) * Factor);
  B := Round(((C shr 16) and $FF) * Factor);
  if R > 255 then R := 255;
  if G > 255 then G := 255;
  if B > 255 then B := 255;
  Result := TColor((B shl 16) or (G shl 8) or R);
end;

function TDiskPlatterForm.PlatterCellColor(const ACell: TSectorCell): TColor;
begin
  if ACell.State = ssFDCError then Exit(clRed);
  if (ACell.ActualLen >= 0) and (ACell.ActualLen <> ACell.SizeBytes) then Exit($0000FFFF);
  if (ACell.DeclaredLen > 0) and (ACell.DeclaredLen <> ACell.SizeBytes) then Exit($000080FF);
  if ACell.IsSuspiciousID then Exit($00FF00FF);
  if ACell.IsTwin then Exit($00FF80FF);
  case ACell.State of
    ssData:   Result := $0000FF00;
    ssBoot:   Result := $00FFFF00;
    ssSystem: Result := $00808000;
    ssEmpty:  Result := $00404040;
  else
    Result := clGray;
  end;
end;

function TDiskPlatterForm.PlatterSectorOwned(ATrackIdx: Integer; ASectorID: Byte): Boolean;
var
  I: Integer;
begin
  for I := 0 to High(FOwnedSectors) do
    if (Integer(FOwnedSectors[I].TrackIdx) = ATrackIdx) and
       (FOwnedSectors[I].SectorID = ASectorID) then
      Exit(True);
  Result := False;
end;

procedure TDiskPlatterForm.DoResize(Sender: TObject);
begin
  FBitmapValid := False;
  FPB.Invalidate;
end;

procedure TDiskPlatterForm.RenderToCache;
var
  W, H, NT, I, J, K: Integer;
  NumSegs, ByteStart, ByteEnd, ByteCount, SectBytes, P: Integer;
  R_outer, R_inner, TotalBytes, CumBytes: Double;
  A1, A2, AS1, AS2, SegA1, SegA2, AvgByte, Factor: Double;
  Data: TBytes;
  Sum: Int64;
  Cell: TSectorCell;
  BaseColor: TColor;

  procedure DrawSlice(ACX, ACY: Integer; AR1, AR2, DAA1, DAA2: Double; AColor: TColor);
  var
    NAP, NTP, SI: Integer;
    Span, SStep, SA: Double;
    SP: array of TPoint;
  begin
    Span := DAA2 - DAA1;
    if Span < 0.001 then Exit;
    NAP := Max(2, Min(48, Round(Span * Max(AR1, AR2) / 3.0)));
    NTP := 2 * (NAP + 1);
    SetLength(SP, NTP);
    SStep := Span / NAP;
    for SI := 0 to NAP do
    begin
      SA := DAA1 + SI * SStep;
      SP[SI]       := Point(ACX + Round(AR2 * Cos(SA)), ACY + Round(AR2 * Sin(SA)));
      SP[NTP-1-SI] := Point(ACX + Round(AR1 * Cos(SA)), ACY + Round(AR1 * Sin(SA)));
    end;
    FBitmapCache.Canvas.Brush.Color := AColor;
    FBitmapCache.Canvas.Pen.Color   := AColor;
    FBitmapCache.Canvas.Pen.Width   := 1;
    FBitmapCache.Canvas.Polygon(SP);
  end;

begin
  W  := FPB.Width;
  H  := FPB.Height;
  NT := Length(FTracks);
  if (W < 20) or (H < 20) or (NT = 0) then Exit;

  FCX    := W div 2;
  FCY    := H div 2;
  FR_max := Min(W, H) / 2.0 - 14;
  FR_min := FR_max * PL_CENTER_FRAC;
  FRingH := (FR_max - FR_min) / NT;

  FBitmapCache.Width  := W;
  FBitmapCache.Height := H;

  FBitmapCache.Canvas.Brush.Color := $00101010;
  FBitmapCache.Canvas.FillRect(0, 0, W, H);

  { First pass: fill every sector with luminance-modulated colour }
  for I := 0 to NT - 1 do
  begin
    R_outer := FR_max - I * FRingH;
    R_inner := R_outer - FRingH * (1.0 - PL_GAP_FRAC);

    TotalBytes := 0;
    for J := 0 to High(FTracks[I].Sectors) do
    begin
      Cell      := FTracks[I].Sectors[J];
      SectBytes := Cell.DeclaredLen;
      if SectBytes <= 0 then SectBytes := Cell.SizeBytes;
      if SectBytes <= 0 then SectBytes := 512;
      TotalBytes := TotalBytes + SectBytes;
    end;
    if TotalBytes = 0 then Continue;

    CumBytes := 0;
    for J := 0 to High(FTracks[I].Sectors) do
    begin
      Cell      := FTracks[I].Sectors[J];
      SectBytes := Cell.DeclaredLen;
      if SectBytes <= 0 then SectBytes := Cell.SizeBytes;
      if SectBytes <= 0 then SectBytes := 512;

      A1 := PL_BASE_ANGLE + (CumBytes / TotalBytes) * 2 * Pi;
      A2 := PL_BASE_ANGLE + ((CumBytes + SectBytes) / TotalBytes) * 2 * Pi;
      CumBytes := CumBytes + SectBytes;

      AS1 := A1 + PL_SECT_GAP / 2;
      AS2 := A2 - PL_SECT_GAP / 2;
      if AS2 <= AS1 then Continue;

      BaseColor := PlatterCellColor(Cell);
      { Owned-sector tint: fold into first pass so byte-density shading
        (Factor below) is still visible through the highlight colour. }
      if PlatterSectorOwned(I, Cell.SectorID) then
        BaseColor := PL_OWNED_COLOR;

      Data := nil;
      if FDisk <> nil then
      try
        Data := FDisk.GetSectorData(I, J);
      except
        Data := nil;
      end;

      NumSegs := 1;
      if (Data <> nil) and (Length(Data) > 0) then
        NumSegs := Max(1, Min(PL_MAX_LUMSEGS,
          Round(Abs(AS2 - AS1) * (R_inner + R_outer) / 2.0 / 6.0)));

      for K := 0 to NumSegs - 1 do
      begin
        SegA1 := AS1 + (AS2 - AS1) * (K / NumSegs);
        SegA2 := AS1 + (AS2 - AS1) * ((K + 1) / NumSegs);

        if (Data <> nil) and (Length(Data) > 0) then
        begin
          ByteStart := (K * Length(Data)) div NumSegs;
          ByteEnd   := ((K + 1) * Length(Data)) div NumSegs;
          ByteCount := ByteEnd - ByteStart;
          if ByteCount < 1 then ByteCount := 1;
          Sum := 0;
          for P := ByteStart to ByteEnd - 1 do
            Sum := Sum + Data[P];
          AvgByte := Sum / ByteCount;
          Factor  := PL_LUM_MIN + (AvgByte / 255.0) * (PL_LUM_MAX - PL_LUM_MIN);
        end
        else
          Factor := (PL_LUM_MIN + PL_LUM_MAX) / 2.0;

        DrawSlice(FCX, FCY, R_inner, R_outer, SegA1, SegA2,
                  AdjustLuminance(BaseColor, Factor));
      end;
    end;
  end;

  { Centre hub }
  FBitmapCache.Canvas.Brush.Color := $00101010;
  FBitmapCache.Canvas.Pen.Color   := $00606060;
  FBitmapCache.Canvas.Pen.Width   := 2;
  FBitmapCache.Canvas.Ellipse(
    FCX - Round(FR_min), FCY - Round(FR_min),
    FCX + Round(FR_min), FCY + Round(FR_min));

  FBitmapValid := True;
end;

procedure TDiskPlatterForm.DoPaint(Sender: TObject);
begin
  if not FBitmapValid then
    RenderToCache;
  if FBitmapValid then
    FPB.Canvas.Draw(0, 0, FBitmapCache);
end;

procedure TDiskPlatterForm.HitTest(AX, AY: Integer; out TrackIdx, SectorIdx: Integer);
var
  Angle, R, dx, dy: Double;
  NT, J: Integer;
  TotalBytes, CumBytes, A1, A2: Double;
  SectBytes: Integer;
  Cell: TSectorCell;
begin
  TrackIdx  := -1;
  SectorIdx := -1;
  if not FBitmapValid then Exit;

  NT := Length(FTracks);
  dx := AX - FCX;
  dy := AY - FCY;
  R  := Sqrt(dx * dx + dy * dy);
  if (R < FR_min) or (R > FR_max) then Exit;

  TrackIdx := Trunc((FR_max - R) / FRingH);
  if (TrackIdx < 0) or (TrackIdx >= NT) then
  begin
    TrackIdx := -1;
    Exit;
  end;

  Angle := ArcTan2(dy, dx);
  if Angle < PL_BASE_ANGLE then
    Angle := Angle + 2 * Pi;

  TotalBytes := 0;
  for J := 0 to High(FTracks[TrackIdx].Sectors) do
  begin
    Cell      := FTracks[TrackIdx].Sectors[J];
    SectBytes := Cell.DeclaredLen;
    if SectBytes <= 0 then SectBytes := Cell.SizeBytes;
    if SectBytes <= 0 then SectBytes := 512;
    TotalBytes := TotalBytes + SectBytes;
  end;
  if TotalBytes = 0 then begin TrackIdx := -1; Exit; end;

  CumBytes := 0;
  for J := 0 to High(FTracks[TrackIdx].Sectors) do
  begin
    Cell      := FTracks[TrackIdx].Sectors[J];
    SectBytes := Cell.DeclaredLen;
    if SectBytes <= 0 then SectBytes := Cell.SizeBytes;
    if SectBytes <= 0 then SectBytes := 512;

    A1 := PL_BASE_ANGLE + (CumBytes / TotalBytes) * 2 * Pi;
    A2 := PL_BASE_ANGLE + ((CumBytes + SectBytes) / TotalBytes) * 2 * Pi;
    CumBytes := CumBytes + SectBytes;

    if (Angle >= A1) and (Angle < A2) then
    begin
      SectorIdx := J;
      Exit;
    end;
  end;
  TrackIdx := -1;
end;

procedure TDiskPlatterForm.DoMouseDown(Sender: TObject; Button: TMouseButton;
                                        Shift: TShiftState; X, Y: Integer);
var
  TrackIdx, SectorIdx: Integer;
  Cell: TSectorCell;
  StateName, Flags: string;
begin
  HitTest(X, Y, TrackIdx, SectorIdx);
  if (TrackIdx < 0) or (SectorIdx < 0) then
  begin
    FStatusLabel.Caption := '  Click on a track sector.';
    Exit;
  end;

  Cell := FTracks[TrackIdx].Sectors[SectorIdx];

  case Cell.State of
    ssEmpty:       StateName := 'Empty';
    ssData:        StateName := 'Data';
    ssSystem:      StateName := 'Dir/System';
    ssBoot:        StateName := 'Boot';
    ssFDCError:    StateName := 'FDC Error';
    ssNonStandard: StateName := 'Non-standard';
  else
    StateName := '?';
  end;

  Flags := '';
  if Cell.IsTwin         then Flags := Flags + ' Twin';
  if Cell.IsSuspiciousID then Flags := Flags + ' SuspID';
  if (Cell.ActualLen >= 0) and (Cell.ActualLen <> Cell.SizeBytes) then
    Flags := Flags + Format(' L(%d/%d)', [Cell.ActualLen, Cell.SizeBytes]);
  if (Cell.DeclaredLen > 0) and (Cell.DeclaredLen <> Cell.SizeBytes) then
    Flags := Flags + Format(' W(%d/%d)', [Cell.DeclaredLen, Cell.SizeBytes]);
  if PlatterSectorOwned(TrackIdx, Cell.SectorID) then
    Flags := Flags + ' [owned]';

  FStatusLabel.Caption := Format(
    '  Track %d   Sector $%2.2x   %d B   %s%s',
    [FTracks[TrackIdx].TrackNum, Cell.SectorID, Cell.SizeBytes, StateName, Flags]);
end;

constructor TDiskPlatterForm.CreateWithData(const ATitle: string;
                                             const ATracks: TTrackColumnArray;
                                             const AOwnedSectors: TPhysicalSectorArray;
                                             ADisk: IVirtualDisk);
var
  DockBar: TPanel;
  BtnDock: TButton;
begin
  CreateNew(nil);
  FDisk         := ADisk;
  FTracks       := ATracks;
  FOwnedSectors := AOwnedSectors;
  FBitmapCache  := TBitmap.Create;
  FBitmapValid  := False;
  FDockHost     := nil;

  Caption     := ATitle;
  Width       := 760;
  Height      := 800;
  Position    := poScreenCenter;
  BorderStyle := bsSizeable;
  OnClose     := @FormClose;

  { Dock toolbar — "Dock →" fires OnDockRequest when TMainForm has wired it. }
  DockBar            := TPanel.Create(Self);
  DockBar.Parent     := Self;
  DockBar.Align      := alTop;
  DockBar.Height     := 28;
  DockBar.BevelOuter := bvNone;

  BtnDock            := TButton.Create(DockBar);
  BtnDock.Parent     := DockBar;
  BtnDock.Align      := alRight;
  BtnDock.Width      := 80;
  BtnDock.Caption    := 'Dock →';
  BtnDock.OnClick    := @DockBtnClick;

  FStatusLabel          := TLabel.Create(Self);
  FStatusLabel.Parent   := Self;
  FStatusLabel.Align    := alBottom;
  FStatusLabel.AutoSize := False;
  FStatusLabel.Height   := 24;
  FStatusLabel.Caption  := '  Click on a track sector.';

  FPB             := TPaintBox.Create(Self);
  FPB.Parent      := Self;
  FPB.Align       := alClient;
  FPB.OnPaint     := @DoPaint;
  FPB.OnMouseDown := @DoMouseDown;
  FPB.OnResize    := @DoResize;
end;

destructor TDiskPlatterForm.Destroy;
begin
  FBitmapCache.Free;
  inherited Destroy;
end;

procedure TDiskPlatterForm.DockBtnClick(Sender: TObject);
begin
  if Assigned(OnDockRequest) then OnDockRequest(Self);
end;

procedure TDiskPlatterForm.DockTo(AHost: TWinControl);
begin
  if FDockHost <> nil then Exit;  { already docked }
  FDockHost := AHost;
  { Re-parent content controls into the dock host.  Order matters: alBottom
    must be added before alClient so the client area claims the correct space. }
  FStatusLabel.Parent := AHost;
  FPB.Parent          := AHost;
  FBitmapValid        := False;
  FPB.Invalidate;
  Hide;
end;

procedure TDiskPlatterForm.Undock;
begin
  if FDockHost = nil then Exit;  { not currently docked }
  { Re-parent controls back to the floating form — same ordering rule. }
  FStatusLabel.Parent := Self;
  FPB.Parent          := Self;
  FDockHost           := nil;
  FBitmapValid        := False;
  Show;
  FPB.Invalidate;
end;

function ShowDiskPlatter(const ATitle: string;
                         const ATracks: TTrackColumnArray;
                         const AOwnedSectors: TPhysicalSectorArray;
                         ADisk: IVirtualDisk): TViewerForm;
begin
  { Caller must wire OnDockRequest then call Result.Show — see ActDiskPlatterExecute. }
  Result := TDiskPlatterForm.CreateWithData(ATitle, ATracks, AOwnedSectors, ADisk);
end;

end.
