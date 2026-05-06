unit uViewers;

{ Programmatic helper forms (created without LFM):
    - ShowHexViewer(Title, Data)  - scrollable hex/ASCII dump
    - ShowTextViewer(Title, Text) - monospace text viewer (used for disk info)
    - ShowDiskMap(Title, Map)     - colour-coded block map grid
  Each helper creates a modal form on demand and frees it on close. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Graphics, Controls, Forms, StdCtrls, ComCtrls, ExtCtrls,
  LCLType;

procedure ShowHexViewer(const Title: string; const Data: TBytes);
procedure ShowTextViewer(const Title, Body: string);
procedure ShowDiskMap(const Title: string; const Map: TBytes; BlocksPerRow: Integer = 32);

implementation

type
  { Minimal form dedicated to painting a colour-coded disk-map grid.
    Declared in the implementation section — unit-private by convention. }
  TDiskMapForm = class(TForm)
  private
    FMap: TBytes;
    FBlocksPerRow: Integer;
    FPB: TPaintBox;
    procedure DoPaint(Sender: TObject);
  public
    constructor CreateWithMap(const ATitle: string; const AMap: TBytes; ABlocksPerRow: Integer);
  end;

{ Build a classic hex dump: "00000000: XX XX XX ...  | ASCII" 16 bytes per row. }
function BuildHexDump(const Data: TBytes): string;
var
  SL: TStringList;
  LineStart, J: Integer;
  HexPart, AsciiPart: string;
  B: Byte;
begin
  SL := TStringList.Create;
  try
    LineStart := 0;
    while LineStart < Length(Data) do
    begin
      HexPart := Format('%8.8x: ', [LineStart]);
      AsciiPart := '';
      for J := 0 to 15 do
      begin
        if LineStart + J < Length(Data) then
        begin
          B := Data[LineStart + J];
          HexPart := HexPart + Format('%2.2x ', [B]);
          if (B >= 32) and (B < 127) then
            AsciiPart := AsciiPart + Chr(B)
          else
            AsciiPart := AsciiPart + '.';
        end
        else
        begin
          HexPart := HexPart + '   ';
          AsciiPart := AsciiPart + ' ';
        end;
        if J = 7 then HexPart := HexPart + ' ';  { extra space in the middle }
      end;
      SL.Add(HexPart + '|' + AsciiPart + '|');
      Inc(LineStart, 16);
    end;
    Result := SL.Text;
  finally
    SL.Free;
  end;
end;

procedure ShowTextViewer(const Title, Body: string);
var
  F: TForm;
  M: TMemo;
begin
  F := TForm.CreateNew(nil);
  try
    F.Caption := Title;
    F.Width := 760;
    F.Height := 540;
    F.Position := poScreenCenter;
    F.BorderStyle := bsSizeable;

    M := TMemo.Create(F);
    M.Parent := F;
    M.Align := alClient;
    M.ReadOnly := True;
    M.ScrollBars := ssAutoBoth;
    M.WordWrap := False;
    M.Font.Name := 'Menlo';
    M.Font.Size := 11;
    M.Text := Body;

    F.ShowModal;
  finally
    F.Free;
  end;
end;

procedure ShowHexViewer(const Title: string; const Data: TBytes);
var
  Body, Header: string;
begin
  Header := Format('Size: %d bytes (%.2f KB)', [Length(Data), Length(Data) / 1024]) +
            LineEnding + LineEnding;
  Body := Header + BuildHexDump(Data);
  ShowTextViewer('Hex View — ' + Title, Body);
end;

{ TDiskMapForm }

constructor TDiskMapForm.CreateWithMap(const ATitle: string; const AMap: TBytes; ABlocksPerRow: Integer);
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

  Caption := ATitle;
  Position := poScreenCenter;

  Rows := (Length(FMap) + FBlocksPerRow - 1) div FBlocksPerRow;
  Width := FBlocksPerRow * (CELL + GAP) + 40;
  Height := Rows * (CELL + GAP) + 120;
  if Width  < 520 then Width := 520;
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
  LegendBody.Caption :=
    'Grey = Free    Navy = Directory-reserved    Teal = Used    Green = Deleted (recoverable)';

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
    case FMap[I] of
      0: C := clGray;           { Free }
      1: C := clNavy;           { Directory-reserved }
      2: C := clTeal;           { Used }
      3: C := $00408040;        { Deleted-still-allocated }
    else
      C := clMaroon;
    end;
    FPB.Canvas.Brush.Color := C;
    FPB.Canvas.Pen.Color := clBlack;
    FPB.Canvas.Rectangle(X, Y, X + CELL, Y + CELL);
  end;
end;

procedure ShowDiskMap(const Title: string; const Map: TBytes; BlocksPerRow: Integer);
var
  F: TDiskMapForm;
begin
  F := TDiskMapForm.CreateWithMap(Title, Map, BlocksPerRow);
  try
    F.ShowModal;
  finally
    F.Free;
  end;
end;

end.
