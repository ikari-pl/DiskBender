unit uMainForm;

{$mode objfpc}{$H+}

{ DiskBender main form — Norton Commander-style dual-pane disk manager.

  Architecture:
  - TPane owns all per-panel state (path, entries, sort, optional DSK) and
    implements Navigate, Scan, Sort, Render, and UpdateDetails.
  - TMainForm owns LCL widgets, actions, and cross-pane operations.
  - FPanes[0] = left panel, FPanes[1] = right panel.  Either pane can be in
    pmDir (directory browser) or pmDSK (CP/M disk content) mode.
  - Each pane has an Other pointer so copy operations can find the sibling. }

interface

uses
  Classes, SysUtils, Math, DateUtils, Forms, Controls, Graphics, Dialogs,
  ComCtrls, ExtCtrls, Menus, ActnList, StdCtrls, Buttons, LCLType,
  uDSK, uCPM, uInterfaces, uCPMTypes, uFormatters, uViewers, CoreAPI,
  uExternalDrive, uDSKLocation, uVFS;

type
  THostEntry = record
    Kind: TRowKind;
    Name: string;
    Size: Int64;
    Time: TDateTime;
  end;
  THostEntryArray = array of THostEntry;

  THostSortField = (hsName, hsSize, hsTime);
  TPaneMode      = (pmDir, pmDSK);

  { ===================================================================== }
  { TPane — encapsulates one panel's entire state and rendering.          }
  { ===================================================================== }

  TPane = class
  private
    FListView:   TListView;
    FPathLabel:  TLabel;     { caption shows current path; nil = no label }
    FDetailsLbl: TLabel;     { shared bottom details label; may be nil }
    FOther:      TPane;      { companion pane }

    FMode:       TPaneMode;

    { Directory mode }
    FPath:       string;
    FEntries:    THostEntryArray;
    FSortField:  THostSortField;
    FSortAsc:    Boolean;
    FDirsFirst:  Boolean;
    FRowTags:    array of TRowTag;

    { DSK mode }
    FDisk:       IVirtualDisk;
    FFS:         IFilesystem;
    FDSKPath:    string;
    FDSKSortFld: TFileSortField;
    FDSKSortAsc: Boolean;

    procedure ScanDir;
    procedure RenderDir;
    procedure RenderDSK;

  public
    constructor Create(AListView: TListView; APathLabel, ADetailsLbl: TLabel);
    destructor  Destroy; override;

    { Navigation }
    procedure NavigateTo(const APath: string);
    procedure OpenDSK(const APath: string);
    procedure CloseDSK;
    procedure Refresh;

    { Sorting }
    procedure ApplyDirSort(Field: THostSortField);
    procedure ApplyDSKSort(Field: TFileSortField);
    procedure SetDirSort(Field: THostSortField; Asc, DirsFirst: Boolean);
    procedure SetDSKSort(Field: TFileSortField; Asc: Boolean);

    { Selection }
    function  RowTag(Item: TListItem): TRowTag;
    function  SelectedFileIdx: Integer;

    { Details panel }
    procedure UpdateDetails(Item: TListItem; Selected: Boolean);

    property Mode:       TPaneMode       read FMode;
    property Path:       string          read FPath;
    property DSKPath:    string          read FDSKPath;
    property Disk:       IVirtualDisk    read FDisk;
    property FS:         IFilesystem     read FFS;
    property Other:      TPane           read FOther    write FOther;
    property ListView:   TListView       read FListView;
    property Entries:    THostEntryArray read FEntries;
    property DirSortFld: THostSortField  read FSortField write FSortField;
    property DirSortAsc: Boolean         read FSortAsc   write FSortAsc;
    property DirDirsFirst: Boolean       read FDirsFirst write FDirsFirst;
    property DSKSortFld: TFileSortField  read FDSKSortFld write FDSKSortFld;
    property DSKSortAsc: Boolean         read FDSKSortAsc write FDSKSortAsc;
  end;

  { ===================================================================== }
  { TMainForm                                                             }
  { ===================================================================== }

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
    BtnF1Help:   TButton;
    BtnF2Rename: TButton;
    BtnF3View:   TButton;
    BtnF4Edit:   TButton;
    BtnF5Copy:   TButton;
    BtnF6Move:   TButton;
    BtnF7NewDir: TButton;
    BtnF8Delete: TButton;
    BtnF9Menu:   TButton;
    BtnF10Quit:  TButton;

    ImageListFiles: TImageList;

    MainSplitter: TSplitter;
    PanelLeft:    TPanel;
    PanelRight:   TPanel;

    LabelDetails: TLabel;
    LabelDSK:     TLabel;
    LabelHost:    TLabel;

    ListViewDSK:  TListView;
    ListViewHost: TListView;

    OpenDialog: TOpenDialog;
    SaveDialog: TSaveDialog;

    ActionList:      TActionList;
    ActOpen:         TAction;
    ActSave:         TAction;
    ActCopyToDSK:    TAction;
    ActCopyToHost:   TAction;
    ActDelete:       TAction;
    ActUndelete:     TAction;
    ActHexViewer:    TAction;
    ActDiskMap:      TAction;
    ActDiskInfo:     TAction;
    ActExit:         TAction;
    ActAbout:        TAction;
    ActDriveRead:    TAction;
    ActDriveWrite:   TAction;
    ActDriveInfo:    TAction;

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

    { LFM-wired list events — delegate to unified pane handlers. }
    procedure ListViewDSKDblClick(Sender: TObject);
    procedure ListViewHostDblClick(Sender: TObject);
    procedure ListViewDSKSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
    procedure ListViewDSKColumnClick(Sender: TObject; Column: TListColumn);
    procedure ListViewHostColumnClick(Sender: TObject; Column: TListColumn);
    procedure ListViewDSKDragOver(Sender, Source: TObject; X, Y: Integer;
      State: TDragState; var Accept: Boolean);
    procedure ListViewDSKDragDrop(Sender, Source: TObject; X, Y: Integer);
    procedure ListViewHostDragOver(Sender, Source: TObject; X, Y: Integer;
      State: TDragState; var Accept: Boolean);
    procedure ListViewHostDragDrop(Sender, Source: TObject; X, Y: Integer);

  private
    FPanes:           array[0..1] of TPane;
    ActSectorMap:     TAction;
    ActDiskPlatter:   TAction;
    FBreadcrumbPanel:  TPanel;
    FBreadcrumbPaths:  array of string;
    FPlatterDockPanel: TPanel;      { dock area; lives in host pane, hidden until used }
    FDockedPlatter:    TViewerForm; { non-nil while a platter is embedded here }

    { Every open selection-aware viewer (sector map, platter, disk map) is kept
      here.  DispatchSelectionChanged iterates this list — you cannot open a new
      viewer without going through TrackViewer, which is the single place that
      registers OnViewerClosed.  The pattern makes it structurally impossible to
      have a viewer that silently misses selection changes. }
    FTrackedViewers:  TList;

    procedure TrackViewer(AForm: TViewerForm);
    procedure ViewerClosed(Sender: TObject);
    procedure DispatchSelectionChanged(APane: TPane; Item: TListItem; Selected: Boolean);

    { Convenience accessors. }
    function  ActivePane: TPane;
    function  LeftPane: TPane;    { = FPanes[0] }
    function  RightPane: TPane;   { = FPanes[1] }
    function  DSKPane: TPane;     { pane with active DSK, preferring focused pane }
    function  HostPane: TPane;    { the sibling of DSKPane }

    { Column setup helpers — called once during FormCreate. }
    procedure AddListColumn(LV: TListView; const ACaption: string; AWidth: Integer);

    { Status / action state. }
    procedure UpdateStatusBar;
    procedure RefreshActionState;

    { Cross-pane operations. }
    procedure DoCopyDSKToHost;
    procedure DoCopyHostToDSK;
    procedure DoDeleteDSKSelection;
    procedure DoRenameDSKSelection;
    procedure DoUndeleteDSKSelection;
    procedure DoShowHexForSelection;

    { Single implementations for all pane list events. }
    procedure PaneDblClick(APane: TPane);
    procedure PaneColumnClick(APane: TPane; Column: TListColumn);
    procedure AnyPaneSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
    procedure AnyPaneKeyPress(Sender: TObject; var Key: Char);

    { Sort dialog — handles all pane modes. }
    procedure ShowSortDialog(APane: TPane);

    { Layout / keyboard. }
    procedure LayoutBottomBar(Sender: TObject);
    procedure FormKeyDownHandler(Sender: TObject; var Key: Word; Shift: TShiftState);

    { Extra actions not in LFM. }
    procedure ActSectorMapExecute(Sender: TObject);
    procedure ActDiskPlatterExecute(Sender: TObject);

    { Platter docking / undocking. }
    procedure PlatterDockRequested(Sender: TObject);
    procedure PlatterUndockBtnClick(Sender: TObject);
    function  HostPanePanel: TWinControl;

    { DSK list row colouring. }
    procedure DSKListCustomDrawItem(Sender: TCustomListView; Item: TListItem;
      State: TCustomDrawState; var DefaultDraw: Boolean);

    { Right-pane breadcrumb. }
    procedure UpdateBreadcrumb(const APath: string);
    procedure BreadcrumbClick(Sender: TObject);

  public
  end;

var
  MainForm: TMainForm;

implementation

{$R *.lfm}

{ ======================================================================= }
{ Shared sort algorithm                                                    }
{ ======================================================================= }

procedure SortHostEntryArray(var Arr: THostEntryArray;
                              Field: THostSortField; Asc, DirsFirst: Boolean);
var
  I, J: Integer;
  Tmp:  THostEntry;

  function Less(const A, B: THostEntry): Boolean;
  var DA, DB, Raw: Integer;
  begin
    if A.Kind = rkParent then Exit(True);
    if B.Kind = rkParent then Exit(False);
    if DirsFirst then
    begin
      DA := Ord(A.Kind <> rkHostDir);
      DB := Ord(B.Kind <> rkHostDir);
      if DA <> DB then Exit(DA < DB);
    end;
    Raw := 0;
    case Field of
      hsName: Raw := AnsiCompareText(A.Name, B.Name);
      hsSize: Raw := CompareValue(A.Size, B.Size);
      hsTime: Raw := CompareDateTime(A.Time, B.Time);
    end;
    if not Asc then Raw := -Raw;
    Result := Raw < 0;
  end;

begin
  for I := 1 to High(Arr) do
  begin
    J := I;
    while (J > 0) and Less(Arr[J], Arr[J - 1]) do
    begin
      Tmp := Arr[J]; Arr[J] := Arr[J - 1]; Arr[J - 1] := Tmp;
      Dec(J);
    end;
  end;
end;

{ ======================================================================= }
{ TPane                                                                    }
{ ======================================================================= }

constructor TPane.Create(AListView: TListView; APathLabel, ADetailsLbl: TLabel);
begin
  inherited Create;
  FListView   := AListView;
  FPathLabel  := APathLabel;
  FDetailsLbl := ADetailsLbl;
  FMode       := pmDir;
  FPath       := GetCurrentDir;
  FSortField  := hsName;
  FSortAsc    := True;
  FDirsFirst  := True;
  FDSKSortFld := fsName;
  FDSKSortAsc := True;
end;

destructor TPane.Destroy;
begin
  FFS   := nil;
  FDisk := nil;
  inherited;
end;

{ --- Directory scan ---------------------------------------------------- }

procedure TPane.ScanDir;
var
  SR: TSearchRec;
  N:  Integer;
begin
  SetLength(FEntries, 0);
  N := 0;

  if FPath <> '/' then
  begin
    SetLength(FEntries, N + 1);
    FEntries[N].Kind := rkParent;
    FEntries[N].Name := '..';
    FEntries[N].Size := 0;
    FEntries[N].Time := 0;
    Inc(N);
  end;

  if FindFirst(FPath + PathDelim + '*', faAnyFile, SR) = 0 then
  begin
    repeat
      if (SR.Name = '.') or (SR.Name = '..') then Continue;
      SetLength(FEntries, N + 1);
      if (SR.Attr and faDirectory) <> 0 then
        FEntries[N].Kind := rkHostDir
      else
        FEntries[N].Kind := rkHostFile;
      FEntries[N].Name := SR.Name;
      FEntries[N].Size := SR.Size;
      FEntries[N].Time := FileDateToDateTime(SR.Time);
      Inc(N);
    until FindNext(SR) <> 0;
    FindClose(SR);
  end;
end;

{ --- Directory render -------------------------------------------------- }

procedure TPane.RenderDir;
const
  DATE_FMT = 'yyyy-mm-dd hh:nn';
var
  I:    Integer;
  Item: TListItem;
  E:    THostEntry;
  WideColumns: Boolean;  { 5-column DSK layout vs 3-column host layout }
begin
  WideColumns := FListView.Columns.Count = 5;

  if WideColumns then
  begin
    { Repurpose CP/M headers for dir mode. }
    FListView.Columns[1].Caption := '';
    FListView.Columns[2].Caption := 'Size';
    FListView.Columns[3].Caption := 'Date';
    FListView.Columns[4].Caption := '';
  end;

  if FPathLabel <> nil then
    FPathLabel.Caption := FPath;

  FListView.Items.BeginUpdate;
  try
    FListView.Items.Clear;
    SetLength(FRowTags, Length(FEntries));

    for I := 0 to High(FEntries) do
    begin
      E := FEntries[I];
      Item := FListView.Items.Add;
      case E.Kind of
        rkParent:   Item.Caption := '..';
        rkHostDir:  Item.Caption := '<' + E.Name + '>';
        rkHostFile: Item.Caption := E.Name;
      else
        Item.Caption := E.Name;
      end;

      if WideColumns then
      begin
        Item.SubItems.Add('');   { Ext — blank in dir mode }
        if E.Kind = rkHostFile then
          Item.SubItems.Add(IntToStr(E.Size div 1024) + 'K')
        else
          Item.SubItems.Add('');
        if (E.Kind <> rkParent) and (E.Time <> 0) then
          Item.SubItems.Add(FormatDateTime(DATE_FMT, E.Time))
        else
          Item.SubItems.Add('');
        Item.SubItems.Add('');   { Attr — blank in dir mode }
      end
      else
      begin
        if E.Kind = rkHostFile then
          Item.SubItems.Add(IntToStr(E.Size))
        else
          Item.SubItems.Add('<DIR>');
        if E.Time <> 0 then
          Item.SubItems.Add(FormatDateTime(DATE_FMT, E.Time))
        else
          Item.SubItems.Add('');
      end;

      FRowTags[I] := TRowTag.Make(E.Kind, I);
    end;
  finally
    FListView.Items.EndUpdate;
  end;
end;

{ --- DSK render -------------------------------------------------------- }

procedure TPane.RenderDSK;
var
  I:     Integer;
  Item:  TListItem;
  VFile: IVirtualFile;
  Attr:  IAttributed;
  Flags: string;
begin
  { Restore CP/M column headers (may have been overwritten in dir mode). }
  if FListView.Columns.Count = 5 then
  begin
    FListView.Columns[1].Caption := 'Ext';
    FListView.Columns[2].Caption := 'Size';
    FListView.Columns[3].Caption := 'User';
    FListView.Columns[4].Caption := 'Attr';
  end;

  if FPathLabel <> nil then
    FPathLabel.Caption := 'DSK: ' + ExtractFileName(FDSKPath);

  FListView.Items.BeginUpdate;
  try
    FListView.Items.Clear;
    SetLength(FRowTags, 1 + FFS.GetFileCount);

    { ".." goes back to the directory browser. }
    Item := FListView.Items.Add;
    Item.Caption := '..';
    if FListView.Columns.Count = 5 then
    begin
      Item.SubItems.Add(''); Item.SubItems.Add('');
      Item.SubItems.Add(''); Item.SubItems.Add('');
    end
    else
    begin
      Item.SubItems.Add(''); Item.SubItems.Add('');
    end;
    FRowTags[0] := TRowTag.Make(rkParent);

    for I := 0 to FFS.GetFileCount - 1 do
    begin
      VFile := FFS.GetFile(I);
      Item  := FListView.Items.Add;
      Item.Caption := VFile.Name;

      if FListView.Columns.Count = 5 then
      begin
        Item.SubItems.Add(VFile.Extension);
        Item.SubItems.Add(IntToStr(VFile.SizeKB) + 'K');
        Item.SubItems.Add(IntToStr(VFile.User));
        Flags := '';
        if VFile.IsDeleted then Flags := 'DEL';
        if Supports(VFile, IAttributed, Attr) then
        begin
          if eaReadOnly in Attr.Attributes then
          begin if Flags <> '' then Flags := Flags + ' '; Flags := Flags + 'R/O'; end;
          if eaSystem in Attr.Attributes then
          begin if Flags <> '' then Flags := Flags + ' '; Flags := Flags + 'SYS'; end;
        end;
        Item.SubItems.Add(Flags);
      end
      else
      begin
        Item.SubItems.Add(IntToStr(VFile.SizeKB) + 'K');
        Item.SubItems.Add('');
      end;

      FRowTags[I + 1] := TRowTag.Make(rkDSKFile, I);
    end;
  finally
    FListView.Items.EndUpdate;
  end;
end;

{ --- Navigation -------------------------------------------------------- }

procedure TPane.NavigateTo(const APath: string);
begin
  if not DirectoryExists(APath) then Exit;
  FPath := ExcludeTrailingPathDelimiter(ExpandFileName(APath));
  if FPath = '' then FPath := '/';
  FMode := pmDir;
  Refresh;
end;

procedure TPane.OpenDSK(const APath: string);
begin
  if not FileExists(APath) then
  begin
    MessageDlg('File Not Found', 'DSK file not found: ' + APath, mtError, [mbOK], 0);
    Exit;
  end;

  { Remember the directory we came from so CloseDSK returns here. }
  FPath := ExcludeTrailingPathDelimiter(ExtractFileDir(APath));
  if FPath = '' then FPath := '/';

  try
    FFS   := nil;
    FDisk := nil;
    FDSKPath := APath;
    FDisk := TDiskBenderDSK.Create(FDSKPath);
    FDisk.Load;
    FFS := TDiskBenderCPM.Create(FDisk);
    FFS.ScanDirectory;
    FFS.SortFiles(FDSKSortFld, FDSKSortAsc);
    FMode := pmDSK;
    RenderDSK;
  except
    on E: Exception do
    begin
      MessageDlg('Load Error', 'Failed to load DSK: ' + E.Message, mtError, [mbOK], 0);
      FFS   := nil;
      FDisk := nil;
    end;
  end;
end;

procedure TPane.CloseDSK;
begin
  FFS   := nil;
  FDisk := nil;
  FDSKPath := '';
  FMode := pmDir;
  Refresh;
end;

procedure TPane.Refresh;
begin
  if FMode = pmDSK then
    RenderDSK
  else
  begin
    ScanDir;
    SortHostEntryArray(FEntries, FSortField, FSortAsc, FDirsFirst);
    RenderDir;
  end;
end;

{ --- Sorting ----------------------------------------------------------- }

procedure TPane.ApplyDirSort(Field: THostSortField);
begin
  if FSortField = Field then
    FSortAsc := not FSortAsc
  else
  begin
    FSortField := Field;
    FSortAsc   := True;
  end;
  if FMode = pmDir then Refresh;
end;

procedure TPane.ApplyDSKSort(Field: TFileSortField);
begin
  if FDSKSortFld = Field then
    FDSKSortAsc := not FDSKSortAsc
  else
  begin
    FDSKSortFld := Field;
    FDSKSortAsc := True;
  end;
  if (FMode = pmDSK) and (FFS <> nil) then
  begin
    FFS.SortFiles(FDSKSortFld, FDSKSortAsc);
    RenderDSK;
  end;
end;

procedure TPane.SetDirSort(Field: THostSortField; Asc, DirsFirst: Boolean);
begin
  FSortField := Field;
  FSortAsc   := Asc;
  FDirsFirst := DirsFirst;
  if FMode = pmDir then Refresh;
end;

procedure TPane.SetDSKSort(Field: TFileSortField; Asc: Boolean);
begin
  FDSKSortFld := Field;
  FDSKSortAsc := Asc;
  if (FMode = pmDSK) and (FFS <> nil) then
  begin
    FFS.SortFiles(FDSKSortFld, FDSKSortAsc);
    RenderDSK;
  end;
end;

{ --- Selection --------------------------------------------------------- }

function TPane.RowTag(Item: TListItem): TRowTag;
begin
  if (Item <> nil) and (Item.Index >= 0) and (Item.Index < Length(FRowTags)) then
    Result := FRowTags[Item.Index]
  else
    Result := TRowTag.Make(rkNone);
end;

function TPane.SelectedFileIdx: Integer;
var Rt: TRowTag;
begin
  Rt := RowTag(FListView.Selected);
  if Rt.Kind = rkDSKFile then Result := Rt.Index else Result := -1;
end;

{ --- Details ----------------------------------------------------------- }

procedure TPane.UpdateDetails(Item: TListItem; Selected: Boolean);
var
  Rt:      TRowTag;
  VFile:   IVirtualFile;
  E:       THostEntry;
  Details: string;
begin
  if FDetailsLbl = nil then Exit;

  Details := '';

  if Selected and (Item <> nil) then
  begin
    Rt := RowTag(Item);
    if FMode = pmDir then
    begin
      if (Rt.Index >= 0) and (Rt.Index < Length(FEntries)) then
      begin
        E := FEntries[Rt.Index];
        case E.Kind of
          rkParent:   Details := 'Parent directory';
          rkHostDir:  Details := 'Directory: ' + E.Name;
          rkHostFile: Details := E.Name + LineEnding +
                                 'Size: ' + IntToStr(E.Size) + ' bytes';
        end;
      end;
    end
    else { DSK mode }
    begin
      if Rt.Kind = rkParent then
        Details := 'Back to directory'
      else if Rt.Index >= 0 then
      begin
        VFile := FFS.GetFile(Rt.Index);
        if VFile <> nil then
        begin
          Details := 'Name: ' + VFile.Name + LineEnding;
          if VFile.Extension <> '' then
            Details := Details + 'Ext: ' + VFile.Extension + LineEnding;
          Details := Details + 'Size: ' + IntToStr(VFile.SizeKB) + ' KB' + LineEnding +
                               'User: ' + IntToStr(VFile.User);
          if VFile.IsDeleted then
            Details := Details + LineEnding + '[DELETED]';
        end;
      end;
    end;
  end;

  FDetailsLbl.Caption := Details;
  if FDetailsLbl.Parent <> nil then
    FDetailsLbl.Parent.Visible := Details <> '';
end;

{ ======================================================================= }
{ TMainForm                                                                }
{ ======================================================================= }

function TMainForm.LeftPane:  TPane; begin Result := FPanes[0]; end;
function TMainForm.RightPane: TPane; begin Result := FPanes[1]; end;

function TMainForm.ActivePane: TPane;
begin
  if FPanes[0].ListView.Focused then Exit(FPanes[0]);
  if FPanes[1].ListView.Focused then Exit(FPanes[1]);
  if FPanes[0].ListView.Selected <> nil then Exit(FPanes[0]);
  Result := FPanes[1];
end;

function TMainForm.DSKPane: TPane;
{ Returns the pane that has a DSK loaded, preferring the focused/active pane. }
begin
  if ActivePane.Mode = pmDSK then Exit(ActivePane);
  if FPanes[0].Mode = pmDSK then Exit(FPanes[0]);
  if FPanes[1].Mode = pmDSK then Exit(FPanes[1]);
  Result := FPanes[0];  { fallback — neither pane has a DSK }
end;

function TMainForm.HostPane: TPane;
{ Returns the sibling of DSKPane — the pane used as copy source/dest. }
begin
  Result := DSKPane.Other;
end;

{ -----------------------------------------------------------------------
  Selection-change dispatch — the single funnel for all selection events.
  Every open viewer is in FTrackedViewers; none can be missed.
----------------------------------------------------------------------- }

procedure TMainForm.TrackViewer(AForm: TViewerForm);
begin
  if AForm = nil then Exit;
  AForm.OnViewerClosed := @ViewerClosed;
  FTrackedViewers.Add(AForm);
end;

procedure TMainForm.ViewerClosed(Sender: TObject);
begin
  { Sender fires BEFORE caFree, so removing while the object is still valid. }
  FTrackedViewers.Remove(Sender);
end;

procedure TMainForm.DispatchSelectionChanged(APane: TPane; Item: TListItem; Selected: Boolean);
var
  AFileIdx:     Integer;
  OwnedSectors: TPhysicalSectorArray;
  Highlight:    TBlockNumberArray;
  I:            Integer;
begin
  { 1. Per-pane detail panel + action/status bar. }
  APane.UpdateDetails(Item, Selected);
  RefreshActionState;
  UpdateStatusBar;

  { 2. Compute ownership data only when a DSK file is actually selected.
     If the selection is in the host pane or nothing is selected, viewers
     receive nil arrays — their highlights clear automatically. }
  OwnedSectors := nil;
  Highlight    := nil;
  if APane.Mode = pmDSK then
  begin
    AFileIdx := APane.SelectedFileIdx;
    if (APane.FS <> nil) and (AFileIdx >= 0) then
    begin
      OwnedSectors := APane.FS.GetFileSectors(AFileIdx);
      Highlight    := APane.FS.GetFileBlocks(AFileIdx);
    end;
  end;

  { 3. Push to every tracked viewer — guaranteed complete by construction. }
  for I := 0 to FTrackedViewers.Count - 1 do
    TViewerForm(FTrackedViewers[I]).UpdateSelection(OwnedSectors, Highlight);
end;

{ -----------------------------------------------------------------------
  FormCreate / FormDestroy
----------------------------------------------------------------------- }

procedure TMainForm.FormCreate(Sender: TObject);
var
  I:           Integer;
  StartDir:    string;
  OpenDSKPath: string;
  DockHeader:  TPanel;
  DockTitle:   TLabel;
  UndockBtn:   TButton;
begin
  { Parse command-line arguments.
    Supported args (injected by LaunchGui via 'open --args'):
      --cwd <dir>   : start directory for both panes
      <path.dsk>    : DSK file to open in the left pane }
  StartDir    := GetCurrentDir;
  OpenDSKPath := '';
  I := 1;
  while I <= ParamCount do
  begin
    if (ParamStr(I) = '--cwd') and (I < ParamCount) then
    begin
      StartDir := ParamStr(I + 1);
      Inc(I, 2);
    end
    else if (Length(ParamStr(I)) > 0) and (ParamStr(I)[1] <> '-') then
    begin
      OpenDSKPath := ParamStr(I);  { first non-flag arg = DSK path }
      Inc(I);
    end
    else
      Inc(I);
  end;

  FTrackedViewers := TList.Create;

  { Platter dock panel — hidden, lives in the host pane.  When a platter is
    docked its FPB + FStatusLabel are re-parented here; on undock they go back.
    PlatterDockRequested re-assigns Parent if the active host pane differs. }
  FDockedPlatter               := nil;
  FPlatterDockPanel            := TPanel.Create(Self);
  FPlatterDockPanel.Parent     := PanelRight;
  FPlatterDockPanel.Align      := alClient;
  FPlatterDockPanel.Visible    := False;
  FPlatterDockPanel.BevelOuter := bvNone;
  FPlatterDockPanel.Color      := clWindow;

  DockHeader                   := TPanel.Create(FPlatterDockPanel);
  DockHeader.Parent            := FPlatterDockPanel;
  DockHeader.Align             := alTop;
  DockHeader.Height            := 28;
  DockHeader.BevelOuter        := bvNone;

  UndockBtn                    := TButton.Create(DockHeader);
  UndockBtn.Parent             := DockHeader;
  UndockBtn.Align              := alRight;
  UndockBtn.Width              := 80;
  UndockBtn.Caption            := '← Undock';
  UndockBtn.OnClick            := @PlatterUndockBtnClick;

  DockTitle                    := TLabel.Create(DockHeader);
  DockTitle.Parent             := DockHeader;
  DockTitle.Align              := alClient;
  DockTitle.Layout             := tlCenter;
  DockTitle.Caption            := 'Platter View';

  { Create the two panes.
    Left pane (index 0): LabelDSK as path label, LabelDetails for selection info.
    Right pane (index 1): no path label (breadcrumb replaces it), same details. }
  FPanes[0] := TPane.Create(ListViewDSK,  LabelDSK,  LabelDetails);
  FPanes[1] := TPane.Create(ListViewHost, nil,        LabelDetails);
  FPanes[0].Other := FPanes[1];
  FPanes[1].Other := FPanes[0];

  { Left pane: 5 columns (Name/Ext/Size/User/Attr) for DSK/CP/M mode.
    Right pane: 3 columns (Name/Size/Date) for host dir mode. }
  AddListColumn(ListViewDSK,  'Name', 180);
  AddListColumn(ListViewDSK,  'Ext',   60);
  AddListColumn(ListViewDSK,  'Size',  70);
  AddListColumn(ListViewDSK,  'User',  50);
  AddListColumn(ListViewDSK,  'Attr',  60);
  { Right pane gets the same 5-column structure — RenderDir/RenderDSK both
    handle the WideColumns = (Columns.Count = 5) layout. }
  AddListColumn(ListViewHost, 'Name', 180);
  AddListColumn(ListViewHost, 'Ext',   60);
  AddListColumn(ListViewHost, 'Size',  70);
  AddListColumn(ListViewHost, 'User',  50);
  AddListColumn(ListViewHost, 'Attr',  60);

  { Wire unified event handlers in code so LFM-wired stubs are overridden. }
  ListViewDSK.OnSelectItem  := @AnyPaneSelectItem;
  ListViewHost.OnSelectItem := @AnyPaneSelectItem;
  ListViewDSK.OnKeyPress    := @AnyPaneKeyPress;
  ListViewHost.OnKeyPress   := @AnyPaneKeyPress;
  ListViewDSK.OnCustomDrawItem  := @DSKListCustomDrawItem;
  ListViewHost.OnCustomDrawItem := @DSKListCustomDrawItem;

  { Breadcrumb: hide the static LabelHost and replace with a clickable panel. }
  LabelHost.Align   := alNone;
  LabelHost.Visible := False;
  FBreadcrumbPanel := TPanel.Create(Self);
  FBreadcrumbPanel.Parent     := PanelRight;
  FBreadcrumbPanel.Align      := alTop;
  FBreadcrumbPanel.Height     := 28;
  FBreadcrumbPanel.BevelOuter := bvNone;

  Self.KeyPreview  := True;
  Self.OnKeyDown   := @FormKeyDownHandler;
  PanelBottom.OnResize := @LayoutBottomBar;
  LayoutBottomBar(PanelBottom);

  { Extra view actions (not in LFM). }
  ActSectorMap := TAction.Create(Self);
  ActSectorMap.Caption   := 'Sector Map...';
  ActSectorMap.OnExecute := @ActSectorMapExecute;
  ActSectorMap.ActionList := ActionList;
  ActSectorMap.ShortCut  := ShortCut(VK_F3, [ssShift]);
  ActSectorMap.Enabled   := False;
  MenuView.Add(NewItem('Sector &Map...', ShortCut(VK_F3, [ssShift]),
                       False, True, @ActSectorMapExecute, 0, ''));

  ActDiskPlatter := TAction.Create(Self);
  ActDiskPlatter.Caption   := 'Platter View...';
  ActDiskPlatter.OnExecute := @ActDiskPlatterExecute;
  ActDiskPlatter.ActionList := ActionList;
  ActDiskPlatter.Enabled   := False;
  MenuView.Add(NewItem('&Platter View...', 0,
                       False, True, @ActDiskPlatterExecute, 0, ''));

  ActHexViewer.ShortCut  := VK_F3;
  ActDelete.ShortCut     := VK_F8;
  ActAbout.ShortCut      := VK_F1;
  MenuHexViewer.ShortCut := VK_F3;

  { Hide details panel until something is selected. }
  if LabelDetails.Parent <> nil then
    LabelDetails.Parent.Visible := False;

  { Navigate both panes to the start directory; fall back to home if missing. }
  if not DirectoryExists(StartDir) then
    StartDir := GetEnvironmentVariable('HOME');
  FPanes[0].NavigateTo(StartDir);
  FPanes[1].NavigateTo(StartDir);
  UpdateBreadcrumb(FPanes[1].Path);
  RefreshActionState;
  UpdateStatusBar;

  if OpenDSKPath <> '' then
    FPanes[0].OpenDSK(OpenDSKPath);
end;

procedure TMainForm.FormDestroy(Sender: TObject);
begin
  { Undock and close any embedded platter before the tracked-viewer list dies. }
  if FDockedPlatter <> nil then
  begin
    FDockedPlatter.Undock;
    FDockedPlatter.Close;
    FDockedPlatter := nil;
  end;
  FPanes[0].Free;
  FPanes[1].Free;
  FTrackedViewers.Free;
end;

procedure TMainForm.FormDropFiles(Sender: TObject; const FileNames: array of string);
begin
  if (Length(FileNames) > 0) and
     (LowerCase(ExtractFileExt(FileNames[0])) = '.dsk') then
  begin
    FPanes[0].OpenDSK(FileNames[0]);
    DispatchSelectionChanged(FPanes[0], nil, False);
  end;
  RefreshActionState;
  UpdateStatusBar;
end;

{ -----------------------------------------------------------------------
  Helpers
----------------------------------------------------------------------- }

procedure TMainForm.AddListColumn(LV: TListView; const ACaption: string; AWidth: Integer);
var Col: TListColumn;
begin
  Col := LV.Columns.Add;
  Col.Caption := ACaption;
  Col.Width   := AWidth;
end;

procedure TMainForm.UpdateStatusBar;
var
  DP:   TPane;
  Disk: IVirtualDisk;
  FS:   IFilesystem;
  State: string;
begin
  DP   := DSKPane;
  Disk := DP.Disk;
  FS   := DP.FS;
  if Disk <> nil then
  begin
    if Disk.Modified then State := 'Modified' else State := 'Saved';
    StatusBar.SimpleText := Format('Tracks: %d | Sides: %d | Files: %d | %s',
      [Disk.NumTracks, Disk.NumSides, FS.GetFileCount, State]);
  end
  else
    StatusBar.SimpleText := 'No disk loaded';
end;

procedure TMainForm.RefreshActionState;
var
  DP:         TPane;
  HP:         TPane;
  HasDisk:    Boolean;
  HasDSKSel:  Boolean;
  HasHostSel: Boolean;
  DSKFiled:   Integer;
begin
  DP        := DSKPane;
  HP        := DP.Other;
  HasDisk   := DP.Disk <> nil;
  DSKFiled  := DP.SelectedFileIdx;
  HasDSKSel := HasDisk and (DSKFiled >= 0);
  HasHostSel := (HP.ListView.Selected <> nil) and
                (HP.RowTag(HP.ListView.Selected).Kind = rkHostFile);

  ActSave.Enabled       := HasDisk and DP.Disk.Modified;
  ActCopyToHost.Enabled := HasDSKSel;
  ActCopyToDSK.Enabled  := HasDisk and HasHostSel;
  ActDelete.Enabled     := HasDSKSel;
  ActUndelete.Enabled   := HasDSKSel;
  ActHexViewer.Enabled  := HasDisk;
  ActDiskMap.Enabled    := HasDisk;
  ActDiskInfo.Enabled   := HasDisk;
  if Assigned(ActSectorMap)   then ActSectorMap.Enabled   := HasDisk;
  if Assigned(ActDiskPlatter) then ActDiskPlatter.Enabled := HasDisk;
end;

{ -----------------------------------------------------------------------
  Unified pane event handlers
----------------------------------------------------------------------- }

procedure TMainForm.AnyPaneSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
var I: Integer;
begin
  for I := 0 to 1 do
    if TObject(FPanes[I].ListView) = Sender then
    begin
      DispatchSelectionChanged(FPanes[I], Item, Selected);
      Break;
    end;
end;

procedure TMainForm.AnyPaneKeyPress(Sender: TObject; var Key: Char);
var
  I, J, Start, Idx: Integer;
  S, Cap: string;
  LV: TListView;
begin
  if Key < ' ' then Exit;
  S := LowerCase(Key);
  for I := 0 to 1 do
    if TObject(FPanes[I].ListView) = Sender then
    begin
      LV    := FPanes[I].ListView;
      Start := LV.ItemIndex;
      if Start < 0 then Start := 0;
      for Idx := 1 to LV.Items.Count do
      begin
        J := (Start + Idx) mod LV.Items.Count;
        Cap := LowerCase(LV.Items[J].Caption);
        if (Length(Cap) > 0) and (Cap[1] = S[1]) and (LV.Items[J].Caption <> '..') then
        begin
          LV.ItemIndex := J;
          LV.Items[J].MakeVisible(False);
          Key := #0;
          Break;
        end;
      end;
      Break;
    end;
end;

procedure TMainForm.PaneDblClick(APane: TPane);
var
  Item: TListItem;
  Rt:   TRowTag;
  E:    THostEntry;
begin
  Item := APane.ListView.Selected;
  if Item = nil then Exit;
  Rt := APane.RowTag(Item);

  if APane.Mode = pmDir then
  begin
    if (Rt.Index < 0) or (Rt.Index >= Length(APane.Entries)) then Exit;
    E := APane.Entries[Rt.Index];
    case Rt.Kind of
      rkParent:   APane.NavigateTo(
                    ExtractFileDir(ExcludeTrailingPathDelimiter(APane.Path)));
      rkHostDir:  APane.NavigateTo(APane.Path + PathDelim + E.Name);
      rkHostFile:
        begin
          if LowerCase(ExtractFileExt(E.Name)) = '.dsk' then
          begin
            APane.OpenDSK(APane.Path + PathDelim + E.Name);
            UpdateStatusBar;
            RefreshActionState;
            DispatchSelectionChanged(APane, nil, False);
          end;
          { Non-DSK files: do nothing for now. }
        end;
    end;
    { Update breadcrumb if this is the right pane. }
    if APane = FPanes[1] then
      UpdateBreadcrumb(APane.Path);
  end
  else { pmDSK }
  begin
    case Rt.Kind of
      rkParent:
        begin
          APane.CloseDSK;
          if APane = FPanes[1] then
            UpdateBreadcrumb(APane.Path);
          UpdateStatusBar;
          RefreshActionState;
          DispatchSelectionChanged(APane, nil, False);
        end;
      rkDSKFile: DoShowHexForSelection;
    end;
  end;
end;

procedure TMainForm.PaneColumnClick(APane: TPane; Column: TListColumn);
begin
  if APane.Mode = pmDir then
  begin
    case Column.Index of
      0: APane.ApplyDirSort(hsName);
      1: APane.ApplyDirSort(hsSize);  { col 1 = Size on right pane }
      2: if APane.ListView.Columns.Count = 5 then
           APane.ApplyDirSort(hsSize)   { col 2 = Size on left pane (wide) }
         else
           APane.ApplyDirSort(hsTime);  { col 2 = Date on right pane (narrow) }
      3: if APane.ListView.Columns.Count = 5 then
           APane.ApplyDirSort(hsTime);  { col 3 = Date on left pane (wide) }
    end;
  end
  else { pmDSK }
  begin
    case Column.Index of
      0: APane.ApplyDSKSort(fsName);
      1: APane.ApplyDSKSort(fsExt);
      2: APane.ApplyDSKSort(fsSize);
      3: APane.ApplyDSKSort(fsUser);
    end;
  end;
end;

{ --- LFM-wired stubs that delegate to unified handlers ---------------- }

procedure TMainForm.ListViewDSKDblClick(Sender: TObject);
begin PaneDblClick(FPanes[0]); end;

procedure TMainForm.ListViewHostDblClick(Sender: TObject);
begin
  PaneDblClick(FPanes[1]);
  UpdateBreadcrumb(FPanes[1].Path);
end;

procedure TMainForm.ListViewDSKSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
begin end; { overridden in FormCreate by AnyPaneSelectItem }

procedure TMainForm.ListViewDSKColumnClick(Sender: TObject; Column: TListColumn);
begin PaneColumnClick(FPanes[0], Column); end;

procedure TMainForm.ListViewHostColumnClick(Sender: TObject; Column: TListColumn);
begin PaneColumnClick(FPanes[1], Column); end;

{ -----------------------------------------------------------------------
  Sort dialog — single dialog for all panes and modes
----------------------------------------------------------------------- }

procedure TMainForm.ShowSortDialog(APane: TPane);
var
  F:            TForm;
  RG:           TRadioGroup;
  CBAsc, CBDir: TCheckBox;
  BtnOK, BtnCn: TButton;
  BtnRow:       Integer;
  IsDSK:        Boolean;
  Fld:          THostSortField;
begin
  IsDSK := APane.Mode = pmDSK;

  F := TForm.CreateNew(nil);
  try
    F.Caption      := 'Sort';
    F.Width        := 290;
    F.Position     := poScreenCenter;
    F.BorderStyle  := bsDialog;

    RG         := TRadioGroup.Create(F);
    RG.Parent  := F;
    RG.Caption := 'Sort by';
    RG.Left    := 12;
    RG.Top     := 12;
    RG.Width   := 256;

    if IsDSK then
    begin
      RG.Height := 130;
      RG.Items.Add('Name');
      RG.Items.Add('Extension');
      RG.Items.Add('Size');
      RG.Items.Add('User');
      case APane.DSKSortFld of
        fsName: RG.ItemIndex := 0;
        fsExt:  RG.ItemIndex := 1;
        fsSize: RG.ItemIndex := 2;
        fsUser: RG.ItemIndex := 3;
      end;
    end
    else
    begin
      RG.Height := 110;
      RG.Items.Add('Name');
      RG.Items.Add('Size');
      RG.Items.Add('Date');
      case APane.DirSortFld of
        hsName: RG.ItemIndex := 0;
        hsSize: RG.ItemIndex := 1;
        hsTime: RG.ItemIndex := 2;
      end;
    end;

    CBAsc        := TCheckBox.Create(F);
    CBAsc.Parent := F;
    CBAsc.Caption := 'Ascending';
    CBAsc.Left   := 16;
    CBAsc.Top    := RG.Top + RG.Height + 8;
    CBAsc.Width  := 200;
    CBAsc.Checked := IsDSK and APane.DSKSortAsc or
                     ((not IsDSK) and APane.DirSortAsc);

    CBDir        := TCheckBox.Create(F);
    CBDir.Parent := F;
    CBDir.Caption := 'Directories first';
    CBDir.Left   := 16;
    CBDir.Top    := CBAsc.Top + 24;
    CBDir.Width  := 200;
    CBDir.Checked := APane.DirDirsFirst;
    CBDir.Visible := not IsDSK;

    if not IsDSK then
      BtnRow := CBDir.Top + 30
    else
      BtnRow := CBAsc.Top + 30;
    F.Height := BtnRow + 56;

    BtnOK          := TButton.Create(F);
    BtnOK.Parent   := F;
    BtnOK.Caption  := 'OK';
    BtnOK.Left     := 88;
    BtnOK.Top      := BtnRow;
    BtnOK.Width    := 80;
    BtnOK.ModalResult := mrOK;
    BtnOK.Default  := True;

    BtnCn          := TButton.Create(F);
    BtnCn.Parent   := F;
    BtnCn.Caption  := 'Cancel';
    BtnCn.Left     := 178;
    BtnCn.Top      := BtnRow;
    BtnCn.Width    := 80;
    BtnCn.ModalResult := mrCancel;
    BtnCn.Cancel   := True;

    if F.ShowModal <> mrOK then Exit;

    if IsDSK then
    begin
      case RG.ItemIndex of
        0: APane.SetDSKSort(fsName, CBAsc.Checked);
        1: APane.SetDSKSort(fsExt,  CBAsc.Checked);
        2: APane.SetDSKSort(fsSize, CBAsc.Checked);
        3: APane.SetDSKSort(fsUser, CBAsc.Checked);
      end;
    end
    else
    begin
      Fld := hsName;
      case RG.ItemIndex of
        0: Fld := hsName;
        1: Fld := hsSize;
        else Fld := hsTime;
      end;
      APane.SetDirSort(Fld, CBAsc.Checked, CBDir.Checked);
    end;

    if APane = FPanes[1] then
      UpdateBreadcrumb(APane.Path);
  finally
    F.Free;
  end;
end;

{ -----------------------------------------------------------------------
  Cross-pane operations
----------------------------------------------------------------------- }

procedure TMainForm.DoCopyDSKToHost;
var
  LP:      TPane;   { pane with the DSK }
  RP:      TPane;   { destination dir pane }
  Idx:     Integer;
  OutPath: string;
  OutFile: TFileStream;
  VFile:   IVirtualFile;
begin
  LP := DSKPane;
  RP := LP.Other;
  if LP.FS = nil then Exit;
  Idx := LP.SelectedFileIdx;
  if Idx < 0 then Exit;

  VFile   := LP.FS.GetFile(Idx);
  OutPath := RP.Path + PathDelim + VFile.Name;
  if VFile.Extension <> '' then
    OutPath := OutPath + '.' + VFile.Extension;

  try
    OutFile := TFileStream.Create(OutPath, fmCreate);
    try
      LP.FS.GetFileContent(Idx, OutFile);
    finally
      OutFile.Free;
    end;
    RP.Refresh;
    UpdateBreadcrumb(RP.Path);
    ShowMessage('Extracted: ' + OutPath);
  except
    on Ex: Exception do
      MessageDlg('Extract Error', Ex.Message, mtError, [mbOK], 0);
  end;
end;

procedure TMainForm.DoCopyHostToDSK;
var
  LP:      TPane;   { pane with the DSK }
  RP:      TPane;   { source dir pane }
  Item:    TListItem;
  Rt:      TRowTag;
  E:       THostEntry;
  InPath:  string;
  InFile:  TFileStream;
  Data:    TBytes;
  NOnly, Ext: string;
  NewIdx:  Integer;
begin
  LP := DSKPane;
  RP := LP.Other;
  if LP.FS = nil then Exit;

  Item := RP.ListView.Selected;
  Rt   := RP.RowTag(Item);
  if Rt.Kind <> rkHostFile then
  begin
    ShowMessage('Select a file in the host pane first');
    Exit;
  end;
  E      := RP.Entries[Rt.Index];
  InPath := RP.Path + PathDelim + E.Name;
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

    NOnly := ChangeFileExt(E.Name, '');
    Ext   := UpperCase(ExtractFileExt(E.Name));
    if Length(Ext) > 0 then Ext := Copy(Ext, 2, MaxInt);

    NewIdx := LP.FS.AddFile(NOnly, Ext, Data, 0);
    if NewIdx < 0 then
    begin
      MessageDlg('Copy Error',
        'Could not add file. Name invalid or directory full.',
        mtError, [mbOK], 0);
      Exit;
    end;

    LP.FS.SortFiles(LP.DSKSortFld, LP.DSKSortAsc);
    LP.Refresh;
    UpdateStatusBar;
    RefreshActionState;
  except
    on Ex: Exception do
      MessageDlg('Copy Error', Ex.Message, mtError, [mbOK], 0);
  end;
end;

procedure TMainForm.DoDeleteDSKSelection;
var LP: TPane; Idx: Integer;
begin
  LP := DSKPane;
  if LP.FS = nil then Exit;
  Idx := LP.SelectedFileIdx;
  if Idx < 0 then Exit;
  LP.FS.ToggleDelete(Idx);
  LP.Refresh;
  UpdateStatusBar;
  RefreshActionState;
end;

procedure TMainForm.DoRenameDSKSelection;
var LP: TPane; Idx: Integer; VFile: IVirtualFile; NewName: string;
begin
  LP := DSKPane;
  if LP.FS = nil then Exit;
  Idx := LP.SelectedFileIdx;
  if Idx < 0 then Exit;
  VFile := LP.FS.GetFile(Idx);
  NewName := VFile.Name;
  if VFile.Extension <> '' then NewName := NewName + '.' + VFile.Extension;
  if not InputQuery('Rename File', 'New name (8.3):', NewName) then Exit;
  try
    LP.FS.RenameFile(Idx, NewName);
    LP.FS.SortFiles(LP.DSKSortFld, LP.DSKSortAsc);
    LP.Refresh;
  except
    on E: Exception do
      MessageDlg('Rename Error', E.Message, mtError, [mbOK], 0);
  end;
end;

procedure TMainForm.DoUndeleteDSKSelection;
var LP: TPane; Idx: Integer; VFile: IVirtualFile; FirstChar: string;
begin
  LP := DSKPane;
  if LP.FS = nil then Exit;
  Idx := LP.SelectedFileIdx;
  if Idx < 0 then Exit;
  VFile := LP.FS.GetFile(Idx);
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
    LP.FS.UndeleteFile(Idx, FirstChar[1]);
    LP.Refresh;
    UpdateStatusBar;
  except
    on E: Exception do
      MessageDlg('Undelete Error', E.Message, mtError, [mbOK], 0);
  end;
end;

procedure TMainForm.DoShowHexForSelection;
var LP: TPane; Idx: Integer; VFile: IVirtualFile; Stream: TMemoryStream; Buf: TBytes;
begin
  LP := DSKPane;
  if LP.FS = nil then Exit;
  Idx := LP.SelectedFileIdx;
  if Idx < 0 then
  begin
    ShowMessage('Select a file to view.');
    Exit;
  end;
  VFile  := LP.FS.GetFile(Idx);
  Stream := TMemoryStream.Create;
  try
    LP.FS.GetFileContent(Idx, Stream);
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

{ -----------------------------------------------------------------------
  Actions wired in the LFM
----------------------------------------------------------------------- }

procedure TMainForm.ActOpenExecute(Sender: TObject);
begin
  if OpenDialog.Execute then
  begin
    FPanes[0].OpenDSK(OpenDialog.FileName);
    RefreshActionState;
    UpdateStatusBar;
    DispatchSelectionChanged(FPanes[0], nil, False);
  end;
end;

procedure TMainForm.ActSaveExecute(Sender: TObject);
var D: IVirtualDisk;
begin
  D := DSKPane.Disk;
  if D <> nil then
  begin
    D.Save;
    UpdateStatusBar;
    RefreshActionState;
  end;
end;

procedure TMainForm.ActCopyToDSKExecute(Sender: TObject);
begin DoCopyHostToDSK; end;

procedure TMainForm.ActCopyToHostExecute(Sender: TObject);
begin DoCopyDSKToHost; end;

procedure TMainForm.ActDeleteExecute(Sender: TObject);
begin DoDeleteDSKSelection; end;

procedure TMainForm.ActUndeleteExecute(Sender: TObject);
begin DoUndeleteDSKSelection; end;

procedure TMainForm.ActHexViewerExecute(Sender: TObject);
begin DoShowHexForSelection; end;

procedure TMainForm.ActDiskMapExecute(Sender: TObject);
var
  DP:        TPane;
  Map:       TBytes;
  Highlight: TBlockNumberArray;
  Idx:       Integer;
begin
  DP := DSKPane;
  if DP.FS = nil then Exit;
  Map       := DP.FS.GetBlockMap;
  Highlight := nil;
  Idx       := DP.SelectedFileIdx;
  if Idx >= 0 then
    Highlight := DP.FS.GetFileBlocks(Idx);
  TrackViewer(ShowDiskMap('Disk Block Map', Map, 32, Highlight));
end;

procedure TMainForm.ActDiskInfoExecute(Sender: TObject);
var
  DP:   TPane;
  Info: string;
begin
  DP := DSKPane;
  if DP.Disk = nil then Exit;
  Info := TDiskFormatter.FormatDiskInfo(DP.Disk, ofTable) + LineEnding +
          DP.FS.GetSummaryInfo + LineEnding + LineEnding +
          'Files: ' + IntToStr(DP.FS.GetFileCount);
  ShowTextViewer('Disk Information', Info);
end;

procedure TMainForm.ActExitExecute(Sender: TObject);
begin Close; end;

procedure TMainForm.ActAboutExecute(Sender: TObject);
begin
  MessageDlg('About DiskBender',
    'DiskBender — Vintage Disk / Snapshot Management' + LineEnding + LineEnding +
    'Supports CPC DSK images with CP/M filesystem.' + LineEnding + LineEnding +
    'Built with Free Pascal and Lazarus LCL.',
    mtInformation, [mbOK], 0);
end;

procedure TMainForm.ActSectorMapExecute(Sender: TObject);
var
  DP:     TPane;
  Tracks: TTrackColumnArray;
  Owned:  TPhysicalSectorArray;
  Idx:    Integer;
begin
  DP := DSKPane;
  if (DP.Disk = nil) or (DP.FS = nil) then Exit;
  Tracks := ComputeDiskSectorMap(DP.Disk, DP.FS);
  Owned  := nil;
  Idx    := DP.SelectedFileIdx;
  if Idx >= 0 then Owned := DP.FS.GetFileSectors(Idx);
  TrackViewer(ShowSectorMap('Sector Map — ' + ExtractFileName(DP.DSKPath), Tracks, Owned));
end;

procedure TMainForm.ActDiskPlatterExecute(Sender: TObject);
var
  DP:     TPane;
  Tracks: TTrackColumnArray;
  Owned:  TPhysicalSectorArray;
  Idx:    Integer;
  V:      TViewerForm;
begin
  DP := DSKPane;
  if (DP.Disk = nil) or (DP.FS = nil) then Exit;
  Tracks := ComputeDiskSectorMap(DP.Disk, DP.FS);
  Owned  := nil;
  Idx    := DP.SelectedFileIdx;
  if Idx >= 0 then Owned := DP.FS.GetFileSectors(Idx);
  V := ShowDiskPlatter('Platter View — ' + ExtractFileName(DP.DSKPath),
                       Tracks, Owned, DP.Disk);
  V.OnDockRequest := @PlatterDockRequested;
  TrackViewer(V);
  V.Show;
end;

{ -----------------------------------------------------------------------
  Platter docking
----------------------------------------------------------------------- }

function TMainForm.HostPanePanel: TWinControl;
begin
  { Return the LCL TPanel that wraps the host (non-DSK) pane's list view. }
  if HostPane = FPanes[0] then Result := PanelLeft
  else Result := PanelRight;
end;

procedure TMainForm.PlatterDockRequested(Sender: TObject);
var TargetPanel: TWinControl;
begin
  if FDockedPlatter <> nil then Exit;  { already something docked }
  FDockedPlatter := TViewerForm(Sender);
  TargetPanel    := HostPanePanel;
  { Move dock panel to the correct host-side panel if needed. }
  if FPlatterDockPanel.Parent <> TargetPanel then
    FPlatterDockPanel.Parent := TargetPanel;
  { Hide the list view so alClient fills correctly, show dock panel instead. }
  HostPane.ListView.Visible := False;
  FPlatterDockPanel.Visible := True;
  { Re-parents FPB + FStatusLabel into FPlatterDockPanel, hides floating form. }
  FDockedPlatter.DockTo(FPlatterDockPanel);
end;

procedure TMainForm.PlatterUndockBtnClick(Sender: TObject);
begin
  if FDockedPlatter = nil then Exit;
  FDockedPlatter.Undock;              { re-parents controls back, shows form }
  FDockedPlatter            := nil;
  FPlatterDockPanel.Visible := False;
  HostPane.ListView.Visible := True;
end;

{ -----------------------------------------------------------------------
  Window menu
----------------------------------------------------------------------- }

procedure TMainForm.MenuMinimizeClick(Sender: TObject);
begin Application.Minimize; end;

{ -----------------------------------------------------------------------
  Bottom bar layout
----------------------------------------------------------------------- }

procedure TMainForm.LayoutBottomBar(Sender: TObject);
const N = 10;
var
  Btns: array[0..N - 1] of TButton;
  W, H, I: Integer;
begin
  Btns[0] := BtnF1Help;   Btns[1] := BtnF2Rename;
  Btns[2] := BtnF3View;   Btns[3] := BtnF4Edit;
  Btns[4] := BtnF5Copy;   Btns[5] := BtnF6Move;
  Btns[6] := BtnF7NewDir; Btns[7] := BtnF8Delete;
  Btns[8] := BtnF9Menu;   Btns[9] := BtnF10Quit;

  W := PanelBottom.ClientWidth div N;
  H := PanelBottom.ClientHeight;
  for I := 0 to N - 1 do
    Btns[I].SetBounds(I * W, 0, W, H);
end;

{ -----------------------------------------------------------------------
  Norton-style F-key button handlers
----------------------------------------------------------------------- }

procedure TMainForm.BtnF1HelpClick(Sender: TObject);
begin ActAboutExecute(Sender); end;

procedure TMainForm.BtnF2RenameClick(Sender: TObject);
begin
  if ActivePane.Mode = pmDSK then
    DoRenameDSKSelection
  else
    ShowMessage('Host rename: Use the Finder to rename files on the host system.');
end;

procedure TMainForm.BtnF3ViewClick(Sender: TObject);
var AP: TPane;
begin
  AP := ActivePane;
  if AP.Mode = pmDSK then
    DoShowHexForSelection
  else if (AP.ListView.Selected <> nil) and
          (AP.RowTag(AP.ListView.Selected).Kind = rkHostFile) then
    ShowMessage('Host file view is not yet implemented (hex viewer for DSK files only).');
end;

procedure TMainForm.BtnF4EditClick(Sender: TObject);
begin BtnF3ViewClick(Sender); end;

procedure TMainForm.BtnF5CopyClick(Sender: TObject);
begin
  if ActivePane = FPanes[0] then
    DoCopyDSKToHost
  else
    DoCopyHostToDSK;
end;

procedure TMainForm.BtnF6MoveClick(Sender: TObject);
begin
  ShowMessage('Move: not yet implemented.');
end;

procedure TMainForm.BtnF7NewDirClick(Sender: TObject);
var NewDir: string;
begin
  NewDir := '';
  if not InputQuery('New Directory', 'Directory name:', NewDir) then Exit;
  if NewDir = '' then Exit;
  NewDir := FPanes[1].Path + PathDelim + NewDir;
  if not CreateDir(NewDir) then
    MessageDlg('Error', 'Could not create directory: ' + NewDir, mtError, [mbOK], 0)
  else
  begin
    FPanes[1].Refresh;
    UpdateBreadcrumb(FPanes[1].Path);
  end;
end;

procedure TMainForm.BtnF8DeleteClick(Sender: TObject);
begin
  if ActivePane.Mode = pmDSK then
    DoDeleteDSKSelection
  else
    ShowMessage('Host delete: Use Finder to delete files on host.');
end;

procedure TMainForm.BtnF9MenuClick(Sender: TObject);
begin ShowSortDialog(ActivePane); end;

procedure TMainForm.BtnF10QuitClick(Sender: TObject);
begin Close; end;

{ -----------------------------------------------------------------------
  Global keyboard handler
----------------------------------------------------------------------- }

procedure TMainForm.FormKeyDownHandler(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  case Key of
    VK_RETURN:
      begin
        if FPanes[0].ListView.Focused then ListViewDSKDblClick(Sender)
        else if FPanes[1].ListView.Focused then ListViewHostDblClick(Sender);
        Key := 0;
      end;
    VK_F1:  begin BtnF1HelpClick(Sender);   Key := 0; end;
    VK_F2:  begin BtnF2RenameClick(Sender); Key := 0; end;
    VK_F3:
      begin
        if ssShift in Shift then
          ActSectorMapExecute(Sender)
        else
          BtnF3ViewClick(Sender);
        Key := 0;
      end;
    VK_F4:  begin BtnF4EditClick(Sender);   Key := 0; end;
    VK_F5:  begin BtnF5CopyClick(Sender);   Key := 0; end;
    VK_F6:  begin BtnF6MoveClick(Sender);   Key := 0; end;
    VK_F7:  begin BtnF7NewDirClick(Sender); Key := 0; end;
    VK_F8:  begin BtnF8DeleteClick(Sender); Key := 0; end;
    VK_F9:  begin BtnF9MenuClick(Sender);   Key := 0; end;
    VK_F10: begin BtnF10QuitClick(Sender);  Key := 0; end;
  end;
end;

{ -----------------------------------------------------------------------
  Drag and drop
----------------------------------------------------------------------- }

{ Drag-and-drop: find source and destination panes generically.
  Drag from a DSK pane to a dir pane → CopyDSKToHost.
  Drag from a dir pane to a DSK pane → CopyHostToDSK. }

function PaneForListView(const Panes: array of TPane; AListView: TObject): TPane;
var I: Integer;
begin
  for I := 0 to High(Panes) do
    if TObject(Panes[I].ListView) = AListView then Exit(Panes[I]);
  Result := nil;
end;

procedure TMainForm.ListViewDSKDragOver(Sender, Source: TObject;
  X, Y: Integer; State: TDragState; var Accept: Boolean);
var
  DestPane, SrcPane: TPane;
begin
  DestPane := PaneForListView(FPanes, Sender);
  SrcPane  := PaneForListView(FPanes, Source);
  Accept := (DestPane <> nil) and (SrcPane <> nil) and (DestPane <> SrcPane) and
            (DestPane.Disk <> nil) and
            (SrcPane.ListView.Selected <> nil) and
            (SrcPane.RowTag(SrcPane.ListView.Selected).Kind = rkHostFile);
end;

procedure TMainForm.ListViewDSKDragDrop(Sender, Source: TObject; X, Y: Integer);
var
  SrcPane: TPane;
begin
  SrcPane := PaneForListView(FPanes, Source);
  if (SrcPane <> nil) and (SrcPane.Mode = pmDir) then DoCopyHostToDSK;
end;

procedure TMainForm.ListViewHostDragOver(Sender, Source: TObject;
  X, Y: Integer; State: TDragState; var Accept: Boolean);
var
  DestPane, SrcPane: TPane;
begin
  DestPane := PaneForListView(FPanes, Sender);
  SrcPane  := PaneForListView(FPanes, Source);
  Accept := (DestPane <> nil) and (SrcPane <> nil) and (DestPane <> SrcPane) and
            (SrcPane.SelectedFileIdx >= 0);
end;

procedure TMainForm.ListViewHostDragDrop(Sender, Source: TObject; X, Y: Integer);
var
  SrcPane: TPane;
begin
  SrcPane := PaneForListView(FPanes, Source);
  if (SrcPane <> nil) and (SrcPane.Mode = pmDSK) then DoCopyDSKToHost;
end;

{ -----------------------------------------------------------------------
  Greaseweazle drive actions
----------------------------------------------------------------------- }

procedure TMainForm.ActDriveReadExecute(Sender: TObject);
var GwPath, ImagePath: string;
begin
  GwPath := FindGwExecutable;
  if GwPath = '' then
  begin
    MessageDlg('Greaseweazle Not Found', GW_NOT_FOUND_HINT, mtError, [mbOK], 0);
    Exit;
  end;
  if ShowGWReadDialog(GwPath, ImagePath) then
    if MessageDlg('Open Image?', 'Open the new image in the DSK pane?',
                  mtConfirmation, [mbYes, mbNo], 0) = mrYes then
    begin
      FPanes[0].OpenDSK(ImagePath);
      RefreshActionState;
      UpdateStatusBar;
      DispatchSelectionChanged(FPanes[0], nil, False);
    end;
end;

procedure TMainForm.ActDriveWriteExecute(Sender: TObject);
var
  DP:     TPane;
  GwPath: string;
  D:      IVirtualDisk;
begin
  DP := DSKPane;
  D  := DP.Disk;
  if D = nil then
  begin
    MessageDlg('No Disc Image', 'No DSK image is loaded.', mtError, [mbOK], 0);
    Exit;
  end;
  GwPath := FindGwExecutable;
  if GwPath = '' then
  begin
    MessageDlg('Greaseweazle Not Found', GW_NOT_FOUND_HINT, mtError, [mbOK], 0);
    Exit;
  end;
  if D.Modified then
    case MessageDlg('Unsaved Changes',
      'The DSK has unsaved changes. Save before writing to hardware?',
      mtConfirmation, [mbYes, mbNo, mbCancel], 0) of
      mrCancel: Exit;
      mrYes:    D.Save;
    end;
  ShowGWWriteDialog(GwPath, DP.DSKPath);
end;

procedure TMainForm.ActDriveInfoExecute(Sender: TObject);
var GwPath, Log: string;
begin
  GwPath := FindGwExecutable;
  if GwPath = '' then
  begin
    MessageDlg('Greaseweazle Not Found', GW_NOT_FOUND_HINT, mtError, [mbOK], 0);
    Exit;
  end;
  if not GwDriveInfo(GwPath, Log) then
  begin
    MessageDlg('Drive Info Failed', 'gw info failed:' + LineEnding + Log, mtError, [mbOK], 0);
    Exit;
  end;
  ShowTextViewer('Greaseweazle Drive Info', Log);
end;

{ -----------------------------------------------------------------------
  DSK list row colouring
----------------------------------------------------------------------- }

procedure TMainForm.DSKListCustomDrawItem(Sender: TCustomListView;
  Item: TListItem; State: TCustomDrawState; var DefaultDraw: Boolean);
var
  Rt:   TRowTag;
  VFile: IVirtualFile;
  Pane: TPane;
  I:    Integer;
begin
  DefaultDraw := True;
  Pane := nil;
  for I := 0 to 1 do
    if TObject(FPanes[I].ListView) = TObject(Sender) then
    begin
      Pane := FPanes[I];
      Break;
    end;
  if (Pane = nil) or (Pane.FS = nil) or (Item = nil) then Exit;
  Rt := Pane.RowTag(Item);
  if Rt.Kind <> rkDSKFile then Exit;
  VFile := Pane.FS.GetFile(Rt.Index);
  if (VFile <> nil) and VFile.IsDeleted then
    Sender.Canvas.Font.Color := $004040C0;
end;

{ -----------------------------------------------------------------------
  Right-pane breadcrumb
----------------------------------------------------------------------- }

procedure TMainForm.UpdateBreadcrumb(const APath: string);
var
  Segs:     array of string;
  N, I, X, P, SegStart: Integer;
  Prefix:   string;
  L, Sep:   TLabel;
  BMP:      TBitmap;
  TW:       Integer;
  IsLast:   Boolean;
begin
  if FBreadcrumbPanel = nil then Exit;

  for I := FBreadcrumbPanel.ControlCount - 1 downto 0 do
    FBreadcrumbPanel.Controls[I].Free;
  SetLength(FBreadcrumbPaths, 0);

  N := 0;
  SetLength(Segs, 64);
  Segs[N] := '/'; Inc(N);
  SegStart := 2;
  for P := 2 to Length(APath) do
  begin
    if APath[P] = PathDelim then
    begin
      if P > SegStart then
      begin
        Segs[N] := Copy(APath, SegStart, P - SegStart); Inc(N);
      end;
      SegStart := P + 1;
    end;
  end;
  if SegStart <= Length(APath) then
  begin
    Segs[N] := Copy(APath, SegStart, MaxInt); Inc(N);
  end;
  SetLength(Segs, N);

  SetLength(FBreadcrumbPaths, N);
  FBreadcrumbPaths[0] := '/';
  Prefix := '';
  for I := 1 to N - 1 do
  begin
    Prefix := Prefix + '/' + Segs[I];
    FBreadcrumbPaths[I] := Prefix;
  end;

  BMP := TBitmap.Create;
  try
    BMP.Canvas.Font.Name := FBreadcrumbPanel.Font.Name;
    BMP.Canvas.Font.Size := FBreadcrumbPanel.Font.Size;
    X := 6;
    for I := 0 to N - 1 do
    begin
      IsLast := (I = N - 1);
      TW := BMP.Canvas.TextWidth(Segs[I]) + 4;

      L := TLabel.Create(FBreadcrumbPanel);
      L.Parent    := FBreadcrumbPanel;
      L.AutoSize  := False;
      L.SetBounds(X, 6, TW, 16);
      L.Caption   := Segs[I];
      L.Tag       := I;
      if IsLast then
      begin
        L.Font.Style := [fsBold];
        L.Font.Color := clWindowText;
      end
      else
      begin
        L.Cursor := crHandPoint;
        if (ColorToRGB(clWindow) and $FF) +
           ((ColorToRGB(clWindow) shr 8) and $FF) +
           ((ColorToRGB(clWindow) shr 16) and $FF) < 384 then
          L.Font.Color := $000080FF
        else
          L.Font.Color := clBlue;
        L.Font.Style := [fsUnderline];
        L.OnClick    := @BreadcrumbClick;
      end;
      Inc(X, TW + 2);

      if not IsLast then
      begin
        TW  := BMP.Canvas.TextWidth(' › ') + 2;
        Sep := TLabel.Create(FBreadcrumbPanel);
        Sep.Parent    := FBreadcrumbPanel;
        Sep.AutoSize  := False;
        Sep.SetBounds(X, 6, TW, 16);
        Sep.Caption   := '›';
        Sep.Font.Color := clGrayText;
        Inc(X, TW + 2);
      end;
    end;
  finally
    BMP.Free;
  end;
end;

procedure TMainForm.BreadcrumbClick(Sender: TObject);
var Idx: Integer;
begin
  if Sender is TLabel then
  begin
    Idx := TLabel(Sender).Tag;
    if (Idx >= 0) and (Idx < Length(FBreadcrumbPaths)) then
    begin
      FPanes[1].NavigateTo(FBreadcrumbPaths[Idx]);
      UpdateBreadcrumb(FPanes[1].Path);
    end;
  end;
end;

end.
