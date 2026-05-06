unit uDSKLocation;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, uVFS, uInterfaces, uDSK, uCPM, uCPMTypes;

type
  { A CP/M file entry on a DSK image.
    Wraps the old IVirtualFile / TCPMFile model behind VFS interfaces. }
  TCPMFileEntry = class(TInterfacedObject, IEntry, ISizeable, IDeletable,
                        IRestorable, IAttributed, ICopySource, IRenameable,
                        IUserArea)
  strict private
    FFS: IFilesystem;
    FIndex: Integer;
    FName: string;
    FExt: string;
    FSizeKB: Integer;
    FIsDeleted: Boolean;
    FUser: Byte;
    FAttrs: TCPMAttrs;
  public
    constructor Create(AFS: IFilesystem; AIndex: Integer);
    { IEntry }
    function GetName: string;
    function GetDisplayName: string;
    { ISizeable }
    function GetSize: Int64;
    function GetSizeUnit: TSizeUnit;
    { IDeletable }
    function GetIsDeleted: Boolean;
    procedure Delete;
    { IRestorable }
    procedure Restore;
    { IAttributed }
    function GetAttributes: TEntryAttributes;
    procedure SetAttributes(AValue: TEntryAttributes);
    { ICopySource }
    procedure CopyTo(AStream: TStream);
    { IRenameable }
    procedure Rename(const NewName: string);
    { IUserArea }
    function GetUser: Byte;
  end;

  { An opened DSK disk image as a container of CP/M files.
    Created when the user enters a .dsk file from the local pane. }
  TDSKContainer = class(TInterfacedObject, IEntry, IContainer,
                        IBlockMappable, IWritable, ICopyTarget,
                        ISortable, ISummary, IPhysicalLayout)
  strict private
    FDisk: IVirtualDisk;
    FFS: IFilesystem;
    FPath: string;
  public
    constructor Create(const ADSKPath: string);
    destructor Destroy; override;
    { IEntry }
    function GetName: string;
    function GetDisplayName: string;
    { IContainer }
    function GetEntryCount: Integer;
    function GetEntry(Index: Integer): IEntry;
    function GetTitle: string;
    procedure Refresh;
    { IBlockMappable }
    function GetBlockMap: TBytes;
    function GetBlockCount: Integer;
    { IWritable }
    function GetModified: Boolean;
    procedure Save;
    procedure Revert;
    { ICopyTarget }
    function Import(ASource: ICopySource; const AName: string): Boolean;
    { ISortable }
    procedure Sort(AField: TSortField; Ascending: Boolean);
    { ISummary }
    function GetSummaryInfo: string;
    { IPhysicalLayout }
    function GetLayoutInfo: TLayoutInfoArray;

    property Disk: IVirtualDisk read FDisk;
    property Filesystem: IFilesystem read FFS;
    property Path: string read FPath;
  end;

implementation

{ ── TCPMFileEntry ─────────────────────────────────────────────── }

constructor TCPMFileEntry.Create(AFS: IFilesystem; AIndex: Integer);
var
  VF: IVirtualFile;
begin
  inherited Create;
  FFS := AFS;
  FIndex := AIndex;
  VF := FFS.GetFile(AIndex);
  FName := VF.Name;
  FExt := VF.Extension;
  FSizeKB := VF.SizeKB;
  FIsDeleted := VF.IsDeleted;
  FUser := VF.User;
  FAttrs := [];
end;

function TCPMFileEntry.GetName: string;
begin
  Result := Trim(FName);
  if FExt <> '' then
    Result := Result + '.' + Trim(FExt);
end;

function TCPMFileEntry.GetDisplayName: string;
begin
  if FIsDeleted then
    Result := '?' + Copy(GetName, 2, MaxInt)
  else
    Result := GetName;
end;

function TCPMFileEntry.GetSize: Int64;
begin
  Result := FSizeKB;
end;

function TCPMFileEntry.GetSizeUnit: TSizeUnit;
begin
  Result := suKB;
end;

function TCPMFileEntry.GetIsDeleted: Boolean;
begin
  Result := FIsDeleted;
end;

procedure TCPMFileEntry.Delete;
begin
  FFS.ToggleDelete(FIndex);
  FIsDeleted := True;
end;

procedure TCPMFileEntry.Restore;
begin
  FFS.UndeleteFile(FIndex, FName[1]);
  FIsDeleted := False;
end;

function TCPMFileEntry.GetAttributes: TEntryAttributes;
begin
  Result := [];
  if caReadOnly in FAttrs then Include(Result, eaReadOnly);
  if caSystem in FAttrs then Include(Result, eaSystem);
  if caArchive in FAttrs then Include(Result, eaArchive);
