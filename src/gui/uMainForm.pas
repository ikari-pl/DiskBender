unit uMainForm;

{$mode objfpc}{$H+}

{ DiskBender main form: Norton-Commander-style dual-pane file manager for
  CPC DSK images. Left pane shows the DSK filesystem, right pane shows the
  host filesystem. F-keys drive common operations.

  Design notes:
  - Row metadata is stored in parallel arrays (FDSKRowTags / FHostRowTags)
    instead of being smuggled through TListItem.Data — cleaner, type-safe,
    and sort-resilient.
  - Sorting is delegated to the filesystem (IFilesystem.SortFiles). Host
    sort happens on FHostEntries in-memory before rendering.
  - Hex viewing, disk info and disk map all open dedicated modal forms from
    uViewers instead of overflowing ShowMessage.
  - F-key keyboard shortcuts are wired to Actions at runtime to avoid
    hand-editing the LFM. }

interface

uses
  Classes, SysUtils, Math, DateUtils, Forms, Controls, Graphics, Dialogs,
  ComCtrls, ExtCtrls, Menus, ActnList, StdCtrls, Buttons, LCLType,
  uDSK, uCPM, uInterfaces, uCPMTypes, uFormatters, uViewers, CoreAPI,
  uExternalDrive;

type
  { Row in the host filesystem listing. Kept separate from FileSystem data
    so the GUI can sort/present it without re-hitting the disk. }
  THostEntry = record
    Kind: TRowKind;      { rkParent / rkHostDir / rkHostFile }
    Name: string;        { display name, without surrounding [] for dirs }
    Size: Int64;
    Time: TDateTime;
  end;
  THostEntryArray = array of THostEntry;

  THostSortField = (hsName, hsSize, hsTime);

  { TMainForm }
  TMainForm = class(TForm)
    MainMenu: TMainMenu;
    MenuFile: TMenuItem;
    MenuOpen: TMenuItem;
    MenuSave: TMenuItem;
    MenuSaveAs: TMenuItem;
    MenuSep1: TMenuItem;
    MenuExit: TMenuItem;
    MenuEdit: TMenuItem;
    MenuCopyToDSK: TMenuItem;
    MenuCopyToHost: TMenuItem;
    MenuDelete: TMenuItem;
    MenuUndelete: TMenuItem;
    MenuView: TMenuItem;
    MenuHexViewer: TMenuItem;
    MenuDiskMap: TMenuItem;
    MenuDiskInfo: TMenuItem;
    MenuDrive: TMenuItem;
    MenuDriveRead: TMenuItem;
    MenuDriveWrite: TMenuItem;
    MenuDriveSep1: TMenuItem;
    MenuDriveInfo: TMenuItem;
    MenuWindow: TMenuItem;
    MenuMinimize: TMenuItem;
    MenuZoom: TMenuItem;
    MenuSep2: TMenuItem;
    MenuBringToFront: TMenuItem;
    MenuHelp: TMenuItem;
    MenuAbout: TMenuItem;

    ToolBar: TToolBar;
    ToolOpen: TToolButton;
    ToolSave: TToolButton;
    ToolSep1: TToolButton;
    ToolCopyToDSK: TToolButton;
    ToolCopyToHost: TToolButton;
    ToolDelete: TToolButton;

    StatusBar: TStatusBar;

    PanelBottom: TPanel;
    BtnF1Help: TButton;
    BtnF2Rename: TButton;
    BtnF3View: TButton;
    BtnF4Edit: TButton;
    BtnF5Copy: TButton;
    BtnF6Move: TButton;
    BtnF7NewDir: TButton;
    BtnF8Delete: TButton;
    BtnF9Menu: TButton;
    BtnF10Quit: TButton;

    ImageListFiles: TImageList;

    MainSplitter: TSplitter;
    PanelLeft: TPanel;
    PanelRight: TPanel;

    LabelDetails: TLabel;

    LabelDSK: TLabel;
    LabelHost: TLabel;

    ListViewDSK: TListView;
    ListViewHost: TListView;

    OpenDialog: TOpenDialog;
    SaveDialog: TSaveDialog;

    ActionList: TActionList;
    ActOpen: TAction;
    ActSave: TAction;
    ActCopyToDSK: TAction;
    ActCopyToHost: TAction;
    ActDelete: TAction;
    ActUndelete: TAction;
    ActHexViewer: TAction;
    ActDiskMap: TAction;
    ActDiskInfo: TAction;
    ActExit: TAction;
    ActAbout: TAction;
    ActDriveRead: TAction;
    ActDriveWrite: TAction;
    ActDriveInfo: TAction;

    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormDropFiles(Sender: TObject; const FileNames: array of string);

    procedure ActOpenExecute(Sender: TObject);
    procedure ActSaveExecute(Sender: TObject);
    procedure ActCopyToDSKExecute(Sender: TObject);
    procedure ActCopyToHostExecute(Sender: TObject);
    procedure ActDeleteExecute(Sender: TObject);
    procedure ActUndeleteExecute(Sender: TObject);
    procedure ActHexViewerExecute(Sender: TObject);
    procedure ActDiskMapExecute(Sender: TObject);
    procedure ActDiskInfoExecute(Sender: TObject);
    procedure ActExitExecute(Sender: TObject);
    procedure ActAboutExecute(Sender: TObject);
    procedure ActDriveReadExecute(Sender: TObject);
    procedure ActDriveWriteExecute(Sender: TObject);
    procedure ActDriveInfoExecute(Sender: TObject);

    procedure MenuMinimizeClick(Sender: TObject);
    procedure BtnF1HelpClick(Sender: TObject);
    procedure BtnF2RenameClick(Sender: TObject);
    procedure BtnF3ViewClick(Sender: TObject);
    procedure BtnF4EditClick(Sender: TObject);
    procedure BtnF5CopyClick(Sender: TObject);
    procedure BtnF6MoveClick(Sender: TObject);
    procedure BtnF7NewDirClick(Sender: TObject);
    procedure BtnF8DeleteClick(Sender: TObject);
    procedure BtnF9MenuClick(Sender: TObject);
    procedure BtnF10QuitClick(Sender: TObject);

    procedure ListViewDSKDblClick(Sender: TObject);
    procedure ListViewHostDblClick(Sender: TObject);
    procedure ListViewDSKSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
    procedure ListViewDSKColumnClick(Sender: TObject; Column: TListColumn);
    procedure ListViewHostColumnClick(Sender: TObject; Column: TListColumn);
    procedure ListViewDSKDragOver(Sender, Source: TObject; X, Y: Integer; State: TDragState; var Accept: Boolean);
    procedure ListViewDSKDragDrop(Sender, Source: TObject; X, Y: Integer);
    procedure ListViewHostDragOver(Sender, Source: TObject; X, Y: Integer; State: TDragState; var Accept: Boolean);
    procedure ListViewHostDragDrop(Sender, Source: TObject; X, Y: Integer);
  private
    FDisk: IVirtualDisk;
    FFS: IFilesystem;
    FDSKPath: string;
    FHostPath: string;

    FDSKSortField: TFileSortField;
    FDSKSortAsc: Boolean;
    FHostSortField: THostSortField;
    FHostSortAsc: Boolean;

    FDSKRowTags: array of TRowTag;     { parallel to ListViewDSK.Items }
    FHostRowTags: array of TRowTag;    { parallel to ListViewHost.Items }
    FHostEntries: THostEntryArray;     { in-memory host model (pre-render) }

    procedure LoadDSK(const APath: string);

    procedure RefreshDSKList;
    procedure RefreshHostList;
    procedure ScanHostDirectory;
    procedure SortHostEntries;
    procedure AddListColumn(LV: TListView; const ACaption: string; AWidth: Integer);
    procedure UpdateStatusBar;
    procedure RefreshActionState;
    procedure UpdateHostDetails(Item: TListItem);
    procedure NavigateHost(const ANewPath: string);

    { Selection helpers — return -1 if nothing useful selected. }
    function SelectedDSKFileIdx: Integer;
    function DSKRowTag(Item: TListItem): TRowTag;
    function HostRowTag(Item: TListItem): TRowTag;

    { Which pane is "active" — focus with a selection fallback. }
    function DSKIsActive: Boolean;

    { Shared primitives used by several F-keys. }
    procedure DoCopySelectedToHost;
    procedure DoCopySelectedToDSK;
    procedure DoDeleteDSKSelection;
    procedure DoRenameDSKSelection;
    procedure DoUndeleteDSKSelection;
    procedure DoShowHexForSelection;

    { Sorting. }
    procedure ApplyDSKSort(Field: TFileSortField);
    procedure ApplyHostSort(Field: THostSortField);

    { Host-side selection feedback. }
    procedure HostSelectChanged(Sender: TObject; Item: TListItem; Selected: Boolean);

    { Global F-key keyboard handler (forward to actions / buttons). }
    procedure FormKeyDownHandler(Sender: TObject; var Key: Word; Shift: TShiftState);
  public
    property DSKPath: string read FDSKPath;
  end;

