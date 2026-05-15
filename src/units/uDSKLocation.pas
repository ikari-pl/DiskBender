unit uDSKLocation;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, uVFS, uInterfaces, uDSK, uCPM, uCPMTypes;

type
  { A CP/M file entry on a DSK image.
    Wraps the old IVirtualFile / TCPMFile model behind VFS interfaces. }
  TCPMFileEntry = class(TInterfacedObject, IEntry, ISizeable, IDeletable,
                        IRestorable, IAttributed, ICopySource, IRenameable,
                        IUserArea, IBlockOwning)
  strict private
    FFS: IFilesystem;
    FIndex: Integer;
    FName: string;
    FExt: string;
    FSizeKB: Integer;
    FIsDeleted: Boolean;
    FUser: Byte;
    FAttrs: TCPMAttrs;
  public
    constructor Create(AFS: IFilesystem; AIndex: Integer);
    { IEntry }
    function GetName: string;
    function GetDisplayName: string;
    { ISizeable }
    function GetSize: Int64;
    function GetSizeUnit: TSizeUnit;
    { IDeletable }
    function GetIsDeleted: Boolean;
    procedure Delete;
    { IRestorable }
    procedure Restore;
    { IAttributed }
    function GetAttributes: TEntryAttributes;
    procedure SetAttributes(AValue: TEntryAttributes);
    { ICopySource }
    procedure CopyTo(AStream: TStream);
    { IRenameable }
    procedure Rename(const NewName: string);
    { IUserArea }
    function GetUser: Byte;
    { IBlockOwning }
    function GetOwnedBlocks: TBlockNumberArray;
  end;

  { Synthetic entry representing boot/system tracks on SYSTEM format disks. }
  TBootEntry = class(TInterfacedObject, IEntry, ISizeable)
  strict private
    FBootTracks: Integer;
    FTotalBytes: Int64;
  public
    constructor Create(ABootTracks: Integer; ATotalBytes: Int64);
    function GetName: string;
    function GetDisplayName: string;
    function GetSize: Int64;
    function GetSizeUnit: TSizeUnit;
  end;

  { An opened DSK disk image as a container of CP/M files.
    Created when the user enters a .dsk file from the local pane. }
  TDSKContainer = class(TInterfacedObject, IEntry, IContainer,
                        IBlockMappable, IWritable, ICopyTarget,
                        ISortable, ISummary, IPhysicalLayout,
                        ISectorMappable, IPathProvider)
  strict private
    FDisk: IVirtualDisk;
    FFS: IFilesystem;
    FPath: string;
    FEntries: array of IEntry;
    { Block-map cache (C1) }
    FBlockMapCache: TBytes;
    FBlockMapValid: Boolean;
    { Sector-map cache (C2) }
    FSectorMapCache: TTrackColumnArray;
    FSectorMapValid: Boolean;
    procedure RebuildCache;
    procedure InvalidateMaps;
    function ComputeSectorMap: TTrackColumnArray;
  public
    constructor Create(const ADSKPath: string);
    destructor Destroy; override;
    { IEntry }
    function GetName: string;
    function GetDisplayName: string;
    { IContainer }
    function GetEntryCount: Integer;
    function GetEntry(Index: Integer): IEntry;
    function GetTitle: string;
    procedure Refresh;
    { IBlockMappable }
    function GetBlockMap: TBytes;
    function GetBlockCount: Integer;
    { IWritable }
    function GetModified: Boolean;
    procedure Save;
    procedure Revert;
    { ICopyTarget }
    function Import(ASource: ICopySource; const AName: string): Boolean;
    { ISortable }
    procedure Sort(AField: TSortField; Ascending: Boolean; DirsFirst: Boolean);
    { ISummary }
    function GetSummaryInfo: string;
    { IPhysicalLayout }
    function GetLayoutInfo: TLayoutInfoArray;
    { ISectorMappable }
    function GetSectorMap: TTrackColumnArray;
    { IPathProvider }
    function GetPath: string;

    property Disk: IVirtualDisk read FDisk;
    property Filesystem: IFilesystem read FFS;
    property Path: string read FPath;
  end;

function CreateDSKAwareEntry(const AFullPath: string): IEntry;

implementation

uses
  uLocalLocation;

{ ── TBootEntry ───────────────────────────────────────────────── }

constructor TBootEntry.Create(ABootTracks: Integer; ATotalBytes: Int64);
begin
  inherited Create;
  FBootTracks := ABootTracks;
  FTotalBytes := ATotalBytes;
end;

function TBootEntry.GetName: string;
begin
  Result := '<BOOT>';
end;

