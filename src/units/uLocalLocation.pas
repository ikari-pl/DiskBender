unit uLocalLocation;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, DateUtils, uVFS
  {$IFDEF UNIX}, BaseUnix{$ENDIF};

type
  TFileEntryFactory = function(const AFullPath: string): IEntry;

var
  FileEntryHook: TFileEntryFactory = nil;

type
  TLocalEntryArray = array of IEntry;

  { A file on the host filesystem. }
  TLocalFileEntry = class(TInterfacedObject, IEntry, ISizeable, ICopySource, IDated)
  strict private
    FName: string;
    FFullPath: string;
    FSize: Int64;
    FModified: TDateTime;
    FCreated: TDateTime;
    FAvailDates: TDateKindSet;
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
    { IDated }
    function GetAvailableDates: TDateKindSet;
    function GetDate(AKind: TDateKind): TDateTime;
    property FullPath: string read FFullPath;
  end;

  { A subdirectory on the host filesystem. Both an entry and a container. }
  TLocalDirEntry = class(TInterfacedObject, IEntry, IContainer, ISortable, IDated)
  strict private
    FName: string;
    FFullPath: string;
    FEntries: TLocalEntryArray;
    FScanned: Boolean;
    FModified: TDateTime;
    FCreated: TDateTime;
    FAvailDates: TDateKindSet;
    procedure Scan;
    procedure LoadDates;
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
    { ISortable }
    procedure Sort(AField: TSortField; Ascending: Boolean; DirsFirst: Boolean);
    { IDated }
    function GetAvailableDates: TDateKindSet;
    function GetDate(AKind: TDateKind): TDateTime;
  end;

  { The root container for a host directory — what fills a pane.
    Identical to TLocalDirEntry but scans eagerly and sets the
    display title to the full path. }
  TLocalContainer = class(TInterfacedObject, IEntry, IContainer, ICopyTarget, ISortable)
  strict private
    FPath: string;
    FEntries: TLocalEntryArray;
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
    { ISortable }
    procedure Sort(AField: TSortField; Ascending: Boolean; DirsFirst: Boolean);
    { Navigation helper }
    function FullPath: string;
  end;

implementation

{ ── TLocalFileEntry ───────────────────────────────────────────── }

constructor TLocalFileEntry.Create(const AFullPath: string);
var
  SR: TSearchRec;
  {$IFDEF UNIX}
  Info: BaseUnix.Stat;
  {$ENDIF}
begin
  inherited Create;
  FFullPath := AFullPath;
  FName := ExtractFileName(AFullPath);
  FSize := 0;
  FModified := 0;
  FCreated := 0;
  FAvailDates := [];
  if FindFirst(AFullPath, faAnyFile, SR) = 0 then
  begin
    FSize := SR.Size;
    FModified := FileDateToDateTime(SR.Time);
    Include(FAvailDates, dkModification);
    FindClose(SR);
  end;
  {$IFDEF UNIX}
  if fpstat(AFullPath, Info) = 0 then
  begin
    FModified := UnixToDateTime(Info.st_mtime);
    Include(FAvailDates, dkModification);
    {$IFDEF DARWIN}
    FCreated := UnixToDateTime(Info.st_birthtime);
    Include(FAvailDates, dkCreation);
    {$ENDIF}
  end;
  {$ENDIF}
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

function TLocalFileEntry.GetAvailableDates: TDateKindSet;
begin
  Result := FAvailDates;
end;

function TLocalFileEntry.GetDate(AKind: TDateKind): TDateTime;
begin
  case AKind of
    dkCreation: Result := FCreated;
    dkModification: Result := FModified;
  else
    Result := 0;
  end;
end;

{ ── TLocalDirEntry ────────────────────────────────────────────── }

procedure TLocalDirEntry.LoadDates;
{$IFDEF UNIX}
var
  Info: BaseUnix.Stat;
{$ENDIF}
begin
  FModified := 0;
  FCreated := 0;
  FAvailDates := [];
  {$IFDEF UNIX}
  if fpstat(FFullPath, Info) = 0 then
  begin
    FModified := UnixToDateTime(Info.st_mtime);
    Include(FAvailDates, dkModification);
    {$IFDEF DARWIN}
    FCreated := UnixToDateTime(Info.st_birthtime);
    Include(FAvailDates, dkCreation);
    {$ENDIF}
  end;
  {$ENDIF}
end;

constructor TLocalDirEntry.Create(const AFullPath: string);
begin
  inherited Create;
  FFullPath := AFullPath;
  FName := ExtractFileName(AFullPath);
  FScanned := False;
  LoadDates;
end;

constructor TLocalDirEntry.CreateParent(const AChildDir: string);
begin
  inherited Create;
  FFullPath := ExtractFileDir(AChildDir);
  FName := '..';
  FScanned := False;
  LoadDates;
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
    Result := '<' + FName + '>';   { dirs in <angle> brackets; [..] is reserved for GUARD pseudo-entries }
end;

