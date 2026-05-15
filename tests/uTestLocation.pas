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

  TTestRenameableEntry = class(TInterfacedObject, IEntry, ISizeable, ICopySource,
                               IRenameable)
  strict private
    FName: string;
    FSize: Int64;
  public
    constructor Create(const AName: string; ASize: Int64);
    function GetName: string;
    function GetDisplayName: string;
    function GetSize: Int64;
    function GetSizeUnit: TSizeUnit;
    procedure CopyTo(AStream: TStream);
    procedure Rename(const NewName: string);
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

  TTestSortableContainer = class(TInterfacedObject, IEntry, IContainer, ISortable)
  strict private
    FTitle: string;
    FEntries: array of IEntry;
    FSorted: Boolean;
    FLastSortField: TSortField;
    FLastDirsFirst: Boolean;
  public
    constructor Create(const ATitle: string; const AEntries: array of IEntry);
    function GetName: string;
    function GetDisplayName: string;
    function GetEntryCount: Integer;
    function GetEntry(Index: Integer): IEntry;
    function GetTitle: string;
    procedure Refresh;
    procedure Sort(AField: TSortField; Ascending: Boolean; DirsFirst: Boolean);
    property Sorted: Boolean read FSorted;
    property LastSortField: TSortField read FLastSortField;
    property LastDirsFirst: Boolean read FLastDirsFirst;
  end;

  TTestWritableContainer = class(TInterfacedObject, IEntry, IContainer, IWritable,
                                 ICopyTarget)
  strict private
    FTitle: string;
    FEntries: array of IEntry;
    FModified: Boolean;
    FSaveCalled: Boolean;
    FRevertCalled: Boolean;
  public
    constructor Create(const ATitle: string; const AEntries: array of IEntry);
    function GetName: string;
    function GetDisplayName: string;
    function GetEntryCount: Integer;
    function GetEntry(Index: Integer): IEntry;
    function GetTitle: string;
    procedure Refresh;
    function GetModified: Boolean;
    procedure Save;
    procedure Revert;
    function Import(ASource: ICopySource; const AName: string): Boolean;
    procedure SetModified(AValue: Boolean);
    property SaveCalled: Boolean read FSaveCalled;
    property RevertCalled: Boolean read FRevertCalled;
  end;

  TTestFullContainer = class(TInterfacedObject, IEntry, IContainer, ISortable,
                             IBlockMappable, IWritable, ISummary, ICopyTarget)
  strict private
    FTitle: string;
    FEntries: array of IEntry;
    FSorted: Boolean;
    FLastSortField: TSortField;
    FLastDirsFirst: Boolean;
    FModified: Boolean;
    FSaveCalled: Boolean;
  public
    constructor Create(const ATitle: string; const AEntries: array of IEntry);
    function GetName: string;
    function GetDisplayName: string;
    function GetEntryCount: Integer;
    function GetEntry(Index: Integer): IEntry;
    function GetTitle: string;
    procedure Refresh;
    procedure Sort(AField: TSortField; Ascending: Boolean; DirsFirst: Boolean);
    function GetBlockMap: TBytes;
    function GetBlockCount: Integer;
    function GetModified: Boolean;
    procedure Save;
    procedure Revert;
    function GetSummaryInfo: string;
    function Import(ASource: ICopySource; const AName: string): Boolean;
    procedure SetModified(AValue: Boolean);
    property Sorted: Boolean read FSorted;
    property LastSortField: TSortField read FLastSortField;
    property LastDirsFirst: Boolean read FLastDirsFirst;
    property SaveCalled: Boolean read FSaveCalled;
  end;

  TTestDatedEntry = class(TInterfacedObject, IEntry, ISizeable, ICopySource, IDated)
  strict private
    FName: string;
    FSize: Int64;
    FModified: TDateTime;
    FCreated: TDateTime;
    FAvailDates: TDateKindSet;
  public
    constructor Create(const AName: string; ASize: Int64;
                       AModified: TDateTime; ACreated: TDateTime = 0);
    function GetName: string;
    function GetDisplayName: string;
    function GetSize: Int64;
    function GetSizeUnit: TSizeUnit;
    procedure CopyTo(AStream: TStream);
    function GetAvailableDates: TDateKindSet;
    function GetDate(AKind: TDateKind): TDateTime;
  end;

  { Test entry that owns a specific list of blocks AND/OR sectors in its
    parent container's maps. Used to drive Block/Sector Map pane highlight
    tests. A sector ref is (track, sectorID). }
  TTestOwningEntry = class(TInterfacedObject, IEntry, ISizeable, ICopySource,
                           IBlockOwning, ISectorOwning)
  strict private
    FName: string;
    FOwned: TBlockNumberArray;
    FOwnedSectors: TPhysicalSectorArray;
  public
    constructor Create(const AName: string; const AOwnedBlocks: array of Word);
    procedure SetOwnedSectors(const APairs: array of Byte);
    function GetName: string;
    function GetDisplayName: string;
    function GetSize: Int64;
    function GetSizeUnit: TSizeUnit;
    procedure CopyTo(AStream: TStream);
    function GetOwnedBlocks: TBlockNumberArray;
    function GetOwnedSectors: TPhysicalSectorArray;
  end;

  TTestUserEntry = class(TInterfacedObject, IEntry, ISizeable, ICopySource,
                         IUserArea, IAttributed)
  strict private
    FName: string;
    FSize: Int64;
    FUser: Byte;
    FAttrs: TEntryAttributes;
  public
    constructor Create(const AName: string; ASize: Int64; AUser: Byte); overload;
    constructor Create(const AName: string; ASize: Int64; AUser: Byte;
                       AAttrs: TEntryAttributes); overload;
    function GetName: string;
    function GetDisplayName: string;
    function GetSize: Int64;
    function GetSizeUnit: TSizeUnit;
    procedure CopyTo(AStream: TStream);
    function GetUser: Byte;
    { IAttributed }
    function GetAttributes: TEntryAttributes;
    procedure SetAttributes(AValue: TEntryAttributes);
  end;

  TTestSectorContainer = class(TInterfacedObject, IEntry, IContainer, ISortable,
                               IBlockMappable, IWritable, ISummary, ICopyTarget,
                               ISectorMappable)
  strict private
    FTitle: string;
    FEntries: array of IEntry;
    FSorted: Boolean;
    FLastSortField: TSortField;
    FModified: Boolean;
  public
    constructor Create(const ATitle: string; const AEntries: array of IEntry);
    function GetName: string;
    function GetDisplayName: string;
    function GetEntryCount: Integer;
    function GetEntry(Index: Integer): IEntry;
    function GetTitle: string;
    procedure Refresh;
    procedure Sort(AField: TSortField; Ascending: Boolean; DirsFirst: Boolean);
    function GetBlockMap: TBytes;
    function GetBlockCount: Integer;
    function GetModified: Boolean;
    procedure Save;
    procedure Revert;
    function GetSummaryInfo: string;
    function Import(ASource: ICopySource; const AName: string): Boolean;
    function GetSectorMap: TTrackColumnArray;
    property Sorted: Boolean read FSorted;
    property LastSortField: TSortField read FLastSortField;
  end;

  { Sector container where tracks have different sector counts.
    Track 0: 9 sectors (boot), Track 1: 5 sectors (data).
    Used by TestSectorMapHeterogeneousLayout (I6). }
  TTestHeteroSectorContainer = class(TInterfacedObject, IEntry, IContainer,
                                     ISectorMappable)
  strict private
    FTitle: string;
  public
    constructor Create(const ATitle: string);
    function GetName: string;
    function GetDisplayName: string;
    function GetEntryCount: Integer;
    function GetEntry(Index: Integer): IEntry;
    function GetTitle: string;
    procedure Refresh;
    function GetSectorMap: TTrackColumnArray;
  end;

  TTestExpandableEntry = class(TInterfacedObject, IEntry, ISizeable, ICopySource,
                                IExpandable)
  strict private
    FName: string;
    FSize: Int64;
    FContainer: IContainer;
  public
    constructor Create(const AName: string; ASize: Int64; AContainer: IContainer);
    function GetName: string;
    function GetDisplayName: string;
    function GetSize: Int64;
    function GetSizeUnit: TSizeUnit;
    procedure CopyTo(AStream: TStream);
    function Expand: IContainer;
  end;

  { ICopySource whose CopyTo always raises — used to test TUI exception handling }
  TTestThrowingEntry = class(TInterfacedObject, IEntry, ISizeable, ICopySource)
  strict private
    FName: string;
    FSize: Int64;
  public
    constructor Create(const AName: string; ASize: Int64);
    function GetName: string;
    function GetDisplayName: string;
    function GetSize: Int64;
    function GetSizeUnit: TSizeUnit;
    procedure CopyTo(AStream: TStream);
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

