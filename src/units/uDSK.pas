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

  { Sector Information Block (8 bytes each, inside Track Info Block) }
  TSectorInfo = packed record
    Track: Byte;
    Side: Byte;
    SectorID: Byte;
    SectorSize: Byte; { (128 << Size) bytes }
    FDCStatus1: Byte;
    FDCStatus2: Byte;
    DataLength: Word; { Not used for Standard DSK }
  end;

  { Track Information Block (Starts each track) }
  TTrackInfoBlock = packed record
    Signature: array[0..11] of Char; { "Track-Info\r\n" }
    Reserved: array[0..3] of Byte;
    TrackNum: Byte;
    SideNum: Byte;
    Reserved2: array[0..1] of Byte;
    SectorSize: Byte;
    NumSectors: Byte;
    GAP3Length: Byte;
    FillerByte: Byte;
    SectorInfos: array[0..28] of TSectorInfo;
  end;

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
    procedure ParseHeader;
    
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
    
    property DSKType: TDSKType read FDSKType;
    property NumTracks: Byte read GetNumTracks;
    property NumSides: Byte read GetNumSides;
    property Modified: Boolean read GetModified;
    property FilePath: string read GetFilePath;
  end;

implementation

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
  if Pos('MV - CPCEMU', Sig) > 0 then
    FDSKType := dtStandard
  else if Pos('EXTENDED', Sig) > 0 then
    FDSKType := dtExtended
  else
    FDSKType := dtUnknown;
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

  SetLength(FTracks, FHeader.NumTracks * FHeader.NumSides);
  SetLength(FDataOffsets, FHeader.NumTracks * FHeader.NumSides);
  SetLength(FSectorDataOffsets, FHeader.NumTracks * FHeader.NumSides);

  CurrentOffset := 256;
  for I := 0 to (FHeader.NumTracks * FHeader.NumSides) - 1 do
  begin
    if CurrentOffset + SizeOf(TTrackInfoBlock) > FStream.Size then
      raise EDiskError.CreateFmt('Truncated DSK image at track %d.', [I]);

    FStream.Position := CurrentOffset;
    FStream.ReadBuffer(FTracks[I], SizeOf(TTrackInfoBlock));
    FDataOffsets[I] := CurrentOffset + 256;

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
  FStream.SaveToFile(FFilePath);
  FModified := False;
end;

procedure TDiskBenderDSK.Revert;
begin
  Load;
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
end;

function TDiskBenderDSK.GetTrackInfo(TrackIdx: Integer): TTrackInfoBlock;
begin
  if (TrackIdx >= 0) and (TrackIdx < Length(FTracks)) then
    Result := FTracks[TrackIdx]
  else
    FillChar(Result, SizeOf(Result), 0);
end;

end.
