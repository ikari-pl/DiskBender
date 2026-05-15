program test_config;

{$mode objfpc}{$H+}

uses
  SysUtils, Classes, uVFS, uPbWire, uConfig;

var
  PassCount: Integer = 0;
  FailCount: Integer = 0;

procedure Check(const ALabel: string; ACond: Boolean);
begin
  if ACond then
  begin
    Inc(PassCount);
    WriteLn('  PASS: ', ALabel);
  end
  else
  begin
    Inc(FailCount);
    WriteLn('  FAIL: ', ALabel);
  end;
end;

function MakeNonDefaultConfig: TDiskBenderConfig;
begin
  Result := DefaultConfig;
  Result.Left.ListMode  := CFG_LM_BRIEF;
  Result.Left.Role      := CFG_ROLE_INFO;
  Result.Left.SortField := Ord(sfSize);
  Result.Left.SortAscending := False;
  Result.Left.DirsFirst := False;
  Result.Left.DateKind  := Ord(dkCreation);
  Result.Left.Glob      := '*.BAS';
  Result.Left.ShowDeleted := True;
  Result.Left.UserArea  := 7;
  SetLength(Result.Left.TreeExpanded, 2);
  Result.Left.TreeExpanded[0] := '/foo';
  Result.Left.TreeExpanded[1] := '/foo/bar';
  Result.Left.Cursor    := 42;
  Result.Left.Scroll    := 12;
  Result.Left.LastPath  := '/Users/ikari/HELLO.dsk';

  Result.Right.ListMode := CFG_LM_WIDE;
  Result.Right.Role     := CFG_ROLE_QUICK_VIEW;
  Result.Right.LastPath := '/tmp/test.dsk';
end;

procedure TestDefaultsRoundtrip;
var
  Bytes: TBytes;
  Cfg, Decoded: TDiskBenderConfig;
begin
  WriteLn('--- TestDefaultsRoundtrip ---');
  Cfg := DefaultConfig;
  Bytes := EncodeConfig(Cfg);
  Decoded := DecodeConfig(Bytes);
  Check('schema_version preserved', Decoded.SchemaVersion = CONFIG_SCHEMA_VERSION);
  Check('left list_mode default = Full', Decoded.Left.ListMode = CFG_LM_FULL);
  Check('left role default = List', Decoded.Left.Role = CFG_ROLE_LIST);
  Check('left dirs_first default = true', Decoded.Left.DirsFirst);
  Check('left show_guards default = true', Decoded.Left.ShowGuards);
  Check('left glob default empty', Decoded.Left.Glob = '');
  Check('left user_area default = -1', Decoded.Left.UserArea = -1);
end;

procedure TestNonDefaultsRoundtrip;
var
  Bytes: TBytes;
  Cfg, Decoded: TDiskBenderConfig;
begin
  WriteLn('--- TestNonDefaultsRoundtrip ---');
  Cfg := MakeNonDefaultConfig;
  Bytes := EncodeConfig(Cfg);
  Decoded := DecodeConfig(Bytes);
  Check('left list_mode Brief', Decoded.Left.ListMode = CFG_LM_BRIEF);
  Check('left role Info', Decoded.Left.Role = CFG_ROLE_INFO);
  Check('left sort_field Size', Decoded.Left.SortField = Ord(sfSize));
  Check('left sort_ascending false', not Decoded.Left.SortAscending);
  Check('left dirs_first false', not Decoded.Left.DirsFirst);
  Check('left date_kind Creation', Decoded.Left.DateKind = Ord(dkCreation));
  Check('left glob *.BAS', Decoded.Left.Glob = '*.BAS');
  Check('left show_deleted true', Decoded.Left.ShowDeleted);
  Check('left user_area 7', Decoded.Left.UserArea = 7);
  Check('left tree_expanded length=2', Length(Decoded.Left.TreeExpanded) = 2);
  Check('left tree_expanded[0]', Decoded.Left.TreeExpanded[0] = '/foo');
  Check('left tree_expanded[1]', Decoded.Left.TreeExpanded[1] = '/foo/bar');
  Check('left cursor 42', Decoded.Left.Cursor = 42);
  Check('left scroll 12', Decoded.Left.Scroll = 12);
  Check('left last_path', Decoded.Left.LastPath = '/Users/ikari/HELLO.dsk');

  Check('right list_mode Wide', Decoded.Right.ListMode = CFG_LM_WIDE);
  Check('right role QuickView', Decoded.Right.Role = CFG_ROLE_QUICK_VIEW);
  Check('right last_path', Decoded.Right.LastPath = '/tmp/test.dsk');