var
  MainForm: TMainForm;

implementation

{$R *.lfm}

{ TMainForm }

procedure TMainForm.FormCreate(Sender: TObject);
begin
  FHostPath := GetCurrentDir;
  FDisk := nil;
  FFS := nil;

  FDSKSortField := fsName;
  FDSKSortAsc := True;
  FHostSortField := hsName;
  FHostSortAsc := True;

  { Column headers. Extracted into a helper for readability. }
  AddListColumn(ListViewDSK,  'Name', 180);
  AddListColumn(ListViewDSK,  'Ext',   60);
  AddListColumn(ListViewDSK,  'Size',  70);
  AddListColumn(ListViewDSK,  'User',  50);
  AddListColumn(ListViewHost, 'Name', 220);
  AddListColumn(ListViewHost, 'Size',  90);
  AddListColumn(ListViewHost, 'Date', 130);

  { Wire the host-side SelectItem and the global keyboard handler that the
    LFM does not already cover. Doing this in code avoids a LFM round-trip. }
  ListViewHost.OnSelectItem := @HostSelectChanged;
  Self.KeyPreview := True;
  Self.OnKeyDown := @FormKeyDownHandler;

  { F-key keyboard shortcuts on actions — clashes with existing LFM bindings
    are resolved by taking the last write. These are the modifier-free F-keys
    that the F-key buttons duplicate. }
  ActHexViewer.ShortCut := VK_F3;
  { F5 is handled dynamically (depends on active pane) via OnKeyDown. }
  ActDelete.ShortCut    := VK_F8;
  ActAbout.ShortCut     := VK_F1;

  { Resolve the earlier Ctrl+H duplicate: give Hex Viewer a distinct shortcut. }
  MenuHexViewer.ShortCut := VK_F3;

  ScanHostDirectory;
  SortHostEntries;
  RefreshHostList;
  RefreshActionState;
  UpdateStatusBar;

  if ParamCount >= 1 then
    LoadDSK(ParamStr(1));
