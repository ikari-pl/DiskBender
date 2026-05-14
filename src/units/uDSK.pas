unit uDSK;

{$mode objfpc}{$H+}
{$packrecords 1}

interface

uses
  Classes, SysUtils, Math, uInterfaces;

type
  { DSK Header (First 256 bytes) }
  TDSKHeader = packed record
    Signature: array[0..33] of Char;
    Creator: array[0..13] of Char;
    NumTracks: Byte;
    NumSides: Byte;
    TrackSize: Word;              { Only for Standard DSK }
    TrackSizes: array[0..203] of Byte; { Only for Extended DSK (TrackSize / 256) }
  end;

  { TSectorInfo / TTrackInfoBlock now live in uInterfaces.pas so IVirtualDisk
    can expose GetTrackInfo without callers casting to TDiskBenderDSK. }

  TDSKType = (dtUnknown, dtStandard, dtExtended);

  EDiskError = class(Exception);

  { Modernized DSK Class implementing IVirtualDisk }
  TDiskBenderDSK = class(TInterfacedObject, IVirtualDisk)
  strict private
    FHeader: TDSKHeader;
    FDSKType: TDSKType;
    FFilePath: string;
    FStream: TMemoryStream;
    FTracks: array of TTrackInfoBlock;
    FDataOffsets: array of Int64;
    FSectorDataOffsets: array of array of Int64;
    FModified: Boolean;
    { Sorted sector-ID cache (lazy). FSortedIDsValid[T]=True means
      FSortedIDs[T] holds the ascending-sorted SectorIDs for track T.
      Invalidated on Load, Revert, and PutSectorData. }
    FSortedIDs: array of TBytes;
    FSortedIDsValid: array of Boolean;
    procedure ParseHeader;
    procedure FixHeaderOffsets;
    procedure InvalidateSortedIDCache;

    { IVirtualDisk implementation }
    function GetNumTracks: Byte;
    function GetNumSides: Byte;
    function GetFilePath: string;
    function GetModified: Boolean;
  public
    constructor Create(const AFilePath: string);
    destructor Destroy; override;

    procedure Load;
    procedure Save;
    procedure Revert;

    function GetSectorData(TrackIdx, SectorIdx: Integer): TBytes;
    procedure PutSectorData(TrackIdx, SectorIdx: Integer; const Data: TBytes);

    function GetTrackInfo(TrackIdx: Integer): TTrackInfoBlock;
    function GetSortedSectorIDs(TrackIdx: Integer): TBytes;

    property DSKType: TDSKType read FDSKType;
    property NumTracks: Byte read GetNumTracks;
    property NumSides: Byte read GetNumSides;
    property Modified: Boolean read GetModified;
    property FilePath: string read GetFilePath;
  end;

implementation

procedure TDiskBenderDSK.InvalidateSortedIDCache;
var
  I: Integer;
begin
  for I := 0 to Length(FSortedIDsValid) - 1 do
    FSortedIDsValid[I] := False;
end;

constructor TDiskBenderDSK.Create(const AFilePath: string);
begin
  inherited Create;
  FFilePath := AFilePath;
  FDSKType := dtUnknown;
  FStream := TMemoryStream.Create;
  FModified := False;
end;

destructor TDiskBenderDSK.Destroy;
begin
  FStream.Free;
  inherited Destroy;
end;

function TDiskBenderDSK.GetNumTracks: Byte;
begin
  Result := FHeader.NumTracks;
end;

function TDiskBenderDSK.GetNumSides: Byte;
begin
  Result := FHeader.NumSides;
end;

function TDiskBenderDSK.GetFilePath: string;
begin
  Result := FFilePath;
end;

function TDiskBenderDSK.GetModified: Boolean;
begin
  Result := FModified;
end;

procedure TDiskBenderDSK.ParseHeader;
var
  Sig: string;
begin
  Sig := string(FHeader.Signature);
  { Anchor the match at offset 0 (prefix check) so a file whose first bytes
    don't start with the expected magic is rejected even if the string appears
    later in the header region. }
  if Copy(Sig, 1, Length('MV - CPCEMU')) = 'MV - CPCEMU' then
    FDSKType := dtStandard
  else if Copy(Sig, 1, Length('EXTENDED CPC DSK')) = 'EXTENDED CPC DSK' then
    FDSKType := dtExtended
  else
    FDSKType := dtUnknown;
end;

procedure TDiskBenderDSK.FixHeaderOffsets;
var
  Raw: array[0..255] of Byte;
  I, DiskInfoPos, FieldBase, Count: Integer;
