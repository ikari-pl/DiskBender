unit uCPMTypes;

{ Shared CP/M value types, enums and filename helpers.

  Centralises logic that was previously duplicated across uCPM.pas:
  splitting/padding 8.3 filenames, validating CP/M character set,
  and decoding the attribute high-bits on filename/extension bytes. }

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  Classes, SysUtils;

const
  CPM_NAME_LEN = 8;
  CPM_EXT_LEN  = 3;
  CPM_DELETED_USER = $E5;
  CPM_MAX_USER     = 15;

type
  { Attributes stored in the high bit of the extension characters on CP/M.
    AMSDOS uses:
      Ext[0] high bit = Read-Only
      Ext[1] high bit = System (hidden from DIR)
      Ext[2] high bit = Archive }
  TCPMAttr = (caReadOnly, caSystem, caArchive);
  TCPMAttrs = set of TCPMAttr;

  { Row tag used by the GUI to distinguish item kinds inside a TListView
    without resorting to Pointer(PtrInt(magic)) smuggling. }
  TRowKind = (
    rkNone,      { placeholder / sentinel }
    rkParent,    { ".." entry in host pane }
    rkHostDir,   { subdirectory in host pane }
    rkHostFile,  { regular file in host pane }
    rkDSKFile    { CP/M file in DSK pane }
  );

  TRowTag = record
    Kind: TRowKind;
    Index: Integer; { Index into underlying model (file index or dir index). -1 for dirs/parent. }
    class function Make(AKind: TRowKind; AIndex: Integer = -1): TRowTag; static; inline;
  end;

  { 8.3 filename helper. Uses an advanced record so callers can write:
      Name := TCPMFileName.Parse('HELLO.BAS');
      if Name.IsValid then ... }
  TCPMFileName = record
    Name: string;   { 1..8 chars, trimmed }
    Ext:  string;   { 0..3 chars, trimmed }
    class function Parse(const S: string): TCPMFileName; static;
    function IsValid: Boolean;
    function Padded: string;        { e.g. 'HELLO   BAS' (11 chars, no dot) }
    function Display: string;       { e.g. 'HELLO.BAS' }
    function PaddedName: string;    { 8 chars, space-padded }
    function PaddedExt:  string;    { 3 chars, space-padded }
  end;

{ Is the byte a legal CP/M filename character?
  Rejects the AMSDOS-forbidden set <>.,;:=?*[] and controls. }
function IsValidCPMChar(B: Byte): Boolean;

{ Decode attribute bits carried on a 3-char CP/M extension field. }
function DecodeCPMAttrs(const ExtBytes: array of Char): TCPMAttrs;

{ Render attribute bits like "R-A" (R=Read-Only, S=System, A=Archive, '-' absent). }
function FormatCPMAttrs(Attrs: TCPMAttrs): string;

implementation

const
  CPM_FORBIDDEN = '<>.,;:=?*[]';

{ TRowTag }

class function TRowTag.Make(AKind: TRowKind; AIndex: Integer): TRowTag;
begin
  Result.Kind := AKind;
  Result.Index := AIndex;
end;

{ TCPMFileName }

class function TCPMFileName.Parse(const S: string): TCPMFileName;
var
  Trimmed: string;
  DotPos: Integer;
begin
  Trimmed := UpperCase(Trim(S));
  DotPos := Pos('.', Trimmed);
  if DotPos > 0 then
  begin
    Result.Name := Copy(Trimmed, 1, DotPos - 1);
    Result.Ext  := Copy(Trimmed, DotPos + 1, MaxInt);
  end
  else
  begin
    Result.Name := Trimmed;
    Result.Ext  := '';
  end;
  if Length(Result.Name) > CPM_NAME_LEN then
    Result.Name := Copy(Result.Name, 1, CPM_NAME_LEN);
  if Length(Result.Ext) > CPM_EXT_LEN then
    Result.Ext := Copy(Result.Ext, 1, CPM_EXT_LEN);
end;

function TCPMFileName.IsValid: Boolean;
var
  I: Integer;
begin
  Result := False;
  if (Length(Name) = 0) or (Length(Name) > CPM_NAME_LEN) then Exit;
  if Length(Ext) > CPM_EXT_LEN then Exit;
  for I := 1 to Length(Name) do
    if not IsValidCPMChar(Byte(Name[I])) then Exit;
  for I := 1 to Length(Ext) do
    if not IsValidCPMChar(Byte(Ext[I])) then Exit;
  Result := True;
end;

function TCPMFileName.PaddedName: string;
begin
  Result := Name + StringOfChar(' ', CPM_NAME_LEN - Length(Name));
end;

function TCPMFileName.PaddedExt: string;
begin
  Result := Ext + StringOfChar(' ', CPM_EXT_LEN - Length(Ext));
end;

function TCPMFileName.Padded: string;
begin
  Result := PaddedName + PaddedExt;
end;

function TCPMFileName.Display: string;
begin
  if Ext = '' then
    Result := Name
  else
    Result := Name + '.' + Ext;
end;

{ unit-level helpers }

function IsValidCPMChar(B: Byte): Boolean;
begin
  { Strip attribute bit first — CP/M filenames are ASCII. }
  B := B and $7F;
  if (B < 32) or (B > 126) then Exit(False);
  if Pos(Char(B), CPM_FORBIDDEN) > 0 then Exit(False);
  { Spaces are legal as padding but not in the middle — callers
    handle trimming; here we accept them so Parse() output survives. }
  Result := True;
end;

function DecodeCPMAttrs(const ExtBytes: array of Char): TCPMAttrs;
begin
  Result := [];
  if Length(ExtBytes) >= 1 then
    if (Byte(ExtBytes[0]) and $80) <> 0 then Include(Result, caReadOnly);
  if Length(ExtBytes) >= 2 then
    if (Byte(ExtBytes[1]) and $80) <> 0 then Include(Result, caSystem);
  if Length(ExtBytes) >= 3 then
    if (Byte(ExtBytes[2]) and $80) <> 0 then Include(Result, caArchive);
end;

function FormatCPMAttrs(Attrs: TCPMAttrs): string;
begin
  if caReadOnly in Attrs then Result := 'R' else Result := '-';
  if caSystem   in Attrs then Result := Result + 'S' else Result := Result + '-';
  if caArchive  in Attrs then Result := Result + 'A' else Result := Result + '-';
end;

end.
