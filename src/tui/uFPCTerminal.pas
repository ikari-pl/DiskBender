unit uFPCTerminal;

{$mode objfpc}{$H+}

interface

uses
  SysUtils,
  {$IFDEF UNIX}BaseUnix, termio,{$ENDIF}
  {$IFDEF WINDOWS}Keyboard, Mouse, Video,{$ENDIF}
  uTerminalIO;

type
  {$IFDEF UNIX}
  TScreenCell = record
    Ch: string[4];
    Attr: Byte;
  end;
  {$ENDIF}

  TFPCTerminalInput = class(TInterfacedObject, ITerminalInput)
  public
    function WaitForKey: TInputEvent;
  end;

  TFPCTerminalOutput = class(TInterfacedObject, ITerminalOutput)
  {$IFDEF UNIX}
  strict private
    FWidth, FHeight: Integer;
    FPending: array of TScreenCell;
    FCurrent: array of TScreenCell;
    FSavedTIO: termios;
  {$ENDIF}
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

{$IFDEF UNIX}

{ ── Unix: raw stdin + xterm mouse protocol ───────────────────── }

var
  GSavedTIO: termios;
  GTIOSaved: Boolean = False;
  { When true the terminal acknowledged the kitty keyboard protocol query and
    we pushed flags 11 (disambiguate + event types + report-all-keys). In that
    mode every keystroke arrives as a CSI u event; ParseCSI maps kitty
    keycodes back to TKeyAction values. }
  GKittyMode: Boolean = False;

  { Pushback queue: bytes the kitty probe consumed that were NOT part of the
    expected CSI ? <flags> u response must be returned to subsequent callers
    of ReadByte so WaitForKey sees them. A 16-byte circular buffer is ample —
    the longest spurious prefix we'd ever encounter is a handful of bytes. }
  GPushback: array[0..15] of Byte;
  GPushHead: Integer = 0;   { read index }
  GPushTail: Integer = 0;   { write index }

procedure PushbackByte(B: Byte);
begin
  { Guard against overflow: if adding one more byte would wrap tail onto head
    the buffer is full — silently drop the byte rather than overwriting
    unread data.  Kitty probe debris is the only realistic source of overflow
    and losing a few of those bytes is harmless. }
  if ((GPushTail + 1) and 15) = GPushHead then Exit;
  GPushback[GPushTail] := B;
  GPushTail := (GPushTail + 1) and 15;
end;

procedure TTYWrite(const S: string);
begin
  if Length(S) > 0 then
    fpWrite(1, S[1], Length(S));
end;

function ReadByte(TimeoutMs: Integer): Integer;
var
  FDS: TFDSet;
  TV: TTimeVal;
  B: Byte;
begin
  { Drain the pushback queue first. }
  if GPushHead <> GPushTail then
  begin
    Result := GPushback[GPushHead];
    GPushHead := (GPushHead + 1) and 15;
    Exit;
  end;
  fpFD_ZERO(FDS);
  fpFD_SET(0, FDS);
  TV.tv_sec := TimeoutMs div 1000;
  TV.tv_usec := (TimeoutMs mod 1000) * 1000;
  if fpSelect(1, @FDS, nil, nil, @TV) > 0 then
  begin
    if fpRead(0, B, 1) = 1 then
      Exit(B);
  end;
  Result := -1;
end;

(* Probe for kitty keyboard protocol support by sending `CSI ? u`. Compliant
   terminals respond with `CSI ? <flags> u`. We wait up to 200ms for the
   leading ESC, then short timeouts for the rest of the sequence. Terminal
   must already be in raw mode.

   Any byte read that does NOT belong to the expected response is pushed back
   via PushbackByte so WaitForKey can return it to the application normally.
   This prevents input loss on terminals that don't support kitty but send
   other data immediately (e.g. a resize event or a pending key). *)
function ProbeKittyKeyboardSupport: Boolean;
var
  B, Stage: Integer;
  Consumed: array[0..15] of Byte;
  NConsumed: Integer;

  procedure PushAllConsumedBack;
  var
    K: Integer;
  begin
    { Push in reverse so the first byte consumed is the first byte returned. }
    for K := NConsumed - 1 downto 0 do
      PushbackByte(Consumed[K]);
    NConsumed := 0;
  end;

begin
  NConsumed := 0;
  Result := False;
  TTYWrite(#27'[?u');
  { Stage 0 = wait for ESC, generous timeout for the round-trip. }
  B := ReadByte(200);
  if B < 0 then Exit;
  if B <> 27 then
  begin
    Consumed[NConsumed] := Byte(B);
    Inc(NConsumed);
    PushAllConsumedBack;
    Exit;
  end;
  Consumed[NConsumed] := Byte(B);
  Inc(NConsumed);
  Stage := 1;
  while True do
  begin
    B := ReadByte(50);
    if B < 0 then
    begin
      PushAllConsumedBack;
      Exit;
    end;
    case Stage of
      1:
        begin
          Consumed[NConsumed] := Byte(B);
          Inc(NConsumed);
          if B = Ord('[') then Stage := 2
          else begin PushAllConsumedBack; Exit; end;
        end;
      2:
        begin
          Consumed[NConsumed] := Byte(B);
          Inc(NConsumed);
          if B = Ord('?') then Stage := 3
          else begin PushAllConsumedBack; Exit; end;
        end;
      3:
        if B = Ord('u') then Exit(True)
        else if (B >= Ord('0')) and (B <= Ord('9')) then
        begin
          { Keep consuming decimal flag digits — these are part of the response,
            don't push them back on success.  Semicolons are not valid in
            CSI ? <flags> u so treat them as unexpected (fall through to else). }
          if NConsumed < 16 then
          begin
            Consumed[NConsumed] := Byte(B);
            Inc(NConsumed);
          end;
        end
        else
        begin
          Consumed[NConsumed] := Byte(B);
          Inc(NConsumed);
          PushAllConsumedBack;
          Exit;
        end;
    end;
  end;
end;

function ParseNumber(const S: string; var P: Integer): Integer;
begin
  Result := 0;
  while (P <= Length(S)) and (S[P] >= '0') and (S[P] <= '9') do
  begin
    { Cap at 1_000_000 — safely above any sane terminal coordinate or key code.
      Continue consuming digits so the caller's position pointer stays valid. }
    if Result < 1000000 then
      Result := Result * 10 + Ord(S[P]) - Ord('0');
    Inc(P);
  end;
end;

function ParseCSI: TInputEvent;
var
  Params: string;
  B, Btn, X, Y, P, N: Integer;
  KMods, KEvt: Integer;   { kitty CSI-u: modifier bitmap+1 and event type }
  Final: Char;

  { An xterm modifier value is (bitmap+1); 2=Shift, 3=Alt, 4=Alt+Shift,
    5=Ctrl, 6=Ctrl+Shift, 7=Ctrl+Alt, 8=Ctrl+Alt+Shift. Convert to KM_* flags. }
  function XtermModToFlags(M: Integer): Byte;
  var Bits: Integer;
  begin
    Result := 0;
    if M <= 1 then Exit;
    Bits := M - 1;
    if (Bits and 1) <> 0 then Result := Result or KM_SHIFT;
    if (Bits and 2) <> 0 then Result := Result or KM_ALT;
    if (Bits and 4) <> 0 then Result := Result or KM_CTRL;
  end;

  procedure TryParseModifiedArrowOrFkey;
  var ModN, EvtType: Integer;
  begin
    (* Pattern: CSI 1;mod[:event_type];Letter  where Letter is A-F (arrows /
       home / end) or P-S (F1-F4). The optional event_type after ':' carries
       1=press, 2=repeat, 3=release in kitty/xterm-modified mode. *)
    P := 1;
    N := ParseNumber(Params, P);
    if N <> 1 then Exit;
    if (P > Length(Params)) or (Params[P] <> ';') then Exit;
    Inc(P);
    ModN := ParseNumber(Params, P);
    EvtType := 1;
    if (P <= Length(Params)) and (Params[P] = ':') then
    begin
      Inc(P);
      EvtType := ParseNumber(Params, P);
    end;
    Result.Modifiers := XtermModToFlags(ModN);
    if EvtType = 3 then Exit;  { release events would double-fire actions }
    case Final of
      'A': Result.Action := kaUp;
      'B': Result.Action := kaDown;
      'C': Result.Action := kaRight;
      'D': Result.Action := kaLeft;
      'H': Result.Action := kaHome;
      'F': Result.Action := kaEnd;
      'P': Result.Action := kaF1;
      'Q': Result.Action := kaF2;
      'R': Result.Action := kaF3;
      'S': Result.Action := kaF4;
    end;
  end;

begin
  Result := InputEvent(kaNone);
  Params := '';
  Final := #0;  { must be initialised; loop may exit via cap without assigning }

  repeat
    B := ReadByte(50);
    if B = -1 then Exit;
    if (B >= $40) and (B <= $7E) then
    begin
      Final := Chr(B);
      Break;
    end;
    { Reject non-ASCII spam early so the param string cannot grow indefinitely
      on a malformed or binary stream. }
    if B >= $80 then Exit;
    Params := Params + Chr(B);
  until Length(Params) > 64;

  { Parameter buffer capped without receiving a real final byte — discard to
    avoid dispatching on a stale Final value. }
  if Final = #0 then Exit;

  if Params = '' then
    case Final of
      'A': begin Result.Action := kaUp; Exit; end;
      'B': begin Result.Action := kaDown; Exit; end;
      'C': begin Result.Action := kaRight; Exit; end;
      'D': begin Result.Action := kaLeft; Exit; end;
      'H': begin Result.Action := kaHome; Exit; end;
      'F': begin Result.Action := kaEnd; Exit; end;
    end;

  (* CSI 1;mod;Letter — modified arrow / F1-F4 from xterm-style terminals. *)
  if Final in ['A','B','C','D','H','F','P','Q','R','S'] then
  begin
    TryParseModifiedArrowOrFkey;
    Exit;
  end;

  if Final = '~' then
  begin
    P := 1;
    N := ParseNumber(Params, P);
    Btn := 1;  { reuse for event type, default 1 = press }
    (* Optional ";mod[:event_type]" tail per xterm: e.g. CSI 13;5~ = Ctrl+F3,
       CSI 13;1:3~ = F3 release. *)
    if (P <= Length(Params)) and (Params[P] = ';') then
    begin
      Inc(P);
      Result.Modifiers := XtermModToFlags(ParseNumber(Params, P));
      if (P <= Length(Params)) and (Params[P] = ':') then
      begin
        Inc(P);
        Btn := ParseNumber(Params, P);
      end;
    end;
    if Btn = 3 then Exit;  { suppress release events }
    case N of
      5:  Result.Action := kaPageUp;
      6:  Result.Action := kaPageDown;
      11: Result.Action := kaF1;
      12: Result.Action := kaF2;
      13: Result.Action := kaF3;
      14: Result.Action := kaF4;
      15: Result.Action := kaF5;
      17: Result.Action := kaF6;
      18: Result.Action := kaF7;
      19: Result.Action := kaF8;
      20: Result.Action := kaF9;
      21: Result.Action := kaF10;
    end;
    Exit;
  end;

  { SGR mouse: ESC [ < Btn;X;Y M/m }
  if ((Final = 'M') or (Final = 'm')) and
     (Length(Params) > 0) and (Params[1] = '<') then
  begin
    if Final = 'm' then Exit;
    P := 2;
    Btn := ParseNumber(Params, P);
    if (P <= Length(Params)) and (Params[P] = ';') then Inc(P);
    X := ParseNumber(Params, P);
    if (P <= Length(Params)) and (Params[P] = ';') then Inc(P);
    Y := ParseNumber(Params, P);

    Result.Action := kaMouse;
    Result.MouseX := X;
    Result.MouseY := Y;
    Result.MouseButton := mbNone;
    Result.MouseWheel := 0;
    if (Btn and 4)  <> 0 then Result.Modifiers := Result.Modifiers or KM_SHIFT;
    if (Btn and 8)  <> 0 then Result.Modifiers := Result.Modifiers or KM_ALT;
    if (Btn and 16) <> 0 then Result.Modifiers := Result.Modifiers or KM_CTRL;

    if (Btn and 64) <> 0 then
    begin
      if (Btn and 1) = 0 then
        Result.MouseWheel := -1
      else
        Result.MouseWheel := 1;
    end
    else
      case Btn and 3 of
        0: Result.MouseButton := mbLeft;
        1: Result.MouseButton := mbMiddle;
        2: Result.MouseButton := mbRight;
      end;
    Exit;
  end;

  (* Kitty keyboard protocol event: CSI key;mods[:event_type] u
     When GKittyMode is true the terminal pushes ALL keystrokes through this
     path (flags 11 active). When false we still see this for the few keys
     that disambiguation forces (mainly modifier-only events from terminals
     that volunteer them). Map the kitty key-code table back to TKeyAction. *)
  if Final = 'u' then
  begin
    P := 1;
    N := ParseNumber(Params, P);
    KMods := 1;  { modifier bitmap+1 (xterm convention) }
    KEvt := 1;   { event type (1=press, 2=repeat, 3=release) }
    if (P <= Length(Params)) and (Params[P] = ';') then
    begin
      Inc(P);
      KMods := ParseNumber(Params, P);
      if (P <= Length(Params)) and (Params[P] = ':') then
      begin
        Inc(P);
        KEvt := ParseNumber(Params, P);
      end;
    end;
    Result.Modifiers := XtermModToFlags(KMods);
    case N of
      { Modifier-only press/release events. Mods bitmap already reflects the
        post-event state so the controller can update its label cache. }
      57441, 57442, 57443, 57447, 57448, 57449:
        Result.Action := kaModifierChange;
      { Special keys (kitty key codes). }
      9:                        Result.Action := kaTab;
      13:                       Result.Action := kaEnter;
      27:                       Result.Action := kaEsc;
      127:                      Result.Action := kaBackspace;
      57352:                    Result.Action := kaLeft;
      57353:                    Result.Action := kaRight;
      57354:                    Result.Action := kaUp;
      57355:                    Result.Action := kaDown;
      57356:                    Result.Action := kaPageUp;
      57357:                    Result.Action := kaPageDown;
      57358:                    Result.Action := kaHome;
      57359:                    Result.Action := kaEnd;
      57364:                    Result.Action := kaF1;
      57365:                    Result.Action := kaF2;
      57366:                    Result.Action := kaF3;
      57367:                    Result.Action := kaF4;
      57368:                    Result.Action := kaF5;
      57369:                    Result.Action := kaF6;
      57370:                    Result.Action := kaF7;
      57371:                    Result.Action := kaF8;
      57372:                    Result.Action := kaF9;
      57373:                    Result.Action := kaF10;
    else
      { Plain ASCII codepoint → emit kaChar. Letters arrive in their
        lowercase form; UpCase() in the controller handles case. }
      if (N >= 32) and (N <= 126) then
      begin
        Result.Action := kaChar;
        Result.CharValue := Chr(N);
      end;
    end;
    { Suppress release events for everything except modifier-change, so a
      single tap doesn't fire two actions in flag-2 mode. }
    if (Result.Action <> kaModifierChange) and (KEvt = 3) then
      Result.Action := kaNone;
    Exit;
  end;

  { Legacy mouse: ESC [ M Cb Cx Cy }
  if (Final = 'M') and (Params = '') then
  begin
    Btn := ReadByte(50);
    X := ReadByte(50);
    Y := ReadByte(50);
    if (Btn = -1) or (X = -1) or (Y = -1) then Exit;
    Btn := Btn - 32;
    X := X - 32;
    Y := Y - 32;

    if (Btn and 3) = 3 then Exit;

    Result.Action := kaMouse;
    Result.MouseX := X;
    Result.MouseY := Y;
    Result.MouseButton := mbNone;
    Result.MouseWheel := 0;
    if (Btn and 4)  <> 0 then Result.Modifiers := Result.Modifiers or KM_SHIFT;
    if (Btn and 8)  <> 0 then Result.Modifiers := Result.Modifiers or KM_ALT;
    if (Btn and 16) <> 0 then Result.Modifiers := Result.Modifiers or KM_CTRL;

    if (Btn and 64) <> 0 then
    begin
      if (Btn and 1) = 0 then
        Result.MouseWheel := -1
      else
        Result.MouseWheel := 1;
    end
    else
      case Btn and 3 of
        0: Result.MouseButton := mbLeft;
        1: Result.MouseButton := mbMiddle;
        2: Result.MouseButton := mbRight;
      end;
  end;
end;

function ParseEscape: TInputEvent;
var
  B: Integer;
begin
  Result := InputEvent(kaNone);
  B := ReadByte(50);
  if B = -1 then
  begin
    Result.Action := kaEsc;
    Exit;
  end;

  case Chr(B) of
    '[': Result := ParseCSI;
    'O': begin
           B := ReadByte(50);
           if B >= 0 then
             case Chr(B) of
               'P': Result.Action := kaF1;
               'Q': Result.Action := kaF2;
               'R': Result.Action := kaF3;
               'S': Result.Action := kaF4;
               'H': Result.Action := kaHome;
               'F': Result.Action := kaEnd;
             end;
         end;
  end;
end;

function TFPCTerminalInput.WaitForKey: TInputEvent;
var
  B: Integer;
begin
  repeat
    B := ReadByte(20);
    if B = -1 then Continue;

    if B = 27 then
    begin
      Result := ParseEscape;
      if Result.Action <> kaNone then Exit;
      Continue;
    end;

    Result := InputEvent(kaNone);
    case B of
      13: Result.Action := kaEnter;
       9: Result.Action := kaTab;
      8, 127: Result.Action := kaBackspace;
    else
      if B >= 32 then
      begin
        Result.Action := kaChar;
        Result.CharValue := Chr(B);
      end;
    end;

    if Result.Action <> kaNone then Exit;
  until False;
end;

{ ── Unix: ANSI/UTF-8 terminal output ────────────────────────── }

const
  CGAtoANSI: array[0..7] of Byte = (0, 4, 2, 6, 1, 5, 3, 7);

function AttrToSGR(AAttr: Byte): string;
var
  FG, BG: Byte;
begin
  FG := AAttr and $0F;
  BG := (AAttr shr 4) and $07;
  if FG < 8 then
    Result := #27'[0;' + IntToStr(30 + CGAtoANSI[FG]) + ';' +
              IntToStr(40 + CGAtoANSI[BG]) + 'm'
  else
    Result := #27'[0;' + IntToStr(90 + CGAtoANSI[FG and 7]) + ';' +
              IntToStr(40 + CGAtoANSI[BG]) + 'm';
end;

function TFPCTerminalOutput.GetWidth: Integer;
begin
  Result := FWidth;
end;

function TFPCTerminalOutput.GetHeight: Integer;
begin
  Result := FHeight;
end;

procedure TFPCTerminalOutput.PutText(X, Y: Integer; const AText: string;
  AAttr: Byte);
var
  ByteIdx, CpLen, Col, CellPos: Integer;
begin
  if (Y < 1) or (Y > FHeight) then Exit;
  ByteIdx := 1;
  Col := 0;
  while ByteIdx <= Length(AText) do
  begin
    CpLen := UTF8CodePointLen(Byte(AText[ByteIdx]));
    if ByteIdx + CpLen - 1 > Length(AText) then
      CpLen := Length(AText) - ByteIdx + 1;
    CellPos := X + Col - 1;
    if (CellPos >= 0) and (CellPos < FWidth) then
    begin
      FPending[(Y - 1) * FWidth + CellPos].Ch := Copy(AText, ByteIdx, CpLen);
      FPending[(Y - 1) * FWidth + CellPos].Attr := AAttr;
    end;
    Inc(ByteIdx, CpLen);
    Inc(Col);
  end;
end;

procedure TFPCTerminalOutput.Clear;
var
  I: Integer;
begin
  for I := 0 to Length(FPending) - 1 do
  begin
    FPending[I].Ch := ' ';
    FPending[I].Attr := $07;
  end;
end;

procedure TFPCTerminalOutput.Flush;
var
  { Pre-allocated string builder: each cell can emit at most ~20 bytes for
    a cursor-move (ESC [ RR ; CC H = ~12), an SGR (ESC [ 0;90;40m = ~13),
    and a 4-byte UTF-8 codepoint.  Use a conservative 40-byte/cell upper
    bound so we never reallocate during the fill loop. }
  Buf: string;
  BufPos: Integer;
  EstSize: Integer;
  I, Row, Col, LastRow, LastCol, LastAttr: Integer;
  CellStr: string;
  SGR: string;
  Move_: string;
begin
  EstSize := Length(FPending) * 40;
  SetLength(Buf, EstSize);
  BufPos := 0;
  LastRow := -1;
  LastCol := -1;
  LastAttr := -1;

  for I := 0 to Length(FPending) - 1 do
  begin
    if (FPending[I].Ch = FCurrent[I].Ch) and
       (FPending[I].Attr = FCurrent[I].Attr) then
      Continue;
    Row := I div FWidth;
    Col := I mod FWidth;
    if (Row <> LastRow) or (Col <> LastCol + 1) then
    begin
      Move_ := #27'[' + IntToStr(Row + 1) + ';' + IntToStr(Col + 1) + 'H';
      if BufPos + Length(Move_) > Length(Buf) then
        SetLength(Buf, Length(Buf) + EstSize);
      Move(Move_[1], Buf[BufPos + 1], Length(Move_));
      Inc(BufPos, Length(Move_));
    end;
    if Integer(FPending[I].Attr) <> LastAttr then
    begin
      SGR := AttrToSGR(FPending[I].Attr);
      if BufPos + Length(SGR) > Length(Buf) then
        SetLength(Buf, Length(Buf) + EstSize);
      Move(SGR[1], Buf[BufPos + 1], Length(SGR));
      Inc(BufPos, Length(SGR));
      LastAttr := FPending[I].Attr;
    end;
    CellStr := string(FPending[I].Ch);
    if BufPos + Length(CellStr) > Length(Buf) then
      SetLength(Buf, Length(Buf) + EstSize);
    Move(CellStr[1], Buf[BufPos + 1], Length(CellStr));
    Inc(BufPos, Length(CellStr));
    LastRow := Row;
    LastCol := Col;
  end;

  if BufPos > 0 then
  begin
    SetLength(Buf, BufPos);
    TTYWrite(Buf);
  end;
  for I := 0 to Length(FPending) - 1 do
    FCurrent[I] := FPending[I];
end;

{ Init / Done are NOT reentrant.  Calling Init a second time while already in
  raw mode would capture the already-raw termios as the "saved" state — Done
  would then restore raw mode instead of the original cooked mode.  The
  GTIOSaved guard ensures the ORIGINAL cooked termios is captured exactly once,
  regardless of how many Init calls occur in a process lifetime. }
procedure TFPCTerminalOutput.Init;
var
  Raw: termios;
  WS: TWinSize;
  I: Integer;
begin
  if not GTIOSaved then
  begin
    TCGetAttr(0, GSavedTIO);
    GTIOSaved := True;
  end;
  FSavedTIO := GSavedTIO;

  Raw := FSavedTIO;
  Raw.c_iflag := Raw.c_iflag and not
    (IGNBRK or BRKINT or PARMRK or ISTRIP or INLCR or IGNCR or ICRNL or IXON);
  Raw.c_oflag := Raw.c_oflag and not OPOST;
  Raw.c_lflag := Raw.c_lflag and not
    (ECHO or ECHONL or ICANON or ISIG or IEXTEN);
  Raw.c_cflag := (Raw.c_cflag and not (CSIZE or PARENB)) or CS8;
  Raw.c_cc[VMIN] := 1;
  Raw.c_cc[VTIME] := 0;
  TCSetAttr(0, TCSANOW, Raw);

  FWidth := 80;
  FHeight := 25;
  if fpioctl(0, TIOCGWINSZ, @WS) = 0 then
  begin
    if WS.ws_col > 0 then FWidth := WS.ws_col;
    if WS.ws_row > 0 then FHeight := WS.ws_row;
  end;

  SetLength(FPending, FWidth * FHeight);
  SetLength(FCurrent, FWidth * FHeight);
  for I := 0 to FWidth * FHeight - 1 do
  begin
    FPending[I].Ch := ' ';
    FPending[I].Attr := $07;
    FCurrent[I].Ch := '';
    FCurrent[I].Attr := $FF;
  end;

  TTYWrite(#27'[?1049h');
  TTYWrite(#27'[?25l');
  TTYWrite(#27'[?1000h'#27'[?1006h');

  (* Probe the terminal for kitty keyboard protocol support. If supported,
     push flags 11 (1=disambiguate, 2=event types, 8=report-all-keys-as-CSI-u)
     which delivers standalone modifier press/release events and lets us
     live-update the status bar while a bare Shift/Ctrl is held. If the probe
     fails, leave the terminal at its default behavior — modifier-on-chord
     (e.g. Shift+F3) still works via xterm-style CSI 1;mod;Letter sequences. *)
  GKittyMode := ProbeKittyKeyboardSupport;
  if GKittyMode then
    TTYWrite(#27'[>11u');
end;

procedure TFPCTerminalOutput.Done;
begin
  if GKittyMode then
  begin
    TTYWrite(#27'[<u');  (* Pop kitty keyboard flags we pushed in Init. *)
    GKittyMode := False;
  end;
  TTYWrite(#27'[0m');
  TTYWrite(#27'[?1000l'#27'[?1006l');
  TTYWrite(#27'[?25h');
  TTYWrite(#27'[?1049l');
  TCSetAttr(0, TCSANOW, FSavedTIO);
  GTIOSaved := False;
end;

{$ENDIF}

{$IFDEF WINDOWS}

{ ── Windows: FPC Keyboard + Mouse units (Win32 Console API) ── }

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
    $47: Result.Action := kaHome;
    $4F: Result.Action := kaEnd;
    $49: Result.Action := kaPageUp;
    $51: Result.Action := kaPageDown;
    $44: Result.Action := kaF10;
  end;

  if Result.Action <> kaNone then
    Exit;

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

function TranslateMouseToEvent(const ME: TMouseEvent): TInputEvent;
begin
  Result := InputEvent(kaNone);
  if (ME.Action = MouseActionDown) then
  begin
    Result.Action := kaMouse;
    Result.MouseX := ME.x + 1;
    Result.MouseY := ME.y + 1;
    Result.MouseWheel := 0;
    case ME.buttons of
      MouseLeftButton:   Result.MouseButton := mbLeft;
      MouseRightButton:  Result.MouseButton := mbRight;
      MouseMiddleButton: Result.MouseButton := mbMiddle;
    else
      Result.MouseButton := mbNone;
    end;
  end
  else if (ME.Action = MouseActionMove) then
  begin
    if (ME.buttons and 8) <> 0 then
    begin
      Result.Action := kaMouse;
      Result.MouseX := ME.x + 1;
      Result.MouseY := ME.y + 1;
      Result.MouseButton := mbNone;
      Result.MouseWheel := 1;
    end
    else if (ME.buttons and 16) <> 0 then
    begin
      Result.Action := kaMouse;
      Result.MouseX := ME.x + 1;
      Result.MouseY := ME.y + 1;
      Result.MouseButton := mbNone;
      Result.MouseWheel := -1;
    end;
  end;
end;

function TFPCTerminalInput.WaitForKey: TInputEvent;
var
  K: TKeyEvent;
  ME: TMouseEvent;
begin
  repeat
    K := PollKeyEvent;
    if K <> 0 then
    begin
      K := GetKeyEvent;
      Result := TranslateRawToEvent(K);
      if Result.Action <> kaNone then Exit;
    end;
    if PollMouseEvent(ME) then
    begin
      GetMouseEvent(ME);
      Result := TranslateMouseToEvent(ME);
      if Result.Action <> kaNone then Exit;
    end;
    Sleep(10);
  until False;
end;

{ ── Windows: Video-based output ──────────────────────────────── }

function TFPCTerminalOutput.GetWidth: Integer;
begin
  Result := ScreenWidth;
end;

function TFPCTerminalOutput.GetHeight: Integer;
begin
  Result := ScreenHeight;
end;

procedure TFPCTerminalOutput.PutText(X, Y: Integer; const AText: string;
  AAttr: Byte);
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
  InitMouse;
end;

procedure TFPCTerminalOutput.Done;
begin
  DoneMouse;
  DoneKeyboard;
  DoneVideo;
end;

{$ENDIF}

finalization
  {$IFDEF UNIX}
  { Only emit terminal-restore sequences if we actually entered raw/TUI mode
    (GTIOSaved is set in TFPCTerminalOutput.Init).  In CLI mode the terminal
    was never touched, so writing these would dump escape bytes into stdout. }
  if GTIOSaved then
  begin
    TTYWrite(#27'[0m');
    TTYWrite(#27'[?1000l'#27'[?1006l');
    TTYWrite(#27'[?25h');
    TTYWrite(#27'[?1049l');
    TCSetAttr(0, TCSANOW, GSavedTIO);
  end;
  {$ENDIF}

end.