begin
  { $30 is the standard-DSK NumTracks field offset.  If FieldBase already
    equals $30 the heuristic has found no new location to read from, so exit
    to avoid overwriting the header bytes we just parsed. }
  if FHeader.NumTracks > 0 then Exit;
  if FDSKType <> dtExtended then Exit;

  FStream.Position := 0;
  FStream.ReadBuffer(Raw, 256);

  DiskInfoPos := -1;
  for I := 15 to 30 do
  begin
    if (Raw[I] = Ord('D')) and (Raw[I+1] = Ord('i')) and
       (Raw[I+2] = Ord('s')) and (Raw[I+3] = Ord('k')) and
       (Raw[I+4] = Ord('-')) and (Raw[I+5] = Ord('I')) then
    begin
      DiskInfoPos := I;
      Break;
    end;
  end;

  if DiskInfoPos < 0 then Exit;

  I := DiskInfoPos + 9;
  while (I < 48) and (Raw[I] in [13, 10]) do Inc(I);

  FieldBase := I + 14;
  { Need at least FieldBase and FieldBase+1 within Raw[0..255], so cap at 254. }
  if (FieldBase >= 255) or (FieldBase = $30) then Exit;

  FHeader.NumTracks := Raw[FieldBase];
  FHeader.NumSides := Raw[FieldBase + 1];
  if FHeader.NumSides > 2 then FHeader.NumSides := 2;

  { Sanity-check NumTracks/NumSides against the actual stream size.  Each track
    occupies at least 256 bytes (one Track Info Block header).  Reject obviously
    implausible values before any SetLength call to avoid huge allocations on
    corrupt images. }
  if FHeader.NumSides = 0 then Exit;
  if FHeader.NumTracks = 0 then
    raise EDiskError.Create('Empty DSK: NumTracks=0 after header parse');
  if Int64(FHeader.NumTracks) * FHeader.NumSides * 256 > FStream.Size then
  begin
    { Clamp rather than zero so the load can still attempt partial recovery. }
    while (FHeader.NumTracks > 0) and
          (Int64(FHeader.NumTracks) * FHeader.NumSides * 256 > FStream.Size) do
      Dec(FHeader.NumTracks);
    if FHeader.NumTracks = 0 then Exit;
  end;

  Count := 256 - FieldBase - 4;
  if Count > 204 then Count := 204;
  if Count > 0 then
    Move(Raw[FieldBase + 4], FHeader.TrackSizes[0], Count);
end;

procedure TDiskBenderDSK.Load;
var
  I, J: Integer;
  CurrentOffset, SectorDataOffset: Int64;
  TSize: Word;
begin
  if not FileExists(FFilePath) then
    raise EDiskError.CreateFmt('File not found: %s', [FFilePath]);

  FStream.Clear;
  FStream.LoadFromFile(FFilePath);
  if FStream.Size < 256 then
    raise EDiskError.Create('File too small to be a DSK image.');

  FStream.Position := 0;
  FStream.ReadBuffer(FHeader, SizeOf(TDSKHeader));
  ParseHeader;

  if FDSKType = dtUnknown then
    raise EDiskError.Create('Unrecognized DSK signature.');

  FixHeaderOffsets;

  SetLength(FTracks, FHeader.NumTracks * FHeader.NumSides);
  SetLength(FDataOffsets, FHeader.NumTracks * FHeader.NumSides);
  SetLength(FSectorDataOffsets, FHeader.NumTracks * FHeader.NumSides);
  SetLength(FSortedIDs, FHeader.NumTracks * FHeader.NumSides);
  SetLength(FSortedIDsValid, FHeader.NumTracks * FHeader.NumSides);
  InvalidateSortedIDCache;

  CurrentOffset := 256;
  for I := 0 to (FHeader.NumTracks * FHeader.NumSides) - 1 do
  begin
    if CurrentOffset + SizeOf(TTrackInfoBlock) > FStream.Size then
      raise EDiskError.CreateFmt('Truncated DSK image at track %d.', [I]);

    FStream.Position := CurrentOffset;
    FStream.ReadBuffer(FTracks[I], SizeOf(TTrackInfoBlock));
    FDataOffsets[I] := CurrentOffset + 256;
    if FTracks[I].NumSectors > 29 then FTracks[I].NumSectors := 29;

    SetLength(FSectorDataOffsets[I], FTracks[I].NumSectors);
    SectorDataOffset := FDataOffsets[I];

    for J := 0 to FTracks[I].NumSectors - 1 do
    begin
      FSectorDataOffsets[I][J] := SectorDataOffset;
      if FDSKType = dtStandard then
        SectorDataOffset := SectorDataOffset + (128 shl FTracks[I].SectorSize)
      else
        SectorDataOffset := SectorDataOffset + FTracks[I].SectorInfos[J].DataLength;
    end;

    if FDSKType = dtStandard then
      TSize := FHeader.TrackSize
    else
      TSize := FHeader.TrackSizes[I] * 256;

    CurrentOffset := CurrentOffset + TSize;
  end;
  FModified := False;
