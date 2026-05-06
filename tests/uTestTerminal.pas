unit uTestTerminal;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, uTerminalIO;

type
  TTestTerminalInput = class(TInterfacedObject, ITerminalInput)
  strict private
    FQueue: array of TInputEvent;
    FPos: Integer;
  public
    procedure Enqueue(AAction: TKeyAction; AChar: Char = #0);
    function WaitForKey: TInputEvent;
    function QueueEmpty: Boolean;
  end;

  TTestScreenCell = record
    Ch: Char;
    Attr: Byte;
  end;

  TTestTerminalOutput = class(TInterfacedObject, ITerminalOutput)
  strict private
    FWidth: Integer;
    FHeight: Integer;
    FBuffer: array of TTestScreenCell;
    FFlushCount: Integer;
  public
    constructor Create(AWidth, AHeight: Integer);
    function GetWidth: Integer;
    function GetHeight: Integer;
    procedure PutText(X, Y: Integer; const AText: string; AAttr: Byte);
    procedure Clear;
    procedure Flush;
    procedure Init;
    procedure Done;

    function TextAt(X, Y, Len: Integer): string;
    property FlushCount: Integer read FFlushCount;
  end;

implementation

{ ── TTestTerminalInput ───────────────────────────────────────── }

procedure TTestTerminalInput.Enqueue(AAction: TKeyAction; AChar: Char = #0);
var
  E: TInputEvent;
begin
  E.Action := AAction;
  E.CharValue := AChar;
  SetLength(FQueue, Length(FQueue) + 1);
  FQueue[High(FQueue)] := E;
end;

function TTestTerminalInput.WaitForKey: TInputEvent;
begin
  if FPos < Length(FQueue) then
  begin
    Result := FQueue[FPos];
    Inc(FPos);
  end
  else
    raise Exception.Create('TTestTerminalInput: key queue exhausted — enqueue kaEsc before calling Run');
end;

function TTestTerminalInput.QueueEmpty: Boolean;
begin
  Result := FPos >= Length(FQueue);
end;

{ ── TTestTerminalOutput ──────────────────────────────────────── }

constructor TTestTerminalOutput.Create(AWidth, AHeight: Integer);
begin
  inherited Create;
  FWidth := AWidth;
  FHeight := AHeight;
  SetLength(FBuffer, FWidth * FHeight);
  Clear;
end;

function TTestTerminalOutput.GetWidth: Integer;
begin
  Result := FWidth;
end;

function TTestTerminalOutput.GetHeight: Integer;
begin
  Result := FHeight;
end;

procedure TTestTerminalOutput.PutText(X, Y: Integer; const AText: string; AAttr: Byte);
var
  I, Pos: Integer;
begin
  if (Y < 1) or (Y > FHeight) then Exit;
  for I := 1 to Length(AText) do
  begin
    Pos := X + I - 2;
    if (Pos >= 0) and (Pos < FWidth) then
    begin
      FBuffer[(Y - 1) * FWidth + Pos].Ch := AText[I];
      FBuffer[(Y - 1) * FWidth + Pos].Attr := AAttr;
    end;
  end;
end;

procedure TTestTerminalOutput.Clear;
var
  I: Integer;
begin
  for I := 0 to Length(FBuffer) - 1 do
  begin
    FBuffer[I].Ch := ' ';
    FBuffer[I].Attr := $07;
  end;
end;

procedure TTestTerminalOutput.Flush;
begin
  Inc(FFlushCount);
end;

procedure TTestTerminalOutput.Init;
begin
  { No-op in tests }
end;

procedure TTestTerminalOutput.Done;
begin
  { No-op in tests }
end;

function TTestTerminalOutput.TextAt(X, Y, Len: Integer): string;
var
  I, Pos: Integer;
begin
  Result := '';
  for I := 0 to Len - 1 do
  begin
    Pos := (Y - 1) * FWidth + (X - 1) + I;
    if (Pos >= 0) and (Pos < Length(FBuffer)) then
      Result := Result + FBuffer[Pos].Ch
    else
      Result := Result + '?';
  end;
end;

end.
