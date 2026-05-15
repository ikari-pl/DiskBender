program test_pbwire;

{$mode objfpc}{$H+}

uses
  SysUtils, uPbWire;

var
  PassCount: Integer = 0;
  FailCount: Integer = 0;

procedure Check(const ALabel: string; ACond: Boolean);
begin
  if ACond then
  begin
    Inc(PassCount);
    WriteLn('  PASS: ', ALabel);
  end
  else
  begin
    Inc(FailCount);
    WriteLn('  FAIL: ', ALabel);
  end;
end;

function BytesEqual(const A, B: TBytes): Boolean;
var I: Integer;
begin
  if Length(A) <> Length(B) then Exit(False);
  for I := 0 to High(A) do
    if A[I] <> B[I] then Exit(False);
  Result := True;
end;

{ ── Varint primitive tests ────────────────────────────────────── }

procedure TestVarintRoundtripSmall;
var
  W: TPbWriter;
  R: TPbReader;
  Encoded: TBytes;
  Field: Integer;
  Wt: Byte;
begin
  WriteLn('--- TestVarintRoundtripSmall ---');
  W := TPbWriter.Create;
  try
    W.WriteUInt32(1, 0);
    W.WriteUInt32(2, 1);
    W.WriteUInt32(3, 127);
    W.WriteUInt32(4, 128);    { boundary -- needs 2 bytes }
    W.WriteUInt32(5, 300);    { from the proto3 docs: 0xAC 0x02 }
    Encoded := W.GetBytes;
  finally
    W.Free;
  end;
  R := TPbReader.Create(Encoded);
  try
    R.ReadTag(Field, Wt); Check('field 1 tag', (Field = 1) and (Wt = WIRE_VARINT));
    Check('field 1 value', R.ReadUInt32 = 0);
    R.ReadTag(Field, Wt); Check('field 2 tag', Field = 2);
    Check('field 2 value', R.ReadUInt32 = 1);
    R.ReadTag(Field, Wt); R.ReadUInt32;  { skip 3 }
    R.ReadTag(Field, Wt); Check('field 4 = 128', R.ReadUInt32 = 128);
    R.ReadTag(Field, Wt); Check('field 5 = 300', R.ReadUInt32 = 300);
    Check('reader at EOF', R.EOF);
  finally
    R.Free;
  end;
end;

procedure TestStringRoundtrip;
var
  W: TPbWriter;
  R: TPbReader;
  Encoded: TBytes;
  Field: Integer;
  Wt: Byte;
begin
  WriteLn('--- TestStringRoundtrip ---');
  W := TPbWriter.Create;
  try
    W.WriteString(1, 'hello');
    W.WriteString(2, '');                       { empty }
    W.WriteString(3, '*.BAS');                  { glob-like }
    W.WriteString(4, '/Users/ikari/HELLO.dsk'); { path }
    Encoded := W.GetBytes;
  finally
    W.Free;
  end;
  R := TPbReader.Create(Encoded);
  try
    R.ReadTag(Field, Wt); Check('s1 = hello', R.ReadString = 'hello');
    R.ReadTag(Field, Wt); Check('s2 = empty', R.ReadString = '');
    R.ReadTag(Field, Wt); Check('s3 = *.BAS', R.ReadString = '*.BAS');
    R.ReadTag(Field, Wt); Check('s4 = path', R.ReadString = '/Users/ikari/HELLO.dsk');
    Check('reader at EOF', R.EOF);
  finally
    R.Free;
  end;
end;

procedure TestBoolAndEnum;
var
  W: TPbWriter;
  R: TPbReader;
  Encoded: TBytes;
  Field: Integer;
  Wt: Byte;
begin
  WriteLn('--- TestBoolAndEnum ---');
  W := TPbWriter.Create;
  try
    W.WriteBool(1, True);
    W.WriteBool(2, False);
    W.WriteEnum(3, 5);
    W.WriteEnum(4, 0);
    Encoded := W.GetBytes;
  finally
    W.Free;
  end;
  R := TPbReader.Create(Encoded);
  try
    R.ReadTag(Field, Wt); Check('b1 = true', R.ReadBool = True);
    R.ReadTag(Field, Wt); Check('b2 = false', R.ReadBool = False);
    R.ReadTag(Field, Wt); Check('e3 = 5', R.ReadEnum = 5);
    R.ReadTag(Field, Wt); Check('e4 = 0', R.ReadEnum = 0);
  finally
    R.Free;
  end;
end;

{ ── Nested message round-trip ─────────────────────────────────── }

procedure TestNestedMessageRoundtrip;
var
  Inner, Outer: TPbWriter;
  R, IR: TPbReader;
  InnerBytes, OuterBytes, NestedBytes: TBytes;
  Field: Integer;
  Wt: Byte;
