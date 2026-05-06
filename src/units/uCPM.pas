unit uCPM;

{$mode objfpc}{$H+}
{$packrecords 1}

interface

uses
  Classes, SysUtils, uDSK, uInterfaces, uCPMTypes, fgl;

type
  { CP/M Directory Entry (32 bytes) }
  TCPMDirEntry = packed record
    User: Byte;                         { 0-15 = User, 0xE5 = Deleted }
    Filename: array[0..7] of Char;
    Extension: array[0..2] of Char;
    ExtentLow: Byte;                    { Extent index }
    Reserved: Byte;
    ExtentHigh: Byte;
    RecordCount: Byte;                  { 0-128 (number of 128-byte records) }
    Allocations: array[0..15] of Byte;  { 16 blocks (8-bit) or 8 blocks (16-bit) }
  end;

  TCPMDirEntryPtr = ^TCPMDirEntry;

  { CP/M Disk Parameter Block (DPB) - defines geometry for a CP/M volume. }
  TCPMDPB = record
    SPT: Word;  { Sectors Per Track }
    BSH: Byte;  { Block Shift (3=1KB, 4=2KB, ...) }
    BLM: Byte;  { Block Mask (BSH=3 => BLM=7) }
    EXM: Byte;  { Extent Mask }
    DSM: Word;  { Total number of blocks - 1 }
    DRM: Word;  { Total number of directory entries - 1 }
    AL0: Byte;  { Allocation bits for directory }
    AL1: Byte;
    CKS: Word;  { Check sum size }
    OFF: Word;  { Track offset (reserved tracks) }
  end;

  { Location of a physical directory entry on disk. }
  TCPMEntryLoc = record
    Track: Byte;
    SectorIdx: Byte;
    EntryIdx: Byte;
  end;

  { Plain data class describing a CP/M file. Owned by TCPMFileList; the GUI
    sees it only through the IVirtualFile interface (via TCPMFileView). }
  TCPMFile = class
  strict private
    FUser: Byte;
    FName: string;
    FExt: string;
    FAttrs: TCPMAttrs;
    FTotalRecords: Integer;
    FSizeKB: Integer;
    FIsDeleted: Boolean;
    FEntries: array of TCPMEntryLoc;
  public
    constructor Create(AUser: Byte; const AName, AExt: string; AAttrs: TCPMAttrs);

    procedure AddEntry(ATrack, ASectorIdx, AEntryIdx: Byte);
    function GetEntry(Index: Integer): TCPMEntryLoc;
    function EntryCount: Integer;

    property User: Byte read FUser write FUser;
    property Name: string read FName write FName;
    property Extension: string read FExt write FExt;
    property Attrs: TCPMAttrs read FAttrs write FAttrs;
    property TotalRecords: Integer read FTotalRecords write FTotalRecords;
    property SizeKB: Integer read FSizeKB write FSizeKB;
    property IsDeleted: Boolean read FIsDeleted write FIsDeleted;
  end;

  TCPMFileList = specialize TFPGObjectList<TCPMFile>;

  { Lightweight interface proxy — constructed transiently by GetFile(Idx).
    Holds a reference to a TCPMFile that is owned elsewhere (by the list).
    Do not persist across a ScanDirectory call. }
  TCPMFileView = class(TInterfacedObject, IVirtualFile)
  strict private
    FFile: TCPMFile;
    function GetName: string;
    function GetExtension: string;
    function GetSizeKB: Integer;
    function GetIsDeleted: Boolean;
    function GetUser: Byte;
  public
    constructor Create(AFile: TCPMFile);
  end;

  { CP/M Filesystem implementation }
  TDiskBenderCPM = class(TInterfacedObject, IFilesystem)
  strict private
    FDisk: IVirtualDisk;
    FDPB: TCPMDPB;
    FFiles: TCPMFileList;

    function GetSectorByID(Track, SectorID: Byte): TBytes;
    function CleanString(const S: array of Char; Start, Count: Integer): string;
    function FindFreeDirEntry(out Track, SecIdx, EntryIdx: Integer): Boolean;
  public
    { IFilesystem }
    procedure ScanDirectory;
    function GetFileCount: Integer;
    function GetFile(Index: Integer): IVirtualFile;
    procedure GetFileContent(FileIdx: Integer; Stream: TStream);
    procedure ToggleDelete(FileIdx: Integer);
    procedure RenameFile(FileIdx: Integer; const NewName: string);
    procedure UndeleteFile(FileIdx: Integer; NewFirstChar: Char);
    function AddFile(const FileName, Ext: string; const Data: TBytes; User: Byte): Integer;
    procedure SortFiles(Field: TFileSortField; Ascending: Boolean);
    function GetBlockMap: TBytes;
    function GetSummaryInfo: string;

    constructor Create(ADisk: IVirtualDisk);
    destructor Destroy; override;

    procedure AutoDetectFormat;

    property DPB: TCPMDPB read FDPB write FDPB;
    property Files: TCPMFileList read FFiles;
  end;

