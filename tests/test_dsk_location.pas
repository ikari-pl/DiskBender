program test_dsk_location;

{ Unit tests for ComputeDiskSectorMap (uDSKLocation).

  Compile:
    cd /Users/ikari/src/cpc/DiskBender && \
      fpc -Fu./src/units -Fu./src -Fu./tests \
          tests/test_dsk_location.pas -otests/test_dsk_location
  Run:
    ./tests/test_dsk_location }

{$mode objfpc}{$H+}

uses
  Classes, SysUtils,
  uCPM, uInterfaces, uVFS, uDSKLocation,
  uTestVirtualDisk;

var
  PassCount: Integer = 0;
  FailCount: Integer = 0;

procedure Check(const AName: string; ACondition: Boolean);
begin
  if ACondition then
  begin
    WriteLn('  PASS: ', AName);
    Inc(PassCount);
  end
  else
  begin
    WriteLn('  FAIL: ', AName);
    Inc(FailCount);
  end;
end;

{ ── Smoke test: minimal CPC-DATA mock disk, no crash ──────────── }

procedure TestSmokeMinimalDisk;
var
  Disk: IVirtualDisk;
  FS:   IFilesystem;
  Map:  TTrackColumnArray;
  I:    Integer;
begin
  WriteLn('--- TestSmokeMinimalDisk ---');

  { Standard CPC DATA format: 40 tracks, 9 sectors, 512-byte sectors,
    sector IDs starting at $C1. }
  Disk := TMockVirtualDisk.Create(40, 9, 2, $C1);
  FS   := TDiskBenderCPM.Create(Disk);
  FS.ScanDirectory;

  Map := ComputeDiskSectorMap(Disk, FS);

  Check('Result has 40 tracks', Length(Map) = 40);
  Check('Track 0 has 9 sectors', Length(Map[0].Sectors) = 9);
  Check('Track 39 has 9 sectors', Length(Map[39].Sectors) = 9);

  { Every sector on every track should be valid (non-zero SectorID for DATA fmt) }
  for I := 0 to High(Map) do
    Check('Track ' + IntToStr(I) + ' sector 0 SectorID >= $C1',
          Map[I].Sectors[0].SectorID >= $C1);

  { Boot track: reserved tracks (OFF field of DPB) are typically 0 for
    CPC DATA format — the first track IS the directory track.
    All sectors on track 0 should be ssSystem (directory). }
  Check('Track 0 sector 0 state is ssSystem',
        Map[0].Sectors[0].State = ssSystem);

  { All remaining data tracks should be ssEmpty (filled with $E5) }
  Check('Track 1 sector 0 state is ssEmpty',
        Map[1].Sectors[0].State = ssEmpty);

  FS   := nil;
  Disk := nil;
end;

{ ── Boot-track disk: 2 reserved tracks → those are ssBoot ─────── }

procedure TestBootTracksMarkedBoot;
var
  Disk: IVirtualDisk;
  FS:   IFilesystem;
  Map:  TTrackColumnArray;
  DPB:  TCPMDPB;
begin
  WriteLn('--- TestBootTracksMarkedBoot ---');

  { CPC SYSTEM format: sector IDs $41-$49, OFF=2 reserved tracks. }
  Disk := TMockVirtualDisk.Create(40, 9, 2, $41);
  FS   := TDiskBenderCPM.Create(Disk);
  FS.ScanDirectory;

  { Override the DPB so OFF=2 to simulate a SYSTEM-format boot area. }
  DPB := FS.GetDPB;
  DPB.OFF := 2;
  FS.SetDPB(DPB);

  Map := ComputeDiskSectorMap(Disk, FS);

  Check('Boot test: 40 tracks', Length(Map) = 40);
  Check('Boot track 0 sector 0 = ssBoot', Map[0].Sectors[0].State = ssBoot);
  Check('Boot track 1 sector 0 = ssBoot', Map[1].Sectors[0].State = ssBoot);
  Check('Dir  track 2 sector 0 = ssSystem', Map[2].Sectors[0].State = ssSystem);
  Check('Data track 3 sector 0 = ssEmpty',  Map[3].Sectors[0].State = ssEmpty);

  FS   := nil;
  Disk := nil;