end;

procedure TCPMFileEntry.SetAttributes(AValue: TEntryAttributes);
begin
  FAttrs := [];
  if eaReadOnly in AValue then Include(FAttrs, caReadOnly);
  if eaSystem in AValue then Include(FAttrs, caSystem);
  if eaArchive in AValue then Include(FAttrs, caArchive);
end;

procedure TCPMFileEntry.CopyTo(AStream: TStream);
begin
  FFS.GetFileContent(FIndex, AStream);
end;

procedure TCPMFileEntry.Rename(const NewName: string);
begin
  FFS.RenameFile(FIndex, NewName);
  FName := NewName;
end;

function TCPMFileEntry.GetUser: Byte;
begin
  Result := FUser;
end;

{ ── TDSKContainer ─────────────────────────────────────────────── }

constructor TDSKContainer.Create(const ADSKPath: string);
begin
  inherited Create;
  FPath := ExpandFileName(ADSKPath);
  FDisk := TDiskBenderDSK.Create(FPath);
  FDisk.Load;
  FFS := TDiskBenderCPM.Create(FDisk);
  (FFS as TDiskBenderCPM).AutoDetectFormat;
  FFS.ScanDirectory;
end;

destructor TDSKContainer.Destroy;
begin
  FFS := nil;
  FDisk := nil;
  inherited Destroy;
end;

function TDSKContainer.GetName: string;
begin
  Result := ExtractFileName(FPath);
end;

function TDSKContainer.GetDisplayName: string;
begin
  Result := ExtractFileName(FPath);
  if GetModified then
    Result := Result + ' [MOD]';
end;

function TDSKContainer.GetEntryCount: Integer;
begin
  Result := FFS.GetFileCount;
end;

function TDSKContainer.GetEntry(Index: Integer): IEntry;
begin
  if (Index >= 0) and (Index < FFS.GetFileCount) then
    Result := TCPMFileEntry.Create(FFS, Index)
  else
    Result := nil;
end;

function TDSKContainer.GetTitle: string;
begin
  Result := ExtractFileName(FPath);
  if GetModified then
    Result := Result + ' [MOD]';
end;

procedure TDSKContainer.Refresh;
begin
  FFS.ScanDirectory;
end;

function TDSKContainer.GetBlockMap: TBytes;
begin
  Result := FFS.GetBlockMap;
end;

function TDSKContainer.GetBlockCount: Integer;
begin
  Result := Length(FFS.GetBlockMap);
end;

function TDSKContainer.GetModified: Boolean;
begin
  Result := FDisk.Modified;
end;

procedure TDSKContainer.Save;
begin
  FDisk.Save;
end;

procedure TDSKContainer.Revert;
begin
  FDisk.Revert;
  FFS.ScanDirectory;
end;

function TDSKContainer.Import(ASource: ICopySource; const AName: string): Boolean;
var
  MS: TMemoryStream;
  Parsed: TCPMFileName;
  Buf: TBytes;
begin
  Result := False;
  Parsed := TCPMFileName.Parse(AName);
  if not Parsed.IsValid then Exit;
  MS := TMemoryStream.Create;
  try
    ASource.CopyTo(MS);
    if MS.Size > 64 * 1024 then Exit;
    SetLength(Buf, MS.Size);
    if MS.Size > 0 then
      Move(MS.Memory^, Buf[0], MS.Size);
    Result := FFS.AddFile(Parsed.Name, Parsed.Ext, Buf, 0) >= 0;
    if Result then
      FFS.ScanDirectory;
  finally
    MS.Free;
  end;
end;

function MapSortField(AField: TSortField): TFileSortField;
begin
  case AField of
    sfName: Result := fsName;
    sfExtension: Result := fsExt;
    sfSize: Result := fsSize;
    sfUser: Result := fsUser;
  else
    Result := fsName;
  end;
end;

procedure TDSKContainer.Sort(AField: TSortField; Ascending: Boolean);
begin
  FFS.SortFiles(MapSortField(AField), Ascending);
end;

function TDSKContainer.GetSummaryInfo: string;
begin
  Result := FFS.GetSummaryInfo;
end;

function TDSKContainer.GetLayoutInfo: TLayoutInfoArray;
var
  I: Integer;
  NumTracks: Byte;
begin
  NumTracks := FDisk.NumTracks;
  SetLength(Result, NumTracks);
  for I := 0 to NumTracks - 1 do
  begin
    Result[I].Kind := lkTrack;
    Result[I].Label_ := 'Track ' + IntToStr(I);
    Result[I].Offset := I;
    Result[I].Size := 0;
    Result[I].Extra := '';
  end;
end;

end.