end;

procedure TDiskBenderDSK.Save;
begin
  try
    FStream.SaveToFile(FFilePath);
  except
    raise;  { do NOT clear FModified on failure — leave state consistent }
  end;
  FModified := False;  { only reached when SaveToFile succeeded }
end;

procedure TDiskBenderDSK.Revert;
begin
  { Wrap Load so a failure leaves FModified unchanged rather than producing a
    torn state where the stream is partially re-initialised but FModified = False. }
  try
    Load;
  except
    raise;  { propagate; caller must not assume disk state is valid }
  end;
end;

function TDiskBenderDSK.GetSectorData(TrackIdx, SectorIdx: Integer): TBytes;
var
  DataSize: Word;
begin
  Result := nil;
  if (TrackIdx < 0) or (TrackIdx >= Length(FTracks)) then Exit;
  if (SectorIdx < 0) or (SectorIdx >= FTracks[TrackIdx].NumSectors) then Exit;

  if FDSKType = dtStandard then
    DataSize := 128 shl FTracks[TrackIdx].SectorSize
  else
    DataSize := FTracks[TrackIdx].SectorInfos[SectorIdx].DataLength;

  if DataSize = 0 then Exit;   { Extended DSK: sector header present, no data stored }
  { Guard against truncated or copy-protected images where the declared sector
    data extends past the actual stream (e.g. the last track of a protection
    disk whose size table sums to more than the file length).  Return nil so
    callers treat the sector as unreadable rather than raising EStreamError. }
  if FSectorDataOffsets[TrackIdx][SectorIdx] + DataSize > FStream.Size then Exit;
  SetLength(Result, DataSize);
  FStream.Position := FSectorDataOffsets[TrackIdx][SectorIdx];
  FStream.ReadBuffer(Result[0], DataSize);
end;

procedure TDiskBenderDSK.PutSectorData(TrackIdx, SectorIdx: Integer; const Data: TBytes);
var
  ExpectedSize: Integer;
begin
  if (TrackIdx < 0) or (TrackIdx >= Length(FTracks)) then Exit;
  if (SectorIdx < 0) or (SectorIdx >= FTracks[TrackIdx].NumSectors) then Exit;

  if FDSKType = dtStandard then
    ExpectedSize := 128 shl FTracks[TrackIdx].SectorSize
  else
    ExpectedSize := FTracks[TrackIdx].SectorInfos[SectorIdx].DataLength;

  FStream.Position := FSectorDataOffsets[TrackIdx][SectorIdx];
  FStream.WriteBuffer(Data[0], Min(Length(Data), ExpectedSize));
  FModified := True;
  { Invalidate the sorted-ID cache for this track — PutSectorData can, in
    principle, rewrite a track header in extended DSK images. }
  if (TrackIdx >= 0) and (TrackIdx < Length(FSortedIDsValid)) then
    FSortedIDsValid[TrackIdx] := False;
end;

function TDiskBenderDSK.GetSortedSectorIDs(TrackIdx: Integer): TBytes;
var
  TI: TTrackInfoBlock;
  I, J, Tmp: Integer;
begin
  Result := nil;
  if (TrackIdx < 0) or (TrackIdx >= Length(FTracks)) then Exit;
  if FSortedIDsValid[TrackIdx] then
  begin
    Result := FSortedIDs[TrackIdx];
    Exit;
  end;
  TI := FTracks[TrackIdx];
  SetLength(FSortedIDs[TrackIdx], TI.NumSectors);
  for I := 0 to TI.NumSectors - 1 do
    FSortedIDs[TrackIdx][I] := TI.SectorInfos[I].SectorID;
  { Insertion sort — n ≤ 36, no need for anything fancier. }
  for I := 1 to TI.NumSectors - 1 do
  begin
    Tmp := FSortedIDs[TrackIdx][I];
    J := I - 1;
    while (J >= 0) and (FSortedIDs[TrackIdx][J] > Tmp) do
    begin
      FSortedIDs[TrackIdx][J + 1] := FSortedIDs[TrackIdx][J];
      Dec(J);
    end;
    FSortedIDs[TrackIdx][J + 1] := Tmp;
  end;
  FSortedIDsValid[TrackIdx] := True;
  Result := FSortedIDs[TrackIdx];
end;

function TDiskBenderDSK.GetTrackInfo(TrackIdx: Integer): TTrackInfoBlock;
begin
  if (TrackIdx >= 0) and (TrackIdx < Length(FTracks)) then
    Result := FTracks[TrackIdx]
  else
    FillChar(Result, SizeOf(Result), 0);
end;

end.
