unit uLocalFS;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes;

type
  TLocalFile = record
    Name: string;
    Size: Int64;
    IsDir: Boolean;
    Attr: Integer;
  end;

  TLocalFS = class
  private
    FCurrentDir: string;
    FFiles: array of TLocalFile;
    procedure Scan;
  public
    constructor Create(const ADir: string);
    procedure SetDir(const ADir: string);
    function GetFile(Index: Integer): TLocalFile;
    function Count: Integer;
    property CurrentDir: string read FCurrentDir;
  end;

implementation

constructor TLocalFS.Create(const ADir: string);
begin
  FCurrentDir := ExpandFileName(ADir);
  Scan;
end;

procedure TLocalFS.SetDir(const ADir: string);
begin
  FCurrentDir := ExpandFileName(ADir);
  Scan;
end;

procedure TLocalFS.Scan;
var
  SR: TSearchRec;
  Idx: Integer;
begin
  SetLength(FFiles, 0);
  Idx := 0;
  
  { Add ".." entry if not at root }
  if FCurrentDir <> '/' then
  begin
    SetLength(FFiles, Idx + 1);
    FFiles[Idx].Name := '..';
    FFiles[Idx].IsDir := True;
    FFiles[Idx].Size := 0;
    Inc(Idx);
  end;

  if FindFirst(FCurrentDir + '/*', faAnyFile, SR) = 0 then
  begin
    repeat
      if (SR.Name <> '.') and (SR.Name <> '..') then
      begin
        SetLength(FFiles, Idx + 1);
        FFiles[Idx].Name := SR.Name;
        FFiles[Idx].IsDir := (SR.Attr and faDirectory) <> 0;
        FFiles[Idx].Size := SR.Size;
        FFiles[Idx].Attr := SR.Attr;
        Inc(Idx);
      end;
    until FindNext(SR) <> 0;
    FindClose(SR);
  end;
end;

function TLocalFS.Count: Integer;
begin
  Result := Length(FFiles);
end;

function TLocalFS.GetFile(Index: Integer): TLocalFile;
begin
  if (Index >= 0) and (Index < Length(FFiles)) then
    Result := FFiles[Index]
  else
    FillChar(Result, SizeOf(Result), 0);
end;

end.
