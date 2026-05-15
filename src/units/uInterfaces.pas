unit uInterfaces;

{$mode objfpc}{$H+}
{$packrecords 1}

interface

uses
  Classes, SysUtils, uVFS;

type
  { Fields a filesystem can sort files by. Concrete filesystems may silently
    ignore unsupported fields (e.g. a filesystem with no "user area" concept
    should no-op on fsUser). }
  TFileSortField = (fsName, fsExt, fsSize, fsUser);

  { Sector Information Block (8 bytes each, inside a Track Info Block).
    Lives here rather than in uDSK so IVirtualDisk can expose track geometry
    without requiring callers to cast to the concrete TDiskBenderDSK class. }
  TSectorInfo = packed record
    Track: Byte;
    Side: Byte;
    SectorID: Byte;
    SectorSize: Byte; { (128 << Size) bytes }
    FDCStatus1: Byte;
    FDCStatus2: Byte;
    DataLength: Word; { Not used for Standard DSK }
  end;

  { Track Information Block (one per track) — describes physical geometry of
    a single track including the sector ID list. }
  TTrackInfoBlock = packed record
    Signature: array[0..11] of Char; { "Track-Info\r\n" }
    Reserved: array[0..3] of Byte;
    TrackNum: Byte;
    SideNum: Byte;
    Reserved2: array[0..1] of Byte;
    SectorSize: Byte;
    NumSectors: Byte;
    GAP3Length: Byte;
    FillerByte: Byte;
    SectorInfos: array[0..28] of TSectorInfo;
  end;

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

    { Physical geometry of a single track. Required by filesystem drivers
      to map block indices to (track, sector) and to discover sector size. }
    function GetTrackInfo(TrackIdx: Integer): TTrackInfoBlock;

    { Return the sector IDs for a track sorted ascending. The result is cached
      per track and invalidated on Load/Revert/PutSectorData. Callers that need
      sorted sector IDs (CP/M logical→physical mapping, sector-map painter)
      should use this rather than sorting inline every call. }
    function GetSortedSectorIDs(TrackIdx: Integer): TBytes;

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

  { Disk Parameter Block — forward-declared here so IFilesystem can expose it
    without callers having to cast to TDiskBenderCPM.  The full definition lives
    in uCPM.pas; this is a structural copy so uInterfaces.pas stays self-contained. }
  TCPMDPB = record
    SPT: Word;
    BSH: Byte;
    BLM: Byte;
    EXM: Byte;
    DSM: Word;
    DRM: Word;
    AL0: Byte;
    AL1: Byte;
    CKS: Word;
    OFF: Word;
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

    { Return the filesystem's Disk Parameter Block.  Avoids callers having to
      cast IFilesystem to TDiskBenderCPM to read geometry. }
    function GetDPB: TCPMDPB;

    { Override the Disk Parameter Block — used by tests that need non-default
      geometry without creating a subclass. }
    procedure SetDPB(const Value: TCPMDPB);

    { Per-file directory-entry location accessors.  Each logical file may span
      multiple CP/M directory entries (extents); these allow callers to probe
      the physical location of each entry without casting to TDiskBenderCPM. }
    function GetFileEntryCount(FileIdx: Integer): Integer;
    function GetFileEntryLoc(FileIdx, LocIdx: Integer;
                              out ATrack, ASectorIdx, AEntryIdx: Byte): Boolean;

    { Enumerate the block numbers (0-based, same coordinate system as
      GetBlockMap) allocated to the file at FileIdx by walking its
      directory extents' allocation arrays. Returns an empty array for
      a 0-byte file or an out-of-range FileIdx. }
    function GetFileBlocks(FileIdx: Integer): TBlockNumberArray;

    { Enumerate the physical (track, sectorID) sectors a file occupies on
      disk by converting its owned blocks through the DPB's geometry
      (sectors-per-block, sectors-per-track, OFF reserved tracks) and
      applying the per-track sector skew via GetSortedSectorIDs. Returns
      an empty array for a 0-byte file or an out-of-range FileIdx. }
    function GetFileSectors(FileIdx: Integer): TPhysicalSectorArray;
  end;

implementation

end.
