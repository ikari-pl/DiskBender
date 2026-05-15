unit uConfig;

{ DiskBender persistent configuration. Encodes to / decodes from the
  proto3 wire format defined in proto/diskbender_config.proto using the
  hand-rolled uPbWire codec.

  Field numbers in this unit MUST match the .proto file. Renames are safe;
  number changes are not (mark the old number `reserved` if you need to
  reuse it).

  Stored as plain integers and strings -- TUI-side enums (TPaneRole,
  TListMode) are kept out of this unit on purpose so persistence stays
  framework-agnostic. The controller does Ord()/Cast() at the boundary. }

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, uVFS, uPbWire;

const
  CONFIG_SCHEMA_VERSION = 1;

  { ListMode tags -- mirror TListMode in uTUIController.pas. }
  CFG_LM_BRIEF = 0;
  CFG_LM_FULL  = 1;
  CFG_LM_WIDE  = 2;

  { PaneRole tags -- mirror TPaneRole in uTUIController.pas. }
  CFG_ROLE_LIST        = 0;
  CFG_ROLE_INFO        = 1;
  CFG_ROLE_QUICK_VIEW  = 2;
  CFG_ROLE_SECTOR_MAP  = 3;
  CFG_ROLE_BLOCK_MAP   = 4;
  CFG_ROLE_TREE        = 5;

  { Field numbers (PaneConfig). Keep stable across releases. }
  PB_PANE_LIST_MODE       = 1;
  PB_PANE_ROLE            = 2;
  PB_PANE_SORT_FIELD      = 3;
  PB_PANE_SORT_ASCENDING  = 4;
  PB_PANE_DIRS_FIRST      = 5;
  PB_PANE_DATE_KIND       = 6;
  PB_PANE_GLOB            = 7;
  PB_PANE_SHOW_DELETED    = 8;
  PB_PANE_SHOW_HIDDEN     = 9;
  PB_PANE_SHOW_GUARDS     = 10;
  PB_PANE_USER_AREA       = 11;
  PB_PANE_TREE_EXPANDED   = 12;
  PB_PANE_CURSOR          = 13;
  PB_PANE_SCROLL          = 14;
  PB_PANE_LAST_PATH       = 15;

  { Field numbers (Config). }
  PB_CONFIG_SCHEMA_VERSION = 1;
  PB_CONFIG_LEFT           = 2;
  PB_CONFIG_RIGHT          = 3;

type
  TPaneConfig = record
    ListMode:      Integer;        { CFG_LM_*  }
    Role:          Integer;        { CFG_ROLE_* }
    SortField:     Integer;        { Ord(TSortField) }
    SortAscending: Boolean;
    DirsFirst:     Boolean;
    DateKind:      Integer;        { Ord(TDateKind) }
    Glob:          string;
    ShowDeleted:   Boolean;
    ShowHidden:    Boolean;
    ShowGuards:    Boolean;
    UserArea:      Integer;        { -1 = all }
    TreeExpanded:  array of string;
    Cursor:        Integer;
    Scroll:        Integer;
    LastPath:      string;
  end;

  TDiskBenderConfig = record
    SchemaVersion: Cardinal;
    Left:          TPaneConfig;
    Right:         TPaneConfig;
  end;

{ Construct the default (fresh-install) config. }
function DefaultConfig: TDiskBenderConfig;
function DefaultPaneConfig: TPaneConfig;

{ Encode a config to its proto3 wire-format bytes. }
function EncodeConfig(const ACfg: TDiskBenderConfig): TBytes;

{ Decode a config from proto3 wire-format bytes. Initialises Result with
  defaults first so missing fields keep their default value -- standard
  proto3 semantics. On malformed input raises EPbError; callers should
  trap it and fall back to DefaultConfig. }
function DecodeConfig(const ABytes: TBytes): TDiskBenderConfig;

{ Load / save against a filesystem path. SaveConfig writes atomically
  (write to .tmp then rename) so a crash mid-write leaves the previous
  file intact. LoadConfig returns DefaultConfig when the file is missing
  or unreadable. }
