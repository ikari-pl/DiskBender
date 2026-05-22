unit uFormatters;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, uInterfaces, uVFS, fpjson
  {$IFDEF UNIX}, BaseUnix{$ENDIF};

type
  TOutputFormat = (ofTable, ofJSON);

  TDiskFormatter = class
  public
    class function FormatFiles(Filesystem: IFilesystem; Formatter: TOutputFormat): string;
    class function FormatMap(const Map: TBytes; BytesPerBlock: Integer; Formatter: TOutputFormat): string;
    class function FormatSectorMap(const Tracks: TTrackColumnArray; Formatter: TOutputFormat;
                                   Color: Boolean = False): string;
    class function FormatDiskInfo(Disk: IVirtualDisk; Formatter: TOutputFormat): string;
  end;

  { TTY detection helper for callers that want to decide whether to enable
    ANSI color escapes. Returns False on non-Unix platforms or when stdout
    is not a character device (i.e. piped or redirected to a file).
    A pragmatic heuristic — equivalent to a typical isatty() check via
    stat'ing fd 1 and looking for S_IFCHR. }
  function OutputIsTTY: Boolean;

implementation

function OutputIsTTY: Boolean;
{$IFDEF UNIX}
var
  St: Stat;
begin
  { fd 1 = stdout. S_IFCHR matches both real ptys and the simulated
    character devices used by terminal multiplexers. A pipe or regular
    file matches S_IFIFO/S_IFREG and returns False — desirable, since
    we don't want ANSI escapes in captured output. }
  Result := (FpFStat(1, St) = 0) and ((St.st_mode and S_IFMT) = S_IFCHR);
end;
{$ELSE}
begin
  Result := False;
end;
{$ENDIF}

const
  ColsPerRow = 64;
  GroupSize  = 8;

  { ANSI SGR escape codes used by the colored sectormap. Truecolor
    (24-bit RGB) escapes are used instead of basic 16-color codes because
    many terminals remap codes 90-97 (bright) inconsistently — some
    palettes render bright-red / bright-yellow / bright-magenta all as
    the same red-ish hue. 38;2;R;G;B forces the literal color and is
    supported by every terminal that handles truecolor (iTerm2,
    Terminal.app, modern xterm, Alacritty, kitty, Wezterm, WindowsTerm).

      State glyphs (foreground only):
        data         — default
        system (S)   — cyan
        boot (B)     — blue
        empty (=)    — dim grey
        nonstd (?)   — amber
        FDC err (!)  — red
      Protection glyphs (foreground, override state):
        susp ID (X)  — magenta
        weak DL (W)  — red
        len mis (L)  — yellow
        twin (T)     — bright blue (rarely wins; see ANSI_BG_TWIN)
      Twin background — applied on top of the foreground glyph color when
      a sector is BOTH a twin AND has another flag, so all four
      protection signals can coexist in a single cell.
      ID markers in the IDs (hex) column:
        ? (suspicious) — magenta
        * (twin)       — bright cyan
    All emissions paired with ANSI_RESET so colors don't bleed past the
    glyph (important when piping through grep/less etc.). }
  ANSI_RESET    = #27'[0m';

  { Truecolor foreground RGB triples (38;2;R;G;B). Picked for both
    distinctness on light + dark terminals and colorblind-friendliness. }
  ANSI_FG_W     = #27'[38;2;255;80;80m';      { weak DataLength: red }
  ANSI_FG_L     = #27'[38;2;240;220;60m';     { length mismatch: yellow }
  ANSI_FG_X     = #27'[38;2;240;80;240m';     { suspicious ID: magenta }
  ANSI_FG_T     = #27'[38;2;110;200;255m';    { twin foreground: sky-blue }
  ANSI_FG_S     = #27'[38;2;80;220;220m';     { system: cyan }
  ANSI_FG_B     = #27'[38;2;100;160;255m';    { boot: blue }
  ANSI_FG_DIM   = #27'[38;2;130;130;130m';    { filler: grey }
  ANSI_FG_AMB   = #27'[38;2;230;170;60m';     { nonstandard: amber }
  ANSI_FG_ERR   = #27'[38;2;220;80;60m';      { FDC error: red-orange }

  { Twin background (48;2;R;G;B) — deep saturated blue so even when the
    foreground is yellow/magenta/red the contrast stays readable. }
  ANSI_BG_TWIN  = #27'[48;2;20;40;120m';

  { ID column markers (used by TrackIDSummary). }
  ANSI_FG_SUSP_MARK = #27'[38;2;240;80;240m'; { '?'  same magenta as X }
  ANSI_FG_TWIN_MARK = #27'[38;2;110;200;255m';{ '*'  same sky-blue as T }

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

{ Wrap a single glyph in the ANSI color escape that matches its category.
  When Color is False this is a no-op — returns the glyph unchanged so
  the caller's row-building logic doesn't have to branch.

  Twin causes the BACKGROUND to turn deep blue regardless of foreground
  color, so a sector that is BOTH a twin AND has a length-mismatch (or
  weak DataLength, or suspicious ID) shows BOTH signals simultaneously:
  the foreground glyph picks the most-diagnostic flag, the background
  reports twin coverage. On Face 2A this produces a visually striking
  "all blue background with mixed-color foreground" pattern that
  immediately tells you "twins everywhere, with W/L/X variations". }
function ColorGlyph(G: Char; Color, Twin: Boolean): string;
var
  FG, BG: string;
begin
  if not Color then Exit(G);
  case G of
    'X': FG := ANSI_FG_X;
    'W': FG := ANSI_FG_W;
    'L': FG := ANSI_FG_L;
    'T': FG := ANSI_FG_T;
    '!': FG := ANSI_FG_ERR;
    'S': FG := ANSI_FG_S;
    'B': FG := ANSI_FG_B;
    '?': FG := ANSI_FG_AMB;
    '=': FG := ANSI_FG_DIM;
  else
    FG := '';
  end;
  if Twin then BG := ANSI_BG_TWIN else BG := '';
  if (FG = '') and (BG = '') then Exit(G);
  Result := BG + FG + G + ANSI_RESET;
end;

{ Pick the glyph for a single sector cell, prioritising Discology-style
  protection fingerprints over the generic State. Order of priority:
    X = suspicious SectorID    (corrupt IDAM)
    W = weak DataLength        (DataLength field differs from nominal SizeBytes)
    L = length mismatch        (actual buffer differs from nominal SizeBytes)
    T = twin SectorID          (another sector on this track has the same ID)
  These override the state because they're more diagnostic — a sector
  whose buffer is short or whose IDAM is corrupt is interesting regardless
  of whether it's "data" or "empty". }
function SectorCellChar(const Cell: TSectorCell): Char;
begin
  if Cell.IsSuspiciousID then Exit('X');
  if (Cell.DeclaredLen <> 0) and (LongInt(Cell.SizeBytes) <> Cell.DeclaredLen) then
    Exit('W');
  if (Cell.State <> ssBoot) and (Cell.ActualLen >= 0) and
     (Cell.ActualLen <> LongInt(Cell.SizeBytes)) then
    Exit('L');
  if Cell.IsTwin then Exit('T');
  Result := SectorStateChar(Cell.State);
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

{ Detect whether any sector on a track carries a Discology-style anomaly
  flag — used to decide whether the ID list can be safely truncated (no
  anomalies = show the compact form; anomalies = show every ID so the
  malformed ones at the tail aren't elided away). }
function TrackHasAnomaly(const Trk: TTrackColumn): Boolean;
var
  S: Integer;
begin
  for S := 0 to High(Trk.Sectors) do
    if Trk.Sectors[S].IsSuspiciousID or Trk.Sectors[S].IsTwin or
       ((Trk.Sectors[S].DeclaredLen <> 0) and
        (LongInt(Trk.Sectors[S].SizeBytes) <> Trk.Sectors[S].DeclaredLen)) or
       ((Trk.Sectors[S].ActualLen >= 0) and
        (Trk.Sectors[S].ActualLen <> LongInt(Trk.Sectors[S].SizeBytes))) then
      Exit(True);
  Result := False;
end;

{ "01-0A" when IDs are a simple ascending run, else a hex list like
  "C1,C2,..,80".  Per-ID markers:
    *  twin (another sector on this track has the same ID)
    ?  suspicious (SectorID outside conventional ranges)
  When the track has ANY anomaly the list is shown in full (no `..(N)`
  elision) so corrupt IDAMs in the tail of long protected tracks stay
  visible. IDs printed in hex since CPC sector IDs are conventionally hex. }
function TrackIDSummary(const Trk: TTrackColumn; Color: Boolean = False): string;
var
  N, S: Integer;
  Contig: Boolean;
  HasAnomaly: Boolean;
  IDStr: string;
begin
  N := Length(Trk.Sectors);
  if N = 0 then Exit('-');

  HasAnomaly := TrackHasAnomaly(Trk);

  { Contiguous-run compression: only when the track is anomaly-free AND
    the IDs form a strict ascending sequence. Otherwise we lose
    information about gaps, twins, or corruption. }
  if not HasAnomaly then
  begin
    Contig := True;
    for S := 1 to N - 1 do
      if Trk.Sectors[S].SectorID <> Trk.Sectors[S - 1].SectorID + 1 then
      begin Contig := False; Break; end;
    if Contig and (N > 2) then
      Exit(Format('%.2x-%.2x', [Trk.Sectors[0].SectorID, Trk.Sectors[N - 1].SectorID]));
  end;

  Result := '';
  for S := 0 to N - 1 do
  begin
    if S > 0 then Result := Result + ',';
    { Elide only when the tail is uniformly normal — protection-aware view. }
    if (S = 12) and (N > 13) and (not HasAnomaly) then
    begin Result := Result + Format('..(%d)', [N]); Break; end;
    IDStr := Format('%.2x', [Trk.Sectors[S].SectorID]);
    if Trk.Sectors[S].IsSuspiciousID then IDStr := IDStr + '?';
    if Trk.Sectors[S].IsTwin           then IDStr := IDStr + '*';
    { Color the whole token when it carries a marker so the eye can pick
      out anomalies at a glance. Both flags can coexist (e.g. 25?* on
      Face 2A track 37). Suspicious wins because it's the louder signal. }
    if Color then
    begin
      if Trk.Sectors[S].IsSuspiciousID then
        IDStr := ANSI_FG_SUSP_MARK + IDStr + ANSI_RESET
      else if Trk.Sectors[S].IsTwin then
        IDStr := ANSI_FG_TWIN_MARK + IDStr + ANSI_RESET;
    end;
    Result := Result + IDStr;
  end;
end;

class function TDiskFormatter.FormatSectorMap(const Tracks: TTrackColumnArray; Formatter: TOutputFormat;
                                              Color: Boolean = False): string;
var
  T, S: Integer;
  NTracks: Integer;
  DataC, SysC, BootC, FillerC, BadC, OtherC, MixedTracks: Integer;
  TwinC, SuspIDC, LenMismatchC, WeakDLC: Integer;   { Discology-style flags }
  SL: TStringList;
  RowLine, SizeCol, IDCol: string;
  ActualLine, DeclLine: string;
  HasL, HasW: Boolean;
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
        JSec.Add('actual_len', Tracks[T].Sectors[S].ActualLen);
        JSec.Add('declared_len', Tracks[T].Sectors[S].DeclaredLen);
        JSec.Add('is_twin', Tracks[T].Sectors[S].IsTwin);
        JSec.Add('is_suspicious_id', Tracks[T].Sectors[S].IsSuspiciousID);
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
  TwinC := 0; SuspIDC := 0; LenMismatchC := 0; WeakDLC := 0;
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
      { Protection-fingerprint counters. A sector can carry multiple flags
        (e.g. twin AND suspicious ID), so each counter is independent. }
      if Tracks[T].Sectors[S].IsTwin then Inc(TwinC);
      if Tracks[T].Sectors[S].IsSuspiciousID then Inc(SuspIDC);
      if (Tracks[T].Sectors[S].State <> ssBoot) and
         (Tracks[T].Sectors[S].ActualLen >= 0) and
         (Tracks[T].Sectors[S].ActualLen <> LongInt(Tracks[T].Sectors[S].SizeBytes)) then
        Inc(LenMismatchC);
      if (Tracks[T].Sectors[S].DeclaredLen <> 0) and
         (LongInt(Tracks[T].Sectors[S].SizeBytes) <> Tracks[T].Sectors[S].DeclaredLen) then
        Inc(WeakDLC);

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
    { Discology-style protection counters — only printed when non-zero so
      the line doesn't clutter the output for ordinary disks. }
    if (TwinC <> 0) or (SuspIDC <> 0) or (LenMismatchC <> 0) or (WeakDLC <> 0) then
      SL.Add(Format('  protection:  twins=%d  suspicious_ids=%d  length_mismatch=%d  weak_DataLength=%d',
        [TwinC, SuspIDC, LenMismatchC, WeakDLC]));
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
      HasL := False;
      HasW := False;
      for S := 0 to High(Tracks[T].Sectors) do
      begin
        RowLine := RowLine + ColorGlyph(SectorCellChar(Tracks[T].Sectors[S]),
                                        Color, Tracks[T].Sectors[S].IsTwin);
        if (Tracks[T].Sectors[S].State <> ssBoot) and
           (Tracks[T].Sectors[S].ActualLen >= 0) and
           (Tracks[T].Sectors[S].ActualLen <> LongInt(Tracks[T].Sectors[S].SizeBytes)) then
          HasL := True;
        if (Tracks[T].Sectors[S].DeclaredLen <> 0) and
           (LongInt(Tracks[T].Sectors[S].SizeBytes) <> Tracks[T].Sectors[S].DeclaredLen) then
          HasW := True;
      end;
      { Pad the sector-cell field to a fixed visible width regardless of
        ANSI escapes — Length(RowLine) over-counts when escapes are
        present, so we compute the pad from the (known) visible glyph
        count instead. Visible prefix = 7 chars ("  NNNN "); each glyph
        contributes exactly 1 visible char. }
      RowLine := RowLine + StringOfChar(' ',
        MaxSectorsPerTrack - Length(Tracks[T].Sectors) + 1);
      SizeCol := TrackSizeSummary(Tracks[T]);
      IDCol   := TrackIDSummary(Tracks[T], Color);
      RowLine := RowLine + Format('%-14s %s', [SizeCol, IDCol]);
      SL.Add(RowLine);

      { Follow-on data lines — only emitted when the track carries a
        Discology-style mismatch flag. Surfaces the actual evidence
        (per-sector buffer lengths or per-sector DataLengths) that drove
        the L/W glyphs above so users can see, for example, the
        track-number-as-length tag (track 7 = 7-byte sectors) or the
        hostile DataLength values (track 29 last sector declares 52285). }
      if HasL then
      begin
        ActualLine := '         actual: ';
        for S := 0 to High(Tracks[T].Sectors) do
        begin
          if S > 0 then ActualLine := ActualLine + ',';
          ActualLine := ActualLine + IntToStr(Tracks[T].Sectors[S].ActualLen);
        end;
        SL.Add(ActualLine);
      end;
      if HasW then
      begin
        DeclLine := '         decl:   ';
        for S := 0 to High(Tracks[T].Sectors) do
        begin
          if S > 0 then DeclLine := DeclLine + ',';
          DeclLine := DeclLine + IntToStr(Tracks[T].Sectors[S].DeclaredLen);
        end;
        SL.Add(DeclLine);
      end;
    end;

    SL.Add('');
    { Conditional legend — only emit entries for glyph categories that
      actually appeared in this disk's output. A clean DOS-format DSK
      gets just one line ("Legend (state): . data"); a Discology disk
      gets the full menagerie. Saves the user from scanning past
      irrelevant legend entries. Glyphs in the legend are colored when
      Color is on, matching the row output. }
    StateStr := 'Legend (state):    ';
    if DataC   > 0 then StateStr := StateStr + ' ' + ColorGlyph('.', Color, False)+ ' data';
    if SysC    > 0 then StateStr := StateStr + '   ' + ColorGlyph('S', Color, False)+ ' system/dir';
    if BootC   > 0 then StateStr := StateStr + '   ' + ColorGlyph('B', Color, False)+ ' boot/reserved';
    if FillerC > 0 then StateStr := StateStr + '   ' + ColorGlyph('=', Color, False)+ ' filler(empty)';
    if OtherC  > 0 then StateStr := StateStr + '   ' + ColorGlyph('?', Color, False)+ ' non-standard';
    if BadC    > 0 then StateStr := StateStr + '   ' + ColorGlyph('!', Color, False)+ ' FDC error';
    if (DataC + SysC + BootC + FillerC + OtherC + BadC) > 0 then
      SL.Add(StateStr);

    if (SuspIDC <> 0) or (WeakDLC <> 0) or (LenMismatchC <> 0) or (TwinC <> 0) then
    begin
      StateStr := 'Legend (protect):  ';
      if SuspIDC      > 0 then StateStr := StateStr + ' ' + ColorGlyph('X', Color, False)+ ' suspicious ID';
      if WeakDLC      > 0 then StateStr := StateStr + '   ' + ColorGlyph('W', Color, False)+ ' weak DataLength';
      if LenMismatchC > 0 then StateStr := StateStr + '   ' + ColorGlyph('L', Color, False)+ ' length mismatch';
      if TwinC        > 0 then StateStr := StateStr + '   ' + ColorGlyph('T', Color, False)+ ' twin SectorID';
      SL.Add(StateStr);
    end;

    if (SuspIDC > 0) or (TwinC > 0) then
    begin
      StateStr := 'IDs row markers:   ';
      if SuspIDC > 0 then
      begin
        if Color then StateStr := StateStr + ' ' + ANSI_FG_SUSP_MARK + '?' + ANSI_RESET +
                                   '  suspicious (out-of-range) ID'
        else          StateStr := StateStr + ' ?  suspicious (out-of-range) ID';
      end;
      if TwinC > 0 then
      begin
        if Color then StateStr := StateStr + '   ' + ANSI_FG_TWIN_MARK + '*' + ANSI_RESET +
                                   '  twin (ID repeated on same track)'
        else          StateStr := StateStr + '   *  twin (ID repeated on same track)';
      end;
      SL.Add(StateStr);
    end;

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