const
  DPB_CPC_DATA: TCPMDPB = (
    SPT: 36; BSH: 3; BLM: 7; EXM: 0; DSM: 170; DRM: 63; AL0: $C0; AL1: $00; CKS: 16; OFF: 0
  );
  DPB_CPC_SYSTEM: TCPMDPB = (
    SPT: 36; BSH: 3; BLM: 7; EXM: 0; DSM: 170; DRM: 63; AL0: $C0; AL1: $00; CKS: 16; OFF: 2
  );

implementation

uses
  Math;

{ Sort comparators (TFPGObjectList<T>.Sort expects TFPGListCompareFunc) }

type
  TCPMFileCompareFunc = function(const A, B: TCPMFile): Integer;

  TSortState = record
    Field: TFileSortField;
    Asc: Boolean;
  end;

var
  { Module-global sort state. Only used while SortFiles() is executing.
    FPC's TFPGList.Sort takes a non-closure function pointer, so we cannot
    pass per-call state through the signature — hence this module scratchpad. }
  GSortState: TSortState;

function CompareCPMFiles(const A, B: TCPMFile): Integer;
begin
  case GSortState.Field of
    fsName:
      Result := AnsiCompareText(A.Name + A.Extension, B.Name + B.Extension);
    fsExt:
      begin
        Result := AnsiCompareText(A.Extension, B.Extension);
        if Result = 0 then Result := AnsiCompareText(A.Name, B.Name);
      end;
    fsSize:
      Result := A.SizeKB - B.SizeKB;
    fsUser:
      Result := Integer(A.User) - Integer(B.User);
  else
    Result := 0;
  end;
  if not GSortState.Asc then Result := -Result;
end;

{ TCPMFile }

constructor TCPMFile.Create(AUser: Byte; const AName, AExt: string; AAttrs: TCPMAttrs);
begin
  inherited Create;
  FUser := AUser;
  FName := AName;
  FExt := AExt;
  FAttrs := AAttrs;
  FTotalRecords := 0;
  FSizeKB := 0;
  FIsDeleted := (AUser = CPM_DELETED_USER);
end;

procedure TCPMFile.AddEntry(ATrack, ASectorIdx, AEntryIdx: Byte);
begin
  SetLength(FEntries, Length(FEntries) + 1);
  FEntries[High(FEntries)].Track     := ATrack;
  FEntries[High(FEntries)].SectorIdx := ASectorIdx;
  FEntries[High(FEntries)].EntryIdx  := AEntryIdx;
end;

function TCPMFile.GetEntry(Index: Integer): TCPMEntryLoc;
begin
  Result := FEntries[Index];
end;

function TCPMFile.EntryCount: Integer;
begin
  Result := Length(FEntries);
end;

{ TCPMFileView }

constructor TCPMFileView.Create(AFile: TCPMFile);
begin
  inherited Create;
  FFile := AFile;
end;

function TCPMFileView.GetName: string;       begin Result := FFile.Name; end;
function TCPMFileView.GetExtension: string;  begin Result := FFile.Extension; end;
function TCPMFileView.GetSizeKB: Integer;    begin Result := FFile.SizeKB; end;
function TCPMFileView.GetIsDeleted: Boolean; begin Result := FFile.IsDeleted; end;
function TCPMFileView.GetUser: Byte;         begin Result := FFile.User; end;

{ TDiskBenderCPM }

