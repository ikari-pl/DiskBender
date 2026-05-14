unit uFormatters;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, uInterfaces, uVFS, fpjson;

type
  TOutputFormat = (ofTable, ofJSON);

  TDiskFormatter = class
  public
    class function FormatFiles(Filesystem: IFilesystem; Formatter: TOutputFormat): string;
    class function FormatMap(const Map: TBytes; BytesPerBlock: Integer; Formatter: TOutputFormat): string;
    class function FormatSectorMap(const Tracks: TTrackColumnArray; Formatter: TOutputFormat): string;
    class function FormatDiskInfo(Disk: IVirtualDisk; Formatter: TOutputFormat): string;
  end;

implementation

const
  ColsPerRow = 64;
  GroupSize  = 8;

class function TDiskFormatter.FormatFiles(Filesystem: IFilesystem; Formatter: TOutputFormat): string;
var
  I: Integer;
  VFile: IVirtualFile;
  SL: TStringList;
  JArray: TJSONArray;
  JObj: TJSONObject;
begin
  SL := TStringList.Create;
  try
    if Formatter = ofTable then
    begin
      SL.Add(SysUtils.Format('%-4s %-12s %-4s %8s', ['User', 'Name', 'Ext', 'Size']));
      SL.Add('----------------------------------------------');
      for I := 0 to Filesystem.GetFileCount - 1 do
      begin
        VFile := Filesystem.GetFile(I);
        SL.Add(SysUtils.Format('%-4d %-12s %-4s %8d',
          [VFile.User, VFile.Name, VFile.Extension, VFile.SizeKB]));
      end;
    end
    else if Formatter = ofJSON then
    begin
      JArray := TJSONArray.Create;
      for I := 0 to Filesystem.GetFileCount - 1 do
      begin
        VFile := Filesystem.GetFile(I);
        JObj := TJSONObject.Create;
        JObj.Add('user', VFile.User);
        JObj.Add('name', VFile.Name);
        JObj.Add('ext', VFile.Extension);
        JObj.Add('size_kb', VFile.SizeKB);
        JObj.Add('is_deleted', VFile.IsDeleted);
        JArray.Add(JObj);
      end;
      SL.Text := JArray.FormatJSON;
      JArray.Free;
    end;
    Result := SL.Text;
  finally
    SL.Free;
  end;
end;

{ Build a two-line column ruler for ColsPerRow columns with GroupSize spacing.
  The ruler sits above the data rows and helps locate a block by eye.
  Example (ColsPerRow=64, GroupSize=8):
    "       0        1         2  ..."
    "       0123456789012345678901..."
  The row-label prefix is 7 chars ("  NNNN "), so the ruler starts 7+1=8 in. }
function BuildRuler: string;
const
  Prefix = '       ';   { 7 chars to align with "  NNNN " label + 1 space }
var
  TensLine, OnesLine: string;
  Col, G, GStart: Integer;
  Grouping: Integer;
begin
  Grouping := GroupSize;
  TensLine := Prefix;
  OnesLine := Prefix;
  G := 0;
  Col := 0;
  while Col < ColsPerRow do
  begin
    { Insert space between groups (not before the first group). }
    if (Col > 0) and (Col mod Grouping = 0) then
    begin
      TensLine := TensLine + ' ';
      OnesLine := OnesLine + ' ';
    end;
    GStart := (G * Grouping);
    { tens digit of block index }
    TensLine := TensLine + IntToStr((GStart + (Col mod Grouping)) div 10 mod 10);
    OnesLine := OnesLine + IntToStr((GStart + (Col mod Grouping)) mod 10);
    Inc(Col);
    if Col mod Grouping = 0 then Inc(G);
  end;
  Result := TensLine + sLineBreak + OnesLine;
end;

class function TDiskFormatter.FormatMap(const Map: TBytes; BytesPerBlock: Integer; Formatter: TOutputFormat): string;
var
  I, Col, RowStart: Integer;
  Total, FreeC, DirC, UsedC, DelC: Integer;
  SL: TStringList;
  RowLine: string;
  Ch: Char;
  JObj: TJSONObject;
  JArray: TJSONArray;
  HeaderLine, CountsLine: string;