{ ── TTestRenameableEntry ────────────────────────────────────── }

constructor TTestRenameableEntry.Create(const AName: string; ASize: Int64);
begin
  inherited Create;
  FName := AName;
  FSize := ASize;
end;

function TTestRenameableEntry.GetName: string;
begin
  Result := FName;
end;

function TTestRenameableEntry.GetDisplayName: string;
begin
  Result := FName;
end;

function TTestRenameableEntry.GetSize: Int64;
begin
  Result := FSize;
end;

function TTestRenameableEntry.GetSizeUnit: TSizeUnit;
begin
  Result := suBytes;
end;

procedure TTestRenameableEntry.CopyTo(AStream: TStream);
begin
  { empty }
end;

procedure TTestRenameableEntry.Rename(const NewName: string);
begin
  FName := NewName;
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
  Result := '<' + FName + '>';
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

{ ── TTestSortableContainer ──────────────────────────────────── }

constructor TTestSortableContainer.Create(const ATitle: string; const AEntries: array of IEntry);
var
  I: Integer;
begin
  inherited Create;
  FTitle := ATitle;
  SetLength(FEntries, Length(AEntries));
  for I := 0 to High(AEntries) do
    FEntries[I] := AEntries[I];
  FSorted := False;
end;

function TTestSortableContainer.GetName: string;
begin
  Result := FTitle;
