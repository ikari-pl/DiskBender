unit CoreAPI;

{$mode objfpc}{$H+}

interface

uses
  SysUtils,
  Classes,
  uDSK,
  uCPM,
  uInterfaces,
  uFormatters;

type
  TDiskBenderResult = record
    Success: Boolean;
    ResultString: string;
    Error: string;
  end;

type
  TDiskBenderAPI = class
  public
    function ExecuteFileCommands(FS: IFilesystem; const Verb, Target, DSKPath: string; const Format: TOutputFormat): TDiskBenderResult;
    function ExecuteDiskCommands(Disk: IVirtualDisk; FS: IFilesystem; const Verb: string; const Format: TOutputFormat): TDiskBenderResult;
  end;

var
  API: TDiskBenderAPI;

implementation

function TDiskBenderAPI.ExecuteFileCommands(FS: IFilesystem; const Verb, Target, DSKPath: string; const Format: TOutputFormat): TDiskBenderResult;
var
  I: Integer;
  OutputFile: TFileStream;
  ExtractedPath: string;
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

    { Find the file by name }
    for I := 0 to FS.GetFileCount - 1 do
    begin
      if (UpCase(FS.GetFile(I).Name) = UpCase(ExtractFileName(Target))) or
         (ChangeFileExt(FS.GetFile(I).Name, '') = ChangeFileExt(ExtractFileName(Target), '')) then
      begin
        { Extract the file content }
        ExtractedPath := ExtractFilePath(DSKPath) + FS.GetFile(I).Name;
        if FS.GetFile(I).Extension <> '' then
          ExtractedPath := ExtractedPath + '.' + FS.GetFile(I).Extension;
        ExtractedPath := ExtractedPath + '.raw';

        try
          OutputFile := TFileStream.Create(ExtractedPath, fmCreate);
          try
            FS.GetFileContent(I, OutputFile);
          finally
            OutputFile.Free;
          end;
          Result.Success := True;
          Result.ResultString := 'Extracted: ' + ExtractedPath;
        except
          on E: Exception do
          begin
            Result.Error := 'Error: Could not extract file - ' + E.Message;
          end;
        end;
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
      if (UpCase(FS.GetFile(I).Name) = UpCase(ExtractFileName(Target))) or
         (ChangeFileExt(FS.GetFile(I).Name, '') = ChangeFileExt(ExtractFileName(Target), '')) then
      begin
        FS.ToggleDelete(I);
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
      if (UpCase(FS.GetFile(I).Name) = UpCase(ExtractFileName(Target))) or
         (ChangeFileExt(FS.GetFile(I).Name, '') = ChangeFileExt(ExtractFileName(Target), '')) then
      begin
        if FS.GetFile(I).IsDeleted then
          FS.ToggleDelete(I);
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

function TDiskBenderAPI.ExecuteDiskCommands(Disk: IVirtualDisk; FS: IFilesystem; const Verb: string; const Format: TOutputFormat): TDiskBenderResult;
var
  Map: TBytes;
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
    Result.Success := True;
    Result.ResultString := TDiskFormatter.FormatMap(Map, Format);
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