begin
  Result := '';

  if Formatter = ofJSON then
  begin
    JObj := TJSONObject.Create;
    JArray := TJSONArray.Create;
    for I := 0 to Length(Map) - 1 do
      JArray.Add(Map[I]);
    JObj.Add('blocks', JArray);
    Result := JObj.FormatJSON;
    JObj.Free;
    Exit;
  end;

  { Table format }
  Total := Length(Map);
  FreeC := 0; DirC := 0; UsedC := 0; DelC := 0;
  for I := 0 to Total - 1 do
    case Map[I] of
      0: Inc(FreeC);
      1: Inc(DirC);
      2: Inc(UsedC);
      3: Inc(DelC);
    end;

  if BytesPerBlock > 0 then
    HeaderLine := Format('Block allocation map — %d blocks, %d bytes/block', [Total, BytesPerBlock])
  else
    HeaderLine := Format('Block allocation map — %d blocks', [Total]);

  CountsLine := Format('  free=%d  dir/system=%d  used=%d  deleted=%d',
    [FreeC, DirC, UsedC, DelC]);

  SL := TStringList.Create;
  try
    SL.Add(HeaderLine);
    SL.Add(CountsLine);
    SL.Add('');
    SL.Add(BuildRuler);

    { Data rows: "  NNNN " + 64 cells with a space every GroupSize cells }
    I := 0;
    while I < Total do
    begin
      RowStart := I;
      RowLine := Format('  %4.4d ', [RowStart]);
      Col := 0;
      while (I < Total) and (Col < ColsPerRow) do
      begin
        if (Col > 0) and (Col mod GroupSize = 0) then
          RowLine := RowLine + ' ';
        case Map[I] of
          0: Ch := '.';
          1: Ch := 'D';
          2: Ch := '#';
          3: Ch := 'x';
        else
          Ch := '?';
        end;
        RowLine := RowLine + Ch;
        Inc(I);
        Inc(Col);
      end;
      SL.Add(RowLine);
    end;

    SL.Add('');
    SL.Add('Legend:  . free   D dir/system   # used   x deleted');

    Result := SL.Text;
  finally
    SL.Free;
  end;
end;

function SectorStateChar(St: TSectorState): Char;
begin
  case St of
    ssEmpty:       Result := '=';
    ssData:        Result := '.';
    ssSystem:      Result := 'S';
    ssBoot:        Result := 'B';
    ssNonStandard: Result := '?';
    ssFDCError:    Result := '!';
  else
    Result := '?';
  end;
end;

function SizeWord(W: Word): string;
begin
  if (W >= 1024) and (W mod 1024 = 0) then Result := IntToStr(W div 1024) + 'K'
  else Result := IntToStr(W) + 'B';
end;

{ "9x512B" when a track is uniform, "8x512B+1x4096B" when mixed (distinct
  sizes in first-seen order, each with its count). }
function TrackSizeSummary(const Trk: TTrackColumn): string;
var
  Sizes: array of Word;
  Counts: array of Integer;
  S, I, J: Integer;
  Found: Boolean;
begin
  SetLength(Sizes, 0); SetLength(Counts, 0);
  for S := 0 to High(Trk.Sectors) do
  begin
    Found := False;
    for I := 0 to High(Sizes) do
      if Sizes[I] = Trk.Sectors[S].SizeBytes then
      begin Inc(Counts[I]); Found := True; Break; end;
    if not Found then
    begin
      J := Length(Sizes);
      SetLength(Sizes, J + 1); SetLength(Counts, J + 1);
      Sizes[J] := Trk.Sectors[S].SizeBytes; Counts[J] := 1;
    end;
  end;
  Result := '';
  for I := 0 to High(Sizes) do
  begin
    if I > 0 then Result := Result + '+';
    Result := Result + IntToStr(Counts[I]) + 'x' + SizeWord(Sizes[I]);
  end;
  if Result = '' then Result := '-';
end;

{ "01-0A" when IDs are a simple ascending run, else a (capped) hex list like
  "C1,C2,..,80".  IDs printed in hex since CPC sector IDs are conventionally hex. }
