unit CoreAPI;

{$mode objfpc}{$H+}

interface

uses
  SysUtils,
  Classes,
  uDSK,
  uCPM,
  uInterfaces,
  uFormatters,
  uVFS,
  uDSKLocation;

type
  TDiskBenderResult = record
    Success: Boolean;
    ResultString: string;
    Error: string;
  end;

type
  TDiskBenderAPI = class
  public
    { Target2 is used by: rename (new name), add (host file path).
      ToStdout routes 'get' output to stdout instead of a file. }
    function ExecuteFileCommands(FS: IFilesystem; Disk: IVirtualDisk;
      const Verb, Target, Target2, DSKPath: string;
      const Format: TOutputFormat; ToStdout: Boolean): TDiskBenderResult;
    function ExecuteDiskCommands(Disk: IVirtualDisk; FS: IFilesystem;
      const Verb, DSKPath: string; const Format: TOutputFormat): TDiskBenderResult;
  end;

var
  API: TDiskBenderAPI;

implementation

function MatchFileName(const EntryName, EntryExt, Query: string): Boolean;
var
  QName, QExt: string;
  DotPos: Integer;
begin
  { Accept "NAME.EXT", "NAME", or bare "NAME.EXT" forms.
    Comparison is case-insensitive. }
  DotPos := Pos('.', Query);
  if DotPos > 0 then
  begin
    QName := UpperCase(Copy(Query, 1, DotPos - 1));
    QExt  := UpperCase(Copy(Query, DotPos + 1, MaxInt));
  end
  else
  begin
    QName := UpperCase(Query);
    QExt  := '';
  end;
  if QExt = '' then
    Result := UpperCase(EntryName) = QName
  else
    Result := (UpperCase(EntryName) = QName) and (UpperCase(EntryExt) = QExt);
end;

function TDiskBenderAPI.ExecuteFileCommands(FS: IFilesystem; Disk: IVirtualDisk;
  const Verb, Target, Target2, DSKPath: string;
  const Format: TOutputFormat; ToStdout: Boolean): TDiskBenderResult;
var
  I: Integer;
  OutputFile: TFileStream;
  StdoutStream: THandleStream;
  ExtractedPath: string;
  HostData: TBytes;
  HostStream: TFileStream;
  HostName, HostExt, NewName, NewExt, NewBase: string;
  Idx: Integer;
  DotPos: Integer;
