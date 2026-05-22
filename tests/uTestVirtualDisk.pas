unit uTestVirtualDisk;

{ Mock IVirtualDisk for unit-testing the CP/M layer without touching real
  DSK files. Builds a synthetic geometry in memory: caller picks tracks,
  sectors per track, sector size, and sector-ID base. All sector data is
  initialised to $E5 (CP/M's empty marker), so a TDiskBenderCPM created
  on top of this mock sees a freshly formatted disk. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, uInterfaces;

type
  TMockVirtualDisk = class(TInterfacedObject, IVirtualDisk)
  strict private
    FNumTracks: Byte;
    FNumSides: Byte;
    FSectorsPerTrack: Byte;
    FSectorSizeCode: Byte;       { 128 << SectorSizeCode = bytes (CPC=2 -> 512) }
    FSectorIDBase: Byte;         { CPC DATA=$C1, SYSTEM=$41, DATA-IBM=$01 }
    FModified: Boolean;
    FSectors: array of array of TBytes;  { [track][sector] = data }
    function GetNumTracks: Byte;
    function GetNumSides: Byte;
    function GetFilePath: string;
    function GetModified: Boolean;
  public
    constructor Create(ATracks, ASectorsPerTrack, ASectorSizeCode,
                       ASectorIDBase: Byte);
    procedure Load;
    procedure Save;
    procedure Revert;
    function GetSectorData(TrackIdx, SectorIdx: Integer): TBytes;
    procedure PutSectorData(TrackIdx, SectorIdx: Integer; const Data: TBytes);
    function GetTrackInfo(TrackIdx: Integer): TTrackInfoBlock;
    function GetSortedSectorIDs(TrackIdx: Integer): TBytes;
  end;

  { A skewed mock disk — sector IDs are assigned in CPC-DATA interleave order
    ($C1,$C6,$C2,$C7,$C3,$C8,$C4,$C9,$C5 for 9 sectors) instead of sequential.
    Use this to test that LogicalSectorID/Read/WriteLogicalSector correctly map
    logical ↔ physical positions even when the physical layout is skewed.
    Only 9-sector tracks use the hard-coded interleave; other counts fall back
    to the parent's sequential IDs. }
  TMockSkewedDisk = class(TMockVirtualDisk)
  public
    function GetTrackInfo(TrackIdx: Integer): TTrackInfoBlock;
    function GetSortedSectorIDs(TrackIdx: Integer): TBytes;
  end;

  { A heterogeneous-geometry mock — track 0 advertises a nominal sector size
    (e.g. 512 bytes via SectorSizeCode=2) but GetSectorData returns a short
    buffer (e.g. 2 bytes). Mirrors what Discology-style copy-protected CPC
    discs do: the IDAM declares one size but the data block was written
    truncated. Use this to test that every directory-buffer dereference in
    uCPM.pas respects the actual buffer length and not the nominal geometry.
    Without the bounds checks this disk causes ScanDirectory to read heap
    garbage and AddFile/Rename/etc. to corrupt the heap on write. }
  TMockHeteroDisk = class(TMockVirtualDisk)
  strict private
    FShortLen: Integer;     { actual data length to return for track 0 sectors }
  public
    constructor Create(ATracks, ASectorsPerTrack, ASectorSizeCode,
                       ASectorIDBase: Byte; AShortLen: Integer);
    function GetSectorData(TrackIdx, SectorIdx: Integer): TBytes;
  end;

implementation

constructor TMockVirtualDisk.Create(ATracks, ASectorsPerTrack, ASectorSizeCode,
                                    ASectorIDBase: Byte);
var
  T, S, Size: Integer;
begin
  inherited Create;
  FNumTracks := ATracks;
  FNumSides := 1;
  FSectorsPerTrack := ASectorsPerTrack;
  FSectorSizeCode := ASectorSizeCode;
  FSectorIDBase := ASectorIDBase;
  FModified := False;

  Size := 128 shl FSectorSizeCode;
  SetLength(FSectors, FNumTracks);
  for T := 0 to FNumTracks - 1 do
  begin
    SetLength(FSectors[T], FSectorsPerTrack);
    for S := 0 to FSectorsPerTrack - 1 do
    begin
      SetLength(FSectors[T][S], Size);
      FillChar(FSectors[T][S][0], Size, $E5);
    end;
  end;
end;

function TMockVirtualDisk.GetNumTracks: Byte;
begin
  Result := FNumTracks;
end;

function TMockVirtualDisk.GetNumSides: Byte;
begin
  Result := FNumSides;
end;

function TMockVirtualDisk.GetFilePath: string;
begin
  Result := '<mock>';
end;

function TMockVirtualDisk.GetModified: Boolean;
begin
  Result := FModified;
end;

procedure TMockVirtualDisk.Load;
begin
  { No-op; constructor already populated the buffers. }
end;

procedure TMockVirtualDisk.Save;
begin
  FModified := False;
end;

procedure TMockVirtualDisk.Revert;
begin
  { Tests that need revert semantics should snapshot externally. }
  FModified := False;
end;

function TMockVirtualDisk.GetSectorData(TrackIdx, SectorIdx: Integer): TBytes;
begin
  Result := nil;
  if (TrackIdx < 0) or (TrackIdx >= FNumTracks) then Exit;
  if (SectorIdx < 0) or (SectorIdx >= FSectorsPerTrack) then Exit;
  Result := Copy(FSectors[TrackIdx][SectorIdx], 0, Length(FSectors[TrackIdx][SectorIdx]));
end;

procedure TMockVirtualDisk.PutSectorData(TrackIdx, SectorIdx: Integer; const Data: TBytes);
var
  Want: Integer;
begin
  if (TrackIdx < 0) or (TrackIdx >= FNumTracks) then Exit;
  if (SectorIdx < 0) or (SectorIdx >= FSectorsPerTrack) then Exit;
  Want := Length(FSectors[TrackIdx][SectorIdx]);
  if Length(Data) >= Want then
    Move(Data[0], FSectors[TrackIdx][SectorIdx][0], Want)
  else if Length(Data) > 0 then
    Move(Data[0], FSectors[TrackIdx][SectorIdx][0], Length(Data));
  FModified := True;
end;

function TMockVirtualDisk.GetTrackInfo(TrackIdx: Integer): TTrackInfoBlock;
var
  S: Integer;
begin
  FillChar(Result, SizeOf(Result), 0);
  if (TrackIdx < 0) or (TrackIdx >= FNumTracks) then Exit;
  Result.TrackNum := TrackIdx;
  Result.SideNum := 0;
  Result.SectorSize := FSectorSizeCode;
  Result.NumSectors := FSectorsPerTrack;
  Result.GAP3Length := $4E;
  Result.FillerByte := $E5;
  for S := 0 to FSectorsPerTrack - 1 do
  begin
    Result.SectorInfos[S].Track := TrackIdx;
    Result.SectorInfos[S].Side := 0;
    Result.SectorInfos[S].SectorID := FSectorIDBase + S;
    Result.SectorInfos[S].SectorSize := FSectorSizeCode;
    Result.SectorInfos[S].DataLength := 128 shl FSectorSizeCode;
  end;
end;

function TMockVirtualDisk.GetSortedSectorIDs(TrackIdx: Integer): TBytes;
var
  TI: TTrackInfoBlock;
  I, J, Tmp: Integer;
begin
  Result := nil;
  TI := GetTrackInfo(TrackIdx);
  if TI.NumSectors = 0 then Exit;
  SetLength(Result, TI.NumSectors);
  for I := 0 to TI.NumSectors - 1 do
    Result[I] := TI.SectorInfos[I].SectorID;
  for I := 1 to TI.NumSectors - 1 do
  begin
    Tmp := Result[I];
    J := I - 1;
    while (J >= 0) and (Result[J] > Tmp) do
    begin
      Result[J + 1] := Result[J];
      Dec(J);
    end;
    Result[J + 1] := Tmp;
  end;
end;

{ TMockSkewedDisk }

const
  { CPC-DATA 9-sector interleave order. Physical positions 0..8 get these
    SectorIDs so that CP/M's sorted-ascending order ($C1..$C9) maps to a
    non-trivial physical permutation. }
  CPC_SKEW_9: array[0..8] of Byte = ($C1,$C6,$C2,$C7,$C3,$C8,$C4,$C9,$C5);

function TMockSkewedDisk.GetTrackInfo(TrackIdx: Integer): TTrackInfoBlock;
var
  TI: TTrackInfoBlock;
  S: Integer;
begin
  TI := inherited GetTrackInfo(TrackIdx);
  if TI.NumSectors = 9 then
    for S := 0 to 8 do
      TI.SectorInfos[S].SectorID := CPC_SKEW_9[S];
  Result := TI;
end;

function TMockSkewedDisk.GetSortedSectorIDs(TrackIdx: Integer): TBytes;
var
  TI: TTrackInfoBlock;
  I, J, Tmp: Integer;
begin
  Result := nil;
  TI := GetTrackInfo(TrackIdx);
  if TI.NumSectors = 0 then Exit;
  SetLength(Result, TI.NumSectors);
  for I := 0 to TI.NumSectors - 1 do
    Result[I] := TI.SectorInfos[I].SectorID;
  for I := 1 to TI.NumSectors - 1 do
  begin
    Tmp := Result[I];
    J := I - 1;
    while (J >= 0) and (Result[J] > Tmp) do
    begin
      Result[J + 1] := Result[J];
      Dec(J);
    end;
    Result[J + 1] := Tmp;
  end;
end;

{ TMockHeteroDisk }

constructor TMockHeteroDisk.Create(ATracks, ASectorsPerTrack, ASectorSizeCode,
                                   ASectorIDBase: Byte; AShortLen: Integer);
begin
  inherited Create(ATracks, ASectorsPerTrack, ASectorSizeCode, ASectorIDBase);
  FShortLen := AShortLen;
end;

function TMockHeteroDisk.GetSectorData(TrackIdx, SectorIdx: Integer): TBytes;
var
  Full: TBytes;
begin
  { Track 0 returns truncated buffers — simulating Discology-style malformed
    sectors where the IDAM advertises one size but the data block is short.
    Other tracks use the parent's normal behaviour so the test can still
    exercise mixed-geometry paths. }
  Full := inherited GetSectorData(TrackIdx, SectorIdx);
  if (TrackIdx <> 0) or (Full = nil) then Exit(Full);
  if Length(Full) <= FShortLen then Exit(Full);
  Result := Copy(Full, 0, FShortLen);
end;

end.