end;

procedure TMainForm.FormDestroy(Sender: TObject);
begin
  FFS := nil;
  FDisk := nil;
end;

procedure TMainForm.FormDropFiles(Sender: TObject; const FileNames: array of string);
begin
  if (Length(FileNames) > 0) and (LowerCase(ExtractFileExt(FileNames[0])) = '.dsk') then
    LoadDSK(FileNames[0]);
end;

procedure TMainForm.AddListColumn(LV: TListView; const ACaption: string; AWidth: Integer);
var
  Col: TListColumn;
begin
  Col := LV.Columns.Add;
  Col.Caption := ACaption;
  Col.Width := AWidth;
end;

procedure TMainForm.LoadDSK(const APath: string);
begin
  if not FileExists(APath) then
  begin
    MessageDlg('File Not Found', 'DSK file not found: ' + APath, mtError, [mbOK], 0);
    Exit;
  end;

  try
    FFS := nil;
    FDisk := nil;

    FDSKPath := APath;
    FDisk := TDiskBenderDSK.Create(FDSKPath);
    FDisk.Load;
    FFS := TDiskBenderCPM.Create(FDisk);
    FFS.ScanDirectory;
    FFS.SortFiles(FDSKSortField, FDSKSortAsc);

    LabelDSK.Caption := 'DSK: ' + ExtractFileName(FDSKPath);
    RefreshDSKList;
    UpdateStatusBar;
    RefreshActionState;
  except
    on E: Exception do
    begin
      MessageDlg('Load Error', 'Failed to load DSK: ' + E.Message, mtError, [mbOK], 0);
      FFS := nil;
      FDisk := nil;
    end;
  end;
end;

procedure TMainForm.RefreshDSKList;
var
  I: Integer;
  VFile: IVirtualFile;
  Item: TListItem;
begin
  ListViewDSK.Items.BeginUpdate;
  try
    ListViewDSK.Items.Clear;
    SetLength(FDSKRowTags, 0);
    if FFS = nil then Exit;

    SetLength(FDSKRowTags, FFS.GetFileCount);
    for I := 0 to FFS.GetFileCount - 1 do
    begin
      VFile := FFS.GetFile(I);
      Item := ListViewDSK.Items.Add;
      if VFile.IsDeleted then
        Item.Caption := '[DEL] ' + VFile.Name
      else
        Item.Caption := VFile.Name;
      Item.SubItems.Add(VFile.Extension);
      Item.SubItems.Add(IntToStr(VFile.SizeKB) + 'K');
      Item.SubItems.Add(IntToStr(VFile.User));
      FDSKRowTags[I] := TRowTag.Make(rkDSKFile, I);
    end;
  finally
    ListViewDSK.Items.EndUpdate;
  end;
end;

procedure TMainForm.ScanHostDirectory;
var
  SR: TSearchRec;
  N: Integer;
begin
  SetLength(FHostEntries, 0);
  N := 0;

  if FHostPath <> '/' then
  begin
    SetLength(FHostEntries, N + 1);
    FHostEntries[N].Kind := rkParent;
    FHostEntries[N].Name := '..';
    FHostEntries[N].Size := 0;
    FHostEntries[N].Time := 0;
    Inc(N);
  end;

  if FindFirst(FHostPath + PathDelim + '*', faAnyFile, SR) = 0 then
  begin
    repeat
      if (SR.Name = '.') or (SR.Name = '..') then Continue;
      SetLength(FHostEntries, N + 1);
      if (SR.Attr and faDirectory) <> 0 then
        FHostEntries[N].Kind := rkHostDir
      else
        FHostEntries[N].Kind := rkHostFile;
      FHostEntries[N].Name := SR.Name;
      FHostEntries[N].Size := SR.Size;
      FHostEntries[N].Time := FileDateToDateTime(SR.Time);
      Inc(N);
    until FindNext(SR) <> 0;
    FindClose(SR);
  end;
end;

procedure TMainForm.SortHostEntries;
var
  I, J: Integer;
  Tmp: THostEntry;

  function Less(const A, B: THostEntry): Boolean;
  var
    DirRankA, DirRankB: Integer;
    Raw: Integer;
  begin
    { Always pin ".." to the top and directories above files. }
    if A.Kind = rkParent then Exit(True);
    if B.Kind = rkParent then Exit(False);
    if A.Kind = rkHostDir then DirRankA := 0 else DirRankA := 1;
    if B.Kind = rkHostDir then DirRankB := 0 else DirRankB := 1;
    if DirRankA <> DirRankB then Exit(DirRankA < DirRankB);

    Raw := 0;
    case FHostSortField of
      hsName: Raw := AnsiCompareText(A.Name, B.Name);
      hsSize: Raw := CompareValue(A.Size, B.Size);
      hsTime: Raw := CompareDateTime(A.Time, B.Time);
    end;
    if not FHostSortAsc then Raw := -Raw;
    Result := Raw < 0;
  end;