procedure TLocalDirEntry.Scan;
var
  SR: TSearchRec;
  ChildPath: string;
  HookEntry: IEntry;
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
      begin
        HookEntry := nil;
        if Assigned(FileEntryHook) then
          HookEntry := FileEntryHook(ChildPath);
        if HookEntry <> nil then
          FEntries[High(FEntries)] := HookEntry
        else
          FEntries[High(FEntries)] := TLocalFileEntry.Create(ChildPath);
      end;
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

{ ── Shared sort ──────────────────────────────────────────────── }

procedure SortEntryArray(var A: TLocalEntryArray; AField: TSortField;
                         AAscending: Boolean; ADirsFirst: Boolean);
var
  StartIdx: Integer;

  function IsDir(E: IEntry): Boolean;
  begin
    Result := Supports(E, IContainer);
  end;

  function CompareDates(const L, R: IEntry; AKind: TDateKind): Integer;
  var
    DL, DR: IDated;
    DtL, DtR: TDateTime;
  begin
    DtL := 0; DtR := 0;
    if Supports(L, IDated, DL) and (AKind in DL.GetAvailableDates) then
      DtL := DL.GetDate(AKind);
    if Supports(R, IDated, DR) and (AKind in DR.GetAvailableDates) then
      DtR := DR.GetDate(AKind);
    if DtL < DtR then Result := -1
    else if DtL > DtR then Result := 1
    else Result := CompareText(L.GetName, R.GetName);
  end;

  function CompareEntries(const L, R: IEntry): Integer;
  var
    SL, SR: ISizeable;
    ExtL, ExtR: string;
    DirL, DirR: Boolean;
  begin
    DirL := IsDir(L);
    DirR := IsDir(R);
    if ADirsFirst then
    begin
      if DirL and not DirR then begin Result := -1; Exit; end;
      if not DirL and DirR then begin Result := 1; Exit; end;
    end;

    case AField of
      sfExtension:
      begin
        ExtL := LowerCase(ExtractFileExt(L.GetName));
        ExtR := LowerCase(ExtractFileExt(R.GetName));
        Result := CompareText(ExtL, ExtR);
        if Result = 0 then
          Result := CompareText(L.GetName, R.GetName);
      end;
      sfSize:
      begin
        Result := 0;
        if Supports(L, ISizeable, SL) and Supports(R, ISizeable, SR) then
        begin
          if SL.GetSize < SR.GetSize then Result := -1
          else if SL.GetSize > SR.GetSize then Result := 1;
        end;
        if Result = 0 then
          Result := CompareText(L.GetName, R.GetName);
      end;
      sfDateModified, sfDate:
        Result := CompareDates(L, R, dkModification);
      sfDateCreated:
        Result := CompareDates(L, R, dkCreation);
    else
      Result := CompareText(L.GetName, R.GetName);
    end;

    if not AAscending then Result := -Result;
  end;

  procedure QSort(Lo, Hi: Integer);
  var
    I, J: Integer;
    Pivot, Tmp: IEntry;
  begin
    if Lo >= Hi then Exit;
    Pivot := A[(Lo + Hi) div 2];
    I := Lo;
    J := Hi;
    while I <= J do
    begin
      while CompareEntries(A[I], Pivot) < 0 do Inc(I);
      while CompareEntries(A[J], Pivot) > 0 do Dec(J);
      if I <= J then
      begin
        Tmp := A[I];
        A[I] := A[J];
        A[J] := Tmp;
        Inc(I);
        Dec(J);
      end;
    end;
    if Lo < J then QSort(Lo, J);
    if I < Hi then QSort(I, Hi);
  end;

begin
  if Length(A) <= 1 then Exit;
  StartIdx := 0;
  if A[0].GetName = '..' then
    StartIdx := 1;
  if StartIdx <= High(A) then
    QSort(StartIdx, High(A));
end;

procedure TLocalDirEntry.Sort(AField: TSortField; Ascending: Boolean; DirsFirst: Boolean);
begin
  if not FScanned then Scan;
  SortEntryArray(FEntries, AField, Ascending, DirsFirst);
end;

function TLocalDirEntry.GetAvailableDates: TDateKindSet;
begin
  Result := FAvailDates;
end;

function TLocalDirEntry.GetDate(AKind: TDateKind): TDateTime;
begin
  case AKind of
    dkCreation: Result := FCreated;
    dkModification: Result := FModified;
  else
    Result := 0;
  end;
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
  HookEntry: IEntry;
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
      begin
        HookEntry := nil;
        if Assigned(FileEntryHook) then
          HookEntry := FileEntryHook(ChildPath);
        if HookEntry <> nil then
          FEntries[High(FEntries)] := HookEntry
        else
          FEntries[High(FEntries)] := TLocalFileEntry.Create(ChildPath);
      end;
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

procedure TLocalContainer.Sort(AField: TSortField; Ascending: Boolean; DirsFirst: Boolean);
begin
  SortEntryArray(FEntries, AField, Ascending, DirsFirst);
end;

function TLocalContainer.FullPath: string;
begin
  Result := FPath;
end;

end.
