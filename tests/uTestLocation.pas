unit uTestLocation;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, uVFS;

type
  TTestFileEntry = class(TInterfacedObject, IEntry, ISizeable, ICopySource,
                         IDeletable, IRestorable)
  strict private
    FName: string;
    FSize: Int64;
    FDeleted: Boolean;
    FContent: string;
  public
    constructor Create(const AName: string; ASize: Int64; const AContent: string = '');
    function GetName: string;
    function GetDisplayName: string;
    function GetSize: Int64;
    function GetSizeUnit: TSizeUnit;
    procedure CopyTo(AStream: TStream);
    function GetIsDeleted: Boolean;
    procedure Delete;
    procedure Restore;
  end;

  TTestDirEntry = class(TInterfacedObject, IEntry, IContainer)
  strict private
    FName: string;
    FEntries: array of IEntry;
  public
    constructor Create(const AName: string; const AEntries: array of IEntry);
    function GetName: string;
    function GetDisplayName: string;
    function GetEntryCount: Integer;
    function GetEntry(Index: Integer): IEntry;
    function GetTitle: string;
    procedure Refresh;
  end;

  TTestContainer = class(TInterfacedObject, IEntry, IContainer, ICopyTarget)
  strict private
    FTitle: string;
    FEntries: array of IEntry;
  public
    constructor Create(const ATitle: string; const AEntries: array of IEntry);
    function GetName: string;
    function GetDisplayName: string;
    function GetEntryCount: Integer;
    function GetEntry(Index: Integer): IEntry;
    function GetTitle: string;
    procedure Refresh;
    function Import(ASource: ICopySource; const AName: string): Boolean;
    procedure AddEntry(AEntry: IEntry);
  end;

implementation

{ ── TTestFileEntry ───────────────────────────────────────────── }

constructor TTestFileEntry.Create(const AName: string; ASize: Int64; const AContent: string = '');
begin
  inherited Create;
  FName := AName;
  FSize := ASize;
  FDeleted := False;
  FContent := AContent;
end;

function TTestFileEntry.GetName: string;
begin
  Result := FName;
end;

function TTestFileEntry.GetDisplayName: string;
begin
  if FDeleted then
    Result := '?' + Copy(FName, 2, MaxInt)
  else
    Result := FName;
end;

function TTestFileEntry.GetSize: Int64;
begin
  Result := FSize;
end;

function TTestFileEntry.GetSizeUnit: TSizeUnit;
begin
  Result := suBytes;
end;

procedure TTestFileEntry.CopyTo(AStream: TStream);
begin
  if FContent <> '' then
    AStream.WriteBuffer(FContent[1], Length(FContent));
end;

function TTestFileEntry.GetIsDeleted: Boolean;
begin
  Result := FDeleted;
end;

procedure TTestFileEntry.Delete;
begin
  FDeleted := True;
end;

procedure TTestFileEntry.Restore;
begin
  FDeleted := False;
end;

{ ── TTestDirEntry ────────────────────────────────────────────── }

constructor TTestDirEntry.Create(const AName: string; const AEntries: array of IEntry);
var
  I: Integer;
begin
  inherited Create;
  FName := AName;
  SetLength(FEntries, Length(AEntries));
  for I := 0 to High(AEntries) do
    FEntries[I] := AEntries[I];
end;

function TTestDirEntry.GetName: string;
begin
  Result := FName;
end;

function TTestDirEntry.GetDisplayName: string;
begin
  Result := '[' + FName + ']';
end;

function TTestDirEntry.GetEntryCount: Integer;
begin
  Result := Length(FEntries);
end;

function TTestDirEntry.GetEntry(Index: Integer): IEntry;
begin
  if (Index >= 0) and (Index < Length(FEntries)) then
    Result := FEntries[Index]
  else
    Result := nil;
end;

function TTestDirEntry.GetTitle: string;
begin
  Result := FName;
end;

procedure TTestDirEntry.Refresh;
begin
  { Static in tests }
end;

{ ── TTestContainer ───────────────────────────────────────────── }

constructor TTestContainer.Create(const ATitle: string; const AEntries: array of IEntry);
var
  I: Integer;
begin
  inherited Create;
  FTitle := ATitle;
  SetLength(FEntries, Length(AEntries));
  for I := 0 to High(AEntries) do
    FEntries[I] := AEntries[I];
end;

function TTestContainer.GetName: string;
begin
  Result := FTitle;
end;

function TTestContainer.GetDisplayName: string;
begin
  Result := FTitle;
end;

function TTestContainer.GetEntryCount: Integer;
begin
  Result := Length(FEntries);
end;

function TTestContainer.GetEntry(Index: Integer): IEntry;
begin
  if (Index >= 0) and (Index < Length(FEntries)) then
    Result := FEntries[Index]
  else
    Result := nil;
end;

function TTestContainer.GetTitle: string;
begin
  Result := FTitle;
end;

procedure TTestContainer.Refresh;
begin
  { Static in tests }
end;

function TTestContainer.Import(ASource: ICopySource; const AName: string): Boolean;
var
  MS: TMemoryStream;
begin
  MS := TMemoryStream.Create;
  try
    ASource.CopyTo(MS);
    Result := True;
  finally
    MS.Free;
  end;
end;

procedure TTestContainer.AddEntry(AEntry: IEntry);
begin
  SetLength(FEntries, Length(FEntries) + 1);
  FEntries[High(FEntries)] := AEntry;
end;

end.