constructor TDiskBenderCPM.Create(ADisk: IVirtualDisk);
begin
  inherited Create;
  FDisk := ADisk;
  FDPB := DPB_CPC_SYSTEM;
  FFiles := TCPMFileList.Create(True); { OwnsObjects }
end;

destructor TDiskBenderCPM.Destroy;
begin
  FFiles.Free;
  inherited Destroy;
end;

function TDiskBenderCPM.GetFileCount: Integer;
begin
  Result := FFiles.Count;
end;

function TDiskBenderCPM.GetFile(Index: Integer): IVirtualFile;
begin
  if (Index < 0) or (Index >= FFiles.Count) then
    Result := nil
  else
    Result := TCPMFileView.Create(FFiles[Index]);
end;

function TDiskBenderCPM.GetSummaryInfo: string;
begin
  Result := Format('CP/M (OFF:%d, SPT:%d)', [FDPB.OFF, FDPB.SPT]);
end;

procedure TDiskBenderCPM.AutoDetectFormat;
var
  TI: TTrackInfoBlock;
  FirstID: Byte;
begin
  if FDisk = nil then Exit;
  TI := (FDisk as TDiskBenderDSK).GetTrackInfo(0);
  if TI.NumSectors = 0 then Exit;

  FirstID := TI.SectorInfos[0].SectorID;
  case FirstID of
    $01: FDPB := DPB_CPC_DATA;
    $41: FDPB := DPB_CPC_SYSTEM;
    $C1: FDPB := DPB_CPC_DATA;
  else
    FDPB := DPB_CPC_DATA;
  end;

  { IBM-compat 8-sector format override. }
  if (FirstID = $01) and (TI.NumSectors = 8) then
  begin
    FDPB.OFF := 1;
    FDPB.SPT := 32;
  end;
end;

function TDiskBenderCPM.CleanString(const S: array of Char; Start, Count: Integer): string;
var
  I: Integer;
  B: Byte;
begin
  Result := '';
  for I := Start to Start + Count - 1 do
  begin
    B := Byte(S[I]) and $7F;
    if (B >= 32) and (B <= 126) then
      Result := Result + Char(B)
    else
      Result := Result + '.';
  end;
  Result := Trim(Result);
end;

procedure TDiskBenderCPM.ScanDirectory;
var
  S, E, I: Integer;
  DirSector: TBytes;
  Entry: TCPMDirEntryPtr;
  FName, FExt: string;
  Attrs: TCPMAttrs;
  IsEmpty: Boolean;
  Found: Boolean;
  CFile: TCPMFile;
  BaseID: Byte;
  TI: TTrackInfoBlock;
begin
  FFiles.Clear;
  AutoDetectFormat;

  TI := (FDisk as TDiskBenderDSK).GetTrackInfo(FDPB.OFF);
  if TI.NumSectors = 0 then Exit;
  BaseID := TI.SectorInfos[0].SectorID;

  for S := 0 to (FDPB.DRM div (512 div 32)) do
  begin
    DirSector := GetSectorByID(FDPB.OFF, BaseID + S);
    if DirSector = nil then Continue;

    for E := 0 to (Length(DirSector) div 32) - 1 do
    begin
      Entry := TCPMDirEntryPtr(@DirSector[E * 32]);
      if (Entry^.User > CPM_MAX_USER) and (Entry^.User <> CPM_DELETED_USER) then Continue;

      { Skip truly empty entries (all bytes $E5 = unused slot) }
      if Entry^.User = CPM_DELETED_USER then
      begin
        IsEmpty := True;
        for I := 0 to 7 do
          if Byte(Entry^.Filename[I]) <> CPM_DELETED_USER then
          begin
            IsEmpty := False;
            Break;
          end;
        if IsEmpty then Continue;
      end;

      FName := CleanString(Entry^.Filename, 0, CPM_NAME_LEN);
      FExt  := CleanString(Entry^.Extension, 0, CPM_EXT_LEN);
      Attrs := DecodeCPMAttrs(Entry^.Extension);
      if (FName = '') or (FName = '........') or (FName = '.') then Continue;

      { Multiple extents of the same file share name+ext — merge record counts. }
      Found := False;
      for I := 0 to FFiles.Count - 1 do
      begin
        CFile := FFiles[I];
        if (CFile.User = Entry^.User) and (CFile.Name = FName) and (CFile.Extension = FExt) then
        begin
          CFile.TotalRecords := CFile.TotalRecords + Entry^.RecordCount;
          CFile.SizeKB := (CFile.TotalRecords + 7) div 8;
          CFile.AddEntry(FDPB.OFF, S, E);
          Found := True;
          Break;
        end;
      end;

      if not Found then
      begin
        CFile := TCPMFile.Create(Entry^.User, FName, FExt, Attrs);
        CFile.TotalRecords := Entry^.RecordCount;
        CFile.SizeKB := (CFile.TotalRecords + 7) div 8;
        CFile.AddEntry(FDPB.OFF, S, E);
        FFiles.Add(CFile);
      end;
    end;
  end;