begin
  { Simple insertion sort — small N (directory listings), stable, and keeps
    us free of the messy FPC-generic-sort surface. }
  for I := 1 to High(FHostEntries) do
  begin
    J := I;
    while (J > 0) and Less(FHostEntries[J], FHostEntries[J - 1]) do
    begin
      Tmp := FHostEntries[J];
      FHostEntries[J] := FHostEntries[J - 1];
      FHostEntries[J - 1] := Tmp;
      Dec(J);
    end;
  end;
end;

procedure TMainForm.RefreshHostList;
const
  DATE_FMT = 'yyyy-mm-dd hh:nn';
var
  I: Integer;
  Item: TListItem;
  E: THostEntry;
begin
  ListViewHost.Items.BeginUpdate;
  try
    ListViewHost.Items.Clear;
    SetLength(FHostRowTags, 0);
    LabelHost.Caption := 'Host: ' + FHostPath;

    SetLength(FHostRowTags, Length(FHostEntries));
    for I := 0 to High(FHostEntries) do
    begin
      E := FHostEntries[I];
      Item := ListViewHost.Items.Add;
      case E.Kind of
        rkParent:   Item.Caption := '..';
        rkHostDir:  Item.Caption := '<' + E.Name + '>';
        rkHostFile: Item.Caption := E.Name;
      end;
      if E.Kind = rkHostFile then
        Item.SubItems.Add(IntToStr(E.Size))
      else
        Item.SubItems.Add('<DIR>');
      if E.Time <> 0 then
        Item.SubItems.Add(FormatDateTime(DATE_FMT, E.Time))
      else
        Item.SubItems.Add('');
      FHostRowTags[I] := TRowTag.Make(E.Kind, I);
    end;
  finally
    ListViewHost.Items.EndUpdate;
  end;
end;

procedure TMainForm.NavigateHost(const ANewPath: string);
begin
  if not DirectoryExists(ANewPath) then Exit;
  FHostPath := ExcludeTrailingPathDelimiter(ExpandFileName(ANewPath));
  if FHostPath = '' then FHostPath := '/';
  ScanHostDirectory;
  SortHostEntries;
  RefreshHostList;
  UpdateHostDetails(nil);
end;

procedure TMainForm.UpdateStatusBar;
var
  State: string;
begin
  if FDisk <> nil then
  begin
    if FDisk.Modified then State := 'Modified' else State := 'Saved';
    StatusBar.SimpleText := Format('Tracks: %d | Sides: %d | Files: %d | %s',
      [FDisk.NumTracks, FDisk.NumSides, FFS.GetFileCount, State]);
  end
  else
    StatusBar.SimpleText := 'No disk loaded';
end;

procedure TMainForm.RefreshActionState;
var
  HasDisk, HasDSKSel, HasHostSel: Boolean;
begin
  HasDisk    := FDisk <> nil;
  HasDSKSel  := HasDisk and (SelectedDSKFileIdx >= 0);
  HasHostSel := (ListViewHost.Selected <> nil) and
                (HostRowTag(ListViewHost.Selected).Kind = rkHostFile);

  ActSave.Enabled        := HasDisk and FDisk.Modified;
  ActCopyToHost.Enabled  := HasDSKSel;
  ActCopyToDSK.Enabled   := HasDisk and HasHostSel;
  ActDelete.Enabled      := HasDSKSel;
  ActUndelete.Enabled    := HasDSKSel;
  ActHexViewer.Enabled   := HasDisk;
  ActDiskMap.Enabled     := HasDisk;
  ActDiskInfo.Enabled    := HasDisk;
end;

function TMainForm.DSKRowTag(Item: TListItem): TRowTag;
begin
  if (Item <> nil) and (Item.Index >= 0) and (Item.Index < Length(FDSKRowTags)) then
    Result := FDSKRowTags[Item.Index]
  else
    Result := TRowTag.Make(rkNone);
end;

function TMainForm.HostRowTag(Item: TListItem): TRowTag;
begin
  if (Item <> nil) and (Item.Index >= 0) and (Item.Index < Length(FHostRowTags)) then
    Result := FHostRowTags[Item.Index]
  else
    Result := TRowTag.Make(rkNone);
end;

function TMainForm.SelectedDSKFileIdx: Integer;
var
  Rt: TRowTag;
begin
  Rt := DSKRowTag(ListViewDSK.Selected);
  if Rt.Kind = rkDSKFile then
    Result := Rt.Index
  else
    Result := -1;
end;

function TMainForm.DSKIsActive: Boolean;
begin
  if ListViewDSK.Focused then Exit(True);
  if ListViewHost.Focused then Exit(False);
  { Fallback when neither has focus (e.g. just after a button click): pick
    the pane with a current selection, DSK preferred. }
  if ListViewDSK.Selected <> nil then Exit(True);
  Result := False;
end;

{ === Host details panel === }