function TBootEntry.GetDisplayName: string;
begin
  Result := '<BOOT>';
end;

function TBootEntry.GetSize: Int64;
begin
  Result := FTotalBytes;
end;

function TBootEntry.GetSizeUnit: TSizeUnit;
begin
  Result := suBytes;
end;

{ ── TCPMFileEntry ─────────────────────────────────────────────── }

constructor TCPMFileEntry.Create(AFS: IFilesystem; AIndex: Integer);
var
  VF: IVirtualFile;
begin
  inherited Create;
  FFS := AFS;
  FIndex := AIndex;
  VF := FFS.GetFile(AIndex);
  FName := VF.Name;
  FExt := VF.Extension;
  FSizeKB := VF.SizeKB;
  FIsDeleted := VF.IsDeleted;
  FUser := VF.User;
  FAttrs := [];
end;

function TCPMFileEntry.GetName: string;
begin
  Result := Trim(FName);
  if FExt <> '' then
    Result := Result + '.' + Trim(FExt);
end;

function TCPMFileEntry.GetDisplayName: string;
begin
  if FIsDeleted then
    Result := '?' + Copy(GetName, 2, MaxInt)
  else
    Result := GetName;
end;

function TCPMFileEntry.GetSize: Int64;
begin
  Result := FSizeKB;
end;

function TCPMFileEntry.GetSizeUnit: TSizeUnit;
begin
  Result := suKB;
end;

function TCPMFileEntry.GetIsDeleted: Boolean;
begin
  Result := FIsDeleted;
end;

procedure TCPMFileEntry.Delete;
begin
  if not FIsDeleted then
  begin
    FFS.ToggleDelete(FIndex);
    FIsDeleted := True;
  end;
end;

procedure TCPMFileEntry.Restore;
begin
  if FIsDeleted and (Length(FName) > 0) then
  begin
    FFS.UndeleteFile(FIndex, FName[1]);
    FIsDeleted := False;
  end;
end;

function TCPMFileEntry.GetAttributes: TEntryAttributes;
begin
  Result := [];
  if caReadOnly in FAttrs then Include(Result, eaReadOnly);
  if caSystem in FAttrs then Include(Result, eaSystem);
  if caArchive in FAttrs then Include(Result, eaArchive);
end;

procedure TCPMFileEntry.SetAttributes(AValue: TEntryAttributes);
begin
  FAttrs := [];
  if eaReadOnly in AValue then Include(FAttrs, caReadOnly);
  if eaSystem in AValue then Include(FAttrs, caSystem);
  if eaArchive in AValue then Include(FAttrs, caArchive);
end;

procedure TCPMFileEntry.CopyTo(AStream: TStream);
begin
  FFS.GetFileContent(FIndex, AStream);
end;

procedure TCPMFileEntry.Rename(const NewName: string);
var
  Parsed: TCPMFileName;
begin
  FFS.RenameFile(FIndex, NewName);
  { Keep both halves of the IEntry mirror in sync with the backend. The
    underlying TDiskBenderCPM.RenameFile splits NewName via TCPMFileName.Parse;
    do the same here so FName/FExt don't drift apart and produce 'BAR.DAT.TXT'
    after a rename from FOO.TXT to BAR.DAT. }
  Parsed := TCPMFileName.Parse(NewName);
  if Parsed.IsValid then
  begin
    FName := Parsed.Name;
    FExt  := Parsed.Ext;
  end;
end;

function TCPMFileEntry.GetUser: Byte;
begin
  Result := FUser;
end;

function TCPMFileEntry.GetOwnedBlocks: TBlockNumberArray;
begin
  Result := FFS.GetFileBlocks(FIndex);
end;

{ ── TDSKContainer ─────────────────────────────────────────────── }

procedure TDSKContainer.InvalidateMaps;
begin
  FBlockMapValid := False;
  FSectorMapValid := False;
end;

procedure TDSKContainer.RebuildCache;
var
  I, Off: Integer;
  TI: TTrackInfoBlock;
  BootBytes: Int64;
begin
  SetLength(FEntries, FFS.GetFileCount);
  for I := 0 to FFS.GetFileCount - 1 do
    FEntries[I] := TCPMFileEntry.Create(FFS, I);

  Off := FFS.GetDPB.OFF;
  if Off > 0 then
  begin
    BootBytes := 0;
    for I := 0 to Off - 1 do
    begin
      TI := FDisk.GetTrackInfo(I);
      BootBytes := BootBytes + TI.NumSectors * (128 shl TI.SectorSize);
    end;
    SetLength(FEntries, Length(FEntries) + 1);
    for I := High(FEntries) downto 1 do
      FEntries[I] := FEntries[I - 1];
    FEntries[0] := TBootEntry.Create(Off, BootBytes);
  end;