function TrackIDSummary(const Trk: TTrackColumn): string;
var
  N, S: Integer;
  Contig: Boolean;
begin
  N := Length(Trk.Sectors);
  if N = 0 then Exit('-');
  Contig := True;
  for S := 1 to N - 1 do
    if Trk.Sectors[S].SectorID <> Trk.Sectors[S - 1].SectorID + 1 then
    begin Contig := False; Break; end;
  if Contig and (N > 2) then
    Exit(Format('%.2x-%.2x', [Trk.Sectors[0].SectorID, Trk.Sectors[N - 1].SectorID]));
  Result := '';
  for S := 0 to N - 1 do
  begin
    if S > 0 then Result := Result + ',';
    if (S = 12) and (N > 13) then begin Result := Result + Format('..(%d)', [N]); Break; end;
    Result := Result + Format('%.2x', [Trk.Sectors[S].SectorID]);
  end;
end;

class function TDiskFormatter.FormatSectorMap(const Tracks: TTrackColumnArray; Formatter: TOutputFormat): string;
var
  T, S: Integer;
  NTracks: Integer;
  DataC, SysC, BootC, FillerC, BadC, OtherC, MixedTracks: Integer;
  SL: TStringList;
  RowLine, SizeCol, IDCol: string;
  JObj: TJSONObject;
  JOuter: TJSONObject;
  JTracks: TJSONArray;
  JSectors: TJSONArray;
  JSec: TJSONObject;
  StateStr: string;
  { disk-wide size histogram }
  HSizes: array of Word;
  HCounts: array of Integer;
  I, K: Integer;
  Found: Boolean;
  Dist: string;
  MaxSectorsPerTrack: Integer;
  PadTarget: Integer;
  HeaderPad: string;
