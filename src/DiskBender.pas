program DiskBender;

{$mode objfpc}{$H+}

uses
  SysUtils, Classes,
  {$IFDEF UNIX}BaseUnix,{$ENDIF}
  uDSK, uCPM, uInterfaces, uFormatters, CoreAPI,
  uVFS, uLocalLocation, uDSKLocation, uTerminalIO, uFPCTerminal, uTUIController,
  uExternalDrive, uConfig;

var
  Disk: IVirtualDisk;
  FS: IFilesystem;
  Format: TOutputFormat = ofTable;
  Noun, Verb, Target, Target2, DSKPath: string;
  ToStdout: Boolean;
  ArgIdx: Integer;
  TUIInput: ITerminalInput;
  TUIOutput: ITerminalOutput;
  TUICtrl: TTUIController;
  LeftCont, RightCont: IContainer;
  DriveLetter: string;
  FluxMode: Boolean;
  RequireYes: Boolean;
  Reply: string;

{$IFDEF UNIX}
function StdinIsATTY: Boolean;
var St: Stat;
begin
  Result := (FpFStat(0, St) = 0) and ((St.st_mode and S_IFMT) = S_IFCHR);
end;
{$ENDIF}

{ Load persisted config, apply to the controller, Run, then save current
  state back to disk. Used by both TUI launch paths so persistence is
  uniform regardless of how the controller was invoked.

  Save is wrapped in a try/except so a write failure (read-only home dir,
  out-of-space, etc.) doesn't surface as an uncaught exception after the
  TUI exited cleanly -- the worst case is a missed save, not a crash. }
procedure RunTUIWithPersistence(ACtrl: TTUIController);
var
  Cfg: TDiskBenderConfig;
  CfgPath: string;
begin
  CfgPath := DefaultConfigPath;
  Cfg := LoadConfig(CfgPath);
  ACtrl.ApplyConfig(Cfg);
  try
    ACtrl.Run;
  finally
    try
      SaveConfig(CfgPath, ACtrl.BuildConfig);
    except
      { swallow -- best-effort persistence; the user has already exited }
    end;
  end;
end;

procedure Usage(ExitCode: Integer = 1);
begin
  WriteLn('DiskBender - Vintage Disk/Snapshot Management');
  WriteLn;
  WriteLn('Usage:');
  WriteLn('  diskbender <dsk_path>                              TUI (interactive)');
  WriteLn('  diskbender <noun> <verb> [args] <dsk_path>        CLI');
  WriteLn('  diskbender gui <dsk_path>                          GUI (Lazarus LCL)');
  WriteLn;
  WriteLn('File commands:');
  WriteLn('  files list <dsk_path>');
  WriteLn('  files get [--stdout] <filename> <dsk_path>');
  WriteLn('  files add <host_file> <dsk_path>');
  WriteLn('  files rename <oldname> <newname> <dsk_path>');
  WriteLn('  files delete <filename> <dsk_path>');
  WriteLn('  files undelete <filename> <dsk_path>');
  WriteLn;
  WriteLn('Disk commands:');
  WriteLn('  disk info <dsk_path>');
  WriteLn('  disk map <dsk_path>            Block allocation map');
  WriteLn('  disk sectormap <dsk_path>      Per-track sector state map');
  WriteLn('  disk read [--drive a] [--flux] <out_path>');
  WriteLn('                                 Read disc from Greaseweazle drive');
  WriteLn('  disk write [--drive a] [--yes] <in_path>');
  WriteLn('                                 Write .dsk image to Greaseweazle drive (destructive)');
  WriteLn('  disk drives                    Show Greaseweazle firmware/drive info');
  WriteLn;
  WriteLn('Greaseweazle options:');
  WriteLn('  --drive a|b    Drive letter (default: omitted, gw picks default)');
  WriteLn('  --flux         Read to raw flux (.scp) instead of decoded .dsk');
  WriteLn;
  WriteLn('  The ''gw'' tool must be on PATH, or set DISKBENDER_GW=/path/to/gw');
  WriteLn('  Install: pipx install greaseweazle');
  WriteLn;
  WriteLn('Options:');
  WriteLn('  -o <table|json>   Output format (default: table)');
  Halt(ExitCode);
end;

function NormalizeNoun(const S: string): string;
var
  L: string;
begin
  L := LowerCase(S);
  if (L = 'file') or (L = 'files') then Result := 'files'
  else if (L = 'disk') or (L = 'disks') then Result := 'disk'
  else if (L = 'gui') then Result := 'gui'
  else Result := L;
end;

procedure HandleFileCommands;
var
  Res: CoreAPI.TDiskBenderResult;