procedure TMainForm.UpdateHostDetails(Item: TListItem);
var
  Rt: TRowTag;
  E: THostEntry;
begin
  if Item = nil then
  begin
    LabelDetails.Caption := 'No file selected';
    Exit;
  end;

  Rt := HostRowTag(Item);
  if (Rt.Kind = rkNone) or (Rt.Index < 0) or (Rt.Index >= Length(FHostEntries)) then
  begin
    LabelDetails.Caption := 'No file selected';
    Exit;
  end;

  E := FHostEntries[Rt.Index];
  case E.Kind of
    rkParent:   LabelDetails.Caption := 'Parent directory';
    rkHostDir:  LabelDetails.Caption := Format('Directory: %s', [E.Name]);
    rkHostFile: LabelDetails.Caption := Format('Host file: %s' + LineEnding +
                                               'Size: %d bytes' + LineEnding +
                                               'Modified: %s',
      [E.Name, E.Size, FormatDateTime('yyyy-mm-dd hh:nn', E.Time)]);
  end;
end;

procedure TMainForm.HostSelectChanged(Sender: TObject; Item: TListItem; Selected: Boolean);
begin
  if Selected then
    UpdateHostDetails(Item);
  RefreshActionState;
end;

{ === Open / Save / Exit / About === }

procedure TMainForm.ActOpenExecute(Sender: TObject);
begin
  if OpenDialog.Execute then
    LoadDSK(OpenDialog.FileName);
end;

procedure TMainForm.ActSaveExecute(Sender: TObject);
begin
  if FDisk <> nil then
  begin
    FDisk.Save;
    UpdateStatusBar;
    RefreshActionState;
  end;
end;

procedure TMainForm.ActExitExecute(Sender: TObject);
begin
  Close;
end;

procedure TMainForm.ActAboutExecute(Sender: TObject);
begin
  MessageDlg('About DiskBender',
    'DiskBender — Vintage Disk / Snapshot Management' + LineEnding + LineEnding +
    'Supports CPC DSK images with CP/M filesystem.' + LineEnding + LineEnding +
    'Built with Free Pascal and Lazarus LCL.',
    mtInformation, [mbOK], 0);
end;

{ === Copy / Delete / Undelete === }

procedure TMainForm.DoCopySelectedToDSK;
var
  Item: TListItem;
  Rt: TRowTag;
  E: THostEntry;
  InPath: string;
  InFile: TFileStream;
  Data: TBytes;
  NameOnly, Ext: string;
  NewIdx: Integer;
begin
  if (FFS = nil) or (FDisk = nil) then Exit;

  Item := ListViewHost.Selected;
  Rt := HostRowTag(Item);
  if Rt.Kind <> rkHostFile then
  begin
    ShowMessage('Select a file in the host pane first');
    Exit;
  end;
  E := FHostEntries[Rt.Index];
  InPath := FHostPath + PathDelim + E.Name;
  if not FileExists(InPath) then
  begin
    MessageDlg('Error', 'File not found: ' + InPath, mtError, [mbOK], 0);
    Exit;
  end;

  try
    InFile := TFileStream.Create(InPath, fmOpenRead or fmShareDenyWrite);
    try
      SetLength(Data, InFile.Size);
      if InFile.Size > 0 then
        InFile.ReadBuffer(Data[0], InFile.Size);
    finally
      InFile.Free;
    end;

    NameOnly := ChangeFileExt(E.Name, '');
    Ext := UpperCase(ExtractFileExt(E.Name));
    if Length(Ext) > 0 then
      Ext := Copy(Ext, 2, MaxInt);

    NewIdx := FFS.AddFile(NameOnly, Ext, Data, 0);
    if NewIdx < 0 then
    begin
      MessageDlg('Copy Error',
        'Could not add file. Either the name is invalid or the directory is full.',
        mtError, [mbOK], 0);
      Exit;
    end;

    FFS.SortFiles(FDSKSortField, FDSKSortAsc);
    RefreshDSKList;
    UpdateStatusBar;
    RefreshActionState;
  except
    on Ex: Exception do
      MessageDlg('Copy Error', Ex.Message, mtError, [mbOK], 0);
  end;
end;

procedure TMainForm.DoCopySelectedToHost;
var
  Idx: Integer;
  OutPath: string;
  OutFile: TFileStream;
  VFile: IVirtualFile;
begin
  Idx := SelectedDSKFileIdx;
  if Idx < 0 then Exit;

  VFile := FFS.GetFile(Idx);
  OutPath := FHostPath + PathDelim + VFile.Name;
  if VFile.Extension <> '' then
    OutPath := OutPath + '.' + VFile.Extension;

  try
    OutFile := TFileStream.Create(OutPath, fmCreate);
    try
      FFS.GetFileContent(Idx, OutFile);
    finally
      OutFile.Free;
    end;
    ScanHostDirectory;
    SortHostEntries;
    RefreshHostList;
    ShowMessage('Extracted: ' + OutPath);
  except
    on Ex: Exception do
      MessageDlg('Extract Error', Ex.Message, mtError, [mbOK], 0);
  end;
end;

procedure TMainForm.DoDeleteDSKSelection;
var
  Idx: Integer;