end;

procedure TDiskBenderCPM.ToggleDelete(FileIdx: Integer);
var
  CFile: TCPMFile;
  I: Integer;
  SecData: TBytes;
  Entry: TCPMDirEntryPtr;
  NewUser: Byte;
  Loc: TCPMEntryLoc;
begin
  if (FileIdx < 0) or (FileIdx >= FFiles.Count) then Exit;
  CFile := FFiles[FileIdx];

  if CFile.IsDeleted then NewUser := 0 else NewUser := CPM_DELETED_USER;

  for I := 0 to CFile.EntryCount - 1 do
  begin
    Loc := CFile.GetEntry(I);
    SecData := FDisk.GetSectorData(Loc.Track, Loc.SectorIdx);
    if SecData <> nil then
    begin
      Entry := TCPMDirEntryPtr(@SecData[Loc.EntryIdx * 32]);
      Entry^.User := NewUser;
      FDisk.PutSectorData(Loc.Track, Loc.SectorIdx, SecData);
    end;
  end;
end;

procedure TDiskBenderCPM.GetFileContent(FileIdx: Integer; Stream: TStream);
var
  CFile: TCPMFile;
  DirSector: TBytes;
  Entry: TCPMDirEntryPtr;
  I, B, S: Integer;
  BlockIdx: Word;
  SectorsPerBlock: Integer;
  PhysTrack, PhysSecIdx: Integer;
  Data: TBytes;
  TotalRecsLeft: Integer;
  Loc: TCPMEntryLoc;
begin
  if (FileIdx < 0) or (FileIdx >= FFiles.Count) then Exit;
  CFile := FFiles[FileIdx];
  TotalRecsLeft := CFile.TotalRecords;

  SectorsPerBlock := (128 shl FDPB.BSH) div 512;

  for I := 0 to CFile.EntryCount - 1 do
  begin
    Loc := CFile.GetEntry(I);
    DirSector := FDisk.GetSectorData(Loc.Track, Loc.SectorIdx);
    if DirSector = nil then Continue;

    Entry := TCPMDirEntryPtr(@DirSector[Loc.EntryIdx * 32]);

    for B := 0 to 15 do
    begin
      BlockIdx := Entry^.Allocations[B];
      if BlockIdx = 0 then Continue;

      for S := 0 to SectorsPerBlock - 1 do
      begin
        PhysTrack  := FDPB.OFF + ((BlockIdx * SectorsPerBlock + S) div (FDPB.SPT div 4));
        PhysSecIdx := (BlockIdx * SectorsPerBlock + S) mod (FDPB.SPT div 4);

        Data := FDisk.GetSectorData(PhysTrack, PhysSecIdx);
        if Data <> nil then
        begin
          if TotalRecsLeft >= 4 then
          begin
            Stream.WriteBuffer(Data[0], 512);
            Dec(TotalRecsLeft, 4);
          end
          else if TotalRecsLeft > 0 then
          begin
            Stream.WriteBuffer(Data[0], TotalRecsLeft * 128);
            TotalRecsLeft := 0;
          end;
        end;
      end;
    end;
  end;
end;

function TDiskBenderCPM.GetBlockMap: TBytes;
var
  I, B, S, E: Integer;
  DirSector: TBytes;
  Entry: TCPMDirEntryPtr;
  BaseID: Byte;
  TI: TTrackInfoBlock;
  BlockIdx: Word;
  TotalBlocks: Integer;
