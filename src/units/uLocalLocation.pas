unit uLocalLocation;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, uVFS;

type
  { A file on the host filesystem. }
  TLocalFileEntry = class(TInterfacedObject, IEntry, ISizeable, ICopySource)
  strict private
    FName: string;
    FFullPath: string;
    FSize: Int64;
  public
    constructor Create(const AFullPath: string);
    { IEntry }
    function GetName: string;
    function GetDisplayName: string;
    { ISizeable }
    function GetSize: Int64;
    function GetSizeUnit: TSizeUnit;
    { ICopySource }
    procedure CopyTo(AStream: TStream);
  end;

  { A subdirectory on the host filesystem. Both an entry and a container. }
  TLocalDirEntry = class(TInterfacedObject, IEntry, IContainer)
  strict private
    FName: string;
    FFullPath: string;
    FEntries: array of IEntry;
    FScanned: Boolean;
    procedure Scan;
  public
    constructor Create(const AFullPath: string);
    constructor CreateParent(const AChildDir: string);
    { IEntry }
    function GetName: string;
    function GetDisplayName: string;
    { IContainer }
    function GetEntryCount: Integer;
    function GetEntry(Index: Integer): IEntry;
    function GetTitle: string;
    procedure Refresh;
  end;

  { The root container for a host directory — what fills a pane.
    Identical to TLocalDirEntry but scans eagerly and sets the
    display title to the full path. }
  TLocalContainer = class(TInterfacedObject, IEntry, IContainer, ICopyTarget)
  strict private
    FPath: string;
    FEntries: array of IEntry;
    procedure Scan;
  public
    constructor Create(const APath: string);
    { IEntry }
    function GetName: string;
    function GetDisplayName: string;
    { IContainer }
    function GetEntryCount: Integer;
    function GetEntry(Index: Integer): IEntry;
    function GetTitle: string;
    procedure Refresh;
    { ICopyTarget }
    function Import(ASource: ICopySource; const AName: string): Boolean;
    { Navigation helper }
    function FullPath: string;
  end;

implementation

{ ── TLocalFileEntry ───────────────────────────────────────────── }

constructor TLocalFileEntry.Create(const AFullPath: string);
var
  SR: TSearchRec;
begin
  inherited Create;
  FFullPath := AFullPath;
  FName := ExtractFileName(AFullPath);
  FSize := 0;
  if FindFirst(AFullPath, faAnyFile, SR) = 0 then
  begin
    FSize := SR.Size;
    FindClose(SR);
  end;
end;

function TLocalFileEntry.GetName: string;
begin
  Result := FName;
end;

function TLocalFileEntry.GetDisplayName: string;
begin
  Result := FName;
end;

function TLocalFileEntry.GetSize: Int64;
begin
  Result := FSize;
end;

function TLocalFileEntry.GetSizeUnit: TSizeUnit;
begin
  Result := suBytes;
end;

procedure TLocalFileEntry.CopyTo(AStream: TStream);
var
  FS: TFileStream;
begin
  FS := TFileStream.Create(FFullPath, fmOpenRead or fmShareDenyNone);
  try
    AStream.CopyFrom(FS, 0);
  finally
    FS.Free;
  end;
end;

{ ── TLocalDirEntry ────────────────────────────────────────────── }

constructor TLocalDirEntry.Create(const AFullPath: string);
begin
  inherited Create;
  FFullPath := AFullPath;
  FName := ExtractFileName(AFullPath);
  FScanned := False;
end;

constructor TLocalDirEntry.CreateParent(const AChildDir: string);
begin
  inherited Create;
  FFullPath := ExtractFileDir(AChildDir);
  FName := '..';
  FScanned := False;
end;

function TLocalDirEntry.GetName: string;
begin
  Result := FName;
end;

function TLocalDirEntry.GetDisplayName: string;
begin
  if FName = '..' then
    Result := '..'
  else
    Result := '[' + FName + ']';
end;

procedure TLocalDirEntry.Scan;
var
  SR: TSearchRec;
  ChildPath: string;