end;

function TTestSortableContainer.GetDisplayName: string;
begin
  Result := FTitle;
end;

function TTestSortableContainer.GetEntryCount: Integer;
begin
  Result := Length(FEntries);
end;

function TTestSortableContainer.GetEntry(Index: Integer): IEntry;
begin
  if (Index >= 0) and (Index < Length(FEntries)) then
    Result := FEntries[Index]
  else
    Result := nil;
end;

function TTestSortableContainer.GetTitle: string;
begin
  Result := FTitle;
end;

procedure TTestSortableContainer.Refresh;
begin
  { Static in tests }
end;

procedure TTestSortableContainer.Sort(AField: TSortField; Ascending: Boolean; DirsFirst: Boolean);
begin
  FSorted := True;
  FLastSortField := AField;
  FLastDirsFirst := DirsFirst;
end;

{ ── TTestWritableContainer ──────────────────────────────────── }

constructor TTestWritableContainer.Create(const ATitle: string; const AEntries: array of IEntry);
var
  I: Integer;
begin
  inherited Create;
  FTitle := ATitle;
  SetLength(FEntries, Length(AEntries));
  for I := 0 to High(AEntries) do
    FEntries[I] := AEntries[I];
  FModified := False;
  FSaveCalled := False;
  FRevertCalled := False;
end;

function TTestWritableContainer.GetName: string;
begin
  Result := FTitle;
end;

function TTestWritableContainer.GetDisplayName: string;
begin
  Result := FTitle;
end;

function TTestWritableContainer.GetEntryCount: Integer;
begin
  Result := Length(FEntries);
end;

function TTestWritableContainer.GetEntry(Index: Integer): IEntry;
begin
  if (Index >= 0) and (Index < Length(FEntries)) then
    Result := FEntries[Index]
  else
    Result := nil;
end;

function TTestWritableContainer.GetTitle: string;
begin
  Result := FTitle;
end;

procedure TTestWritableContainer.Refresh;
begin
  { Static in tests }
end;

function TTestWritableContainer.GetModified: Boolean;
begin
  Result := FModified;
end;

procedure TTestWritableContainer.Save;
begin
  FSaveCalled := True;
  FModified := False;
end;

procedure TTestWritableContainer.Revert;
begin
  FRevertCalled := True;
  FModified := False;
end;

function TTestWritableContainer.Import(ASource: ICopySource; const AName: string): Boolean;
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

procedure TTestWritableContainer.SetModified(AValue: Boolean);
begin
  FModified := AValue;
end;

{ ── TTestFullContainer ──────────────────────────────────────── }

constructor TTestFullContainer.Create(const ATitle: string; const AEntries: array of IEntry);
var
  I: Integer;
begin
  inherited Create;
  FTitle := ATitle;
  SetLength(FEntries, Length(AEntries));
  for I := 0 to High(AEntries) do
    FEntries[I] := AEntries[I];
  FSorted := False;
  FModified := False;
  FSaveCalled := False;
end;

function TTestFullContainer.GetName: string;
begin
  Result := FTitle;
end;