end;

procedure TestSaveLoadFile;
var
  Path: string;
  Cfg, Loaded: TDiskBenderConfig;
begin
  WriteLn('--- TestSaveLoadFile ---');
  Path := GetTempDir + 'diskbender_test_config_' + IntToStr(GetProcessID) + '.pb';
  try
    Cfg := MakeNonDefaultConfig;
    SaveConfig(Path, Cfg);
    Check('config file exists after save', FileExists(Path));
    Loaded := LoadConfig(Path);
    Check('saved->loaded left glob round-trips', Loaded.Left.Glob = '*.BAS');
    Check('saved->loaded left cursor round-trips', Loaded.Left.Cursor = 42);
    Check('saved->loaded right last_path round-trips',
          Loaded.Right.LastPath = '/tmp/test.dsk');
  finally
    if FileExists(Path) then DeleteFile(Path);
  end;
end;

procedure TestLoadMissingReturnsDefaults;
var
  Cfg: TDiskBenderConfig;
begin
  WriteLn('--- TestLoadMissingReturnsDefaults ---');
  Cfg := LoadConfig('/nonexistent/path/that/should/not/exist.pb');
  Check('missing file -> default schema_version', Cfg.SchemaVersion = CONFIG_SCHEMA_VERSION);
  Check('missing file -> default list_mode', Cfg.Left.ListMode = CFG_LM_FULL);
end;

procedure TestLoadCorruptReturnsDefaults;
var
  Path: string;
  Fs: TFileStream;
  Junk: TBytes;
  Cfg: TDiskBenderConfig;
begin
  WriteLn('--- TestLoadCorruptReturnsDefaults ---');
  Path := GetTempDir + 'diskbender_test_corrupt_' + IntToStr(GetProcessID) + '.pb';
  try
    { Write a deliberately malformed payload: leading varint that runs off
      the end (continuation bit set with no follow-up). }
    SetLength(Junk, 1);
    Junk[0] := $80;
    Fs := TFileStream.Create(Path, fmCreate);
    try
      Fs.WriteBuffer(Junk[0], 1);
    finally
      Fs.Free;
    end;
    Cfg := LoadConfig(Path);
    Check('corrupt file -> defaults (no crash)',
          Cfg.SchemaVersion = CONFIG_SCHEMA_VERSION);
  finally
    if FileExists(Path) then DeleteFile(Path);
  end;
end;

procedure TestDumpAsTextHasKeyFields;
var
  Cfg: TDiskBenderConfig;
  Dump: string;
begin
  WriteLn('--- TestDumpAsTextHasKeyFields ---');
  Cfg := MakeNonDefaultConfig;
  Dump := DumpConfigAsText(Cfg);
  Check('dump contains schema_version', Pos('schema_version: 1', Dump) > 0);
  Check('dump contains left.glob', Pos('glob: "*.BAS"', Dump) > 0);
  Check('dump contains last_path', Pos('/Users/ikari/HELLO.dsk', Dump) > 0);
  Check('dump contains tree_expanded entry', Pos('/foo/bar', Dump) > 0);
end;

procedure TestForwardCompatUnknownFieldsSkipped;
var
  W: TPbWriter;
  Raw: TBytes;
  Cfg: TDiskBenderConfig;
begin
  WriteLn('--- TestForwardCompatUnknownFieldsSkipped ---');
  { Pretend a future schema added field 99 (a uint32) at the top level. }
  W := TPbWriter.Create;
  try
    W.WriteUInt32(PB_CONFIG_SCHEMA_VERSION, CONFIG_SCHEMA_VERSION);
    W.WriteUInt32(99, 12345);  { unknown to our reader }
    Raw := W.GetBytes;
  finally
    W.Free;
  end;
  Cfg := DecodeConfig(Raw);
  Check('unknown field skipped without error', Cfg.SchemaVersion = CONFIG_SCHEMA_VERSION);
end;

begin
  WriteLn;
  WriteLn('=== DiskBender config persistence tests ===');
  WriteLn;

  TestDefaultsRoundtrip;
  TestNonDefaultsRoundtrip;
  TestSaveLoadFile;
  TestLoadMissingReturnsDefaults;
  TestLoadCorruptReturnsDefaults;
  TestDumpAsTextHasKeyFields;
  TestForwardCompatUnknownFieldsSkipped;

  WriteLn;
  WriteLn('=== Results: ', PassCount, ' passed, ', FailCount, ' failed ===');
  WriteLn;

  if FailCount > 0 then Halt(1);
end.