begin
  WriteLn('--- TestNestedMessageRoundtrip ---');

  { Inner message: { list_mode=2, glob="BAS" } }
  Inner := TPbWriter.Create;
  try
    Inner.WriteEnum(1, 2);
    Inner.WriteString(2, 'BAS');
    InnerBytes := Inner.GetBytes;
  finally
    Inner.Free;
  end;

  { Outer message: { left=Inner, last_path="HELLO.dsk" } }
  Outer := TPbWriter.Create;
  try
    Outer.WriteMessage(1, InnerBytes);
    Outer.WriteString(2, 'HELLO.dsk');
    OuterBytes := Outer.GetBytes;
  finally
    Outer.Free;
  end;

  { Decode }
  R := TPbReader.Create(OuterBytes);
  try
    R.ReadTag(Field, Wt);
    Check('outer field 1 LEN', (Field = 1) and (Wt = WIRE_LEN));
    NestedBytes := R.ReadBytes;
    Check('nested bytes length matches', Length(NestedBytes) = Length(InnerBytes));
    Check('nested bytes content matches', BytesEqual(NestedBytes, InnerBytes));

    IR := TPbReader.Create(NestedBytes);
    try
      IR.ReadTag(Field, Wt);
      Check('inner field 1 enum', (Field = 1) and (Wt = WIRE_VARINT));
      Check('inner enum value = 2', IR.ReadEnum = 2);
      IR.ReadTag(Field, Wt);
      Check('inner field 2 string', (Field = 2) and (Wt = WIRE_LEN));
      Check('inner string = BAS', IR.ReadString = 'BAS');
      Check('inner reader at EOF', IR.EOF);
    finally
      IR.Free;
    end;

    R.ReadTag(Field, Wt);
    Check('outer last_path = HELLO.dsk', R.ReadString = 'HELLO.dsk');
  finally
    R.Free;
  end;
end;

{ ── Unknown-field skipping (forward compat) ────────────────────── }

procedure TestSkipUnknownVarint;
var
  W: TPbWriter;
  R: TPbReader;
  Encoded: TBytes;
  Field: Integer;
  Wt: Byte;
  SeenString: string;
begin
  WriteLn('--- TestSkipUnknownVarint ---');
  W := TPbWriter.Create;
  try
    W.WriteUInt32(99, 12345);   { unknown to the reader }
    W.WriteString(1, 'hello');
    Encoded := W.GetBytes;
  finally
    W.Free;
  end;

  R := TPbReader.Create(Encoded);
  try
    SeenString := '';
    while R.ReadTag(Field, Wt) do
    begin
      case Field of
        1: SeenString := R.ReadString;
      else
        R.SkipField(Wt);
      end;
    end;
    Check('SkipField recovered subsequent string', SeenString = 'hello');
  finally
    R.Free;
  end;
end;

procedure TestSkipUnknownLen;
var
  W: TPbWriter;
  R: TPbReader;
  Encoded: TBytes;
  Field: Integer;
  Wt: Byte;
  SeenInt: Cardinal;
begin
  WriteLn('--- TestSkipUnknownLen ---');
  W := TPbWriter.Create;
  try
    W.WriteString(99, 'unknown payload that the reader does not expect');
    W.WriteUInt32(1, 42);
    Encoded := W.GetBytes;
  finally
    W.Free;
  end;

  R := TPbReader.Create(Encoded);
  try
    SeenInt := 0;
    while R.ReadTag(Field, Wt) do
    begin
      case Field of
        1: SeenInt := R.ReadUInt32;
      else
        R.SkipField(Wt);
      end;
    end;
    Check('SkipField LEN recovered subsequent uint32', SeenInt = 42);
  finally
    R.Free;
  end;
end;

procedure TestEmptyBytesYieldsEmptyReader;
var
  R: TPbReader;
  Empty: TBytes;
begin
  WriteLn('--- TestEmptyBytesYieldsEmptyReader ---');
  SetLength(Empty, 0);
  R := TPbReader.Create(Empty);
  try
    Check('empty reader at EOF', R.EOF);
  finally
    R.Free;
  end;
end;

procedure TestNegativeInt32Roundtrip;
var
  W: TPbWriter;
  R: TPbReader;
  Encoded: TBytes;
  Field: Integer;
  Wt: Byte;
begin
  WriteLn('--- TestNegativeInt32Roundtrip ---');
  W := TPbWriter.Create;
  try
    W.WriteInt32(1, -1);
    W.WriteInt32(2, -100);
    Encoded := W.GetBytes;
  finally
    W.Free;
  end;
  R := TPbReader.Create(Encoded);
  try
    R.ReadTag(Field, Wt); Check('int32 -1 round-trips', R.ReadInt32 = -1);
    R.ReadTag(Field, Wt); Check('int32 -100 round-trips', R.ReadInt32 = -100);
  finally
    R.Free;
  end;
end;

{ ── Runner ────────────────────────────────────────────────────── }

begin
  WriteLn;
  WriteLn('=== DiskBender proto3 wire-format codec tests ===');
  WriteLn;

  TestVarintRoundtripSmall;
  TestStringRoundtrip;
  TestBoolAndEnum;
  TestNestedMessageRoundtrip;
  TestSkipUnknownVarint;
  TestSkipUnknownLen;
  TestEmptyBytesYieldsEmptyReader;
  TestNegativeInt32Roundtrip;

  WriteLn;
  WriteLn('=== Results: ', PassCount, ' passed, ', FailCount, ' failed ===');
  WriteLn;

  if FailCount > 0 then Halt(1);
end.