function TTestFullContainer.GetDisplayName: string;
begin
  Result := FTitle;
end;

function TTestFullContainer.GetEntryCount: Integer;
begin
  Result := Length(FEntries);
end;

function TTestFullContainer.GetEntry(Index: Integer): IEntry;
begin
  if (Index >= 0) and (Index < Length(FEntries)) then
    Result := FEntries[Index]
  else
    Result := nil;
end;

function TTestFullContainer.GetTitle: string;
begin
  Result := FTitle;
end;

procedure TTestFullContainer.Refresh;
begin
  { Static in tests }
end;

procedure TTestFullContainer.Sort(AField: TSortField; Ascending: Boolean; DirsFirst: Boolean);
begin
  FSorted := True;
  FLastSortField := AField;
  FLastDirsFirst := DirsFirst;
end;

function TTestFullContainer.GetBlockMap: TBytes;
var
  I: Integer;
begin
  SetLength(Result, 16);
  for I := 0 to 15 do
    Result[I] := I mod 4;
end;

function TTestFullContainer.GetBlockCount: Integer;
begin
  Result := 16;
end;

function TTestFullContainer.GetModified: Boolean;
begin
  Result := FModified;
end;

procedure TTestFullContainer.Save;
begin
  FSaveCalled := True;
  FModified := False;
end;

procedure TTestFullContainer.Revert;
begin
  FModified := False;
end;

function TTestFullContainer.GetSummaryInfo: string;
begin
  Result := 'Test disk: 40 tracks, 9 sectors';
end;

function TTestFullContainer.Import(ASource: ICopySource; const AName: string): Boolean;
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

procedure TTestFullContainer.SetModified(AValue: Boolean);
begin
  FModified := AValue;
end;

{ ── TTestDatedEntry ─────────────────────────────────────────── }

constructor TTestDatedEntry.Create(const AName: string; ASize: Int64;
                                   AModified: TDateTime; ACreated: TDateTime = 0);
begin
  inherited Create;
  FName := AName;
  FSize := ASize;
  FModified := AModified;
  FCreated := ACreated;
  FAvailDates := [dkModification];
  if ACreated <> 0 then
    Include(FAvailDates, dkCreation);
end;

function TTestDatedEntry.GetName: string;
begin
  Result := FName;
end;

function TTestDatedEntry.GetDisplayName: string;
begin
  Result := FName;
end;

function TTestDatedEntry.GetSize: Int64;
begin
  Result := FSize;
end;

function TTestDatedEntry.GetSizeUnit: TSizeUnit;
begin
  Result := suBytes;
end;

procedure TTestDatedEntry.CopyTo(AStream: TStream);
begin
  { empty }
end;

function TTestDatedEntry.GetAvailableDates: TDateKindSet;
begin
  Result := FAvailDates;
end;

function TTestDatedEntry.GetDate(AKind: TDateKind): TDateTime;
begin
  case AKind of
    dkCreation: Result := FCreated;
    dkModification: Result := FModified;
  else
    Result := 0;
  end;
end;

{ ── TTestUserEntry ──────────────────────────────────────────── }

{ ── TTestOwningEntry ────────────────────────────────────────── }

constructor TTestOwningEntry.Create(const AName: string;
                                    const AOwnedBlocks: array of Word);
var
  I: Integer;
begin
  inherited Create;
  FName := AName;
  SetLength(FOwned, Length(AOwnedBlocks));
  for I := 0 to High(AOwnedBlocks) do
    FOwned[I] := AOwnedBlocks[I];
end;

function TTestOwningEntry.GetName: string;
begin Result := FName; end;

function TTestOwningEntry.GetDisplayName: string;
begin Result := FName; end;

function TTestOwningEntry.GetSize: Int64;
begin Result := 0; end;

function TTestOwningEntry.GetSizeUnit: TSizeUnit;
begin Result := suBytes; end;

procedure TTestOwningEntry.CopyTo(AStream: TStream);
begin
  { empty -- present only because some helpers expect ICopySource. }
end;

function TTestOwningEntry.GetOwnedBlocks: TBlockNumberArray;
var I: Integer;
begin
  SetLength(Result, Length(FOwned));
  for I := 0 to High(FOwned) do Result[I] := FOwned[I];
end;

{ APairs is flattened [track0, sectorID0, track1, sectorID1, ...]. Odd
  length is silently truncated to the last full pair. }
