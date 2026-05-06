program TestDSK;

{$mode objfpc}{$H+}

uses
  SysUtils, Classes, uDSK, uTestRunner;

const
  TEST_DSK = 'test_dsk_image.dsk';

procedure CreateMockDSK;
var
  FS: TFileStream;
  Header: TDSKHeader;
  TIB: TTrackInfoBlock;
  I, T, S: Integer;
  DummySector: array[0..511] of Byte;
begin
  FS := TFileStream.Create(TEST_DSK, fmCreate);
  try
    FillChar(Header, SizeOf(Header), 0);
    Move('EXTENDED CPC DSK File'#13#10, Header.Signature, 22);
    Header.NumTracks := 2;
    Header.NumSides := 1;
    { Track size is 256 + (9 * 512) = 4864 (0x1300) => 0x13 in TrackSizes }
    Header.TrackSizes[0] := $13;
    Header.TrackSizes[1] := $13;
    FS.WriteBuffer(Header, 256);

    for T := 0 to 1 do
    begin
      FillChar(TIB, SizeOf(TIB), 0);
      Move('Track-Info'#13#10, TIB.Signature, 12);
      TIB.TrackNum := T;
      TIB.SideNum := 0;
      TIB.SectorSize := 2; { 512 bytes }
      TIB.NumSectors := 9;
      for S := 0 to 8 do
      begin
        TIB.SectorInfos[S].SectorID := $C1 + S;
        TIB.SectorInfos[S].DataLength := 512;
      end;
      FS.WriteBuffer(TIB, 256);

      for S := 0 to 8 do
      begin
        FillChar(DummySector, 512, (T shl 4) or S);
        FS.WriteBuffer(DummySector, 512);
      end;
    end;
  finally
    FS.Free;
  end;
end;

procedure TestRecordSizes;
begin
  AssertEquals(256, SizeOf(TDSKHeader), 'TDSKHeader size must be 256 bytes');
  AssertEquals(8, SizeOf(TSectorInfo), 'TSectorInfo size must be 8 bytes');
  AssertEquals(256, SizeOf(TTrackInfoBlock), 'TTrackInfoBlock size must be 256 bytes');
end;

procedure TestDSKLoading;
var
  Disk: TDiskBenderDSK;
  SecSize: Word;
  Data: PByteArray;
begin
  Disk := TDiskBenderDSK.Create(TEST_DSK);
  try
    Disk.Load;
    AssertEquals(Ord(dtExtended), Ord(Disk.DSKType), 'Disk type must be Extended');
    AssertEquals(2, Disk.NumTracks, 'Tracks count mismatch');
    AssertEquals(1, Disk.NumSides, 'Sides count mismatch');

    { Check data from Track 1, Sector $C5 (Index 4) }
    Data := Disk.GetSectorData(1, 4, SecSize);
    AssertEquals(512, SecSize, 'Sector size mismatch');
    AssertTrue(Data <> nil, 'Sector data pointer must not be nil');
    AssertEquals($14, Data^[0], 'Sector content mismatch at Track 1, Sector $C5');
    FreeMem(Data);
  finally
    Disk.Free;
  end;
end;

begin
  RunTest('Record Packing', @TestRecordSizes);
  RunTest('Mock DSK Creation', @CreateMockDSK);
  RunTest('DSK Parsing & Offsets', @TestDSKLoading);
  DeleteFile(TEST_DSK);
end.