begin
  TotalBlocks := FDPB.DSM + 1;
  SetLength(Result, TotalBlocks);
  FillChar(Result[0], TotalBlocks, 0);

  for I := 0 to 7 do if (FDPB.AL0 and ($80 shr I)) <> 0 then Result[I]   := 1;
  for I := 0 to 7 do if (FDPB.AL1 and ($80 shr I)) <> 0 then Result[I+8] := 1;

  TI := (FDisk as TDiskBenderDSK).GetTrackInfo(FDPB.OFF);
  if TI.NumSectors > 0 then
  begin
    BaseID := TI.SectorInfos[0].SectorID;
    for S := 0 to (FDPB.DRM div (512 div 32)) do
    begin
      DirSector := GetSectorByID(FDPB.OFF, BaseID + S);
      if DirSector = nil then Continue;
      for E := 0 to (Length(DirSector) div 32) - 1 do
      begin
        Entry := TCPMDirEntryPtr(@DirSector[E * 32]);
        if (Entry^.User <= CPM_MAX_USER) then
        begin
          for B := 0 to 15 do
          begin
            BlockIdx := Entry^.Allocations[B];
            if (BlockIdx > 0) and (BlockIdx < TotalBlocks) then
              Result[BlockIdx] := 2;
          end;
        end
        else if (Entry^.User = CPM_DELETED_USER) then
        begin
          for B := 0 to 15 do
          begin
            BlockIdx := Entry^.Allocations[B];
            if (BlockIdx > 0) and (BlockIdx < TotalBlocks) and (Result[BlockIdx] = 0) then
              Result[BlockIdx] := 3;
          end;
        end;
      end;
    end;
  end;
end;

function TDiskBenderCPM.GetSectorByID(Track, SectorID: Byte): TBytes;
var
  TI: TTrackInfoBlock;
  S: Integer;
begin
  Result := nil;
  TI := (FDisk as TDiskBenderDSK).GetTrackInfo(Track);
  for S := 0 to TI.NumSectors - 1 do
  begin
    if TI.SectorInfos[S].SectorID = SectorID then
    begin
      Result := FDisk.GetSectorData(Track, S);
      Exit;
    end;
  end;
end;

procedure TDiskBenderCPM.RenameFile(FileIdx: Integer; const NewName: string);
var
  CFile: TCPMFile;
  I: Integer;
  SecData: TBytes;
  Entry: TCPMDirEntryPtr;
  Loc: TCPMEntryLoc;
  Parsed: TCPMFileName;
  NameBuf: string;
  ExtBuf: string;
begin
  if (FileIdx < 0) or (FileIdx >= FFiles.Count) then Exit;
  CFile := FFiles[FileIdx];

  Parsed := TCPMFileName.Parse(NewName);
  if not Parsed.IsValid then
    raise Exception.CreateFmt('Invalid CP/M filename: %s', [NewName]);

  NameBuf := Parsed.PaddedName;
  ExtBuf  := Parsed.PaddedExt;

  for I := 0 to CFile.EntryCount - 1 do
  begin
    Loc := CFile.GetEntry(I);
    SecData := FDisk.GetSectorData(Loc.Track, Loc.SectorIdx);
    if SecData <> nil then
    begin
      Entry := TCPMDirEntryPtr(@SecData[Loc.EntryIdx * 32]);
      Move(NameBuf[1], Entry^.Filename, CPM_NAME_LEN);
      Move(ExtBuf[1],  Entry^.Extension, CPM_EXT_LEN);
      FDisk.PutSectorData(Loc.Track, Loc.SectorIdx, SecData);
    end;
  end;

  { Keep the in-memory model in sync. }
  CFile.Name := Parsed.Name;
  CFile.Extension := Parsed.Ext;
end;

procedure TDiskBenderCPM.UndeleteFile(FileIdx: Integer; NewFirstChar: Char);
var
  CFile: TCPMFile;
  I: Integer;
  SecData: TBytes;
  Entry: TCPMDirEntryPtr;
  Loc: TCPMEntryLoc;