function LoadConfig(const APath: string): TDiskBenderConfig;
procedure SaveConfig(const APath: string; const ACfg: TDiskBenderConfig);

{ Returns the platform-appropriate config path:
    macOS:  ~/Library/Application Support/DiskBender/config.pb
    Linux:  ${XDG_CONFIG_HOME:-~/.config}/DiskBender/config.pb }
function DefaultConfigPath: string;

{ Human-readable proto3-text-ish dump for debugging. Binary configs are
  opaque otherwise; this gives the user a way to inspect what is being
  persisted without parsing the wire format manually. }
function DumpConfigAsText(const ACfg: TDiskBenderConfig): string;

implementation

function DefaultPaneConfig: TPaneConfig;
begin
  Result.ListMode      := CFG_LM_FULL;
  Result.Role          := CFG_ROLE_LIST;
  Result.SortField     := Ord(sfName);
  Result.SortAscending := True;
  Result.DirsFirst     := True;
  Result.DateKind      := Ord(dkModification);
  Result.Glob          := '';
  Result.ShowDeleted   := False;
  Result.ShowHidden    := False;
  Result.ShowGuards    := True;
  Result.UserArea      := -1;
  SetLength(Result.TreeExpanded, 0);
  Result.Cursor        := 0;
  Result.Scroll        := 0;
  Result.LastPath      := '';
end;

function DefaultConfig: TDiskBenderConfig;
begin
  Result.SchemaVersion := CONFIG_SCHEMA_VERSION;
  Result.Left  := DefaultPaneConfig;
  Result.Right := DefaultPaneConfig;
end;

{ ── Encode ────────────────────────────────────────────────────── }

function EncodePane(const APane: TPaneConfig): TBytes;
var
  W: TPbWriter;
  I: Integer;
begin
  W := TPbWriter.Create;
  try
    W.WriteEnum   (PB_PANE_LIST_MODE,      APane.ListMode);
    W.WriteEnum   (PB_PANE_ROLE,           APane.Role);
    W.WriteEnum   (PB_PANE_SORT_FIELD,     APane.SortField);
    W.WriteBool   (PB_PANE_SORT_ASCENDING, APane.SortAscending);
    W.WriteBool   (PB_PANE_DIRS_FIRST,     APane.DirsFirst);
    W.WriteEnum   (PB_PANE_DATE_KIND,      APane.DateKind);
    W.WriteString (PB_PANE_GLOB,           APane.Glob);
    W.WriteBool   (PB_PANE_SHOW_DELETED,   APane.ShowDeleted);
    W.WriteBool   (PB_PANE_SHOW_HIDDEN,    APane.ShowHidden);
    W.WriteBool   (PB_PANE_SHOW_GUARDS,    APane.ShowGuards);
    W.WriteInt32  (PB_PANE_USER_AREA,      APane.UserArea);
    { repeated string -- write the same field number per element. }
    for I := 0 to High(APane.TreeExpanded) do
      W.WriteString(PB_PANE_TREE_EXPANDED, APane.TreeExpanded[I]);
    W.WriteInt32  (PB_PANE_CURSOR,         APane.Cursor);
    W.WriteInt32  (PB_PANE_SCROLL,         APane.Scroll);
    W.WriteString (PB_PANE_LAST_PATH,      APane.LastPath);
    Result := W.GetBytes;
  finally
    W.Free;
  end;
end;

function EncodeConfig(const ACfg: TDiskBenderConfig): TBytes;
var
  W: TPbWriter;
begin
  W := TPbWriter.Create;
  try
    W.WriteUInt32 (PB_CONFIG_SCHEMA_VERSION, ACfg.SchemaVersion);
    W.WriteMessage(PB_CONFIG_LEFT,  EncodePane(ACfg.Left));
    W.WriteMessage(PB_CONFIG_RIGHT, EncodePane(ACfg.Right));
    Result := W.GetBytes;
  finally
    W.Free;
  end;