begin
  if (Verb = 'list') or (Verb = 'get') or (Verb = 'add') or
     (Verb = 'rename') or (Verb = 'delete') or (Verb = 'undelete') then
    Res := API.ExecuteFileCommands(FS, Disk, Verb, Target, Target2,
                                   DSKPath, Format, ToStdout)
  else
  begin
    Res.Success := False;
    Res.ResultString := '';
    Res.Error := '';
    Usage;
  end;

  if Res.Success then
    Write(Res.ResultString)
  else if Res.Error <> '' then
    WriteLn(Res.Error);
end;

procedure HandleDiskCommands;
var
  Res: TDiskBenderResult;
  GwPath, Log, TmpPath: string;
  Ok: Boolean;
  {$IFDEF UNIX}
  LSt: Stat;
  {$ENDIF}
begin
  { Greaseweazle verbs: no DSKPath required — handled before the DSK open. }
  if Verb = 'drives' then
  begin
    GwPath := FindGwExecutable;
    if GwPath = '' then
    begin
      WriteLn(GW_NOT_FOUND_HINT);
      Halt(1);
    end;
    Ok := GwDriveInfo(GwPath, Log);
    Write(Log);
    if not Ok then Halt(1);
    Exit;
  end;

  if Verb = 'read' then
  begin
    { Target holds the output path (last positional arg set by caller). }
    if Target = '' then
    begin
      WriteLn('Error: No output path specified.');
      Usage;
    end;
    { B7: Refuse to write to a symlink or an existing directory. }
    if DirectoryExists(Target) then
    begin
      WriteLn('Error: Output path is a directory: ', Target);
      Halt(1);
    end;
    {$IFDEF UNIX}
    if (FpLStat(Target, LSt) = 0) and ((LSt.st_mode and S_IFMT) = S_IFLNK) then
    begin
      WriteLn('Error: Output path is a symlink: ', Target);
      Halt(1);
    end;
    {$ENDIF}
    GwPath := FindGwExecutable;
    if GwPath = '' then
    begin
      WriteLn(GW_NOT_FOUND_HINT);
      Halt(1);
    end;
    { B6: suppress progress noise when machine-readable output is requested. }
    if Format <> ofJSON then
      WriteLn('Reading disc from drive ', DriveLetter, ' ...');
    { B8: write to a temp file first, rename atomically on success. }
    TmpPath := Target + '.tmp';
    Ok := GwReadDisc(GwPath, DriveLetter, TmpPath, Log);
    if Format <> ofJSON then
      WriteLn(Log);
    if not Ok then
    begin
      DeleteFile(TmpPath);
      WriteLn('Error: gw read failed.');
      Halt(1);
    end;
    if not RenameFile(TmpPath, Target) then
    begin
      WriteLn('Error: Could not rename temp file to ', Target);
      Halt(1);
    end;
    if FluxMode then
    begin
      if Format <> ofJSON then
        WriteLn('Wrote flux image: ', Target);
    end
    else
    begin
      if Format <> ofJSON then
        WriteLn('Wrote DSK image: ', Target);
      { Open the resulting DSK and show its directory + block map. }
      try
        Disk := TDiskBenderDSK.Create(Target);
        Disk.Load;
        FS := TDiskBenderCPM.Create(Disk);
        FS.ScanDirectory;
        Write(TDiskFormatter.FormatFiles(FS, Format));
        Write(TDiskFormatter.FormatMap(FS.GetBlockMap,
              128 shl FS.GetDPB.BSH, Format));
        FS := nil;
      except
        on E: Exception do
          if Format <> ofJSON then
            WriteLn('Note: could not open result DSK: ', E.Message);
      end;
      Disk := nil;
    end;
    Exit;
  end;

  if Verb = 'write' then
  begin
    if Target = '' then
    begin
      WriteLn('Error: No input path specified.');
      Usage;
    end;
    if not FileExists(Target) then
    begin
      WriteLn('Error: File not found: ', Target);
      Halt(1);
    end;
    { Verify the file is a valid DSK before sending it to hardware. }
    try
      Disk := TDiskBenderDSK.Create(Target);
      Disk.Load;
      Disk := nil;
    except
      on E: Exception do
      begin
        WriteLn('Error: Not a valid DSK image (', E.Message, ')');
        Halt(1);
      end;
    end;
    { Confirm destructive write unless --yes/--force was passed. }
    if not RequireYes then
    begin
      {$IFDEF UNIX}
      if StdinIsATTY then
      begin
        WriteLn('About to ERASE the disc on drive ', DriveLetter,
                '. Type YES to confirm:');
        ReadLn(Reply);
        if Reply <> 'YES' then
        begin
          WriteLn('Aborted.');
          Halt(2);
        end;
      end
      else
      {$ENDIF}
      begin
        WriteLn('Error: ''disk write'' is destructive. Pass --yes to confirm in non-interactive contexts.');
        Halt(2);
      end;
    end;
    GwPath := FindGwExecutable;
    if GwPath = '' then
    begin
      WriteLn(GW_NOT_FOUND_HINT);
      Halt(1);
    end;
    WriteLn('Writing ', Target, ' to drive ', DriveLetter, ' ...');
    Ok := GwWriteDisc(GwPath, DriveLetter, Target, Log);
    WriteLn(Log);
    if not Ok then
    begin
      WriteLn('Error: gw write failed.');
      Halt(1);
    end;
    WriteLn('Done.');
    Exit;
  end;

  if (Verb = 'info') or (Verb = 'map') or (Verb = 'sectormap') then
    Res := API.ExecuteDiskCommands(Disk, FS, Verb, DSKPath, Format)
  else
  begin
    Res.Success := False;
    Res.ResultString := '';
    Res.Error := '';
    Usage;
  end;

  if Res.Success then
    Write(Res.ResultString)
  else if Res.Error <> '' then
    WriteLn(Res.Error);