begin
  if (FileIdx < 0) or (FileIdx >= FFiles.Count) then Exit;
  if not IsValidCPMChar(Byte(NewFirstChar)) then
    raise Exception.CreateFmt('Invalid CP/M filename character: %s', [NewFirstChar]);

  CFile := FFiles[FileIdx];

  for I := 0 to CFile.EntryCount - 1 do
  begin
    Loc := CFile.GetEntry(I);
    SecData := FDisk.GetSectorData(Loc.Track, Loc.SectorIdx);
    if SecData <> nil then
    begin
      Entry := TCPMDirEntryPtr(@SecData[Loc.EntryIdx * 32]);
      if Entry^.User = CPM_DELETED_USER then
        Entry^.User := 0;
      Entry^.Filename[0] := NewFirstChar;
      FDisk.PutSectorData(Loc.Track, Loc.SectorIdx, SecData);
    end;
  end;

  CFile.User := 0;
  CFile.IsDeleted := False;
  if Length(CFile.Name) > 0 then
    CFile.Name := NewFirstChar + Copy(CFile.Name, 2, MaxInt)
  else
    CFile.Name := NewFirstChar;
end;

function TDiskBenderCPM.FindFreeDirEntry(out Track, SecIdx, EntryIdx: Integer): Boolean;
var
  T, S, I: Integer;
  SecData: TBytes;
  Entry: TCPMDirEntryPtr;
begin
  Result := False;
  for T := 0 to FDPB.OFF - 1 do
  begin
    for S := 0 to (FDPB.SPT div 4) - 1 do
    begin
      SecData := FDisk.GetSectorData(T, S);
      if SecData = nil then Continue;
      for I := 0 to 15 do
      begin
        Entry := TCPMDirEntryPtr(@SecData[I * 32]);
        if (Entry^.User = 0) or (Entry^.User = CPM_DELETED_USER) then
        begin
          { Must also have filename slot looking empty. }
          if (Byte(Entry^.Filename[0]) = 0) or (Byte(Entry^.Filename[0]) = CPM_DELETED_USER) then
          begin
            Track := T; SecIdx := S; EntryIdx := I;
            Exit(True);
          end;
        end;
      end;
    end;
  end;
end;

function TDiskBenderCPM.AddFile(const FileName, Ext: string; const Data: TBytes; User: Byte): Integer;
var
  SecData: TBytes;
  Entry: TCPMDirEntryPtr;
  Track, SecIdx, EntryIdx: Integer;
  Parsed: TCPMFileName;
  NameBuf, ExtBuf: string;
  SizeRecords: Word;
begin
  Result := -1;

  Parsed := TCPMFileName.Parse(FileName + '.' + Ext);
  if not Parsed.IsValid then Exit;

  if not FindFreeDirEntry(Track, SecIdx, EntryIdx) then Exit;

  SecData := FDisk.GetSectorData(Track, SecIdx);
  if SecData = nil then Exit;

  SizeRecords := (Length(Data) + 127) div 128;
  NameBuf := Parsed.PaddedName;
  ExtBuf  := Parsed.PaddedExt;

  Entry := TCPMDirEntryPtr(@SecData[EntryIdx * 32]);
  FillChar(Entry^, 32, 0);
  Move(NameBuf[1], Entry^.Filename, CPM_NAME_LEN);
  Move(ExtBuf[1],  Entry^.Extension, CPM_EXT_LEN);
  Entry^.User := User;
  Entry^.RecordCount := SizeRecords;

  FDisk.PutSectorData(Track, SecIdx, SecData);

  { Insert into the in-memory model so callers don't need a full rescan. }
  FFiles.Add(TCPMFile.Create(User, Parsed.Name, Parsed.Ext, []));
  FFiles[FFiles.Count - 1].TotalRecords := SizeRecords;
  FFiles[FFiles.Count - 1].SizeKB := (SizeRecords + 7) div 8;
  FFiles[FFiles.Count - 1].AddEntry(Track, SecIdx, EntryIdx);
  Result := FFiles.Count - 1;
end;

procedure TDiskBenderCPM.SortFiles(Field: TFileSortField; Ascending: Boolean);
begin
  GSortState.Field := Field;
  GSortState.Asc := Ascending;
  FFiles.Sort(@CompareCPMFiles);
end;

end.
