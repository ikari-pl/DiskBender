program DiskBender;

{$mode objfpc}{$H+}

uses
  SysUtils, Classes, uDSK, uCPM, uInterfaces, uFormatters, CoreAPI,
  uVFS, uLocalLocation, uDSKLocation, uTerminalIO, uFPCTerminal, uTUIController;

var
  Disk: IVirtualDisk;
  FS: IFilesystem;
  Format: TOutputFormat = ofTable;
  Noun, Verb, Target, DSKPath: string;
  ArgIdx: Integer;
  TUIInput: ITerminalInput;
  TUIOutput: ITerminalOutput;
  TUICtrl: TTUIController;
  LeftCont, RightCont: IContainer;

procedure Usage;
begin
  WriteLn('DiskBender - Vintage Disk/Snapshot Management');
  WriteLn;
  WriteLn('Usage:');
  WriteLn('  diskbender <dsk_path>                          TUI (interactive)');
  WriteLn('  diskbender <noun> <verb> [args] <dsk_path>    CLI');
  WriteLn('  diskbender gui <dsk_path>                      GUI (Lazarus LCL)');
  WriteLn;
  WriteLn('Nouns:');
  WriteLn('  file(s)  <list|get|delete|undelete> [filename] <dsk_path>');
  WriteLn('  disk(s)  <info|map> <dsk_path>');
  WriteLn;
  WriteLn('Options:');
  WriteLn('  -o <table|json>   Output format (default: table)');
  Halt(1);
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
  Result: CoreAPI.TDiskBenderResult;
begin
  if Verb = 'list' then
    Result := API.ExecuteFileCommands(FS, Verb, Target, DSKPath, Format)
  else if Verb = 'get' then
  begin
    if Target = '' then
    begin
      Result.Success := False;
      Result.ResultString := '';
      Result.Error := 'Error: No filename specified.';
    end
    else
    begin
      Result := API.ExecuteFileCommands(FS, Verb, Target, DSKPath, Format);
    end;
  end
  else if (Verb = 'delete') or (Verb = 'undelete') then
  begin
    Result := API.ExecuteFileCommands(FS, Verb, Target, DSKPath, Format);
  end
  else
  begin
    Result.Success := False;
    Result.ResultString := '';
    Result.Error := '';
    Usage;
  end;

  // Handle presentation based on API result
  if Result.Success then
    Write(Result.ResultString)
  else if Result.Error <> '' then
    WriteLn(Result.Error);
end;

procedure HandleDiskCommands;
var
  Result: TDiskBenderResult;
begin
  if Verb = 'info' then
    Result := API.ExecuteDiskCommands(Disk, FS, Verb, Format)
  else if Verb = 'map' then
  begin
    Result := API.ExecuteDiskCommands(Disk, FS, Verb, Format);
  end
  else
  begin
    Result.Success := False;
    Result.ResultString := '';
    Result.Error := '';
    Usage;
  end;

  // Handle presentation based on API result
  if Result.Success then
    Write(Result.ResultString)
  else if Result.Error <> '' then
    WriteLn(Result.Error);
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

begin
  if ParamCount = 0 then
  begin
    TUIInput := TFPCTerminalInput.Create;
    TUIOutput := TFPCTerminalOutput.Create;
    LeftCont := TLocalContainer.Create(GetCurrentDir);
    RightCont := TLocalContainer.Create(GetCurrentDir);
    TUICtrl := TTUIController.Create(TUIInput, TUIOutput, LeftCont, RightCont);
    try
      TUICtrl.Run;
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
      Target := '';
      DSKPath := '';
    
      while ArgIdx <= ParamCount do
      begin
        if ParamStr(ArgIdx) = '-o' then
        begin
          if ParamStr(ArgIdx + 1) = 'json' then Format := ofJSON;
          Inc(ArgIdx, 2);
        end
        else if (Target = '') and (Verb <> 'list') and (Verb <> 'info') and (Verb <> 'map') then
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
    end
  else
    begin
      // --- TUI MODE: diskbender <dsk_path> ---
      TUIInput := TFPCTerminalInput.Create;
      TUIOutput := TFPCTerminalOutput.Create;
      LeftCont := TDSKContainer.Create(ParamStr(1));
      RightCont := TLocalContainer.Create(GetCurrentDir);
      TUICtrl := TTUIController.Create(TUIInput, TUIOutput, LeftCont, RightCont);
      try
        TUICtrl.Run;
      finally
        TUICtrl.Free;
      end;
    end;
end.