end;

{ ── Decode ────────────────────────────────────────────────────── }

function DecodePane(const ABytes: TBytes): TPaneConfig;
var
  R: TPbReader;
  Field: Integer;
  Wt: Byte;
  ExpandedList: array of string;
begin
  Result := DefaultPaneConfig;
  SetLength(ExpandedList, 0);
  R := TPbReader.Create(ABytes);
  try
    while R.ReadTag(Field, Wt) do
    begin
      case Field of
        PB_PANE_LIST_MODE:      Result.ListMode      := R.ReadEnum;
        PB_PANE_ROLE:           Result.Role          := R.ReadEnum;
        PB_PANE_SORT_FIELD:     Result.SortField     := R.ReadEnum;
        PB_PANE_SORT_ASCENDING: Result.SortAscending := R.ReadBool;
        PB_PANE_DIRS_FIRST:     Result.DirsFirst     := R.ReadBool;
        PB_PANE_DATE_KIND:      Result.DateKind      := R.ReadEnum;
        PB_PANE_GLOB:           Result.Glob          := R.ReadString;
        PB_PANE_SHOW_DELETED:   Result.ShowDeleted   := R.ReadBool;
        PB_PANE_SHOW_HIDDEN:    Result.ShowHidden    := R.ReadBool;
        PB_PANE_SHOW_GUARDS:    Result.ShowGuards    := R.ReadBool;
        PB_PANE_USER_AREA:      Result.UserArea      := R.ReadInt32;
        PB_PANE_TREE_EXPANDED:
          begin
            SetLength(ExpandedList, Length(ExpandedList) + 1);
            ExpandedList[High(ExpandedList)] := R.ReadString;
          end;
        PB_PANE_CURSOR:         Result.Cursor        := R.ReadInt32;
        PB_PANE_SCROLL:         Result.Scroll        := R.ReadInt32;
        PB_PANE_LAST_PATH:      Result.LastPath      := R.ReadString;
      else
        R.SkipField(Wt);
      end;
    end;
  finally
    R.Free;
  end;
  Result.TreeExpanded := ExpandedList;
end;

function DecodeConfig(const ABytes: TBytes): TDiskBenderConfig;
var
  R: TPbReader;
  Field: Integer;
  Wt: Byte;
begin
  Result := DefaultConfig;
  R := TPbReader.Create(ABytes);
  try
    while R.ReadTag(Field, Wt) do
    begin
      case Field of
        PB_CONFIG_SCHEMA_VERSION: Result.SchemaVersion := R.ReadUInt32;
        PB_CONFIG_LEFT:           Result.Left          := DecodePane(R.ReadBytes);
        PB_CONFIG_RIGHT:          Result.Right         := DecodePane(R.ReadBytes);
      else
        R.SkipField(Wt);
      end;
    end;
  finally
    R.Free;
  end;
end;

{ ── Load / Save ───────────────────────────────────────────────── }

function ReadAllBytes(const APath: string): TBytes;
var
  Fs: TFileStream;
begin
  Fs := TFileStream.Create(APath, fmOpenRead or fmShareDenyWrite);
  try
    SetLength(Result, Fs.Size);
    if Fs.Size > 0 then
      Fs.ReadBuffer(Result[0], Fs.Size);
  finally
    Fs.Free;
  end;
end;

procedure WriteAllBytes(const APath: string; const ABytes: TBytes);
var
  Fs: TFileStream;
begin
  Fs := TFileStream.Create(APath, fmCreate);
  try
    if Length(ABytes) > 0 then
      Fs.WriteBuffer(ABytes[0], Length(ABytes));
  finally
    Fs.Free;
  end;
end;

function LoadConfig(const APath: string): TDiskBenderConfig;
var
  Raw: TBytes;