begin
  Result := '';
  NTracks := Length(Tracks);

  if Formatter = ofJSON then
  begin
    JOuter := TJSONObject.Create;
    JTracks := TJSONArray.Create;
    for T := 0 to NTracks - 1 do
    begin
      JObj := TJSONObject.Create;
      JObj.Add('track', Tracks[T].TrackNum);
      JObj.Add('side', Tracks[T].SideNum);
      JObj.Add('filler_byte', Tracks[T].FillerByte);
      JSectors := TJSONArray.Create;
      for S := 0 to High(Tracks[T].Sectors) do
      begin
        JSec := TJSONObject.Create;
        JSec.Add('sector_id', Tracks[T].Sectors[S].SectorID);
        JSec.Add('size_bytes', Tracks[T].Sectors[S].SizeBytes);
        JSec.Add('fdc_st1', Tracks[T].Sectors[S].FDCSt1);
        JSec.Add('fdc_st2', Tracks[T].Sectors[S].FDCSt2);
        case Tracks[T].Sectors[S].State of
          ssEmpty:       StateStr := 'empty';
          ssData:        StateStr := 'data';
          ssSystem:      StateStr := 'system';
          ssBoot:        StateStr := 'boot';
          ssNonStandard: StateStr := 'nonstandard';
          ssFDCError:    StateStr := 'fdc_error';
        else
          StateStr := 'unknown';
        end;
        JSec.Add('state', StateStr);
        JSectors.Add(JSec);
      end;
      JObj.Add('sectors', JSectors);
      JTracks.Add(JObj);
    end;
    JOuter.Add('tracks', JTracks);
    Result := JOuter.FormatJSON;
    JOuter.Free;
    Exit;
  end;

  { Table format }
  DataC := 0; SysC := 0; BootC := 0; FillerC := 0; BadC := 0; OtherC := 0;
  MixedTracks := 0;
  SetLength(HSizes, 0); SetLength(HCounts, 0);
  for T := 0 to NTracks - 1 do
  begin
    for S := 0 to High(Tracks[T].Sectors) do
    begin
      case Tracks[T].Sectors[S].State of
        ssEmpty:       Inc(FillerC);
        ssData:        Inc(DataC);
        ssSystem:      Inc(SysC);
        ssBoot:        Inc(BootC);
        ssNonStandard: Inc(OtherC);
        ssFDCError:    Inc(BadC);
      end;
      Found := False;
      for I := 0 to High(HSizes) do
        if HSizes[I] = Tracks[T].Sectors[S].SizeBytes then
        begin Inc(HCounts[I]); Found := True; Break; end;
      if not Found then
      begin
        K := Length(HSizes);
        SetLength(HSizes, K + 1); SetLength(HCounts, K + 1);
        HSizes[K] := Tracks[T].Sectors[S].SizeBytes; HCounts[K] := 1;
      end;
    end;
    { mixed-size track? }
    for S := 1 to High(Tracks[T].Sectors) do
      if Tracks[T].Sectors[S].SizeBytes <> Tracks[T].Sectors[0].SizeBytes then
      begin Inc(MixedTracks); Break; end;
  end;

  Dist := '';
  for I := 0 to High(HSizes) do
  begin
    if I > 0 then Dist := Dist + '  ';
    Dist := Dist + SizeWord(HSizes[I]) + 'x' + IntToStr(HCounts[I]);
  end;

  { Compute the maximum sector count across all tracks so the sector-cell
    column has a fixed width regardless of disk geometry.  7 = len("  NNNN "). }
  MaxSectorsPerTrack := 0;
  for T := 0 to NTracks - 1 do
    if Length(Tracks[T].Sectors) > MaxSectorsPerTrack then
      MaxSectorsPerTrack := Length(Tracks[T].Sectors);
  { +1 extra space between sector cells and size column }
  PadTarget := 7 + MaxSectorsPerTrack + 1;

  SL := TStringList.Create;
  try
    SL.Add(Format('Sector map — %d tracks', [NTracks]));
    SL.Add(Format('  states:  data=%d  system=%d  boot=%d  filler(empty)=%d  bad/FDC=%d  other=%d',
      [DataC, SysC, BootC, FillerC, BadC, OtherC]));
    SL.Add(Format('  sector sizes:  %s', [Dist]));
    if MixedTracks > 0 then
      SL.Add(Format('  ** %d track(s) have mixed sector sizes — see the "size" column **', [MixedTracks]));
    SL.Add('');
    { Build a header whose "size" column starts at PadTarget.
      "  Trk " = 7 chars; sector-state cells = MaxSectorsPerTrack chars;
      one trailing space = total PadTarget chars before "size". }
    HeaderPad := StringOfChar(' ', MaxSectorsPerTrack);
    SL.Add('  Trk  ' + HeaderPad + 'size           IDs (hex)');

    for T := 0 to NTracks - 1 do
    begin
      RowLine := Format('  %4.4d ', [T]);
      for S := 0 to High(Tracks[T].Sectors) do
        RowLine := RowLine + SectorStateChar(Tracks[T].Sectors[S].State);
      { Pad the sector-cell field to PadTarget so the size column lines up
        correctly even for tracks with fewer sectors than the widest track. }
      while Length(RowLine) < PadTarget do RowLine := RowLine + ' ';
      SizeCol := TrackSizeSummary(Tracks[T]);
      IDCol   := TrackIDSummary(Tracks[T]);
      RowLine := RowLine + Format('%-14s %s', [SizeCol, IDCol]);
      SL.Add(RowLine);
    end;

    SL.Add('');
    SL.Add('Legend:  . data   S system/dir   B boot/reserved   = filler(empty)   ? non-standard   ! FDC error');

    Result := SL.Text;
  finally
    SL.Free;
  end;
end;

class function TDiskFormatter.FormatDiskInfo(Disk: IVirtualDisk; Formatter: TOutputFormat): string;
var
  JObj: TJSONObject;
begin
  if Formatter = ofJSON then
  begin
    JObj := TJSONObject.Create;
    JObj.Add('path', Disk.FilePath);
    JObj.Add('tracks', Disk.NumTracks);
    JObj.Add('sides', Disk.NumSides);
    JObj.Add('modified', Disk.Modified);
    Result := JObj.FormatJSON;
    JObj.Free;
  end
  else
  begin
    Result := SysUtils.Format('Path: %s, Tracks: %d, Sides: %d, Modified: %s' + LineEnding,
      [Disk.FilePath, Disk.NumTracks, Disk.NumSides, BoolToStr(Disk.Modified, True)]);
  end;
end;

end.