end;

constructor TDSKContainer.Create(const ADSKPath: string);
begin
  inherited Create;
  FPath := ExpandFileName(ADSKPath);
  FDisk := TDiskBenderDSK.Create(FPath);
  FDisk.Load;
  FFS := TDiskBenderCPM.Create(FDisk);
  FFS.ScanDirectory;
  RebuildCache;
end;

destructor TDSKContainer.Destroy;
begin
  FFS := nil;
  FDisk := nil;
  inherited Destroy;
end;

function TDSKContainer.GetName: string;
begin
  Result := ExtractFileName(FPath);
end;

function TDSKContainer.GetDisplayName: string;
begin
  Result := ExtractFileName(FPath);
end;

function TDSKContainer.GetEntryCount: Integer;
begin
  Result := Length(FEntries);
end;

function TDSKContainer.GetEntry(Index: Integer): IEntry;
begin
  if (Index >= 0) and (Index < Length(FEntries)) then
    Result := FEntries[Index]
  else
    Result := nil;
end;

function TDSKContainer.GetTitle: string;
begin
  Result := ExtractFileName(FPath);
end;

procedure TDSKContainer.Refresh;
begin
  FFS.ScanDirectory;
  RebuildCache;
  InvalidateMaps;
end;

function TDSKContainer.GetBlockMap: TBytes;
begin
  if not FBlockMapValid then
  begin
    FBlockMapCache := FFS.GetBlockMap;
    FBlockMapValid := True;
  end;
  Result := FBlockMapCache;
end;

function TDSKContainer.GetBlockCount: Integer;
begin
  { Populate cache if needed, then return length without a second computation. }
  if not FBlockMapValid then
  begin
    FBlockMapCache := FFS.GetBlockMap;
    FBlockMapValid := True;
  end;
  Result := Length(FBlockMapCache);
end;

function TDSKContainer.GetModified: Boolean;
begin
  Result := FDisk.Modified;
end;

procedure TDSKContainer.Save;
begin
  FDisk.Save;
  InvalidateMaps;
end;

procedure TDSKContainer.Revert;
begin
  FDisk.Revert;
  FFS.ScanDirectory;
  RebuildCache;
  InvalidateMaps;
end;

function TDSKContainer.Import(ASource: ICopySource; const AName: string): Boolean;
var
  MS: TMemoryStream;
  Parsed: TCPMFileName;
  Buf: TBytes;
begin
  Result := False;
  Parsed := TCPMFileName.Parse(AName);
  if not Parsed.IsValid then Exit;
  MS := TMemoryStream.Create;
  try
    ASource.CopyTo(MS);
    if MS.Size > 64 * 1024 then Exit;
    SetLength(Buf, MS.Size);
    if MS.Size > 0 then
      Move(MS.Memory^, Buf[0], MS.Size);
    Result := FFS.AddFile(Parsed.Name, Parsed.Ext, Buf, 0) >= 0;
    if Result then
    begin
      FFS.ScanDirectory;
      RebuildCache;
      InvalidateMaps;
    end;
  finally
    MS.Free;
  end;
end;

function MapSortField(AField: TSortField): TFileSortField;
begin
  case AField of
    sfName: Result := fsName;
    sfExtension: Result := fsExt;
    sfSize: Result := fsSize;
    sfUser: Result := fsUser;
  else
    Result := fsName;
  end;
end;

procedure TDSKContainer.Sort(AField: TSortField; Ascending: Boolean; DirsFirst: Boolean);
begin
  FFS.SortFiles(MapSortField(AField), Ascending);
  RebuildCache;
end;

function TDSKContainer.GetSummaryInfo: string;
begin
  Result := FFS.GetSummaryInfo;
end;

function TDSKContainer.GetLayoutInfo: TLayoutInfoArray;
var
  I: Integer;
  NumTracks: Byte;
begin
  NumTracks := FDisk.NumTracks;
  SetLength(Result, NumTracks);
  for I := 0 to NumTracks - 1 do
  begin
    Result[I].Kind := lkTrack;
    Result[I].Label_ := 'Track ' + IntToStr(I);
    Result[I].Offset := I;
    Result[I].Size := 0;
    Result[I].Extra := '';
  end;
end;

function TDSKContainer.GetSectorMap: TTrackColumnArray;
begin
  if FSectorMapValid then
  begin
    Result := FSectorMapCache;
    Exit;
  end;
  Result := ComputeSectorMap;
  FSectorMapCache := Result;
  FSectorMapValid := True;
end;