end;

{ ── FDC error sectors propagate correctly ─────────────────────── }

procedure TestFDCErrorSectors;
var
  Disk: IVirtualDisk;
  FS:   IFilesystem;
  Map:  TTrackColumnArray;
begin
  WriteLn('--- TestFDCErrorSectors ---');

  Disk := TMockVirtualDisk.Create(40, 9, 2, $C1);
  FS   := TDiskBenderCPM.Create(Disk);
  FS.ScanDirectory;

  { The mock disk doesn't surface FDC errors through PutSectorData.
    We can only verify that non-error sectors stay non-error, and that
    the map has the correct shape on a clean disk. }
  Map := ComputeDiskSectorMap(Disk, FS);
  Check('FDC test: 40 tracks', Length(Map) = 40);
  Check('FDC test: track 5 has 9 sectors', Length(Map[5].Sectors) = 9);
  Check('FDC test: no false FDC errors on clean disk',
        Map[5].Sectors[0].State <> ssFDCError);

  FS   := nil;
  Disk := nil;
end;

{ ── Suspicious sector IDs flagged correctly ───────────────────── }

procedure TestSuspiciousIDDetection;
var
  Disk: IVirtualDisk;
  FS:   IFilesystem;
  Map:  TTrackColumnArray;
begin
  WriteLn('--- TestSuspiciousIDDetection ---');

  { CPC DATA format: sector IDs $C1-$C9 — NOT suspicious }
  Disk := TMockVirtualDisk.Create(10, 9, 2, $C1);
  FS   := TDiskBenderCPM.Create(Disk);
  FS.ScanDirectory;
  Map  := ComputeDiskSectorMap(Disk, FS);
  Check('$C1 sector ID: not suspicious', not Map[0].Sectors[0].IsSuspiciousID);

  FS   := nil;
  Disk := nil;

  { CPC SYSTEM format: sector IDs $41-$49 — NOT suspicious }
  Disk := TMockVirtualDisk.Create(10, 9, 2, $41);
  FS   := TDiskBenderCPM.Create(Disk);
  FS.ScanDirectory;
  Map  := ComputeDiskSectorMap(Disk, FS);
  Check('$41 sector ID: not suspicious', not Map[0].Sectors[0].IsSuspiciousID);

  FS   := nil;
  Disk := nil;

  { IBM-compat sector IDs $01 — NOT suspicious ($00-$1F range) }
  Disk := TMockVirtualDisk.Create(10, 9, 2, $01);
  FS   := TDiskBenderCPM.Create(Disk);
  FS.ScanDirectory;
  Map  := ComputeDiskSectorMap(Disk, FS);
  Check('$01 sector ID: not suspicious', not Map[0].Sectors[0].IsSuspiciousID);

  FS   := nil;
  Disk := nil;
end;

{ ── Skewed disk: map still has correct track/sector count ──────── }

procedure TestSkewedDisk;
var
  Disk: IVirtualDisk;
  FS:   IFilesystem;
  Map:  TTrackColumnArray;
begin
  WriteLn('--- TestSkewedDisk ---');

  Disk := TMockSkewedDisk.Create(40, 9, 2, $C1);
  FS   := TDiskBenderCPM.Create(Disk);
  FS.ScanDirectory;

  Map := ComputeDiskSectorMap(Disk, FS);

  Check('Skewed: 40 tracks', Length(Map) = 40);
  Check('Skewed: track 0 has 9 sectors', Length(Map[0].Sectors) = 9);
  { The dir track sectors are painted ssSystem even on skewed layout }
  Check('Skewed: track 0 contains at least one ssSystem sector',
        Map[0].Sectors[0].State = ssSystem);

  FS   := nil;
  Disk := nil;
end;

begin
  WriteLn('=== test_dsk_location ===');

  TestSmokeMinimalDisk;
  TestBootTracksMarkedBoot;
  TestFDCErrorSectors;
  TestSuspiciousIDDetection;
  TestSkewedDisk;

  WriteLn;
  WriteLn('Passed: ', PassCount, '  Failed: ', FailCount);
  if FailCount > 0 then
    Halt(1);
end.