begin
  SetLength(FEntries, 0);

  if FFullPath <> ExtractFileDir(FFullPath) then
  begin
    SetLength(FEntries, 1);
    FEntries[0] := TLocalDirEntry.CreateParent(FFullPath);
  end;

  if FindFirst(FFullPath + PathDelim + '*', faAnyFile, SR) = 0 then
  begin
    repeat
      if (SR.Name = '.') or (SR.Name = '..') then Continue;
      ChildPath := FFullPath + PathDelim + SR.Name;
      SetLength(FEntries, Length(FEntries) + 1);
      if (SR.Attr and faDirectory) <> 0 then
        FEntries[High(FEntries)] := TLocalDirEntry.Create(ChildPath)
      else
        FEntries[High(FEntries)] := TLocalFileEntry.Create(ChildPath);
    until FindNext(SR) <> 0;
    FindClose(SR);
  end;
  FScanned := True;
end;

function TLocalDirEntry.GetEntryCount: Integer;
begin
  if not FScanned then Scan;
  Result := Length(FEntries);
end;

function TLocalDirEntry.GetEntry(Index: Integer): IEntry;
begin
  if not FScanned then Scan;
  if (Index >= 0) and (Index < Length(FEntries)) then
    Result := FEntries[Index]
  else
    Result := nil;
end;

function TLocalDirEntry.GetTitle: string;
begin
  Result := FFullPath;
end;

procedure TLocalDirEntry.Refresh;
begin
  FScanned := False;
  SetLength(FEntries, 0);
end;

{ ── TLocalContainer ───────────────────────────────────────────── }

constructor TLocalContainer.Create(const APath: string);
begin
  inherited Create;
  FPath := ExpandFileName(APath);
  Scan;
end;

procedure TLocalContainer.Scan;
var
  SR: TSearchRec;
  ChildPath: string;
begin
  SetLength(FEntries, 0);

  if FPath <> ExtractFileDir(FPath) then
  begin
    SetLength(FEntries, 1);
    FEntries[0] := TLocalDirEntry.CreateParent(FPath);
  end;

  if FindFirst(FPath + PathDelim + '*', faAnyFile, SR) = 0 then
  begin
    repeat
      if (SR.Name = '.') or (SR.Name = '..') then Continue;
      ChildPath := FPath + PathDelim + SR.Name;
      SetLength(FEntries, Length(FEntries) + 1);
      if (SR.Attr and faDirectory) <> 0 then
        FEntries[High(FEntries)] := TLocalDirEntry.Create(ChildPath)
      else
        FEntries[High(FEntries)] := TLocalFileEntry.Create(ChildPath);
    until FindNext(SR) <> 0;
    FindClose(SR);
  end;
end;

function TLocalContainer.GetName: string;
begin
  Result := ExtractFileName(FPath);
end;

function TLocalContainer.GetDisplayName: string;
begin
  Result := FPath;
end;

function TLocalContainer.GetEntryCount: Integer;
begin
  Result := Length(FEntries);
end;

function TLocalContainer.GetEntry(Index: Integer): IEntry;
begin
  if (Index >= 0) and (Index < Length(FEntries)) then
    Result := FEntries[Index]
  else
    Result := nil;
end;

function TLocalContainer.GetTitle: string;
begin
  Result := FPath;
end;

procedure TLocalContainer.Refresh;
begin
  Scan;
end;

function TLocalContainer.Import(ASource: ICopySource; const AName: string): Boolean;
var
  FS: TFileStream;
  SafeName: string;
begin
  Result := False;
  SafeName := ExtractFileName(AName);
  if (SafeName = '') or (SafeName = '.') or (SafeName = '..') then Exit;
  if SafeName <> AName then Exit;
  FS := TFileStream.Create(FPath + PathDelim + SafeName, fmCreate);
  try
    ASource.CopyTo(FS);
    Result := True;
  finally
    FS.Free;
  end;
  Refresh;
end;

function TLocalContainer.FullPath: string;
begin
  Result := FPath;
end;

end.