begin
  Idx := SelectedDSKFileIdx;
  if Idx < 0 then Exit;

  FFS.ToggleDelete(Idx);
  RefreshDSKList;
  UpdateStatusBar;
  RefreshActionState;
end;

procedure TMainForm.DoRenameDSKSelection;
var
  Idx: Integer;
  VFile: IVirtualFile;
  NewName: string;
begin
  Idx := SelectedDSKFileIdx;
  if Idx < 0 then Exit;

  VFile := FFS.GetFile(Idx);
  NewName := VFile.Name;
  if VFile.Extension <> '' then
    NewName := NewName + '.' + VFile.Extension;

  if not InputQuery('Rename File', 'New name (8.3):', NewName) then Exit;

  try
    FFS.RenameFile(Idx, NewName);
    FFS.SortFiles(FDSKSortField, FDSKSortAsc);
    RefreshDSKList;
  except
    on E: Exception do
      MessageDlg('Rename Error', E.Message, mtError, [mbOK], 0);
  end;
end;

procedure TMainForm.DoUndeleteDSKSelection;
var
  Idx: Integer;
  VFile: IVirtualFile;
  FirstChar: string;
begin
  Idx := SelectedDSKFileIdx;
  if Idx < 0 then Exit;

  VFile := FFS.GetFile(Idx);
  if not VFile.IsDeleted then
  begin
    MessageDlg('Not Deleted', 'File is not deleted.', mtInformation, [mbOK], 0);
    Exit;
  end;

  FirstChar := 'A';
  if not InputQuery('Undelete', 'Enter first character of filename:', FirstChar) then Exit;
  if Length(FirstChar) <> 1 then
  begin
    MessageDlg('Invalid', 'Please enter exactly one character.', mtError, [mbOK], 0);
    Exit;
  end;

  try
    FFS.UndeleteFile(Idx, FirstChar[1]);
    RefreshDSKList;
    UpdateStatusBar;
  except
    on E: Exception do
      MessageDlg('Undelete Error', E.Message, mtError, [mbOK], 0);
  end;
end;

procedure TMainForm.DoShowHexForSelection;
var
  Idx: Integer;
  VFile: IVirtualFile;
  Stream: TMemoryStream;
  Buf: TBytes;
begin
  Idx := SelectedDSKFileIdx;
  if Idx < 0 then
  begin
    ShowMessage('Select a file to view.');
    Exit;
  end;

  VFile := FFS.GetFile(Idx);
  Stream := TMemoryStream.Create;
  try
    FFS.GetFileContent(Idx, Stream);
    SetLength(Buf, Stream.Size);
    if Stream.Size > 0 then
    begin
      Stream.Position := 0;
      Stream.ReadBuffer(Buf[0], Stream.Size);
    end;
    ShowHexViewer(VFile.Name + '.' + VFile.Extension, Buf);
  finally
    Stream.Free;
  end;
end;

{ === Actions wired in the LFM === }

procedure TMainForm.ActCopyToDSKExecute(Sender: TObject);
begin
  DoCopySelectedToDSK;
end;

procedure TMainForm.ActCopyToHostExecute(Sender: TObject);
begin
  DoCopySelectedToHost;
end;

procedure TMainForm.ActDeleteExecute(Sender: TObject);
begin
  DoDeleteDSKSelection;
end;

procedure TMainForm.ActUndeleteExecute(Sender: TObject);
begin
  DoUndeleteDSKSelection;
end;

procedure TMainForm.ActHexViewerExecute(Sender: TObject);
begin
  DoShowHexForSelection;
end;

procedure TMainForm.ActDiskMapExecute(Sender: TObject);
var
  Map: TBytes;
begin
  if FFS = nil then Exit;
  Map := FFS.GetBlockMap;
  ShowDiskMap('Disk Block Map', Map, 32);
end;

procedure TMainForm.ActDiskInfoExecute(Sender: TObject);
var
  Info: string;
begin
  if FDisk = nil then Exit;
  Info := TDiskFormatter.FormatDiskInfo(FDisk, ofTable) + LineEnding +
          FFS.GetSummaryInfo + LineEnding + LineEnding +
          'Files: ' + IntToStr(FFS.GetFileCount);
  ShowTextViewer('Disk Information', Info);
end;

{ === Window menu === }

procedure TMainForm.MenuMinimizeClick(Sender: TObject);
begin
  Application.Minimize;
end;

{ === Norton-style F-key button handlers — thin delegations === }

procedure TMainForm.BtnF1HelpClick(Sender: TObject);
begin
  ActAboutExecute(Sender);
end;

procedure TMainForm.BtnF2RenameClick(Sender: TObject);
begin
  if DSKIsActive then
    DoRenameDSKSelection
  else
    ShowMessage('Host rename: Use the Finder to rename files on the host system.');
end;

procedure TMainForm.BtnF3ViewClick(Sender: TObject);
begin
  if DSKIsActive then
    DoShowHexForSelection
  else if (ListViewHost.Selected <> nil) and
          (HostRowTag(ListViewHost.Selected).Kind = rkHostFile) then
    ShowMessage('Host file view is not yet implemented (hex viewer for DSK files only).');
end;

procedure TMainForm.BtnF4EditClick(Sender: TObject);
begin
  BtnF3ViewClick(Sender);