end;

procedure LaunchGui(const APath: string);
var
  AppPath: string;
begin
  AppPath := ExtractFilePath(ParamStr(0)) + 'DiskBenderGUI.app';
  if not DirectoryExists(AppPath) then
  begin
    WriteLn('Error: GUI not found at ', AppPath);
    WriteLn('Build it with: lazbuild src/gui/DiskBenderGUI.lpi');
    Halt(1);
  end;
  ExecuteProcess('/usr/bin/open', [AppPath, '--args', APath]);
end;

function IsValidDrive(const S: string): Boolean;
begin
  Result := (S = '') or
            ((Length(S) = 1) and (S[1] in ['a', 'b']));
end;

function IsHelpFlag(const S: string): Boolean;
var
  L: string;
begin
  L := LowerCase(S);
  Result := (L = '--help') or (L = '-help') or (L = '-h') or
            (L = '/help') or (L = '/?') or (L = '/h') or (L = 'help');
end;

begin
  FileEntryHook := @CreateDSKAwareEntry;

  if (ParamCount >= 1) and IsHelpFlag(ParamStr(1)) then
    Usage(0);

  if ParamCount = 0 then
  begin
    TUIInput := TFPCTerminalInput.Create;
    TUIOutput := TFPCTerminalOutput.Create;
    LeftCont := TLocalContainer.Create(GetCurrentDir);
    RightCont := TLocalContainer.Create(GetCurrentDir);
    TUICtrl := TTUIController.Create(TUIInput, TUIOutput, LeftCont, RightCont);
    try
      RunTUIWithPersistence(TUICtrl);
    finally
      TUICtrl.Free;
    end;
    Halt(0);
  end;

  // Check for GUI mode: diskbender gui <dsk_path> OR diskbender <noun> <verb> [args]
  if (ParamCount >= 2) and (NormalizeNoun(ParamStr(1)) = 'gui') then
    begin
      DSKPath := ExpandFileName(ParamStr(2));
      if not FileExists(DSKPath) then
      begin
        WriteLn('Error: File not found: ', DSKPath);
        Halt(1);
      end;
      LaunchGui(DSKPath);
      Halt(0);
    end
    else if ParamCount >= 2 then
    begin
      // --- CLI MODE: Parse arguments and execute commands ---
      Noun := NormalizeNoun(ParamStr(1));
      Verb := LowerCase(ParamStr(2));

      ArgIdx := 3;
      Target  := '';
      Target2 := '';
      DSKPath := '';
      ToStdout := False;
      DriveLetter := '';
      FluxMode := False;
      RequireYes := False;

      while ArgIdx <= ParamCount do
      begin
        if ParamStr(ArgIdx) = '-o' then
        begin
          if ArgIdx + 1 <= ParamCount then
          begin
            if LowerCase(ParamStr(ArgIdx + 1)) = 'json' then Format := ofJSON;
            Inc(ArgIdx, 2);
          end
          else
            Inc(ArgIdx);
        end
        else if ParamStr(ArgIdx) = '--stdout' then
        begin
          ToStdout := True;
          Inc(ArgIdx);
        end
        else if ParamStr(ArgIdx) = '--drive' then
        begin
          if ArgIdx + 1 <= ParamCount then
          begin
            DriveLetter := LowerCase(ParamStr(ArgIdx + 1));
            Inc(ArgIdx, 2);
          end
          else
          begin
            WriteLn('Warning: --drive given no value; using gw default.');
            Inc(ArgIdx);
          end;
        end
        else if ParamStr(ArgIdx) = '--flux' then
        begin
          FluxMode := True;
          Inc(ArgIdx);
        end
        else if (ParamStr(ArgIdx) = '--yes') or (ParamStr(ArgIdx) = '--force') then
        begin
          RequireYes := True;
          Inc(ArgIdx);
        end
        { No-target verbs: last positional arg is DSKPath. }
        else if (Verb = 'list') or (Verb = 'info') or
                (Verb = 'map') or (Verb = 'sectormap') then
        begin
          DSKPath := ParamStr(ArgIdx);
          Inc(ArgIdx);
        end
        { Greaseweazle verbs that take a single path as Target. }
        else if (Verb = 'read') or (Verb = 'write') then
        begin
          Target := ParamStr(ArgIdx);
          Inc(ArgIdx);
        end
        { drives: no positional args }
        else if Verb = 'drives' then
          Inc(ArgIdx)
        { Two-target verbs: get first Target then Target2 then DSKPath. }
        else if Verb = 'rename' then
        begin
          if Target = '' then
          begin
            Target := ParamStr(ArgIdx);
            Inc(ArgIdx);
          end
          else if Target2 = '' then
          begin
            Target2 := ParamStr(ArgIdx);
            Inc(ArgIdx);
          end
          else
          begin
            DSKPath := ParamStr(ArgIdx);
            Inc(ArgIdx);
          end;
        end
        { One-target verbs: first positional is Target, second is DSKPath. }
        else
        begin
          if Target = '' then
          begin
            Target := ParamStr(ArgIdx);
            Inc(ArgIdx);
          end
          else
          begin
            DSKPath := ParamStr(ArgIdx);
            Inc(ArgIdx);
          end;
        end;
      end;

      { Validate flag/verb combinations before dispatching. }
      if FluxMode and not ((Noun = 'disk') and (Verb = 'read')) then
      begin
        WriteLn('Error: --flux only applies to ''disk read''.');
        Halt(2);
      end;
      if (DriveLetter <> '') and (Noun = 'disk') and
         not ((Verb = 'read') or (Verb = 'write') or (Verb = 'drives')) then
      begin
        WriteLn('Error: --drive only applies to disk read/write/drives.');
        Halt(2);
      end;
      if not IsValidDrive(DriveLetter) then
      begin
        WriteLn('Error: --drive must be ''a'' or ''b'' (got ''', DriveLetter, ''').');
        Halt(2);
      end;

      { Greaseweazle verbs bypass the DSK open entirely — handle and done. }
      if (Noun = 'disk') and
         ((Verb = 'read') or (Verb = 'write') or (Verb = 'drives')) then
      begin
        HandleDiskCommands;
        Disk := nil;
      end
      else
      begin
        { For no-target verbs where only DSKPath was set, Target holds nothing. }
        if DSKPath = '' then DSKPath := Target;

        if not FileExists(DSKPath) then
        begin
          WriteLn('Error: File not found: ', DSKPath);
          Halt(1);
        end;
        DSKPath := ExpandFileName(DSKPath);

        Disk := TDiskBenderDSK.Create(DSKPath);
        try
          Disk.Load;
          FS := TDiskBenderCPM.Create(Disk);
          try
            FS.ScanDirectory;

            if Noun = 'files' then HandleFileCommands
            else if Noun = 'disk' then HandleDiskCommands
            else Usage;
          finally
            FS := nil;  { Release filesystem before disk }
          end;
        except
          on E: Exception do
            WriteLn('Error: ', E.Message);
        end;
        Disk := nil;
      end;
    end
  else
    begin
      // --- TUI MODE: diskbender <dsk_path> ---
      DSKPath := ExpandFileName(ParamStr(1));
      if not FileExists(DSKPath) then
      begin
        WriteLn('Error: File not found: ', DSKPath);
        Halt(1);
      end;
      try
        LeftCont := TDSKContainer.Create(DSKPath);
      except
        on E: Exception do
        begin
          WriteLn('Error: Cannot open DSK image: ', E.Message);
          Halt(1);
        end;
      end;
      TUIInput := TFPCTerminalInput.Create;
      TUIOutput := TFPCTerminalOutput.Create;
      RightCont := TLocalContainer.Create(GetCurrentDir);
      TUICtrl := TTUIController.Create(TUIInput, TUIOutput, LeftCont, RightCont);
      try
        RunTUIWithPersistence(TUICtrl);
      finally
        TUICtrl.Free;
      end;
    end;
end.
