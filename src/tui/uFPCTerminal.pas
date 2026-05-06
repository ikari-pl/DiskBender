unit uFPCTerminal;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Keyboard, Video, uTerminalIO;

type
  TFPCTerminalInput = class(TInterfacedObject, ITerminalInput)
  public
    function WaitForKey: TInputEvent;
  end;

  TFPCTerminalOutput = class(TInterfacedObject, ITerminalOutput)
  public
    function GetWidth: Integer;
    function GetHeight: Integer;
    procedure PutText(X, Y: Integer; const AText: string; AAttr: Byte);
    procedure Clear;
    procedure Flush;
    procedure Init;
    procedure Done;
  end;

implementation

function TranslateRawToEvent(K: TKeyEvent): TInputEvent;
var
  Code: LongWord;
  ScanHi: Byte;
  CharLo: Byte;
begin
  Result.Action := kaNone;
  Result.CharValue := #0;

  K := TranslateKeyEvent(K);
  Code := GetKeyEventCode(K);
  ScanHi := (Code shr 8) and $FF;
  CharLo := Code and $FF;

  case ScanHi of
    $48: Result.Action := kaUp;
    $50: Result.Action := kaDown;
    $4B: Result.Action := kaLeft;
    $4D: Result.Action := kaRight;
    $1C: Result.Action := kaEnter;
    $01: Result.Action := kaEsc;
    $0F: Result.Action := kaTab;
    $0E: Result.Action := kaBackspace;
    $3B: Result.Action := kaF1;
    $3C: Result.Action := kaF2;
    $3D: Result.Action := kaF3;
    $3E: Result.Action := kaF4;
    $3F: Result.Action := kaF5;
    $40: Result.Action := kaF6;
    $41: Result.Action := kaF7;
    $42: Result.Action := kaF8;
    $43: Result.Action := kaF9;
    $44: Result.Action := kaF10;
  else
    { FPC on macOS sometimes uses high-byte codes from ncurses }
    case Code of
      $FF21: Result.Action := kaUp;
      $FF27: Result.Action := kaDown;
      $FF24: Result.Action := kaLeft;
      $FF26: Result.Action := kaRight;
    else
      { Fall through to character check }
    end;
  end;

  if Result.Action <> kaNone then
    Exit;

  { Check for plain characters }
  case CharLo of
    $0D: Result.Action := kaEnter;
    $1B: Result.Action := kaEsc;
    $09: Result.Action := kaTab;
    $08, $7F: Result.Action := kaBackspace;
  else
    if CharLo >= 32 then
    begin
      Result.Action := kaChar;
      Result.CharValue := Chr(CharLo);
    end;
  end;
end;

{ ── TFPCTerminalInput ────────────────────────────────────────── }

function TFPCTerminalInput.WaitForKey: TInputEvent;
begin
  Result := TranslateRawToEvent(GetKeyEvent);
end;

{ ── TFPCTerminalOutput ───────────────────────────────────────── }

function TFPCTerminalOutput.GetWidth: Integer;
begin
  Result := ScreenWidth;
end;

function TFPCTerminalOutput.GetHeight: Integer;
begin
  Result := ScreenHeight;
end;

procedure TFPCTerminalOutput.PutText(X, Y: Integer; const AText: string; AAttr: Byte);
var
  I, Pos: Integer;
begin
  if (Y < 1) or (Y > ScreenHeight) then Exit;
  for I := 1 to Length(AText) do
  begin
    Pos := X + I - 2;
    if (Pos >= 0) and (Pos < ScreenWidth) then
      VideoBuf^[(Y - 1) * ScreenWidth + Pos] :=
        Ord(AText[I]) or (Word(AAttr) shl 8);
  end;
end;

procedure TFPCTerminalOutput.Clear;
var
  I: Integer;
begin
  for I := 0 to ScreenWidth * ScreenHeight - 1 do
    VideoBuf^[I] := Ord(' ') or ($07 shl 8);
end;

procedure TFPCTerminalOutput.Flush;
begin
  Video.UpdateScreen(False);
end;

procedure TFPCTerminalOutput.Init;
begin
  InitVideo;
  InitKeyboard;
end;

procedure TFPCTerminalOutput.Done;
begin
  DoneKeyboard;
  DoneVideo;
end;

end.
