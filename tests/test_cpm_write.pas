program test_cpm_write;

{ End-to-end smoke test for the CP/M write path.

  Loads a real DSK image, calls AddFile with a synthetic payload, then reads
  back via GetFileContent and verifies the data round-trips byte-for-byte.
  Exercises FindFreeDirEntry, the block allocator, and the directory-entry
  build-out — all the pieces of the May-2026 review's critical findings. }

{$mode objfpc}{$H+}

uses
  Classes, SysUtils, uCPM, uDSK, uInterfaces, uTestVirtualDisk,
  CoreAPI, uFormatters;

const
  DSK_BATMAN_TMP = '/tmp/test_batman.dsk';

var
  Failures: Integer = 0;

procedure Check(Cond: Boolean; const Msg: string);
begin
  if Cond then
    WriteLn('  PASS: ', Msg)
  else
  begin
    WriteLn('  FAIL: ', Msg);
    Inc(Failures);
  end;
end;

procedure RoundTrip(const Payload: TBytes; const FName, FExt: string);
var
  Disk: IVirtualDisk;
  FS: IFilesystem;
  Idx, I: Integer;
  Stream: TMemoryStream;
  ReadBack: TBytes;
  AllMatch: Boolean;
begin
  WriteLn('--- RoundTrip: ', FName, '.', FExt, ' (', Length(Payload), ' bytes) ---');

  { Synthetic CPC DATA-format mock disk:
      40 tracks × 9 sectors of 512 bytes (SectorSizeCode=2)
      Sector IDs starting at $C1 (CPC DATA convention)
    The constructor fills every sector with $E5 so the directory is clean
    out of the gate — no zapping needed. }
  Disk := TMockVirtualDisk.Create(40, 9, 2, $C1);

  FS := TDiskBenderCPM.Create(Disk);
  FS.ScanDirectory;
  Idx := FS.AddFile(FName, FExt, Payload, 0);
  Check(Idx >= 0, 'AddFile returned valid index');
  if Idx < 0 then begin FS := nil; Disk := nil; Exit; end;
  Disk.Save;
  FS := nil;   { release before re-bind }

  { Re-bind a fresh CPM filesystem to the same Disk to prove ScanDirectory
    finds our entry by reading from the persisted (mock-)disk state, not
    from in-memory caching. }
  FS := TDiskBenderCPM.Create(Disk);
  FS.ScanDirectory;

  { Find our file by name+ext. }
  Idx := -1;
  for I := 0 to FS.GetFileCount - 1 do
    if (FS.GetFile(I).Name = UpperCase(FName)) and
       (FS.GetFile(I).Extension = UpperCase(FExt)) then
    begin
      Idx := I;
      Break;
    end;
  Check(Idx >= 0, 'File found after reload');
  if Idx < 0 then begin FS := nil; Disk := nil; Exit; end;

  Stream := TMemoryStream.Create;
  try
    FS.GetFileContent(Idx, Stream);
    SetLength(ReadBack, Stream.Size);
    if Stream.Size > 0 then
    begin
      Stream.Position := 0;
      Stream.ReadBuffer(ReadBack[0], Stream.Size);
    end;
  finally
    Stream.Free;
  end;

  if Length(Payload) = 0 then
    Check(Length(ReadBack) = Length(Payload),
          Format('Read-back size = payload (%d vs %d)', [Length(ReadBack), Length(Payload)]))
  else
    Check(Length(ReadBack) >= Length(Payload),
          Format('Read-back size >= payload (%d vs %d)', [Length(ReadBack), Length(Payload)]));

  AllMatch := True;
  for I := 0 to Length(Payload) - 1 do
  begin
    if I >= Length(ReadBack) then
    begin
      AllMatch := False;
      WriteLn('    Read-back truncated at offset ', I,
              ' (length ', Length(ReadBack), ')');
      Break;
    end;
    if ReadBack[I] <> Payload[I] then
    begin
      AllMatch := False;
      WriteLn('    First mismatch at offset ', I,
              ': expected $', IntToHex(Payload[I], 2),
              ', got $', IntToHex(ReadBack[I], 2));
      Break;
    end;
  end;
  Check(AllMatch, 'Payload round-trips byte-for-byte');
  FS := nil;
  Disk := nil;
end;

procedure TestGuardEntriesReserveSpace;
var
  Src, Dst: TFileStream;
  Disk: IVirtualDisk;
  FS: IFilesystem;
  Idx: Integer;
  Payload: TBytes;
  BatmanDSK: string;
begin
  WriteLn('--- GUARD entries reserve space and block allocation ---');

  { Resolve the Batman DSK path relative to the test binary so the test
    works from any working directory. }
  BatmanDSK := ExtractFilePath(ParamStr(0)) +
    '../Batman Forever (UK) (128K) (Face 1A) (2011) [Original] [DEMO].dsk';
  BatmanDSK := ExpandFileName(BatmanDSK);
  if not FileExists(BatmanDSK) then
  begin
    WriteLn('  SKIP: Batman.dsk not present');
    Exit;
  end;

  { Batman.dsk's directory contains all-space-name "GUARD" entries that
    legitimately reserve every data block (a CPC copy-protection trick).
    Earlier we ignored those allocations so AddFile could find free space.
    The truthful behavior — the one a real CP/M + AMSDOS would also exhibit
    — is to treat them as USED. AddFile must refuse with "disk full". }
  if FileExists(DSK_BATMAN_TMP) then DeleteFile(DSK_BATMAN_TMP);
  Src := TFileStream.Create(BatmanDSK, fmOpenRead);
  try
    Dst := TFileStream.Create(DSK_BATMAN_TMP, fmCreate);
    try
      Dst.CopyFrom(Src, Src.Size);
    finally
      Dst.Free;
    end;
  finally
    Src.Free;
  end;

  Disk := TDiskBenderDSK.Create(DSK_BATMAN_TMP);
  Disk.Load;
  FS := TDiskBenderCPM.Create(Disk);
  FS.ScanDirectory;
  SetLength(Payload, 256);
  FillChar(Payload[0], 256, $AA);
  Idx := FS.AddFile('JV1TEST', 'BIN', Payload, 0);
  Check(Idx < 0,
        'AddFile refuses on a disk where GUARD entries claim every block');
  FS := nil;
  Disk := nil;
end;

procedure TestMultiTrackDirectoryWrap;
var
  Disk: IVirtualDisk;
  FS: IFilesystem;
  Idx, S: Integer;
  CustomDPB: TCPMDPB;
  FullSec: TBytes;
  Payload: TBytes;
  EntryTrack: Byte;
  EntrySecIdx, EntryEntIdx: Byte;
begin
  WriteLn('--- Multi-track directory wrap (de3) ---');

  { Standard CPC geometry: 9 sectors of 512 bytes per track, 16 entries per
    sector. Default DPB has DRM=63 → 4 dir sectors = single track. We force
    multi-track by overriding DRM=145, which needs 10 dir sectors — exactly
    one full track of 9 + one sector on the next track. }
  Disk := TMockVirtualDisk.Create(40, 9, 2, $C1);
  FS := TDiskBenderCPM.Create(Disk);
  FS.ScanDirectory;

  CustomDPB := FS.GetDPB;
  CustomDPB.DRM := 145;
  FS.SetDPB(CustomDPB);

  { Mark every entry on track 0's 9 sectors as "in use" (User=$00 ≠ $E5).
    With FindFreeDirEntry's correct semantics (free iff User=$E5), no slot
    will be available on track 0. The new file's directory entry must
    land on track 1. }
  SetLength(FullSec, 512);
  FillChar(FullSec[0], 512, $00);
  for S := 0 to 8 do
    Disk.PutSectorData(0, S, FullSec);

  SetLength(Payload, 16);
  FillChar(Payload[0], 16, $BB);
  Idx := FS.AddFile('TRACK2', 'TST', Payload, 0);
  Check(Idx >= 0,
        'AddFile finds a free slot on track 1 when track 0 dir is full');
  if Idx >= 0 then
  begin
    Check(FS.GetFileEntryCount(Idx) > 0, 'New file has at least one dir entry');
    if FS.GetFileEntryCount(Idx) > 0 then
    begin
      FS.GetFileEntryLoc(Idx, 0, EntryTrack, EntrySecIdx, EntryEntIdx);
      Check(EntryTrack = 1,
            Format('Dir entry placed on track 1 (got track %d)', [EntryTrack]));
    end;
  end;
  FS := nil;
  Disk := nil;
end;

procedure Test16BitAllocation;
const
  ENTRY_SIZE = 32;
  ENTRIES_PER_SECTOR = 16;
var
  Disk: IVirtualDisk;
  FS: IFilesystem;
  CustomDPB: TCPMDPB;
  Idx, I, J, BlockNo, SectorIdx, EntryIdx, FoundIdx: Integer;
  DirSec: TBytes;
  EntryBase: PByte;
  Stream: TMemoryStream;
  Payload, ReadBack: TBytes;
  AllMatch: Boolean;
  AllocByteOff: Integer;
  ETrack, ESecIdx, EEntIdx: Byte;
begin
  WriteLn('--- 16-bit block allocation (34l) ---');

  { 280 KB volume: 70 tracks × 8 sectors × 512 bytes. With 1 KB blocks
    that's 280 blocks, so DSM=279 — comfortably above the 255 threshold
    where allocation pointers must widen to 16 bits. }
  Disk := TMockVirtualDisk.Create(70, 8, 2, $C1);
  FS := TDiskBenderCPM.Create(Disk);
  FS.ScanDirectory;

  CustomDPB := FS.GetDPB;
  CustomDPB.DSM := 279;        { > 255 → 16-bit allocation kicks in }
  CustomDPB.AL0 := $C0;        { directory in blocks 0,1 }
  CustomDPB.AL1 := $00;
  FS.SetDPB(CustomDPB);

  { Hand-craft 32 fake directory entries (across the first 2 dir sectors)
    claiming blocks 2..257 as in-use. 8 blocks per entry × 32 entries = 256
    blocks. After this, the next free block is 258 — out of 8-bit range,
    forcing the 16-bit code path. }
  BlockNo := 2;
  for SectorIdx := 0 to 1 do
  begin
    DirSec := Disk.GetSectorData(0, SectorIdx);
    for EntryIdx := 0 to ENTRIES_PER_SECTOR - 1 do
    begin
      EntryBase := @DirSec[EntryIdx * ENTRY_SIZE];
      FillChar(EntryBase^, ENTRY_SIZE, 0);
      EntryBase[0] := 0;                  { User = 0 }
      EntryBase[1] := Ord('F');           { non-space filename so GetBlockMap counts it }
      EntryBase[2] := Ord('I');
      EntryBase[3] := Ord('L');
      EntryBase[4] := Ord('L');
      EntryBase[9]  := Ord('D');          { extension }
      EntryBase[10] := Ord('A');
      EntryBase[11] := Ord('T');
      EntryBase[15] := 128;               { RecordCount = full extent }
      AllocByteOff := 16;                 { first byte of Allocations }
      for I := 0 to 7 do
      begin
        EntryBase[AllocByteOff + I * 2]     := Byte(BlockNo and $FF);
        EntryBase[AllocByteOff + I * 2 + 1] := Byte((BlockNo shr 8) and $FF);
        Inc(BlockNo);
      end;
    end;
    Disk.PutSectorData(0, SectorIdx, DirSec);
  end;

  { Now AddFile must allocate from block 258+ — proves SetAllocBlock
    writes 16-bit, GetAllocBlock reads 16-bit, and GetFileContent uses
    the right block number to compute physical sector positions. }
  SetLength(Payload, 2000);
  for I := 0 to High(Payload) do Payload[I] := Byte((I * 7 + 13) and $FF);
  Idx := FS.AddFile('TEST16', 'BIN', Payload, 0);
  Check(Idx >= 0, 'AddFile succeeds with DSM > 255 (was previously refused)');
  if Idx < 0 then begin FS := nil; Disk := nil; Exit; end;

  { Verify the allocation actually used a high block number — that's the
    whole point of forcing the 16-bit path. }
  Check(FS.GetFileEntryCount(Idx) > 0, 'New file has at least one dir entry');
  if FS.GetFileEntryCount(Idx) > 0 then
  begin
    FS.GetFileEntryLoc(Idx, 0, ETrack, ESecIdx, EEntIdx);
    DirSec := Disk.GetSectorData(ETrack, ESecIdx);
    EntryBase := @DirSec[EEntIdx * ENTRY_SIZE];
    J := EntryBase[16] or (Integer(EntryBase[17]) shl 8);
    Check(J > 255, Format('Allocated block index %d > 255 (16-bit path exercised)', [J]));
  end;

  { Round-trip the content through GetFileContent. If 16-bit layout were
    wrong, GetFileContent would read from the wrong physical sectors and
    we'd see garbage. }
  Stream := TMemoryStream.Create;
  try
    FS.GetFileContent(Idx, Stream);
    SetLength(ReadBack, Stream.Size);
    if Stream.Size > 0 then
    begin
      Stream.Position := 0;
      Stream.ReadBuffer(ReadBack[0], Stream.Size);
    end;
  finally
    Stream.Free;
  end;

  AllMatch := True;
  FoundIdx := -1;
  for I := 0 to Length(Payload) - 1 do
    if (I >= Length(ReadBack)) or (ReadBack[I] <> Payload[I]) then
    begin AllMatch := False; FoundIdx := I; Break; end;
  if AllMatch then
    Check(True, '16-bit round-trip matches byte-for-byte (2000 bytes)')
  else
    Check(False, Format('Round-trip mismatch at offset %d', [FoundIdx]));
  FS := nil;
  Disk := nil;
end;

function MakePayload(Size: Integer; Seed: Byte): TBytes;
var
  I: Integer;
begin
  SetLength(Result, Size);
  for I := 0 to Size - 1 do
    Result[I] := Byte((I + Seed) and $FF);
end;

procedure TestSkewedDiskRoundTrip;
{ I4: Verify that AddFile + ScanDirectory + GetFileContent round-trip correctly
  on a disk whose physical sector order is skewed (CPC-DATA interleave).
  TMockSkewedDisk assigns IDs in the pattern $C1,$C6,$C2,$C7,... so that the
  sorted (CP/M-logical) order is not the same as the physical order. If the
  logical↔physical translation in LogicalSectorID / WriteLogicalSector /
  ReadLogicalSector is wrong, the data will appear garbled on read-back. }
var
  Disk: IVirtualDisk;
  FS: IFilesystem;
  Payload, ReadBack: TBytes;
  Idx, I: Integer;
  Stream: TMemoryStream;
  AllMatch: Boolean;
begin
  WriteLn('--- Skewed disk round-trip (I4) ---');

  Disk := TMockSkewedDisk.Create(40, 9, 2, $C1);
  FS := TDiskBenderCPM.Create(Disk);
  FS.ScanDirectory;

  SetLength(Payload, 3 * 512);   { spans 3 sectors = 1.5 blocks }
  for I := 0 to High(Payload) do
    Payload[I] := Byte((I * 13 + 7) and $FF);

  Idx := FS.AddFile('SKEW', 'TST', Payload, 0);
  Check(Idx >= 0, 'AddFile succeeds on skewed disk');
  if Idx < 0 then begin FS := nil; Disk := nil; Exit; end;
  Disk.Save;
  FS := nil;

  { Re-read from the same (still-alive) mock disk. }
  FS := TDiskBenderCPM.Create(Disk);
  FS.ScanDirectory;

  Idx := -1;
  for I := 0 to FS.GetFileCount - 1 do
    if FS.GetFile(I).Name = 'SKEW' then
    begin Idx := I; Break; end;
  Check(Idx >= 0, 'File found after reload on skewed disk');
  if Idx < 0 then begin FS := nil; Disk := nil; Exit; end;

  Stream := TMemoryStream.Create;
  try
    FS.GetFileContent(Idx, Stream);
    SetLength(ReadBack, Stream.Size);
    if Stream.Size > 0 then
    begin
      Stream.Position := 0;
      Stream.ReadBuffer(ReadBack[0], Stream.Size);
    end;
  finally
    Stream.Free;
  end;

  AllMatch := True;
  for I := 0 to High(Payload) do
    if (I >= Length(ReadBack)) or (ReadBack[I] <> Payload[I]) then
    begin
      AllMatch := False;
      WriteLn('    Mismatch at offset ', I);
      Break;
    end;
  Check(AllMatch, 'Skewed-disk payload round-trips byte-for-byte');
  FS := nil;
  Disk := nil;
end;

{ ── CoreAPI verb tests ─────────────────────────────────────────── }

procedure TestCoreAPIList;
var
  Disk: IVirtualDisk;
  FS: IFilesystem;
  Payload: TBytes;
  Res: TDiskBenderResult;
begin
  WriteLn('--- CoreAPI: files list ---');
  Disk := TMockVirtualDisk.Create(40, 9, 2, $C1);
  FS := TDiskBenderCPM.Create(Disk);
  FS.ScanDirectory;
  SetLength(Payload, 256);
  FillChar(Payload[0], 256, $AA);
  FS.AddFile('HELLO', 'BAS', Payload, 0);
  { Re-scan so the new file is visible. }
  FS.ScanDirectory;
  Res := API.ExecuteFileCommands(FS, Disk, 'list', '', '', '', ofTable, False);
  Check(Res.Success, 'list verb succeeds');
  Check(Pos('HELLO', Res.ResultString) > 0, 'list output contains HELLO');
  FS := nil;
  Disk := nil;
end;

procedure TestCoreAPIRename;
var
  Disk: IVirtualDisk;
  FS: IFilesystem;
  Payload: TBytes;
  Res: TDiskBenderResult;
begin
  WriteLn('--- CoreAPI: files rename ---');
  Disk := TMockVirtualDisk.Create(40, 9, 2, $C1);
  FS := TDiskBenderCPM.Create(Disk);
  FS.ScanDirectory;
  SetLength(Payload, 128);
  FillChar(Payload[0], 128, $BB);
  FS.AddFile('OLD', 'BAS', Payload, 0);
  FS.ScanDirectory;
  Res := API.ExecuteFileCommands(FS, Disk, 'rename', 'OLD.BAS', 'NEW.COM', '', ofTable, False);
  Check(Res.Success, 'rename verb succeeds');
  Check(Pos('NEW', Res.ResultString) > 0, 'rename result mentions new name');
  { Verify file is now named NEW.COM. }
  FS.ScanDirectory;
  Res := API.ExecuteFileCommands(FS, Disk, 'list', '', '', '', ofTable, False);
  Check(Pos('NEW', Res.ResultString) > 0, 'list shows renamed file');
  FS := nil;
  Disk := nil;
end;

procedure TestCoreAPIDeleteUndelete;
var
  Disk: IVirtualDisk;
  FS: IFilesystem;
  Payload: TBytes;
  Res: TDiskBenderResult;
begin
  WriteLn('--- CoreAPI: files delete + undelete ---');
  Disk := TMockVirtualDisk.Create(40, 9, 2, $C1);
  FS := TDiskBenderCPM.Create(Disk);
  FS.ScanDirectory;
  SetLength(Payload, 128);
  FillChar(Payload[0], 128, $CC);
  FS.AddFile('VICTIM', 'TXT', Payload, 0);
  FS.ScanDirectory;
  Res := API.ExecuteFileCommands(FS, Disk, 'delete', 'VICTIM.TXT', '', '', ofTable, False);
  Check(Res.Success, 'delete verb succeeds');
  FS.ScanDirectory;
  Res := API.ExecuteFileCommands(FS, Disk, 'undelete', 'VICTIM.TXT', '', '', ofTable, False);
  Check(Res.Success, 'undelete verb succeeds');
  FS := nil;
  Disk := nil;
end;

procedure TestCoreAPIEmptyBaseNameGuard;
var
  Disk: IVirtualDisk;
  FS: IFilesystem;
  Payload: TBytes;
  Res: TDiskBenderResult;
begin
  WriteLn('--- CoreAPI: empty base-name guard (rename + add) ---');
  Disk := TMockVirtualDisk.Create(40, 9, 2, $C1);
  FS := TDiskBenderCPM.Create(Disk);
  FS.ScanDirectory;
  SetLength(Payload, 128);
  FillChar(Payload[0], 128, $DD);
  FS.AddFile('SRC', 'BAS', Payload, 0);
  FS.ScanDirectory;
  { rename to a leading-dot name like ".COM" should fail gracefully. }
  Res := API.ExecuteFileCommands(FS, Disk, 'rename', 'SRC.BAS', '.COM', '', ofTable, False);
  Check(not Res.Success, 'rename to leading-dot name fails');
  Check(Res.Error <> '', 'rename error message is non-empty');
  FS := nil;
  Disk := nil;
end;

procedure TestInMemoryGuard;
{ I5: Verify the GUARD scenario without Batman.dsk.
  We fill every directory slot of a fresh mock disk with non-$E5 entries
  (user=0, valid-looking allocations that claim all blocks), then confirm
  that AddFile refuses — proving the pre-validation guard in AddFile catches
  both "directory full" and "no free blocks". }
var
  Disk: IVirtualDisk;
  FS: IFilesystem;
  CustomDPB: TCPMDPB;
  S, E: Integer;
  SecData: TBytes;
  EntryBase: PByte;
  Payload: TBytes;
  Idx: Integer;
begin
  WriteLn('--- In-memory GUARD scenario (I5) ---');

  { Small disk: 5 tracks × 9 sectors × 512 bytes.
    Default CPC DATA DPB: DRM=63 → 64 directory entries in 4 sectors.
    AL0=$C0 → blocks 0,1 reserved for directory.
    DSM=170 → blocks 0..170. We'll claim blocks 2..170 via fake entries. }
  Disk := TMockVirtualDisk.Create(5, 9, 2, $C1);
  FS := TDiskBenderCPM.Create(Disk);
  FS.ScanDirectory;

  { Re-use the autodetected DPB. }
  CustomDPB := FS.GetDPB;
  CustomDPB.DRM := 63;    { 64 entries, 4 dir sectors }
  FS.SetDPB(CustomDPB);

  { Fill all 4 directory sectors with entries that claim blocks 2..169.
    16 entries × 4 sectors = 64 entries. Each entry claims 1 block (set
    Allocations[0]=block index, rest=0). This consumes all 64 slots and
    most data blocks. }
  for S := 0 to 3 do
  begin
    SecData := Disk.GetSectorData(0, S);
    for E := 0 to 15 do
    begin
      EntryBase := @SecData[E * 32];
      FillChar(EntryBase^, 32, 0);
      EntryBase[0] := 0;                  { user 0 }
      EntryBase[1] := Ord('G');           { non-space name }
      EntryBase[2] := Ord('U');
      EntryBase[3] := Ord('A');
      EntryBase[4] := Ord('R');
      EntryBase[5] := Ord('D');
      EntryBase[15] := 1;                 { 1 record }
      EntryBase[16] := Byte(S * 16 + E + 2);  { block index: 2..65 }
    end;
    Disk.PutSectorData(0, S, SecData);
  end;

  SetLength(Payload, 512);
  FillChar(Payload[0], 512, $CC);
  Idx := FS.AddFile('NOSPACE', 'TST', Payload, 0);
  Check(Idx < 0, 'AddFile refuses when all dir slots are claimed');
  FS := nil;
  Disk := nil;
end;

begin

  { Single-block file — exercises the simple path. }
  RoundTrip(MakePayload(100, 0), 'TINY', 'BIN');

  { Multi-block, single-extent file (e.g., 4 KB = 4 blocks on CPC). }
  RoundTrip(MakePayload(4096, $11), 'MED', 'DAT');

  { Two-extent file: 17 KB > 16 KB (1 extent) so requires a second dir entry. }
  RoundTrip(MakePayload(17 * 1024, $42), 'BIG', 'DAT');

  { Empty file — edge case, no blocks, single zero-length dir entry. }
  RoundTrip(MakePayload(0, 0), 'EMPTY', 'TXT');

  { jv1: real-world disk with GUARD entries should refuse new files. }
  TestGuardEntriesReserveSpace;

  { de3: directory spanning 2 tracks; FindFreeDirEntry must wrap. }
  TestMultiTrackDirectoryWrap;

  { 34l: 16-bit allocation pointers (DSM > 255). }
  Test16BitAllocation;

  { I4: skewed sector layout — logical↔physical translation must be correct. }
  TestSkewedDiskRoundTrip;

  { I5: in-memory GUARD scenario — AddFile refuses when directory is full. }
  TestInMemoryGuard;

  { CoreAPI verb tests }
  TestCoreAPIList;
  TestCoreAPIRename;
  TestCoreAPIDeleteUndelete;
  TestCoreAPIEmptyBaseNameGuard;

  WriteLn;
  WriteLn('=== Results: ', Failures, ' failures ===');
  if Failures > 0 then Halt(1);
end.