begin
  Result := DefaultConfig;
  if not FileExists(APath) then Exit;
  try
    Raw := ReadAllBytes(APath);
    Result := DecodeConfig(Raw);
  except
    { Corrupt file: return defaults rather than crash. The user can delete
      the file or report the bug; we don't auto-clobber it. }
    Result := DefaultConfig;
  end;
end;

procedure SaveConfig(const APath: string; const ACfg: TDiskBenderConfig);
var
  Dir, Tmp: string;
  Raw: TBytes;
begin
  Dir := ExtractFilePath(APath);
  if (Dir <> '') and (not DirectoryExists(Dir)) then
    ForceDirectories(Dir);
  Raw := EncodeConfig(ACfg);
  Tmp := APath + '.tmp';
  WriteAllBytes(Tmp, Raw);
  { Atomic replace: rename overwrites APath on POSIX. }
  if FileExists(APath) then DeleteFile(APath);
  RenameFile(Tmp, APath);
end;

function DefaultConfigPath: string;
var
  Home: string;
begin
  Home := GetEnvironmentVariable('HOME');
  if Home = '' then Home := GetUserDir;   { fallback }
  {$IFDEF DARWIN}
  Result := IncludeTrailingPathDelimiter(Home) +
            'Library/Application Support/DiskBender/config.pb';
  {$ELSE}
  if GetEnvironmentVariable('XDG_CONFIG_HOME') <> '' then
    Result := IncludeTrailingPathDelimiter(GetEnvironmentVariable('XDG_CONFIG_HOME')) +
              'DiskBender/config.pb'
  else
    Result := IncludeTrailingPathDelimiter(Home) + '.config/DiskBender/config.pb';
  {$ENDIF}
end;

{ ── Text dump (debug aid) ─────────────────────────────────────── }

function BoolToStr3(B: Boolean): string;
begin
  if B then Result := 'true' else Result := 'false';
end;

function DumpPaneAsText(const APane: TPaneConfig; const APrefix: string): string;
var
  Lines: TStringList;
  I: Integer;
begin
  Lines := TStringList.Create;
  try
    Lines.Add(APrefix + 'list_mode: '      + IntToStr(APane.ListMode));
    Lines.Add(APrefix + 'role: '           + IntToStr(APane.Role));
    Lines.Add(APrefix + 'sort_field: '     + IntToStr(APane.SortField));
    Lines.Add(APrefix + 'sort_ascending: ' + BoolToStr3(APane.SortAscending));
    Lines.Add(APrefix + 'dirs_first: '     + BoolToStr3(APane.DirsFirst));
    Lines.Add(APrefix + 'date_kind: '      + IntToStr(APane.DateKind));
    Lines.Add(APrefix + 'glob: "'          + APane.Glob + '"');
    Lines.Add(APrefix + 'show_deleted: '   + BoolToStr3(APane.ShowDeleted));
    Lines.Add(APrefix + 'show_hidden: '    + BoolToStr3(APane.ShowHidden));
    Lines.Add(APrefix + 'show_guards: '    + BoolToStr3(APane.ShowGuards));
    Lines.Add(APrefix + 'user_area: '      + IntToStr(APane.UserArea));
    for I := 0 to High(APane.TreeExpanded) do
      Lines.Add(APrefix + 'tree_expanded: "' + APane.TreeExpanded[I] + '"');
    Lines.Add(APrefix + 'cursor: ' + IntToStr(APane.Cursor));
    Lines.Add(APrefix + 'scroll: ' + IntToStr(APane.Scroll));
    Lines.Add(APrefix + 'last_path: "' + APane.LastPath + '"');
    Result := Lines.Text;
  finally
    Lines.Free;
  end;
end;

function DumpConfigAsText(const ACfg: TDiskBenderConfig): string;
begin
  Result := 'schema_version: ' + IntToStr(ACfg.SchemaVersion) + LineEnding +
            'left {' + LineEnding +
            DumpPaneAsText(ACfg.Left, '  ') +
            '}' + LineEnding +
            'right {' + LineEnding +
            DumpPaneAsText(ACfg.Right, '  ') +
            '}';
end;

end.