procedure TTestOwningEntry.SetOwnedSectors(const APairs: array of Byte);
var
  I, N: Integer;
begin
  N := Length(APairs) div 2;
  SetLength(FOwnedSectors, N);
  for I := 0 to N - 1 do
  begin
    FOwnedSectors[I].TrackIdx := APairs[I * 2];
    FOwnedSectors[I].SectorID := APairs[I * 2 + 1];
  end;
end;

function TTestOwningEntry.GetOwnedSectors: TPhysicalSectorArray;
var I: Integer;
begin
  SetLength(Result, Length(FOwnedSectors));
  for I := 0 to High(FOwnedSectors) do Result[I] := FOwnedSectors[I];
end;

{ ── TTestUserEntry ───────────────────────────────────────────── }

constructor TTestUserEntry.Create(const AName: string; ASize: Int64; AUser: Byte);
begin
  inherited Create;
  FName := AName;
  FSize := ASize;
  FUser := AUser;
  FAttrs := [];
end;

constructor TTestUserEntry.Create(const AName: string; ASize: Int64; AUser: Byte;
                                  AAttrs: TEntryAttributes);
begin
  inherited Create;
  FName := AName;
  FSize := ASize;
  FUser := AUser;
  FAttrs := AAttrs;
end;

function TTestUserEntry.GetAttributes: TEntryAttributes;
begin
  Result := FAttrs;
end;

procedure TTestUserEntry.SetAttributes(AValue: TEntryAttributes);
begin
  FAttrs := AValue;
end;

function TTestUserEntry.GetName: string;
begin
  Result := FName;
end;

function TTestUserEntry.GetDisplayName: string;
begin
  Result := IntToStr(FUser) + ':' + FName;
end;

function TTestUserEntry.GetSize: Int64;
begin
  Result := FSize;
end;

function TTestUserEntry.GetSizeUnit: TSizeUnit;
begin
  Result := suBytes;
end;

procedure TTestUserEntry.CopyTo(AStream: TStream);
begin
  { empty }
end;

function TTestUserEntry.GetUser: Byte;
begin
  Result := FUser;
end;

{ ── TTestSectorContainer ────────────────────────────────────── }

constructor TTestSectorContainer.Create(const ATitle: string; const AEntries: array of IEntry);
var
  I: Integer;
begin
  inherited Create;
  FTitle := ATitle;
  SetLength(FEntries, Length(AEntries));
  for I := 0 to High(AEntries) do
    FEntries[I] := AEntries[I];
  FSorted := False;
  FModified := False;
end;

function TTestSectorContainer.GetName: string;
begin
  Result := FTitle;
end;

function TTestSectorContainer.GetDisplayName: string;
begin
  Result := FTitle;
end;

function TTestSectorContainer.GetEntryCount: Integer;
begin
  Result := Length(FEntries);
end;

function TTestSectorContainer.GetEntry(Index: Integer): IEntry;
begin
  if (Index >= 0) and (Index < Length(FEntries)) then
    Result := FEntries[Index]
  else
    Result := nil;
end;

function TTestSectorContainer.GetTitle: string;
begin
  Result := FTitle;
end;

procedure TTestSectorContainer.Refresh;
begin
end;

procedure TTestSectorContainer.Sort(AField: TSortField; Ascending: Boolean; DirsFirst: Boolean);
begin
  FSorted := True;
  FLastSortField := AField;
end;

function TTestSectorContainer.GetBlockMap: TBytes;
var
  I: Integer;
begin
  SetLength(Result, 16);
  for I := 0 to 15 do
    Result[I] := I mod 4;
end;

function TTestSectorContainer.GetBlockCount: Integer;
begin
  Result := 16;
end;

function TTestSectorContainer.GetModified: Boolean;
begin
  Result := FModified;
end;

procedure TTestSectorContainer.Save;
begin
  FModified := False;
end;

procedure TTestSectorContainer.Revert;
begin
  FModified := False;
end;

function TTestSectorContainer.GetSummaryInfo: string;
begin
  Result := 'Test: 3 tracks, 9 sectors';
end;

function TTestSectorContainer.Import(ASource: ICopySource; const AName: string): Boolean;
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

function TTestSectorContainer.GetSectorMap: TTrackColumnArray;
var
  I, J: Integer;