function TDSKContainer.ComputeSectorMap: TTrackColumnArray;
var
  I, J, K, L: Integer;
  DPB: TCPMDPB;
  TI: TTrackInfoBlock;
  Data: TBytes;
  AllFiller: Boolean;
  ReservedTracks, DirBlocks, DirSectors, PhysSectorSize: Integer;
  SortedIDs: TBytes;
  IsDir: array of Boolean;
begin
  DPB := FFS.GetDPB;
  ReservedTracks := DPB.OFF;

  DirBlocks := 0;
  for K := 0 to 7 do
  begin
    if (DPB.AL0 and ($80 shr K)) <> 0 then Inc(DirBlocks);
    if (DPB.AL1 and ($80 shr K)) <> 0 then Inc(DirBlocks);
  end;

  DirSectors := 0;
  if (ReservedTracks < FDisk.NumTracks) then
  begin
    TI := FDisk.GetTrackInfo(ReservedTracks);
    if TI.NumSectors > 0 then
    begin
      PhysSectorSize := 128 shl TI.SectorInfos[0].SectorSize;
      if PhysSectorSize > 0 then
        DirSectors := DirBlocks * (128 shl DPB.BSH) div PhysSectorSize;
    end;
  end;

  SetLength(Result, FDisk.NumTracks);

  for I := 0 to FDisk.NumTracks - 1 do
  begin
    TI := FDisk.GetTrackInfo(I);
    Result[I].TrackNum := TI.TrackNum;
    Result[I].SideNum := TI.SideNum;
    Result[I].FillerByte := TI.FillerByte;
    SetLength(Result[I].Sectors, TI.NumSectors);

    { Pre-compute which physical sector positions on this track host the
      CP/M-logical dir sectors 0..DirSectors-1. The CP/M view orders sectors
      by sorted SectorID; the physical layout on disk is skewed (e.g. CPC
      C1, C6, C2, C7, …). Without this translation we'd paint the wrong
      sectors yellow on every skewed disc. }
    SetLength(IsDir, TI.NumSectors);
    for J := 0 to TI.NumSectors - 1 do
      IsDir[J] := False;
    if (I = ReservedTracks) and (DirSectors > 0) and (TI.NumSectors > 0) then
    begin
      SortedIDs := FDisk.GetSortedSectorIDs(I);
      for L := 0 to DirSectors - 1 do
      begin
        if L >= TI.NumSectors then Break;
        for J := 0 to TI.NumSectors - 1 do
          if TI.SectorInfos[J].SectorID = SortedIDs[L] then
          begin
            IsDir[J] := True;
            Break;
          end;
      end;
    end;

    for J := 0 to TI.NumSectors - 1 do
    begin
      Result[I].Sectors[J].SectorID := TI.SectorInfos[J].SectorID;
      Result[I].Sectors[J].SizeBytes := 128 shl TI.SectorInfos[J].SectorSize;
      Result[I].Sectors[J].FDCSt1 := TI.SectorInfos[J].FDCStatus1;
      Result[I].Sectors[J].FDCSt2 := TI.SectorInfos[J].FDCStatus2;

      if (TI.SectorInfos[J].FDCStatus1 <> 0) or
         (TI.SectorInfos[J].FDCStatus2 <> 0) then
        Result[I].Sectors[J].State := ssFDCError
      else if I < ReservedTracks then
        Result[I].Sectors[J].State := ssBoot
      else
      begin
        Data := FDisk.GetSectorData(I, J);
        AllFiller := True;
        if Data <> nil then
          for K := 0 to Length(Data) - 1 do
            if Data[K] <> TI.FillerByte then
            begin AllFiller := False; Break; end;
        if AllFiller then
          Result[I].Sectors[J].State := ssEmpty
        else
          Result[I].Sectors[J].State := ssData;
      end;

      if IsDir[J] and (Result[I].Sectors[J].State <> ssFDCError) then
        Result[I].Sectors[J].State := ssSystem;
    end;
  end;
end;

function TDSKContainer.GetPath: string;
begin
  Result := FPath;
end;

{ ── TDSKFileEntry ─────────────────────────────────────────────── }

type
  TDSKFileEntry = class(TLocalFileEntry, IExpandable)
  public
    function Expand: IContainer;
  end;

function TDSKFileEntry.Expand: IContainer;
begin
  Result := TDSKContainer.Create(FullPath);
end;

function CreateDSKAwareEntry(const AFullPath: string): IEntry;
begin
  if LowerCase(ExtractFileExt(AFullPath)) = '.dsk' then
    Result := TDSKFileEntry.Create(AFullPath)
  else
    Result := nil;
end;

end.
