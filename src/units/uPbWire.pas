unit uPbWire;

{ Minimal proto3 wire-format codec, hand-rolled so we don't pull in a third-
  party Pascal protobuf library. Implements only the subset needed for the
  DiskBender config:

    - Wire types: 0 (VARINT) and 2 (LEN). No 32-bit, 64-bit, or group types.
    - Scalars: bool, int32, uint32, enum (all via varint).
    - Length-delimited: string (UTF-8), bytes (TBytes), embedded message.

  Skipping rules follow proto3: unknown fields are consumed and discarded
  according to their wire type so forward-compatibility is preserved.

  Reference: https://protobuf.dev/programming-guides/encoding/

  Why hand-roll? The wire format is ~50 LOC of real logic and the
  alternatives (Cetfor's protobuf-pascal, FpcProtobufRuntime, etc.) are
  either unmaintained, license-incompatible, or pull in code-generation
  toolchains that overkill a 30-field config file. }

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes;

const
  WIRE_VARINT = 0;
  WIRE_LEN    = 2;

type
  EPbError = class(Exception);

  { Streaming proto3 encoder. Accumulates encoded bytes; call GetBytes at
    the end. For nested messages, build the inner blob with a separate
    writer then WriteMessage(field_num, inner.GetBytes). }
  TPbWriter = class
  strict private
    FBuf: TBytes;
    procedure AppendByte(B: Byte);
    procedure AppendBytes(const B: TBytes);
    procedure WriteVarint(V: UInt64);
    procedure WriteTag(AFieldNum: Integer; AWireType: Byte);
  public
    constructor Create;
    procedure WriteBool(AFieldNum: Integer; V: Boolean);
    procedure WriteInt32(AFieldNum: Integer; V: Integer);
    procedure WriteUInt32(AFieldNum: Integer; V: Cardinal);
    procedure WriteEnum(AFieldNum: Integer; V: Integer);
    procedure WriteString(AFieldNum: Integer; const S: string);
    procedure WriteBytes(AFieldNum: Integer; const B: TBytes);
    { WriteMessage is identical to WriteBytes -- proto3 encodes embedded
      messages as length-prefixed bytes. Named differently for clarity. }
    procedure WriteMessage(AFieldNum: Integer; const B: TBytes);
    function GetBytes: TBytes;
  end;

  { Streaming proto3 decoder. Constructed from a TBytes; caller drives
    a ReadTag/ReadX loop and uses SkipField for unknown field numbers. }
  TPbReader = class
  strict private
    FBuf: TBytes;
    FPos: Integer;
    function ReadByte: Byte;
    function PeekByte: Byte;
  public
    constructor Create(const ABytes: TBytes);
    function EOF: Boolean;
    function ReadVarint: UInt64;
    function ReadTag(out AFieldNum: Integer; out AWireType: Byte): Boolean;
    function ReadBool: Boolean;
    function ReadInt32: Integer;
    function ReadUInt32: Cardinal;
    function ReadEnum: Integer;
    function ReadString: string;
    function ReadBytes: TBytes;
    procedure SkipField(AWireType: Byte);
  end;

implementation

{ ── Writer ───────────────────────────────────────────────────── }

constructor TPbWriter.Create;
begin
  inherited Create;
  SetLength(FBuf, 0);
end;

procedure TPbWriter.AppendByte(B: Byte);
var
  N: Integer;
begin
  N := Length(FBuf);
  SetLength(FBuf, N + 1);
  FBuf[N] := B;
end;

procedure TPbWriter.AppendBytes(const B: TBytes);
var
  N: Integer;
begin
  if Length(B) = 0 then Exit;
  N := Length(FBuf);
  SetLength(FBuf, N + Length(B));
  Move(B[0], FBuf[N], Length(B));
end;

procedure TPbWriter.WriteVarint(V: UInt64);
begin
  while V >= $80 do
  begin
    AppendByte((V and $7F) or $80);
    V := V shr 7;
  end;
  AppendByte(V and $7F);
end;

procedure TPbWriter.WriteTag(AFieldNum: Integer; AWireType: Byte);
begin
  WriteVarint((UInt64(AFieldNum) shl 3) or AWireType);
end;

procedure TPbWriter.WriteBool(AFieldNum: Integer; V: Boolean);
begin
  WriteTag(AFieldNum, WIRE_VARINT);
  if V then WriteVarint(1) else WriteVarint(0);
end;

procedure TPbWriter.WriteInt32(AFieldNum: Integer; V: Integer);
begin
  WriteTag(AFieldNum, WIRE_VARINT);
  { proto3 int32 uses two's complement varint -- negative values become 10 bytes. }
  WriteVarint(UInt64(Int64(V)));
end;

procedure TPbWriter.WriteUInt32(AFieldNum: Integer; V: Cardinal);
begin
  WriteTag(AFieldNum, WIRE_VARINT);
  WriteVarint(V);
end;

procedure TPbWriter.WriteEnum(AFieldNum: Integer; V: Integer);
begin
  WriteInt32(AFieldNum, V);
end;

procedure TPbWriter.WriteString(AFieldNum: Integer; const S: string);
var
  Raw: TBytes;
begin
  WriteTag(AFieldNum, WIRE_LEN);
  if S = '' then
  begin
    WriteVarint(0);
    Exit;
  end;
  SetLength(Raw, Length(S));
  Move(S[1], Raw[0], Length(S));
  WriteVarint(Length(Raw));
  AppendBytes(Raw);
end;

procedure TPbWriter.WriteBytes(AFieldNum: Integer; const B: TBytes);
begin
  WriteTag(AFieldNum, WIRE_LEN);
  WriteVarint(Length(B));
  AppendBytes(B);
end;

procedure TPbWriter.WriteMessage(AFieldNum: Integer; const B: TBytes);
begin
  WriteBytes(AFieldNum, B);
end;

function TPbWriter.GetBytes: TBytes;
begin
  Result := Copy(FBuf, 0, Length(FBuf));
end;

{ ── Reader ───────────────────────────────────────────────────── }

constructor TPbReader.Create(const ABytes: TBytes);
begin
  inherited Create;
  FBuf := ABytes;
  FPos := 0;
end;

function TPbReader.EOF: Boolean;
begin
  Result := FPos >= Length(FBuf);
end;

function TPbReader.ReadByte: Byte;
begin
  if FPos >= Length(FBuf) then
    raise EPbError.Create('TPbReader: unexpected end of buffer');
  Result := FBuf[FPos];
  Inc(FPos);
end;

function TPbReader.PeekByte: Byte;
begin
  if FPos >= Length(FBuf) then
    raise EPbError.Create('TPbReader: unexpected end of buffer (peek)');
  Result := FBuf[FPos];
end;

function TPbReader.ReadVarint: UInt64;
var
  Shift: Integer;
  B: Byte;
begin
  Result := 0;
  Shift := 0;
  repeat
    if Shift > 63 then
      raise EPbError.Create('TPbReader: varint too long');
    B := ReadByte;
    Result := Result or (UInt64(B and $7F) shl Shift);
    Inc(Shift, 7);
  until (B and $80) = 0;
end;

function TPbReader.ReadTag(out AFieldNum: Integer; out AWireType: Byte): Boolean;
var
  Tag: UInt64;
begin
  if EOF then Exit(False);
  Tag := ReadVarint;
  AWireType := Tag and $07;
  AFieldNum := Tag shr 3;
  Result := True;
end;

function TPbReader.ReadBool: Boolean;
begin
  Result := ReadVarint <> 0;
end;

function TPbReader.ReadInt32: Integer;
begin
  Result := Integer(Int64(ReadVarint));
end;

function TPbReader.ReadUInt32: Cardinal;
begin
  Result := Cardinal(ReadVarint);
end;

function TPbReader.ReadEnum: Integer;
begin
  Result := ReadInt32;
end;

function TPbReader.ReadString: string;
var
  Len: UInt64;
begin
  Len := ReadVarint;
  if Len = 0 then Exit('');
  if FPos + Integer(Len) > Length(FBuf) then
    raise EPbError.Create('TPbReader: string runs past buffer end');
  SetLength(Result, Len);
  Move(FBuf[FPos], Result[1], Len);
  Inc(FPos, Integer(Len));
end;

function TPbReader.ReadBytes: TBytes;
var
  Len: UInt64;
begin
  Len := ReadVarint;
  SetLength(Result, Len);
  if Len = 0 then Exit;
  if FPos + Integer(Len) > Length(FBuf) then
    raise EPbError.Create('TPbReader: bytes run past buffer end');
  Move(FBuf[FPos], Result[0], Len);
  Inc(FPos, Integer(Len));
end;

procedure TPbReader.SkipField(AWireType: Byte);
var
  Len: UInt64;
begin
  case AWireType of
    WIRE_VARINT: ReadVarint;
    WIRE_LEN:
      begin
        Len := ReadVarint;
        if FPos + Integer(Len) > Length(FBuf) then
          raise EPbError.Create('TPbReader: skipped LEN field runs past buffer end');
        Inc(FPos, Integer(Len));
      end;
  else
    raise EPbError.CreateFmt('TPbReader: unsupported wire type %d', [AWireType]);
  end;
end;

end.