begin
  Result.Success := False;
  Result.ResultString := '';
  Result.Error := '';

  if Verb = 'list' then
  begin
    Result.Success := True;
    Result.ResultString := TDiskFormatter.FormatFiles(FS, Format);
  end
  else if Verb = 'get' then
  begin
    if Target = '' then
    begin
      Result.Error := 'Error: No filename specified.';
      Exit;
    end;

    for I := 0 to FS.GetFileCount - 1 do
    begin
      if MatchFileName(FS.GetFile(I).Name, FS.GetFile(I).Extension, ExtractFileName(Target)) then
      begin
        try
          if ToStdout then
          begin
            StdoutStream := THandleStream.Create(StdOutputHandle);
            try
              FS.GetFileContent(I, StdoutStream);
            finally
              StdoutStream.Free;
            end;
            Result.Success := True;
            Result.ResultString := '';
          end
          else
          begin
            { Sanitise CP/M name and extension: strip path separators and
              dot-sequences to prevent directory traversal on hostile DSKs. }
            HostName := StringReplace(FS.GetFile(I).Name, '/', '_', [rfReplaceAll]);
            HostName := StringReplace(HostName, '\', '_', [rfReplaceAll]);
            HostName := StringReplace(HostName, '..', '__', [rfReplaceAll]);
            HostExt  := StringReplace(FS.GetFile(I).Extension, '/', '_', [rfReplaceAll]);
            HostExt  := StringReplace(HostExt, '\', '_', [rfReplaceAll]);
            HostExt  := StringReplace(HostExt, '..', '__', [rfReplaceAll]);
            if HostName = '' then HostName := '_unnamed';
            ExtractedPath := ExtractFilePath(DSKPath) + HostName;
            if HostExt <> '' then
              ExtractedPath := ExtractedPath + '.' + HostExt;
            ExtractedPath := ExtractedPath + '.raw';
            OutputFile := TFileStream.Create(ExtractedPath, fmCreate);
            try
              FS.GetFileContent(I, OutputFile);
            finally
              OutputFile.Free;
            end;
            Result.Success := True;
            Result.ResultString := 'Extracted: ' + ExtractedPath;
          end;
        except
          on E: Exception do
            Result.Error := 'Error: Could not extract file - ' + E.Message;
        end;
        Exit;
      end;
    end;

    Result.Error := 'Error: File not found: ' + Target;
  end
  else if Verb = 'add' then
  begin
    { files add <host_file> <dsk_path>
      Target = host file path; Target2 unused (parsed by caller). }
    if Target = '' then
    begin
      Result.Error := 'Error: No host file specified.';
      Exit;
    end;
    if not FileExists(Target) then
    begin
      Result.Error := 'Error: Host file not found: ' + Target;
      Exit;
    end;

    HostName := ChangeFileExt(ExtractFileName(Target), '');
    HostExt  := Copy(ExtractFileExt(Target), 2, MaxInt);   { strip leading dot }

    { Guard against leading-dot names (e.g. ".bashrc") which produce an empty
      base name — CP/M filenames require at least one non-dot character. }
    if HostName = '' then
    begin
      Result.Error := 'Error: filename ''' + ExtractFileName(Target) +
                      ''' has no base name (leading-dot names not supported).';
      Exit;
    end;

    HostStream := TFileStream.Create(Target, fmOpenRead);
    try
      SetLength(HostData, HostStream.Size);
      if HostStream.Size > 0 then
        HostStream.ReadBuffer(HostData[0], HostStream.Size);
    finally
      HostStream.Free;
    end;

    Idx := FS.AddFile(HostName, HostExt, HostData, 0);
    if Idx < 0 then
    begin
      Result.Error := 'Error: Could not add file (disk full or invalid name)';
      Exit;
    end;

    Disk.Save;
    Result.Success := True;
    if HostExt <> '' then
      Result.ResultString := 'Added: ' + HostName + '.' + HostExt
    else
      Result.ResultString := 'Added: ' + HostName;
  end
  else if Verb = 'rename' then
  begin
    { files rename <oldname> <newname> <dsk_path>
      Target = old name, Target2 = new name. }
    if Target = '' then
    begin
      Result.Error := 'Error: No source filename specified.';
      Exit;
    end;
    if Target2 = '' then
    begin
      Result.Error := 'Error: No destination filename specified.';
      Exit;
    end;

    { Guard: empty base name on the new name side.
      Extract the part before the first dot using Pos/Copy so that leading-dot
      names like ".COM" (where ChangeFileExt returns the whole string) are
      caught reliably. }
    DotPos := Pos('.', Target2);
    if DotPos = 1 then
    begin
      Result.Error := 'Error: filename ''' + Target2 +
                      ''' has no base name (leading-dot names not supported).';
      Exit;
    end;
    if DotPos > 1 then
      NewBase := Copy(Target2, 1, DotPos - 1)
    else
      NewBase := Target2;
    if NewBase = '' then
    begin
      Result.Error := 'Error: filename ''' + Target2 +
                      ''' has no base name (leading-dot names not supported).';
      Exit;
    end;

    for I := 0 to FS.GetFileCount - 1 do
    begin
      if MatchFileName(FS.GetFile(I).Name, FS.GetFile(I).Extension, Target) then
      begin
        { Parse new name — accept "NAME.EXT" or just "NAME". }
        DotPos := Pos('.', Target2);
        if DotPos > 0 then
        begin
          NewName := Copy(Target2, 1, DotPos - 1);
          NewExt  := Copy(Target2, DotPos + 1, MaxInt);
        end
        else
        begin
          NewName := Target2;
          NewExt  := FS.GetFile(I).Extension;
        end;
        FS.RenameFile(I, NewName + '.' + NewExt);
        Disk.Save;
        Result.Success := True;
        if NewExt <> '' then
          Result.ResultString := 'Renamed to: ' + NewName + '.' + NewExt
        else
          Result.ResultString := 'Renamed to: ' + NewName;
        Exit;
      end;
    end;

    Result.Error := 'Error: File not found: ' + Target;
  end
  else if Verb = 'delete' then
  begin
    if Target = '' then
    begin
      Result.Error := 'Error: No filename specified.';
      Exit;
    end;

    for I := 0 to FS.GetFileCount - 1 do
    begin
      if MatchFileName(FS.GetFile(I).Name, FS.GetFile(I).Extension, ExtractFileName(Target)) then
      begin
        FS.ToggleDelete(I);
        Disk.Save;
        Result.Success := True;
        Result.ResultString := 'Deleted: ' + FS.GetFile(I).Name;
        Exit;
      end;
    end;

    Result.Error := 'Error: File not found: ' + Target;
  end
  else if Verb = 'undelete' then
  begin
    if Target = '' then
    begin
      Result.Error := 'Error: No filename specified.';
      Exit;
    end;

    for I := 0 to FS.GetFileCount - 1 do
    begin
      if MatchFileName(FS.GetFile(I).Name, FS.GetFile(I).Extension, ExtractFileName(Target)) then
      begin
        if FS.GetFile(I).IsDeleted then
          FS.ToggleDelete(I);
        Disk.Save;
        Result.Success := True;
        Result.ResultString := 'Undeleted: ' + FS.GetFile(I).Name;
        Exit;
      end;
    end;

    Result.Error := 'Error: File not found: ' + Target;
  end
  else
  begin
    Result.Error := 'Error: Unknown verb: ' + Verb;
  end;
end;

function TDiskBenderAPI.ExecuteDiskCommands(Disk: IVirtualDisk; FS: IFilesystem;
  const Verb, DSKPath: string; const Format: TOutputFormat): TDiskBenderResult;
var
  Map: TBytes;
  DPB: TCPMDPB;
  BytesPerBlock: Integer;
  Cont: IContainer;
  SM: ISectorMappable;
  SMap: TTrackColumnArray;
begin
  Result.Success := False;
  Result.ResultString := '';
  Result.Error := '';

  if Verb = 'info' then
  begin
    Result.Success := True;
    Result.ResultString := TDiskFormatter.FormatDiskInfo(Disk, Format);
  end
  else if Verb = 'map' then
  begin
    Map := FS.GetBlockMap;
    DPB := FS.GetDPB;
    BytesPerBlock := 128 shl DPB.BSH;
    Result.Success := True;
    Result.ResultString := TDiskFormatter.FormatMap(Map, BytesPerBlock, Format);
  end
  else if Verb = 'sectormap' then
  begin
    { ISectorMappable is only implemented by TDSKContainer (VFS layer), not by
      IFilesystem directly.  Construct a TDSKContainer from the DSK path — it is
      a TInterfacedObject so we hold it via IContainer and let the ref drop. }
    try
      Cont := TDSKContainer.Create(DSKPath);
    except
      on E: Exception do
      begin
        Result.Success := False;
        Result.Error := 'Sector map: ' + E.Message;
        Exit;
      end;
    end;
    if not Supports(Cont, ISectorMappable, SM) then
    begin
      Result.Success := False;
      Result.Error := 'Error: Disk does not support sector maps.';
      Cont := nil;
      Exit;
    end;
    SMap := SM.GetSectorMap;
    SM := nil;
    Cont := nil;
    Result.Success := True;
    { Enable ANSI color escapes only for the table format on a TTY.
      Piped/redirected output and JSON output stay plain so captured
      data can be parsed without stripping escape sequences. }
    Result.ResultString := TDiskFormatter.FormatSectorMap(SMap, Format,
      (Format = ofTable) and OutputIsTTY);
  end
  else
  begin
    Result.Error := 'Error: Unknown verb: ' + Verb;
  end;
end;

initialization
  API := TDiskBenderAPI.Create;

finalization
  API.Free;

end.