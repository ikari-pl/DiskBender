program test_drive;

{ Tests for uExternalDrive — exercises RunGw, GwReadDisc, GwWriteDisc, and
  GwDriveInfo against tests/fake_gw.sh so no real hardware is needed.

  Build:
    fpc -Fu./src/units -Fu./src/tui -Fu./src -Fu./tests \
        tests/test_drive.pas -otests/test_drive
  Run:
    ./tests/test_drive
}

{$mode objfpc}{$H+}

uses
  SysUtils, Classes,
  {$IFDEF UNIX}BaseUnix,{$ENDIF}
  uExternalDrive, uDSK, uInterfaces;

{ ── Environment helpers (UNIX-only) ─────────────────────────── }

procedure SetEnvVar(const Name, Value: string);
begin
  {$IFDEF UNIX}fpsetenv(PChar(Name), PChar(Value), 1);{$ENDIF}
end;

procedure RestoreEnvVar(const Name, OldValue: string);
begin
  {$IFDEF UNIX}
  if OldValue = '' then fpunsetenv(PChar(Name))
  else fpsetenv(PChar(Name), PChar(OldValue), 1);
  {$ENDIF}
end;

var
  PassCount: Integer = 0;
  FailCount: Integer = 0;

procedure Check(Cond: Boolean; const Msg: string);
begin
  if Cond then
  begin
    WriteLn('  PASS: ', Msg);
    Inc(PassCount);
  end
  else
  begin
    WriteLn('  FAIL: ', Msg);
    Inc(FailCount);
  end;
end;

function ScriptPath: string;
begin
  { Resolve fake_gw.sh relative to this executable's directory so the test
    works when run from any cwd.  At build time the test binary is placed in
    the project root (tests/test_drive), so ExeDir is the project root and
    tests/fake_gw.sh is one level below it. }
  Result := ExtractFilePath(ParamStr(0)) + 'tests/fake_gw.sh';
  if not FileExists(Result) then
    { Fallback: invoked from within the tests/ directory itself }
    Result := ExtractFilePath(ParamStr(0)) + 'fake_gw.sh';
end;

procedure TestFindGwExecutable_NotFound;
var
  Saved, Path: string;
begin
  WriteLn('--- TestFindGwExecutable_NotFound ---');
  Saved := GetEnvironmentVariable('DISKBENDER_GW');
  { Point env at a path that cannot exist. }
  SetEnvVar('DISKBENDER_GW', '/tmp/diskbender-nonexistent-gw-xyz');
  Path := FindGwExecutable;
  if Path = '' then
    Check(True, 'FindGwExecutable returns empty when DISKBENDER_GW is invalid AND no gw on PATH')
  else
    { Acceptable: gw is genuinely installed on PATH — verify the override fell through to PATH. }
    Check(FileExists(Path), 'FindGwExecutable fell back to a real binary on PATH');
  RestoreEnvVar('DISKBENDER_GW', Saved);
end;

procedure TestFindGwExecutable_EnvVar;
var
  Saved, Path: string;
begin
  WriteLn('--- TestFindGwExecutable_EnvVar ---');
  Saved := GetEnvironmentVariable('DISKBENDER_GW');
  { Point DISKBENDER_GW at the fake_gw.sh script, which definitely exists. }
  SetEnvVar('DISKBENDER_GW', ScriptPath);
  Path := FindGwExecutable;
  if FileExists(ScriptPath) then
    Check(Path = ScriptPath, 'DISKBENDER_GW env override is honoured (got: ' + Path + ')')
  else
    Check(True, 'fake_gw.sh not present; env-var path is set but unreachable');
  RestoreEnvVar('DISKBENDER_GW', Saved);
end;

procedure TestRunGwInfo;
var
  Log: string;
  Ok: Boolean;
  GwPath: string;
begin
  WriteLn('--- TestRunGwInfo ---');
  GwPath := ScriptPath;
  if not FileExists(GwPath) then
  begin
    WriteLn('  SKIP: fake_gw.sh not found at ', GwPath);
    Exit;
  end;
  Ok := GwDriveInfo(GwPath, Log);
  Check(Ok, 'GwDriveInfo returns True');
  Check(Pos('firmware', Log) > 0, 'Log contains "firmware"');
end;

