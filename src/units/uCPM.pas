unit uCPM;

{$mode objfpc}{$H+}
{$packrecords 1}

interface

uses
  Classes, SysUtils, uInterfaces, uCPMTypes, uVFS, fgl;

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

  { CP/M Disk Parameter Block (DPB) - defines geometry for a CP/M volume.
    The structural definition is shared with uInterfaces (TCPMDPB there);
    this is the same record — they are assignment-compatible in FPC because
    the field layout is identical. }
  TCPMDPB = uInterfaces.TCPMDPB;

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

    { Map a CP/M-logical sector index (0..NumSectors-1) at a given track to
      the physical SectorID on disk. CP/M expects sector access in sorted
      sector-ID order; the DSK stores sectors in skewed physical order, so
      we must sort the track's IDs. Wraps for sub-functions below. }
    function LogicalSectorID(Track, LogicalIdx: Integer): Integer;
    function ReadLogicalSector(Track, LogicalIdx: Integer): TBytes;
    procedure WriteLogicalSector(Track, LogicalIdx: Integer; const Data: TBytes);

    { Block allocation width — derived from DPB.DSM. Volumes with > 255
      blocks need 16-bit pointers (8 entries × 2 bytes per dir entry); else
      8-bit (16 entries × 1 byte). }
    function Is16BitAlloc: Boolean; inline;
    function BlocksPerExtent: Integer; inline;
    function GetAllocBlock(Entry: TCPMDirEntryPtr; SlotIdx: Integer): Word;
    procedure SetAllocBlock(Entry: TCPMDirEntryPtr; SlotIdx: Integer; BlockIdx: Word);
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
    function GetDPB: TCPMDPB;
    procedure SetDPB(const Value: TCPMDPB);
    function GetFileEntryCount(FileIdx: Integer): Integer;
    function GetFileEntryLoc(FileIdx, LocIdx: Integer;
                              out ATrack, ASectorIdx, AEntryIdx: Byte): Boolean;
    function GetFileBlocks(FileIdx: Integer): TBlockNumberArray;
    function GetFileSectors(FileIdx: Integer): TPhysicalSectorArray;

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
  TI:          TTrackInfoBlock;
  FirstID:     Byte;
  ProbeSec:    TBytes;
  ProbeOff:    Integer;
  ValidCount:  Integer;
  TotalEntries: Integer;
  E:           Integer;
  UserByte:    Byte;
begin
  if FDisk = nil then Exit;
  TI := FDisk.GetTrackInfo(0);
  if TI.NumSectors = 0 then Exit;

  FirstID := TI.SectorInfos[0].SectorID;
  case FirstID of
    { IBM-compatible and CP/M Plus boot disks both use sector IDs $01–$09.
      Default to OFF=0 (IBM directory at track 0); the probe below adjusts
      OFF if the directory turns out to be on a later track (CP/M Plus). }
    $01: FDPB := DPB_CPC_DATA;
    { CP/M 2.2 SYSTEM format: sector IDs $41–$49, two reserved boot tracks
      (OFF=2).  AMSDOS recognises this as a "system disc" and |CPM boots it. }
    $41: FDPB := DPB_CPC_SYSTEM;
    { Standard CPC DATA format: sector IDs $C1–$C9 (AMSDOS games and user
      files).  This is the format AMSDOS uses for its own filesystem, with
      the directory at track 0 (OFF=0).  No boot sector descriptor. }
    $C1: FDPB := DPB_CPC_DATA;
  else
    FDPB := DPB_CPC_DATA;
  end;

  { True IBM 8-sector format: $01-based IDs with exactly 8 sectors/track. }
  if (FirstID = $01) and (TI.NumSectors = 8) then
  begin
    FDPB.OFF := 1;
    FDPB.SPT := 32;
  end;

  { For 9-sector $01-based disks the sector-ID lookup defaults to OFF=0
    (IBM-style directory at track 0).  CP/M Plus boot disks also use
    $01-based IDs but reserve one or more tracks for bootstrap code and
    place the directory at a higher track.  Validate the candidate OFF
    track by sampling its first sector and counting entries with valid
    user bytes (0..CPM_MAX_USER or CPM_DELETED_USER).  Machine code
    scores ~6 % valid by chance; a real directory scores 100 %.  If
    fewer than 3/4 qualify, advance OFF and retry — up to two extra
    tracks.  Note: TryGetDirEntry is defined after this function; bounds
    are checked inline via SizeOf(TCPMDirEntry) rather than calling it. }
  if (FirstID = $01) and (TI.NumSectors <> 8) then
  begin
    for ProbeOff := FDPB.OFF to FDPB.OFF + 2 do
    begin
      if ProbeOff >= FDisk.NumTracks then Break;
      ProbeSec := ReadLogicalSector(ProbeOff, 0);
      if ProbeSec = nil then Continue;
      ValidCount    := 0;
      TotalEntries  := 0;
      E := 0;
      while (E + 1) * SizeOf(TCPMDirEntry) <= Length(ProbeSec) do
      begin
        UserByte := ProbeSec[E * SizeOf(TCPMDirEntry)];
        Inc(TotalEntries);
        if (UserByte <= CPM_MAX_USER) or (UserByte = CPM_DELETED_USER) then
          Inc(ValidCount);
        Inc(E);
      end;
      { Accept this track as the directory if ≥ 75 % of entry slots have
        a plausible user byte. }
      if (TotalEntries > 0) and (ValidCount * 4 >= TotalEntries * 3) then
      begin
        FDPB.OFF := ProbeOff;
        Break;
      end;
    end;
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

{ Bounds-checked accessor for the (Idx*32)-th 32-byte directory entry inside
  a sector buffer. Returns False if the buffer is too short to safely
  dereference. Centralises the guard against Discology-style copy-protected
  discs where the track's nominal sector size (used to compute EntriesPerSec)
  exceeds the actual sector data length — without this, @Buf[Idx*32] walks
  past the buffer end and reads (or, far worse, writes) adjacent heap
  memory. Every directory-buffer dereference in this unit MUST go through
  this helper. See the Face 2A nondeterminism investigation for context. }
function TryGetDirEntry(const Buf: TBytes; Idx: Integer; out Entry: TCPMDirEntryPtr): Boolean;
begin
  Entry := nil;
  if Idx < 0 then Exit(False);
  if (Idx + 1) * SizeOf(TCPMDirEntry) > Length(Buf) then Exit(False);
  Entry := TCPMDirEntryPtr(@Buf[Idx * SizeOf(TCPMDirEntry)]);
  Result := True;
end;

procedure TDiskBenderCPM.ScanDirectory;
var
  S, E, I, CurTrack, SecsConsumed: Integer;
  DirSector: TBytes;
  Entry: TCPMDirEntryPtr;
  FName, FExt: string;
  Attrs: TCPMAttrs;
  IsEmpty, IsAllSpace: Boolean;
  Found: Boolean;
  CFile: TCPMFile;
  TI: TTrackInfoBlock;
  SectorSize, EntriesPerSec, TotalDirSecs: Integer;
  GuardCount: Integer;   { sequential index for GUARD entries, makes names unique }
begin
  FFiles.Clear;
  AutoDetectFormat;
  GuardCount := 0;

  CurTrack := FDPB.OFF;
  TI := FDisk.GetTrackInfo(CurTrack);
  if TI.NumSectors = 0 then Exit;
  SectorSize := 128 shl TI.SectorSize;
  if SectorSize <= 0 then Exit;
  EntriesPerSec := SectorSize div SizeOf(TCPMDirEntry);
  if EntriesPerSec <= 0 then Exit;
  TotalDirSecs := ((FDPB.DRM + 1) + EntriesPerSec - 1) div EntriesPerSec;

  S := 0;
  SecsConsumed := 0;
  while SecsConsumed < TotalDirSecs do
  begin
    if S >= TI.NumSectors then
    begin
      Inc(CurTrack);
      TI := FDisk.GetTrackInfo(CurTrack);
      if TI.NumSectors = 0 then Exit;
      S := 0;
    end;
    { S is a CP/M-logical sector index (sorted-by-SectorID position).
      ReadLogicalSector handles the skew translation to physical. }
    DirSector := ReadLogicalSector(CurTrack, S);
    if DirSector = nil then
    begin
      Inc(S);
      Inc(SecsConsumed);
      Continue;
    end;

    for E := 0 to EntriesPerSec - 1 do
    begin
      { TryGetDirEntry is the one-and-only safe way to dereference a 32-byte
        directory entry — see its declaration for the Discology rationale.
        Break (not Continue) because once a buffer is too short for index E,
        every higher E is also out of bounds. }
      if not TryGetDirEntry(DirSector, E, Entry) then Break;
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
      if FName = '' then
      begin
        IsAllSpace := True;
        for I := 0 to CPM_NAME_LEN - 1 do
          if (Byte(Entry^.Filename[I]) and $7F) <> $20 then
          begin IsAllSpace := False; Break; end;
        if not IsAllSpace then Continue;
        { [GUARD#nn] in square brackets; directories use <..> here, so the
          two bracket styles stay visually distinct. }
        FName := Format('[GUARD#%.2d]', [GuardCount]);   { %.Nd = zero-padded to N digits }
        Inc(GuardCount);
      end
      else if (FName = '........') or (FName = '.') then Continue;

      { Multiple extents of the same file share name+ext — merge record counts. }
      Found := False;
      for I := 0 to FFiles.Count - 1 do
      begin
        CFile := FFiles[I];
        if (CFile.User = Entry^.User) and (CFile.Name = FName) and (CFile.Extension = FExt) then
        begin
          CFile.TotalRecords := CFile.TotalRecords + Entry^.RecordCount;
          CFile.SizeKB := (CFile.TotalRecords + 7) div 8;
          CFile.AddEntry(CurTrack, S, E);
          Found := True;
          Break;
        end;
      end;

      if not Found then
      begin
        CFile := TCPMFile.Create(Entry^.User, FName, FExt, Attrs);
        CFile.TotalRecords := Entry^.RecordCount;
        CFile.SizeKB := (CFile.TotalRecords + 7) div 8;
        CFile.AddEntry(CurTrack, S, E);
        FFiles.Add(CFile);
      end;
    end;
    Inc(S);
    Inc(SecsConsumed);
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
    SecData := ReadLogicalSector(Loc.Track, Loc.SectorIdx);
    if SecData <> nil then
    begin
      if not TryGetDirEntry(SecData, Loc.EntryIdx, Entry) then Continue;
      Entry^.User := NewUser;
      WriteLogicalSector(Loc.Track, Loc.SectorIdx, SecData);
    end;
  end;
end;

procedure TDiskBenderCPM.GetFileContent(FileIdx: Integer; Stream: TStream);
var
  CFile: TCPMFile;
  DirSector, Data: TBytes;
  Entry: TCPMDirEntryPtr;
  I, B, S: Integer;
  BlockIdx: Word;
  TI: TTrackInfoBlock;
  SectorSize, SectorsPerBlock, PhysSPT, RecsPerSector: Integer;
  PhysTrack, PhysSecIdx: Integer;
  TotalRecsLeft, BytesToWrite: Integer;
  Loc: TCPMEntryLoc;
begin
  if (FileIdx < 0) or (FileIdx >= FFiles.Count) then Exit;
  CFile := FFiles[FileIdx];
  TotalRecsLeft := CFile.TotalRecords;

  { Derive all geometry from the actual track info, not from constants.
    Sample track FDPB.OFF since that's where data sectors start; we assume
    uniform geometry across data tracks (which is true for CPC + PCW). }
  TI := FDisk.GetTrackInfo(FDPB.OFF);
  if TI.NumSectors = 0 then Exit;
  SectorSize := 128 shl TI.SectorSize;
  if SectorSize <= 0 then Exit;
  SectorsPerBlock := (128 shl FDPB.BSH) div SectorSize;
  if SectorsPerBlock <= 0 then SectorsPerBlock := 1;
  PhysSPT := TI.NumSectors;
  RecsPerSector := SectorSize div 128;

  for I := 0 to CFile.EntryCount - 1 do
  begin
    Loc := CFile.GetEntry(I);
    DirSector := ReadLogicalSector(Loc.Track, Loc.SectorIdx);
    if DirSector = nil then Continue;

    if not TryGetDirEntry(DirSector, Loc.EntryIdx, Entry) then Continue;

    for B := 0 to BlocksPerExtent - 1 do
    begin
      BlockIdx := GetAllocBlock(Entry, B);
      if BlockIdx = 0 then Continue;

      for S := 0 to SectorsPerBlock - 1 do
      begin
        PhysTrack  := FDPB.OFF + ((BlockIdx * SectorsPerBlock + S) div PhysSPT);
        PhysSecIdx := (BlockIdx * SectorsPerBlock + S) mod PhysSPT;

        Data := ReadLogicalSector(PhysTrack, PhysSecIdx);
        if Data <> nil then
        begin
          if TotalRecsLeft >= RecsPerSector then
          begin
            Stream.WriteBuffer(Data[0], SectorSize);
            Dec(TotalRecsLeft, RecsPerSector);
          end
          else if TotalRecsLeft > 0 then
          begin
            BytesToWrite := TotalRecsLeft * 128;
            if BytesToWrite > Length(Data) then BytesToWrite := Length(Data);
            Stream.WriteBuffer(Data[0], BytesToWrite);
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
  TI: TTrackInfoBlock;
  BlockIdx: Word;
  TotalBlocks, SectorSize, EntriesPerSec, TotalDirSecs, SecsConsumed: Integer;
  CurTrack: Integer;
begin
  TotalBlocks := FDPB.DSM + 1;
  SetLength(Result, TotalBlocks);
  FillChar(Result[0], TotalBlocks, 0);

  for I := 0 to 7 do if (FDPB.AL0 and ($80 shr I)) <> 0 then Result[I]   := 1;
  for I := 0 to 7 do if (FDPB.AL1 and ($80 shr I)) <> 0 then Result[I+8] := 1;

  CurTrack := FDPB.OFF;
  TI := FDisk.GetTrackInfo(CurTrack);
  if TI.NumSectors = 0 then Exit;

  SectorSize := 128 shl TI.SectorSize;
  if SectorSize <= 0 then Exit;
  EntriesPerSec := SectorSize div SizeOf(TCPMDirEntry);
  if EntriesPerSec <= 0 then Exit;
  TotalDirSecs := ((FDPB.DRM + 1) + EntriesPerSec - 1) div EntriesPerSec;

  { Walk the directory in CP/M-logical sector order, wrapping to the next
    track when necessary. Mirrors FindFreeDirEntry's traversal so non-CPC
    formats with multi-track directories (e.g. PCW B-format) get accurate
    maps. }
  S := 0;
  SecsConsumed := 0;
  while SecsConsumed < TotalDirSecs do
  begin
    if S >= TI.NumSectors then
    begin
      Inc(CurTrack);
      TI := FDisk.GetTrackInfo(CurTrack);
      if TI.NumSectors = 0 then Exit;
      S := 0;
    end;
    DirSector := ReadLogicalSector(CurTrack, S);
    if DirSector <> nil then
    begin
      for E := 0 to EntriesPerSec - 1 do
      begin
        { TryGetDirEntry is the bounds-checked accessor — see its declaration. }
        if not TryGetDirEntry(DirSector, E, Entry) then Break;
        if (Entry^.User <= CPM_MAX_USER) then
        begin
          { Anonymous (all-space-name) dir entries are real allocations on
            copy-protected discs (the "GUARD" trick). Trust their
            Allocations bytes — the block map must tell the truth, even
            if that prevents AddFile from finding free space.
            This is the deliberate decision recorded in DiskBender-jv1
            (the issue's close-reason predates the reversal). }
          for B := 0 to BlocksPerExtent - 1 do
          begin
            BlockIdx := GetAllocBlock(Entry, B);
            if (BlockIdx > 0) and (BlockIdx < TotalBlocks) then
              Result[BlockIdx] := 2;
          end;
        end
        else if (Entry^.User = CPM_DELETED_USER) then
        begin
          for B := 0 to BlocksPerExtent - 1 do
          begin
            BlockIdx := GetAllocBlock(Entry, B);
            if (BlockIdx > 0) and (BlockIdx < TotalBlocks) and (Result[BlockIdx] = 0) then
              Result[BlockIdx] := 3;
          end;
        end;
      end;
    end;
    Inc(S);
    Inc(SecsConsumed);
  end;
end;

function TDiskBenderCPM.GetSectorByID(Track, SectorID: Byte): TBytes;
{ Map a CP/M sector ID to physical sector data on the given track.

  Contract on duplicate IDs: when a track has multiple physical sectors
  sharing the same SectorID (the Discology copy-protection "twin sector"
  trick), this function returns the FIRST match by physical index. This
  is the correct behaviour for CP/M filesystem operations — CP/M itself
  only ever sees one sector per ID, and the protected twin is invisible
  to a normal CP/M loader by design.

  Callers that need to access duplicate-ID twins explicitly (e.g. a hex
  viewer, copy-protection analyzer) must not use this function — they
  should index by physical position via FDisk.GetTrackInfo +
  FDisk.GetSectorData(Track, S) directly. The current callers
  (LogicalSectorID / ReadLogicalSector / WriteLogicalSector) all operate
  in CP/M's worldview, so first-match-wins is the right contract for
  them. See DiskBender-9zn. }
var
  TI: TTrackInfoBlock;
  S: Integer;
begin
  Result := nil;
  TI := FDisk.GetTrackInfo(Track);
  for S := 0 to TI.NumSectors - 1 do
  begin
    if TI.SectorInfos[S].SectorID = SectorID then
    begin
      Result := FDisk.GetSectorData(Track, S);
      Exit;
    end;
  end;
end;

function TDiskBenderCPM.LogicalSectorID(Track, LogicalIdx: Integer): Integer;
var
  TI: TTrackInfoBlock;
  SortedIDs: TBytes;
begin
  Result := -1;
  TI := FDisk.GetTrackInfo(Track);
  if (LogicalIdx < 0) or (LogicalIdx >= TI.NumSectors) then Exit;
  { Delegate sorting to the disk object which caches the result per track. }
  SortedIDs := FDisk.GetSortedSectorIDs(Track);
  if (SortedIDs = nil) or (LogicalIdx >= Length(SortedIDs)) then Exit;
  Result := SortedIDs[LogicalIdx];
end;

function TDiskBenderCPM.ReadLogicalSector(Track, LogicalIdx: Integer): TBytes;
var
  ID: Integer;
begin
  Result := nil;
  ID := LogicalSectorID(Track, LogicalIdx);
  if ID < 0 then Exit;
  Result := GetSectorByID(Track, Byte(ID));
end;

procedure TDiskBenderCPM.WriteLogicalSector(Track, LogicalIdx: Integer; const Data: TBytes);
var
  TI: TTrackInfoBlock;
  ID, S: Integer;
begin
  ID := LogicalSectorID(Track, LogicalIdx);
  if ID < 0 then Exit;
  TI := FDisk.GetTrackInfo(Track);
  for S := 0 to TI.NumSectors - 1 do
    if TI.SectorInfos[S].SectorID = ID then
    begin
      FDisk.PutSectorData(Track, S, Data);
      Exit;
    end;
end;

function TDiskBenderCPM.Is16BitAlloc: Boolean;
begin
  Result := FDPB.DSM > 255;
end;

function TDiskBenderCPM.BlocksPerExtent: Integer;
begin
  if Is16BitAlloc then Result := 8 else Result := 16;
end;

function TDiskBenderCPM.GetAllocBlock(Entry: TCPMDirEntryPtr; SlotIdx: Integer): Word;
begin
  if Is16BitAlloc then
    Result := Entry^.Allocations[SlotIdx * 2] or
              (Word(Entry^.Allocations[SlotIdx * 2 + 1]) shl 8)
  else
    Result := Entry^.Allocations[SlotIdx];
end;

procedure TDiskBenderCPM.SetAllocBlock(Entry: TCPMDirEntryPtr; SlotIdx: Integer; BlockIdx: Word);
begin
  if Is16BitAlloc then
  begin
    Entry^.Allocations[SlotIdx * 2]     := Byte(BlockIdx and $FF);
    Entry^.Allocations[SlotIdx * 2 + 1] := Byte((BlockIdx shr 8) and $FF);
  end
  else
    Entry^.Allocations[SlotIdx] := Byte(BlockIdx);
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
    SecData := ReadLogicalSector(Loc.Track, Loc.SectorIdx);
    if SecData <> nil then
    begin
      if not TryGetDirEntry(SecData, Loc.EntryIdx, Entry) then Continue;
      Move(NameBuf[1], Entry^.Filename, CPM_NAME_LEN);
      Move(ExtBuf[1],  Entry^.Extension, CPM_EXT_LEN);
      WriteLogicalSector(Loc.Track, Loc.SectorIdx, SecData);
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
    SecData := ReadLogicalSector(Loc.Track, Loc.SectorIdx);
    if SecData <> nil then
    begin
      if not TryGetDirEntry(SecData, Loc.EntryIdx, Entry) then Continue;
      if Entry^.User = CPM_DELETED_USER then
        Entry^.User := 0;
      Entry^.Filename[0] := NewFirstChar;
      WriteLogicalSector(Loc.Track, Loc.SectorIdx, SecData);
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
  CurTrack, S, I: Integer;
  EntriesPerSec, TotalDirSecs, SectorSize, SecsConsumed: Integer;
  TI: TTrackInfoBlock;
  SecData: TBytes;
  Entry: TCPMDirEntryPtr;
begin
  { Locate a free directory slot. CP/M defines free as User = $E5; the
    filename bytes are NOT cleared by ToggleDelete, so we must not also
    require them to be $E5. Geometry comes from DPB + the actual track info,
    not from hardcoded constants — directories may use 256-byte sectors and
    span multiple tracks on non-CPC formats. }
  Result := False;
  CurTrack := FDPB.OFF;
  TI := FDisk.GetTrackInfo(CurTrack);
  if TI.NumSectors = 0 then Exit;

  SectorSize := 128 shl TI.SectorSize;
  if SectorSize <= 0 then Exit;
  EntriesPerSec := SectorSize div SizeOf(TCPMDirEntry);
  if EntriesPerSec <= 0 then Exit;
  TotalDirSecs := ((FDPB.DRM + 1) + EntriesPerSec - 1) div EntriesPerSec;

  S := 0;
  SecsConsumed := 0;
  while SecsConsumed < TotalDirSecs do
  begin
    if S >= TI.NumSectors then
    begin
      Inc(CurTrack);
      TI := FDisk.GetTrackInfo(CurTrack);
      if TI.NumSectors = 0 then Exit;
      S := 0;
    end;
    SecData := ReadLogicalSector(CurTrack, S);
    if SecData <> nil then
    begin
      for I := 0 to EntriesPerSec - 1 do
      begin
        { Bounds-checked accessor — see TryGetDirEntry declaration for
          rationale. Short sectors on Discology-style copy-protected discs
          would otherwise let us return a 'free slot' pointing past the
          buffer end, and a subsequent AddFile write would corrupt the heap. }
        if not TryGetDirEntry(SecData, I, Entry) then Break;
        if Entry^.User = CPM_DELETED_USER then
        begin
          Track := CurTrack;
          SecIdx := S;  { logical sector index — uniform across the layer }
          EntryIdx := I;
          Exit(True);
        end;
      end;
    end;
    Inc(S);
    Inc(SecsConsumed);
  end;
end;

function TDiskBenderCPM.AddFile(const FileName, Ext: string; const Data: TBytes; User: Byte): Integer;
const
  { One CP/M extent holds exactly 128 128-byte records = 16 KB.
    This is a fixed CP/M constant; it does NOT depend on EXM — EXM only
    controls how many extents share a single directory entry on very large
    volumes. DiskBender uses one directory entry per extent for simplicity,
    which is always correct (EXM=0 behaviour). }
  RECS_PER_EXTENT = 128;
var
  BlocksPerExt: Integer;
  Parsed: TCPMFileName;
  TI: TTrackInfoBlock;
  BlockSize, SectorSize, SectorsPerBlock, PhysSPT: Integer;
  BlockMap: TBytes;
  TotalBlocks, BlocksNeeded, ExtentsNeeded: Integer;
  FreeBlocks: array of Word;
  FoundFree, CursorBlock: Integer;
  FreeDirSlots, CheckTrack, CheckS, CheckI: Integer;
  CheckTI: TTrackInfoBlock;
  CheckSec: TBytes;
  CheckEntry: TCPMDirEntryPtr;
  CheckEntriesPerSec, CheckTotalDirSecs, CheckSecsConsumed, CheckSectorSize: Integer;
  B, I, S, BlockIdx: Integer;
  ByteOffset, BytesThisSector, BytesLeft: Integer;
  PhysTrack, PhysSecIdx: Integer;
  Sector, DirSec: TBytes;
  Track, SecIdx, EntryIdx: Integer;
  Entry: TCPMDirEntryPtr;
  TotalRecords, RecsLeft, ExtentIndex: Integer;
  RecsThisExtent, BlocksThisExtent: Integer;
  NewFile: TCPMFile;
  NameBuf, ExtBuf: string;
begin
  { Allocate blocks, write file content into them, then create one or more
    directory entries (one extent per 16 KB of data). Allocation width is
    chosen by DSM: 8-bit allocation (DSM<=255) packs 16 blocks per extent,
    16-bit (DSM>255) packs 8 Word entries into the same 16-byte field.
    Pre-validation ensures we have both enough free blocks AND enough free
    directory slots before writing anything — keeping the disk consistent
    even if we run out of space mid-write. }
  Result := -1;

  Parsed := TCPMFileName.Parse(FileName + '.' + Ext);
  if not Parsed.IsValid then Exit;

  TI := FDisk.GetTrackInfo(FDPB.OFF);
  if TI.NumSectors = 0 then Exit;
  SectorSize := 128 shl TI.SectorSize;
  if SectorSize <= 0 then Exit;
  BlockSize := 128 shl FDPB.BSH;
  if BlockSize <= 0 then Exit;
  SectorsPerBlock := BlockSize div SectorSize;
  if SectorsPerBlock <= 0 then SectorsPerBlock := 1;

  { Physical sectors per track come straight from the track info — TI.NumSectors
    is the authoritative source. The old 'FDPB.SPT div 4' shortcut assumed
    512-byte sectors and broke on 256-byte-sector formats. }
  PhysSPT := TI.NumSectors;
  if PhysSPT <= 0 then Exit;

  { Allocation width and entries-per-extent now derive from DSM. 8-bit
    formats (DSM <= 255) get 16 blocks/extent; 16-bit formats (DSM > 255)
    pack 8 Word entries into the same 16-byte Allocations array. }
  BlocksPerExt := BlocksPerExtent;

  if Length(Data) = 0 then
    BlocksNeeded := 0
  else
    BlocksNeeded := (Length(Data) + BlockSize - 1) div BlockSize;
  TotalRecords := (Length(Data) + 127) div 128;

  { Number of directory entries we will need: one per extent, minimum one. }
  if BlocksNeeded = 0 then
    ExtentsNeeded := 1
  else
    ExtentsNeeded := (BlocksNeeded + BlocksPerExt - 1) div BlocksPerExt;

  { Scan the block-allocation map for free blocks. GetBlockMap codes are
    0=free, 1=system, 2=live-file, 3=deleted-but-still-referenced. CP/M's
    deletion semantics retain the Allocations bytes — those blocks are
    available for reuse by new files (so we treat 3 as allocatable).
    NOTE: when reusing a code-3 block the deleted directory entry retains
    its Allocations pointer; a subsequent GetBlockMap call will re-code it
    as 2 (live-file) once this new file's entry is visible. The old entry
    remains harmless because ToggleDelete will restore User=$E5 on the slot
    and the slot will be reused on the next AddFile. }
  BlockMap := GetBlockMap;
  TotalBlocks := Length(BlockMap);
  SetLength(FreeBlocks, BlocksNeeded);
  FoundFree := 0;
  CursorBlock := 0;
  while (CursorBlock < TotalBlocks) and (FoundFree < BlocksNeeded) do
  begin
    if (BlockMap[CursorBlock] = 0) or (BlockMap[CursorBlock] = 3) then
    begin
      FreeBlocks[FoundFree] := CursorBlock;
      Inc(FoundFree);
    end;
    Inc(CursorBlock);
  end;
  if FoundFree < BlocksNeeded then Exit;   { disk full }

  { Pre-validate: count free directory slots. If there aren't enough for all
    extents we'd need, bail now before writing any block data. }
  CheckSectorSize := SectorSize;
  CheckEntriesPerSec := CheckSectorSize div SizeOf(TCPMDirEntry);
  if CheckEntriesPerSec <= 0 then Exit;
  CheckTotalDirSecs := ((FDPB.DRM + 1) + CheckEntriesPerSec - 1) div CheckEntriesPerSec;
  CheckTrack := FDPB.OFF;
  CheckTI := FDisk.GetTrackInfo(CheckTrack);
  if CheckTI.NumSectors = 0 then Exit;
  FreeDirSlots := 0;
  CheckS := 0;
  CheckSecsConsumed := 0;
  while CheckSecsConsumed < CheckTotalDirSecs do
  begin
    if CheckS >= CheckTI.NumSectors then
    begin
      Inc(CheckTrack);
      CheckTI := FDisk.GetTrackInfo(CheckTrack);
      if CheckTI.NumSectors = 0 then Break;
      CheckS := 0;
    end;
    CheckSec := ReadLogicalSector(CheckTrack, CheckS);
    if CheckSec <> nil then
      for CheckI := 0 to CheckEntriesPerSec - 1 do
      begin
        { Bounds-checked accessor — see TryGetDirEntry. A short sector here
          previously over-counted FreeDirSlots based on heap garbage, leading
          AddFile to believe it had space when FindFreeDirEntry would later
          fail (or worse, write past the buffer). }
        if not TryGetDirEntry(CheckSec, CheckI, CheckEntry) then Break;
        if CheckEntry^.User = CPM_DELETED_USER then
          Inc(FreeDirSlots);
      end;
    Inc(CheckS);
    Inc(CheckSecsConsumed);
  end;
  if FreeDirSlots < ExtentsNeeded then Exit;   { directory full }

  { Pre-validate: verify every target sector is readable before writing
    anything.  If any sector fails to read now, bail cleanly rather than
    leaving a partially written file on disk. }
  for B := 0 to BlocksNeeded - 1 do
    for S := 0 to SectorsPerBlock - 1 do
    begin
      PhysTrack  := FDPB.OFF + ((FreeBlocks[B] * SectorsPerBlock + S) div PhysSPT);
      PhysSecIdx := (FreeBlocks[B] * SectorsPerBlock + S) mod PhysSPT;
      if ReadLogicalSector(PhysTrack, PhysSecIdx) = nil then Exit;
    end;

  { Write file content into the allocated blocks. }
  ByteOffset := 0;
  BytesLeft := Length(Data);
  for B := 0 to BlocksNeeded - 1 do
  begin
    BlockIdx := FreeBlocks[B];
    for S := 0 to SectorsPerBlock - 1 do
    begin
      PhysTrack  := FDPB.OFF + ((BlockIdx * SectorsPerBlock + S) div PhysSPT);
      PhysSecIdx := (BlockIdx * SectorsPerBlock + S) mod PhysSPT;
      Sector := ReadLogicalSector(PhysTrack, PhysSecIdx);
      if Sector = nil then Exit;

      BytesThisSector := Length(Sector);
      if BytesThisSector > BytesLeft then BytesThisSector := BytesLeft;
      if BytesThisSector > 0 then
      begin
        Move(Data[ByteOffset], Sector[0], BytesThisSector);
        Inc(ByteOffset, BytesThisSector);
        Dec(BytesLeft, BytesThisSector);
      end;
      { Pad the tail of the last partial sector with $1A (CP/M EOF). Avoids
        leaking residual sector contents into the read of the final 128-byte
        record and matches CP/M's textual-file convention. }
      if BytesThisSector < Length(Sector) then
        FillChar(Sector[BytesThisSector], Length(Sector) - BytesThisSector, $1A);
      WriteLogicalSector(PhysTrack, PhysSecIdx, Sector);
      if BytesLeft <= 0 then Break;
    end;
    if BytesLeft <= 0 then Break;
  end;

  { Build directory entries — one extent per 16-block / 128-record chunk.
    The repeat..until form deliberately runs at least once so an empty
    Data still produces a single zero-block dir entry. }
  NewFile := TCPMFile.Create(User, Parsed.Name, Parsed.Ext, []);
  NewFile.TotalRecords := TotalRecords;
  NewFile.SizeKB := (TotalRecords + 7) div 8;

  NameBuf := Parsed.PaddedName;
  ExtBuf  := Parsed.PaddedExt;

  ExtentIndex := 0;
  RecsLeft := TotalRecords;
  B := 0;

  repeat
    if not FindFreeDirEntry(Track, SecIdx, EntryIdx) then
    begin
      NewFile.Free;
      Exit;
    end;
    DirSec := ReadLogicalSector(Track, SecIdx);
    if DirSec = nil then begin NewFile.Free; Exit; end;

    { Bounds check before the 32-byte FillChar — without this, a short
      sector returned by ReadLogicalSector (Discology-style malformed disc)
      would cause a 32-byte heap-corrupting write at the buffer tail.
      FindFreeDirEntry uses the same helper so the slot it returns should
      always pass this check; we re-verify here because the cost is one
      compare and the failure mode otherwise is heap corruption. }
    if not TryGetDirEntry(DirSec, EntryIdx, Entry) then
    begin NewFile.Free; Exit; end;
    FillChar(Entry^, SizeOf(TCPMDirEntry), 0);
    Move(NameBuf[1], Entry^.Filename, CPM_NAME_LEN);
    Move(ExtBuf[1],  Entry^.Extension, CPM_EXT_LEN);
    Entry^.User       := User;
    Entry^.ExtentLow  := ExtentIndex and $1F;
    Entry^.ExtentHigh := (ExtentIndex shr 5) and $3F;

    BlocksThisExtent := BlocksNeeded - B;
    if BlocksThisExtent > BlocksPerExt then
      BlocksThisExtent := BlocksPerExt;

    RecsThisExtent := RecsLeft;
    if RecsThisExtent > RECS_PER_EXTENT then
      RecsThisExtent := RECS_PER_EXTENT;
    { CP/M convention: full extents store RC=128 ($80); the final extent
      stores the remainder. RecsLeft <=0 falls through as RC=0 for empty files. }
    if RecsThisExtent >= 128 then
      Entry^.RecordCount := 128
    else if RecsThisExtent > 0 then
      Entry^.RecordCount := RecsThisExtent
    else
      Entry^.RecordCount := 0;

    for I := 0 to BlocksThisExtent - 1 do
      SetAllocBlock(Entry, I, FreeBlocks[B + I]);

    WriteLogicalSector(Track, SecIdx, DirSec);
    NewFile.AddEntry(Track, SecIdx, EntryIdx);

    Inc(B, BlocksThisExtent);
    Dec(RecsLeft, RecsThisExtent);
    Inc(ExtentIndex);
  until B >= BlocksNeeded;

  FFiles.Add(NewFile);
  Result := FFiles.Count - 1;
end;

procedure TDiskBenderCPM.SortFiles(Field: TFileSortField; Ascending: Boolean);
begin
  GSortState.Field := Field;
  GSortState.Asc := Ascending;
  FFiles.Sort(@CompareCPMFiles);
end;

function TDiskBenderCPM.GetDPB: TCPMDPB;
begin
  Result := FDPB;
end;

procedure TDiskBenderCPM.SetDPB(const Value: TCPMDPB);
begin
  FDPB := Value;
end;

function TDiskBenderCPM.GetFileBlocks(FileIdx: Integer): TBlockNumberArray;
var
  F: TCPMFile;
  Loc: TCPMEntryLoc;
  DirSec: TBytes;
  Entry: TCPMDirEntryPtr;
  I, B: Integer;
  BlockIdx, TotalBlocks: Word;
  Seen: array of Boolean;
  ResLen: Integer;
begin
  SetLength(Result, 0);
  if (FileIdx < 0) or (FileIdx >= FFiles.Count) then Exit;
  F := FFiles[FileIdx];
  if F = nil then Exit;

  TotalBlocks := FDPB.DSM + 1;
  SetLength(Seen, TotalBlocks);
  FillChar(Seen[0], TotalBlocks, 0);

  { Walk each directory extent the file owns; for each, pull its allocation
    slots and collect unique non-zero block numbers. Multiple extents share
    no blocks in valid CP/M directories, but we dedupe via Seen[] anyway
    to be defensive against malformed images. }
  for I := 0 to F.EntryCount - 1 do
  begin
    Loc := F.GetEntry(I);
    DirSec := ReadLogicalSector(Loc.Track, Loc.SectorIdx);
    if (DirSec = nil) or (Length(DirSec) < (Loc.EntryIdx + 1) * SizeOf(TCPMDirEntry)) then
      Continue;
    Entry := TCPMDirEntryPtr(@DirSec[Loc.EntryIdx * SizeOf(TCPMDirEntry)]);
    for B := 0 to BlocksPerExtent - 1 do
    begin
      BlockIdx := GetAllocBlock(Entry, B);
      if (BlockIdx = 0) or (BlockIdx >= TotalBlocks) then Continue;
      if Seen[BlockIdx] then Continue;
      Seen[BlockIdx] := True;
      ResLen := Length(Result);
      SetLength(Result, ResLen + 1);
      Result[ResLen] := BlockIdx;
    end;
  end;
end;

function TDiskBenderCPM.GetFileSectors(FileIdx: Integer): TPhysicalSectorArray;
var
  Blocks: TBlockNumberArray;
  TI: TTrackInfoBlock;
  SectorSize, SectorsPerBlock, PhysSPT: Integer;
  I, S, PhysTrack, PhysSecIdx, ResLen: Integer;
  BlockIdx: Word;
  SortedIDs: TBytes;
  Ref: TPhysicalSectorRef;
begin
  SetLength(Result, 0);
  Blocks := GetFileBlocks(FileIdx);
  if Length(Blocks) = 0 then Exit;

  { Same geometry derivation as GetFileContent at line ~470. Sample track
    OFF since data sectors start there and CPC/PCW have uniform geometry
    across data tracks. }
  TI := FDisk.GetTrackInfo(FDPB.OFF);
  if TI.NumSectors = 0 then Exit;
  SectorSize := 128 shl TI.SectorSize;
  if SectorSize <= 0 then Exit;
  SectorsPerBlock := (128 shl FDPB.BSH) div SectorSize;
  if SectorsPerBlock <= 0 then SectorsPerBlock := 1;
  PhysSPT := TI.NumSectors;

  for I := 0 to High(Blocks) do
  begin
    BlockIdx := Blocks[I];
    for S := 0 to SectorsPerBlock - 1 do
    begin
      PhysTrack  := FDPB.OFF + ((BlockIdx * SectorsPerBlock + S) div PhysSPT);
      PhysSecIdx := (BlockIdx * SectorsPerBlock + S) mod PhysSPT;
      { Map the logical sector position within the track to the physical
        SectorID byte via the per-track sorted ID list (handles CP/M skew). }
      SortedIDs := FDisk.GetSortedSectorIDs(PhysTrack);
      if (Length(SortedIDs) = 0) or (PhysSecIdx >= Length(SortedIDs)) then
        Continue;
      Ref.TrackIdx := PhysTrack;
      Ref.SectorID := SortedIDs[PhysSecIdx];
      ResLen := Length(Result);
      SetLength(Result, ResLen + 1);
      Result[ResLen] := Ref;
    end;
  end;
end;

function TDiskBenderCPM.GetFileEntryCount(FileIdx: Integer): Integer;
begin
  if (FileIdx < 0) or (FileIdx >= FFiles.Count) then
    Result := 0
  else
    Result := FFiles[FileIdx].EntryCount;
end;

function TDiskBenderCPM.GetFileEntryLoc(FileIdx, LocIdx: Integer;
                                          out ATrack, ASectorIdx, AEntryIdx: Byte): Boolean;
var
  Loc: TCPMEntryLoc;
begin
  ATrack := 0; ASectorIdx := 0; AEntryIdx := 0;
  Result := False;
  if (FileIdx < 0) or (FileIdx >= FFiles.Count) then Exit;
  if (LocIdx < 0) or (LocIdx >= FFiles[FileIdx].EntryCount) then Exit;
  Loc := FFiles[FileIdx].GetEntry(LocIdx);
  ATrack    := Loc.Track;
  ASectorIdx := Loc.SectorIdx;
  AEntryIdx  := Loc.EntryIdx;
  Result := True;
end;

end.
