unit uTerminalIO;

{$mode objfpc}{$H+}

interface

type
  TKeyAction = (
    kaUp, kaDown, kaLeft, kaRight,
    kaHome, kaEnd, kaPageUp, kaPageDown,
    kaEnter, kaEsc, kaTab, kaBackspace,
    kaF1, kaF2, kaF3, kaF4, kaF5,
    kaF6, kaF7, kaF8, kaF9, kaF10,
    kaChar,
    kaMouse,
    { Emitted only when the terminal supports the kitty keyboard protocol:
      a bare modifier (Shift/Ctrl/Alt) was pressed or released. The action
      carries no semantic command — the controller redraws the status bar
      and otherwise ignores it. }
    kaModifierChange,
    kaNone
  );

  TMouseButton = (mbLeft, mbRight, mbMiddle, mbNone);

const
  KM_SHIFT = $01;
  KM_ALT   = $02;
  KM_CTRL  = $04;

type
  TInputEvent = record
    Action: TKeyAction;
    CharValue: Char;
    MouseX, MouseY: Integer;
    MouseButton: TMouseButton;
    MouseWheel: Integer;
    Modifiers: Byte;        { Bitmap of KM_SHIFT/KM_ALT/KM_CTRL active during this event }
  end;

  ITerminalInput = interface
    ['{DB100001-0001-4E49-8E00-000000000001}']
    function WaitForKey: TInputEvent;
  end;

  ITerminalOutput = interface
    ['{DB100001-0002-4E49-8E00-000000000002}']
    function GetWidth: Integer;
    function GetHeight: Integer;
    procedure PutText(X, Y: Integer; const AText: string; AAttr: Byte);
    procedure Clear;
    procedure Flush;
    procedure Init;
    procedure Done;
    property Width: Integer read GetWidth;
    property Height: Integer read GetHeight;
  end;

const
  CH_HLINE    = #$E2#$94#$80;  { ─ U+2500 }
  CH_VLINE    = #$E2#$94#$82;  { │ U+2502 }
  CH_TLCORNER = #$E2#$94#$8C;  { ┌ U+250C }
  CH_TRCORNER = #$E2#$94#$90;  { ┐ U+2510 }
  CH_BLCORNER = #$E2#$94#$94;  { └ U+2514 }
  CH_BRCORNER = #$E2#$94#$98;  { ┘ U+2518 }
  CH_LTEE     = #$E2#$94#$9C;  { ├ U+251C }
  CH_RTEE     = #$E2#$94#$A4;  { ┤ U+2524 }

  { Double-line frame (Norton-Commander style outer borders). Single-line
    glyphs above are used for dividers *inside* a double-line frame. }
  CH_DHLINE    = #$E2#$95#$90;  { ═ U+2550 }
  CH_DVLINE    = #$E2#$95#$91;  { ║ U+2551 }
  CH_DTLCORNER = #$E2#$95#$94;  { ╔ U+2554 }
  CH_DTRCORNER = #$E2#$95#$97;  { ╗ U+2557 }
  CH_DBLCORNER = #$E2#$95#$9A;  { ╚ U+255A }
  CH_DBRCORNER = #$E2#$95#$9D;  { ╝ U+255D }
  CH_DLTEE     = #$E2#$95#$9F;  { ╟ U+255F  double vertical, single horizontal right }
  CH_DRTEE     = #$E2#$95#$A2;  { ╢ U+2562  double vertical, single horizontal left  }

  CH_FULL     = #$E2#$96#$88;  { █ U+2588 }
  CH_LHALF    = #$E2#$96#$84;  { ▄ U+2584 }
  CH_UHALF    = #$E2#$96#$80;  { ▀ U+2580 }

  CH_BLK1     = #$E2#$96#$81;  { ▁ U+2581  1/8 }
  CH_BLK2     = #$E2#$96#$82;  { ▂ U+2582  2/8 }
  CH_BLK3     = #$E2#$96#$83;  { ▃ U+2583  3/8 }
  CH_BLK4     = #$E2#$96#$84;  { ▄ U+2584  4/8 = lower half }
  CH_BLK5     = #$E2#$96#$85;  { ▅ U+2585  5/8 }
  CH_BLK6     = #$E2#$96#$86;  { ▆ U+2586  6/8 }
  CH_BLK7     = #$E2#$96#$87;  { ▇ U+2587  7/8 }

  CH_SHADE_LIGHT  = #$E2#$96#$91;  { ░ U+2591 }
  CH_SHADE_MEDIUM = #$E2#$96#$92;  { ▒ U+2592 }
  CH_SHADE_DARK   = #$E2#$96#$93;  { ▓ U+2593 }

function InputEvent(AAction: TKeyAction; AChar: Char = #0): TInputEvent;
function InputEventMod(AAction: TKeyAction; AChar: Char; AModifiers: Byte): TInputEvent;
function MouseEvent(AX, AY: Integer; AButton: TMouseButton; AWheel: Integer = 0): TInputEvent;
function RepeatUTF8Char(const ACh: string; ACount: Integer): string;
function UTF8CodePointLen(AByte: Byte): Integer;

implementation

function InputEvent(AAction: TKeyAction; AChar: Char = #0): TInputEvent;
begin
  Result.Action := AAction;
  Result.CharValue := AChar;
  Result.MouseX := 0;
  Result.MouseY := 0;
  Result.MouseButton := mbNone;
  Result.MouseWheel := 0;
  Result.Modifiers := 0;
end;

function InputEventMod(AAction: TKeyAction; AChar: Char; AModifiers: Byte): TInputEvent;
begin
  Result := InputEvent(AAction, AChar);
  Result.Modifiers := AModifiers;
end;

function MouseEvent(AX, AY: Integer; AButton: TMouseButton; AWheel: Integer = 0): TInputEvent;
begin
  Result.Action := kaMouse;
  Result.CharValue := #0;
  Result.MouseX := AX;
  Result.MouseY := AY;
  Result.MouseButton := AButton;
  Result.MouseWheel := AWheel;
  Result.Modifiers := 0;
end;

function RepeatUTF8Char(const ACh: string; ACount: Integer): string;
var
  I: Integer;
begin
  Result := '';
  for I := 1 to ACount do
    Result := Result + ACh;
end;

function UTF8CodePointLen(AByte: Byte): Integer;
begin
  if AByte < $80 then Result := 1
  else if AByte < $C0 then Result := 1
  else if AByte < $E0 then Result := 2
  else if AByte < $F0 then Result := 3
  else Result := 4;
end;

end.
