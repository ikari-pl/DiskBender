unit uVFS;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

type
  { ── Size units ──────────────────────────────────────────────────── }

  TSizeUnit = (suBytes, suKB, suBlocks, suRecords, suSectors);

  { ── Entry attributes (bit flags) ────────────────────────────────── }

  TEntryAttribute = (eaReadOnly, eaSystem, eaHidden, eaArchive);
  TEntryAttributes = set of TEntryAttribute;

  { ── Sort fields ─────────────────────────────────────────────────── }

  TSortField = (sfName, sfExtension, sfSize, sfUser, sfDate);

  { ── Physical layout descriptor ──────────────────────────────────── }

  TLayoutKind = (lkDisk, lkTrack, lkSector, lkFileRegion);

  TLayoutInfo = record
    Kind: TLayoutKind;
    Label_: string;
    Offset: Int64;
    Size: Int64;
    Extra: string;
  end;

  TLayoutInfoArray = array of TLayoutInfo;

  { ══════════════════════════════════════════════════════════════════
    FOUNDATION INTERFACES
    ══════════════════════════════════════════════════════════════════ }

  IEntry = interface
    ['{B0A10001-0001-4C50-8D00-000000000001}']
    function GetName: string;
    function GetDisplayName: string;
    property Name: string read GetName;
    property DisplayName: string read GetDisplayName;
  end;

  IContainer = interface
    ['{B0A10001-0002-4C50-8D00-000000000002}']
    function GetEntryCount: Integer;
    function GetEntry(Index: Integer): IEntry;
    function GetTitle: string;
    procedure Refresh;
    property EntryCount: Integer read GetEntryCount;
    property Title: string read GetTitle;
  end;

  { ══════════════════════════════════════════════════════════════════
    CAPABILITY INTERFACES — orthogonal, attach to any entry/container
    ══════════════════════════════════════════════════════════════════ }

  ISizeable = interface
    ['{B0A10001-0010-4C50-8D00-000000000010}']
    function GetSize: Int64;
    function GetSizeUnit: TSizeUnit;
    property Size: Int64 read GetSize;
    property SizeUnit: TSizeUnit read GetSizeUnit;
  end;

  IWritable = interface
    ['{B0A10001-0011-4C50-8D00-000000000011}']
    function GetModified: Boolean;
    procedure Save;
    procedure Revert;
    property Modified: Boolean read GetModified;
  end;

  IRenameable = interface
    ['{B0A10001-0012-4C50-8D00-000000000012}']
    procedure Rename(const NewName: string);
  end;

  IDeletable = interface
    ['{B0A10001-0013-4C50-8D00-000000000013}']
    function GetIsDeleted: Boolean;
    procedure Delete;
    property IsDeleted: Boolean read GetIsDeleted;
  end;

  IRestorable = interface
    ['{B0A10001-0014-4C50-8D00-000000000014}']
    procedure Restore;
  end;

  IAttributed = interface
    ['{B0A10001-0015-4C50-8D00-000000000015}']
    function GetAttributes: TEntryAttributes;
    procedure SetAttributes(AValue: TEntryAttributes);
    property Attributes: TEntryAttributes read GetAttributes write SetAttributes;
  end;

  IBlockMappable = interface
    ['{B0A10001-0016-4C50-8D00-000000000016}']
    function GetBlockMap: TBytes;
    function GetBlockCount: Integer;
    property BlockCount: Integer read GetBlockCount;
  end;

  IPhysicalLayout = interface
    ['{B0A10001-0017-4C50-8D00-000000000017}']
    function GetLayoutInfo: TLayoutInfoArray;
  end;

  ICopySource = interface
    ['{B0A10001-0018-4C50-8D00-000000000018}']
    procedure CopyTo(AStream: TStream);
  end;

  ICopyTarget = interface
    ['{B0A10001-0019-4C50-8D00-000000000019}']
    function Import(ASource: ICopySource; const AName: string): Boolean;
  end;

  ISortable = interface
    ['{B0A10001-001A-4C50-8D00-000000000020}']
    procedure Sort(AField: TSortField; Ascending: Boolean);
  end;

  IUserArea = interface
    ['{B0A10001-001B-4C50-8D00-000000000021}']
    function GetUser: Byte;
    property User: Byte read GetUser;
  end;

  ISummary = interface
    ['{B0A10001-001C-4C50-8D00-000000000022}']
    function GetSummaryInfo: string;
  end;

implementation

end.