begin
  SetLength(Result, 3);
  for I := 0 to 2 do
  begin
    Result[I].TrackNum := I;
    Result[I].SideNum := 0;
    Result[I].FillerByte := $E5;
    SetLength(Result[I].Sectors, 9);
    for J := 0 to 8 do
    begin
      Result[I].Sectors[J].SectorID := $C1 + J;
      Result[I].Sectors[J].SizeBytes := 512;
      Result[I].Sectors[J].FDCSt1 := 0;
      Result[I].Sectors[J].FDCSt2 := 0;
      if I = 0 then
        Result[I].Sectors[J].State := ssBoot
      else if (I = 1) and (J < 4) then
        Result[I].Sectors[J].State := ssSystem
      else
        Result[I].Sectors[J].State := ssData;
    end;
  end;
end;

{ ── TTestHeteroSectorContainer ──────────────────────────────── }

constructor TTestHeteroSectorContainer.Create(const ATitle: string);
begin
  inherited Create;
  FTitle := ATitle;
end;

function TTestHeteroSectorContainer.GetName: string;        begin Result := FTitle; end;
function TTestHeteroSectorContainer.GetDisplayName: string; begin Result := FTitle; end;
function TTestHeteroSectorContainer.GetEntryCount: Integer; begin Result := 0; end;
function TTestHeteroSectorContainer.GetEntry(Index: Integer): IEntry; begin Result := nil; end;
function TTestHeteroSectorContainer.GetTitle: string;       begin Result := FTitle; end;
procedure TTestHeteroSectorContainer.Refresh;               begin end;

function TTestHeteroSectorContainer.GetSectorMap: TTrackColumnArray;
var
  J: Integer;
begin
  { Track 0: 9 sectors (boot), Track 1: 5 sectors (data).
    The two tracks deliberately differ in sector count to exercise
    DrawSectorMap's column-width handling across heterogeneous layouts. }
  SetLength(Result, 2);

  Result[0].TrackNum  := 0;
  Result[0].SideNum   := 0;
  Result[0].FillerByte := $E5;
  SetLength(Result[0].Sectors, 9);
  for J := 0 to 8 do
  begin
    Result[0].Sectors[J].SectorID  := $C1 + J;
    Result[0].Sectors[J].SizeBytes := 512;
    Result[0].Sectors[J].FDCSt1   := 0;
    Result[0].Sectors[J].FDCSt2   := 0;
    Result[0].Sectors[J].State    := ssBoot;
  end;

  Result[1].TrackNum  := 1;
  Result[1].SideNum   := 0;
  Result[1].FillerByte := $E5;
  SetLength(Result[1].Sectors, 5);
  for J := 0 to 4 do
  begin
    Result[1].Sectors[J].SectorID  := $01 + J;
    Result[1].Sectors[J].SizeBytes := 1024;
    Result[1].Sectors[J].FDCSt1   := 0;
    Result[1].Sectors[J].FDCSt2   := 0;
    Result[1].Sectors[J].State    := ssData;
  end;
end;

{ ── TTestThrowingEntry ───────────────────────────────────────── }

constructor TTestThrowingEntry.Create(const AName: string; ASize: Int64);
begin
  inherited Create;
  FName := AName;
  FSize := ASize;
end;

function TTestThrowingEntry.GetName: string;
begin
  Result := FName;
end;

function TTestThrowingEntry.GetDisplayName: string;
begin
  Result := FName;
end;

function TTestThrowingEntry.GetSize: Int64;
begin
  Result := FSize;
end;

function TTestThrowingEntry.GetSizeUnit: TSizeUnit;
begin
  Result := suBytes;
end;

procedure TTestThrowingEntry.CopyTo(AStream: TStream);
begin
  raise Exception.Create('Simulated read error');
end;

{ ── TTestExpandableEntry ─────────────────────────────────────── }

constructor TTestExpandableEntry.Create(const AName: string; ASize: Int64;
  AContainer: IContainer);
begin
  inherited Create;
  FName := AName;
  FSize := ASize;
  FContainer := AContainer;
end;

function TTestExpandableEntry.GetName: string;
begin
  Result := FName;
end;

function TTestExpandableEntry.GetDisplayName: string;
begin
  Result := FName;
end;

function TTestExpandableEntry.GetSize: Int64;
begin
  Result := FSize;
end;

function TTestExpandableEntry.GetSizeUnit: TSizeUnit;
begin
  Result := suBytes;
end;

procedure TTestExpandableEntry.CopyTo(AStream: TStream);
begin
  { empty }
end;

function TTestExpandableEntry.Expand: IContainer;
begin
  Result := FContainer;
end;

end.