end;

procedure TMainForm.BtnF5CopyClick(Sender: TObject);
begin
  if DSKIsActive then
    DoCopySelectedToHost
  else
    DoCopySelectedToDSK;
end;

procedure TMainForm.BtnF6MoveClick(Sender: TObject);
begin
  if DSKIsActive then
    DoRenameDSKSelection
  else
    ShowMessage('Host move: Use Finder to move files on host.');
end;

procedure TMainForm.BtnF7NewDirClick(Sender: TObject);
begin
  ShowMessage('CP/M has no subdirectories. Use F5 to copy files to DSK.');
end;

procedure TMainForm.BtnF8DeleteClick(Sender: TObject);
begin
  if DSKIsActive then
    DoDeleteDSKSelection
  else
    ShowMessage('Host delete: Use Finder to delete files on host.');
end;

procedure TMainForm.BtnF9MenuClick(Sender: TObject);
begin
  ShowMessage('F9 Menu — Tab switches focus between DSK and Host panes.');
end;

procedure TMainForm.BtnF10QuitClick(Sender: TObject);
begin
  Close;
end;

{ === Global keyboard handler — real F-key wiring === }

procedure TMainForm.FormKeyDownHandler(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  case Key of
    VK_F1:  begin BtnF1HelpClick(Sender);   Key := 0; end;
    VK_F2:  begin BtnF2RenameClick(Sender); Key := 0; end;
    VK_F3:  begin BtnF3ViewClick(Sender);   Key := 0; end;
    VK_F4:  begin BtnF4EditClick(Sender);   Key := 0; end;
    VK_F5:  begin BtnF5CopyClick(Sender);   Key := 0; end;
    VK_F6:  begin BtnF6MoveClick(Sender);   Key := 0; end;
    VK_F7:  begin BtnF7NewDirClick(Sender); Key := 0; end;
    VK_F8:  begin BtnF8DeleteClick(Sender); Key := 0; end;
    VK_F9:  begin BtnF9MenuClick(Sender);   Key := 0; end;
    VK_F10: begin BtnF10QuitClick(Sender);  Key := 0; end;
  end;
end;

{ === List view events === }

procedure TMainForm.ListViewDSKDblClick(Sender: TObject);
begin
  DoShowHexForSelection;
end;

procedure TMainForm.ListViewHostDblClick(Sender: TObject);
var
  Item: TListItem;
  Rt: TRowTag;
  E: THostEntry;
begin
  Item := ListViewHost.Selected;
  if Item = nil then Exit;
  Rt := HostRowTag(Item);
  case Rt.Kind of
    rkParent:
      NavigateHost(ExtractFileDir(ExcludeTrailingPathDelimiter(FHostPath)));
    rkHostDir:
      begin
        E := FHostEntries[Rt.Index];
        NavigateHost(FHostPath + PathDelim + E.Name);
      end;
    rkHostFile:
      DoCopySelectedToDSK;
  end;
end;

procedure TMainForm.ListViewDSKSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
var
  VFile: IVirtualFile;
  Details: string;
  Idx: Integer;
begin
  RefreshActionState;
  if not Selected or (Item = nil) or (FFS = nil) then Exit;

  Idx := SelectedDSKFileIdx;
  if Idx < 0 then Exit;

  VFile := FFS.GetFile(Idx);
  if VFile = nil then Exit;

  Details := 'Name: ' + VFile.Name + LineEnding;
  if VFile.Extension <> '' then
    Details := Details + 'Ext: ' + VFile.Extension + LineEnding;
  Details := Details + 'Size: ' + IntToStr(VFile.SizeKB) + ' KB' + LineEnding +
                       'User: ' + IntToStr(VFile.User);
  if VFile.IsDeleted then
    Details := Details + LineEnding + '[DELETED]';
  LabelDetails.Caption := Details;
end;

{ === Column click → sort === }

procedure TMainForm.ApplyDSKSort(Field: TFileSortField);
begin
  if FDSKSortField = Field then
    FDSKSortAsc := not FDSKSortAsc
  else
  begin
    FDSKSortField := Field;
    FDSKSortAsc := True;
  end;
  if FFS <> nil then
  begin
    FFS.SortFiles(FDSKSortField, FDSKSortAsc);
    RefreshDSKList;
  end;
end;

procedure TMainForm.ApplyHostSort(Field: THostSortField);
begin
  if FHostSortField = Field then
    FHostSortAsc := not FHostSortAsc
  else
  begin
    FHostSortField := Field;
    FHostSortAsc := True;
  end;
  SortHostEntries;
  RefreshHostList;
end;

procedure TMainForm.ListViewDSKColumnClick(Sender: TObject; Column: TListColumn);
begin
  case Column.Index of
    0: ApplyDSKSort(fsName);
    1: ApplyDSKSort(fsExt);
    2: ApplyDSKSort(fsSize);
    3: ApplyDSKSort(fsUser);
  end;
end;

procedure TMainForm.ListViewHostColumnClick(Sender: TObject; Column: TListColumn);
begin
  case Column.Index of
    0: ApplyHostSort(hsName);
    1: ApplyHostSort(hsSize);
    2: ApplyHostSort(hsTime);
  end;
end;

{ === Drag & drop — two directions === }

procedure TMainForm.ListViewDSKDragOver(Sender, Source: TObject; X, Y: Integer;
  State: TDragState; var Accept: Boolean);
begin
  { Drop onto DSK pane => copy host-selected file into DSK. }
  Accept := (Source = ListViewHost) and
            (FDisk <> nil) and
            (ListViewHost.Selected <> nil) and
            (HostRowTag(ListViewHost.Selected).Kind = rkHostFile);
end;

procedure TMainForm.ListViewDSKDragDrop(Sender, Source: TObject; X, Y: Integer);
begin
  if Source = ListViewHost then
    DoCopySelectedToDSK;
end;

procedure TMainForm.ListViewHostDragOver(Sender, Source: TObject; X, Y: Integer;
  State: TDragState; var Accept: Boolean);
begin
  { Drop onto Host pane => extract DSK-selected file to current host dir. }
  Accept := (Source = ListViewDSK) and (SelectedDSKFileIdx >= 0);
end;

procedure TMainForm.ListViewHostDragDrop(Sender, Source: TObject; X, Y: Integer);
begin
  if Source = ListViewDSK then
    DoCopySelectedToHost;
end;

{ === Greaseweazle drive actions === }

procedure TMainForm.ActDriveReadExecute(Sender: TObject);
var
  GwPath, DriveStr, ImagePath, Log: string;
  SD: TSaveDialog;
begin
  GwPath := FindGwExecutable;
  if GwPath = '' then
  begin
    MessageDlg('Greaseweazle Not Found',
      GW_NOT_FOUND_HINT, mtError, [mbOK], 0);
    Exit;
  end;

  if not InputQuery('Read Disc', 'Drive letter (a/b):', DriveStr) then Exit;
  if DriveStr = '' then DriveStr := 'a';

  SD := TSaveDialog.Create(Self);
  try
    SD.Title   := 'Save disc image as...';
    SD.Filter  := 'DSK images (*.dsk)|*.dsk|All files (*.*)|*.*';
    SD.DefaultExt := 'dsk';
    if not SD.Execute then Exit;
    ImagePath := SD.FileName;
  finally
    SD.Free;
  end;

  if not GwReadDisc(GwPath, DriveStr, ImagePath, Log) then
  begin
    MessageDlg('Read Failed', 'gw read failed:' + LineEnding + Log,
      mtError, [mbOK], 0);
    Exit;
  end;

  MessageDlg('Read Complete',
    'Disc read successfully.' + LineEnding + 'Image saved to:' + LineEnding +
    ImagePath, mtInformation, [mbOK], 0);

  { Offer to open the resulting DSK in the left pane. }
  if MessageDlg('Open Image?',
    'Open the new image in the DSK pane?',
    mtConfirmation, [mbYes, mbNo], 0) = mrYes then
    LoadDSK(ImagePath);
end;

procedure TMainForm.ActDriveWriteExecute(Sender: TObject);
var
  GwPath, DriveStr, Log: string;
begin
  if FDisk = nil then
  begin
    MessageDlg('No Disc Image', 'No DSK image is loaded.', mtError, [mbOK], 0);
    Exit;
  end;

  GwPath := FindGwExecutable;
  if GwPath = '' then
  begin
    MessageDlg('Greaseweazle Not Found',
      GW_NOT_FOUND_HINT, mtError, [mbOK], 0);
    Exit;
  end;

  if FDisk.Modified then
  begin
    case MessageDlg('Unsaved Changes',
      'The DSK has unsaved changes. Save before writing to hardware?',
      mtConfirmation, [mbYes, mbNo, mbCancel], 0) of
      mrCancel: Exit;
      mrYes:    FDisk.Save;
      { mrNo: proceed with on-disk version }
    end;
  end;

  if not InputQuery('Write Disc', 'Drive letter (a/b):', DriveStr) then Exit;
  if DriveStr = '' then DriveStr := 'a';

  if MessageDlg('Confirm Write',
    'Write ' + ExtractFileName(FDSKPath) + ' to drive ' + DriveStr + '?' +
    LineEnding + 'This will ERASE the physical disc.',
    mtWarning, [mbYes, mbNo], 0) <> mrYes then Exit;

  if not GwWriteDisc(GwPath, DriveStr, FDSKPath, Log) then
  begin
    MessageDlg('Write Failed', 'gw write failed:' + LineEnding + Log,
      mtError, [mbOK], 0);
    Exit;
  end;

  MessageDlg('Write Complete', 'Disc written successfully.', mtInformation, [mbOK], 0);
end;

procedure TMainForm.ActDriveInfoExecute(Sender: TObject);
var
  GwPath, Log: string;
begin
  GwPath := FindGwExecutable;
  if GwPath = '' then
  begin
    MessageDlg('Greaseweazle Not Found',
      GW_NOT_FOUND_HINT, mtError, [mbOK], 0);
    Exit;
  end;

  if not GwDriveInfo(GwPath, Log) then
  begin
    MessageDlg('Drive Info Failed', 'gw info failed:' + LineEnding + Log,
      mtError, [mbOK], 0);
    Exit;
  end;

  ShowTextViewer('Greaseweazle Drive Info', Log);
end;

end.
