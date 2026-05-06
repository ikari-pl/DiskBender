unit uInterfaces;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

type
  { Fields a filesystem can sort files by. Concrete filesystems may silently
    ignore unsupported fields (e.g. a filesystem with no "user area" concept
    should no-op on fsUser). }
  TFileSortField = (fsName, fsExt, fsSize, fsUser);

  { Represents a raw disk or snapshot container }
  IVirtualDisk = interface
    ['{A1B2C3D4-E5F6-4A5B-8C9D-0E1F2A3B4C5D}']
    function GetNumTracks: Byte;
    function GetNumSides: Byte;
    function GetFilePath: string;
    function GetModified: Boolean;

    procedure Load;
    procedure Save;
    procedure Revert;

    function GetSectorData(TrackIdx, SectorIdx: Integer): TBytes;
    procedure PutSectorData(TrackIdx, SectorIdx: Integer; const Data: TBytes);

    property NumTracks: Byte read GetNumTracks;
    property NumSides: Byte read GetNumSides;
    property FilePath: string read GetFilePath;
    property Modified: Boolean read GetModified;
  end;

  { Represents a file on a virtual disk }
  IVirtualFile = interface
    ['{D4C3B2A1-F6E5-5B4A-9D8C-5D4C3B2A1F0E}']
    function GetName: string;
    function GetExtension: string;
    function GetSizeKB: Integer;
    function GetIsDeleted: Boolean;
    function GetUser: Byte;

    property Name: string read GetName;
    property Extension: string read GetExtension;
    property SizeKB: Integer read GetSizeKB;
    property IsDeleted: Boolean read GetIsDeleted;
    property User: Byte read GetUser;
  end;

  { Represents a filesystem (CP/M, Amsdos, etc.) }
  IFilesystem = interface
    ['{E1D2C3B4-A5B6-C7D8-E9F0-1A2B3C4D5E6F}']
    procedure ScanDirectory;
    function GetFileCount: Integer;
    function GetFile(Index: Integer): IVirtualFile;

    procedure GetFileContent(FileIdx: Integer; Stream: TStream);
    procedure ToggleDelete(FileIdx: Integer);
    procedure RenameFile(FileIdx: Integer; const NewName: string);
    procedure UndeleteFile(FileIdx: Integer; NewFirstChar: Char);

    { Add a new file from host filesystem. Returns >=0 on success (new file
      index), -1 on failure (no free directory entry or invalid name). }
    function AddFile(const FileName, Ext: string; const Data: TBytes; User: Byte): Integer;

    { Reorder files in-place. Implementations should be stable. }
    procedure SortFiles(Field: TFileSortField; Ascending: Boolean);

    function GetBlockMap: TBytes;

    function GetSummaryInfo: string;
  end;

implementation

end.