procedure TestGwReadDisc;
var
  Log, TmpFile: string;
  Ok: Boolean;
  GwPath: string;
  Disk: IVirtualDisk;
begin
  WriteLn('--- TestGwReadDisc ---');
  GwPath := ScriptPath;
  if not FileExists(GwPath) then
  begin
    WriteLn('  SKIP: fake_gw.sh not found at ', GwPath);
    Exit;
  end;
  TmpFile := GetTempDir + 'test_drive_read.dsk';
  try
    Ok := GwReadDisc(GwPath, 'a', TmpFile, Log);
    Check(Ok, 'GwReadDisc returns True');
    Check(FileExists(TmpFile), 'Output file exists');
    Check(Pos('read complete', Log) > 0, 'Log mentions read complete');
    { Verify the written DSK is loadable by TDiskBenderDSK }
    if FileExists(TmpFile) then
    begin
      try
        Disk := TDiskBenderDSK.Create(TmpFile);
        Disk.Load;
        Check(Disk.NumTracks >= 1, 'DSK has at least 1 track');
        Disk := nil;
      except
        on E: Exception do
          Check(False, 'TDiskBenderDSK.Load raised: ' + E.Message);
      end;
    end;
  finally
    if FileExists(TmpFile) then DeleteFile(TmpFile);
  end;
end;

procedure TestGwReadDisc_NoDrive;
var
  Log, TmpFile: string;
  Ok: Boolean;
  GwPath: string;
begin
  WriteLn('--- TestGwReadDisc_NoDrive ---');
  GwPath := ScriptPath;
  if not FileExists(GwPath) then
  begin
    WriteLn('  SKIP: fake_gw.sh not found at ', GwPath);
    Exit;
  end;
  TmpFile := GetTempDir + 'test_drive_read_nodrive.dsk';
  try
    Ok := GwReadDisc(GwPath, '', TmpFile, Log);
    Check(Ok, 'GwReadDisc with empty drive returns True');
    Check(FileExists(TmpFile), 'Output file exists without --drive arg');
  finally
    if FileExists(TmpFile) then DeleteFile(TmpFile);
  end;
end;

procedure TestGwWriteDisc;
var
  Log, TmpFile: string;
  Ok: Boolean;
  GwPath: string;
begin
  WriteLn('--- TestGwWriteDisc ---');
  GwPath := ScriptPath;
  if not FileExists(GwPath) then
  begin
    WriteLn('  SKIP: fake_gw.sh not found at ', GwPath);
    Exit;
  end;
  { Create a dummy file to write }
  TmpFile := GetTempDir + 'test_drive_write.dsk';
  try
    { Create the file so fake_gw can find it }
    GwReadDisc(GwPath, '', TmpFile, Log);
    if not FileExists(TmpFile) then
    begin
      WriteLn('  SKIP: could not create temp DSK for write test');
      Exit;
    end;
    Ok := GwWriteDisc(GwPath, 'a', TmpFile, Log);
    Check(Ok, 'GwWriteDisc returns True');
    Check(Pos('write complete', Log) > 0, 'Log mentions write complete');
  finally
    if FileExists(TmpFile) then DeleteFile(TmpFile);
  end;
end;

procedure TestGwWriteDisc_MissingFile;
var
  Log: string;
  Ok: Boolean;
  GwPath: string;
begin
  WriteLn('--- TestGwWriteDisc_MissingFile ---');
  GwPath := ScriptPath;
  if not FileExists(GwPath) then
  begin
    WriteLn('  SKIP: fake_gw.sh not found at ', GwPath);
    Exit;
  end;
  Ok := GwWriteDisc(GwPath, 'a', '/tmp/does_not_exist_xyz.dsk', Log);
  Check(not Ok, 'GwWriteDisc returns False for missing file');
end;

begin
  WriteLn('=== test_drive ===');
  TestFindGwExecutable_NotFound;
  TestFindGwExecutable_EnvVar;
  TestRunGwInfo;
  TestGwReadDisc;
  TestGwReadDisc_NoDrive;
  TestGwWriteDisc;
  TestGwWriteDisc_MissingFile;
  WriteLn;
  WriteLn(PassCount, ' passed, ', FailCount, ' failed');
  if FailCount > 0 then Halt(1);
end.
