program test_gui_sort;

{ Unit tests for uGUISorting.SortHostEntryArray.

  Compile:
    cd /Users/ikari/src/cpc/DiskBender && \
      fpc -Fu./src/units -Fu./src/gui -Fu./src \
          tests/test_gui_sort.pas -otests/test_gui_sort
  Run:
    ./tests/test_gui_sort }

{$mode objfpc}{$H+}

uses
  SysUtils, DateUtils, uCPMTypes, uGUISorting;

var
  PassCount: Integer = 0;
  FailCount: Integer = 0;

procedure Check(const AName: string; ACondition: Boolean);
begin
  if ACondition then
  begin
    WriteLn('  PASS: ', AName);
    Inc(PassCount);
  end
  else
  begin
    WriteLn('  FAIL: ', AName);
    Inc(FailCount);
  end;
end;

function MakeEntry(AKind: TRowKind; const AName: string;
                   ASize: Int64; ATime: TDateTime): THostEntry;
begin
  Result.Kind := AKind;
  Result.Name := AName;
  Result.Size := ASize;
  Result.Time := ATime;
end;

{ ── Helper to build a fixed-length array ─────────────────────── }

function MakeArr(const E0, E1, E2: THostEntry): THostEntryArray;
begin
  SetLength(Result, 3);
  Result[0] := E0;
  Result[1] := E1;
  Result[2] := E2;
end;

function MakeArr4(const E0, E1, E2, E3: THostEntry): THostEntryArray;
begin
  SetLength(Result, 4);
  Result[0] := E0;
  Result[1] := E1;
  Result[2] := E2;
  Result[3] := E3;
end;

{ ── Tests ─────────────────────────────────────────────────────── }

procedure TestParentAlwaysFirst;
var
  Arr: THostEntryArray;
  T0: TDateTime;
begin
  WriteLn('--- TestParentAlwaysFirst ---');
  T0 := Now;

  { Parent sandwiched between two files — name ascending }
  Arr := MakeArr(
    MakeEntry(rkHostFile, 'AAA.TXT', 100, T0),
    MakeEntry(rkParent,   '..',      0,   T0),
    MakeEntry(rkHostFile, 'ZZZ.TXT', 200, T0)
  );
  SortHostEntryArray(Arr, hsName, True, False);
  Check('Parent first (name asc)', Arr[0].Kind = rkParent);

  { Parent last in input — size descending }
  Arr := MakeArr(
    MakeEntry(rkHostFile, 'A', 500, T0),
    MakeEntry(rkHostFile, 'B', 300, T0),
    MakeEntry(rkParent,   '..', 0, T0)
  );
  SortHostEntryArray(Arr, hsSize, False, False);
  Check('Parent first (size desc)', Arr[0].Kind = rkParent);

  { Parent last in input — DirsFirst=True }
  Arr := MakeArr(
    MakeEntry(rkHostDir,  'DOCS', 0,  T0),
    MakeEntry(rkHostFile, 'README', 10, T0),
    MakeEntry(rkParent,   '..',  0,  T0)
  );
  SortHostEntryArray(Arr, hsName, True, True);
  Check('Parent first even with DirsFirst', Arr[0].Kind = rkParent);
end;

procedure TestDirsFirst;
var
  Arr: THostEntryArray;
  T0: TDateTime;
begin
  WriteLn('--- TestDirsFirst ---');
  T0 := Now;

  { Files mixed with dirs; DirsFirst=True should push dirs before files }
  Arr := MakeArr4(
    MakeEntry(rkHostFile, 'alpha.txt', 10, T0),
    MakeEntry(rkHostDir,  'zebra',     0,  T0),
    MakeEntry(rkHostFile, 'beta.txt',  20, T0),
    MakeEntry(rkHostDir,  'aardvark',  0,  T0)
  );
  SortHostEntryArray(Arr, hsName, True, True);
  Check('DirsFirst: [0] is dir', Arr[0].Kind = rkHostDir);
  Check('DirsFirst: [1] is dir', Arr[1].Kind = rkHostDir);
  Check('DirsFirst: [2] is file', Arr[2].Kind = rkHostFile);
  Check('DirsFirst: dirs sorted by name (aardvark < zebra)',
        Arr[0].Name = 'aardvark');
  Check('DirsFirst: files sorted by name (alpha < beta)',
        Arr[2].Name = 'alpha.txt');
end;

procedure TestDirsMixedWithFiles;
var
  Arr: THostEntryArray;
  T0: TDateTime;
begin
  WriteLn('--- TestDirsMixedWithFiles (DirsFirst=False) ---');
  T0 := Now;

  Arr := MakeArr4(
    MakeEntry(rkHostFile, 'charlie.txt', 10, T0),
    MakeEntry(rkHostDir,  'bravo',       0,  T0),
    MakeEntry(rkHostFile, 'alpha.txt',   20, T0),
    MakeEntry(rkHostDir,  'delta',       0,  T0)
  );
  SortHostEntryArray(Arr, hsName, True, False);
  Check('Mixed (DirsFirst=False): [0] = alpha.txt', Arr[0].Name = 'alpha.txt');
  Check('Mixed (DirsFirst=False): [1] = bravo',     Arr[1].Name = 'bravo');
  Check('Mixed (DirsFirst=False): [2] = charlie.txt', Arr[2].Name = 'charlie.txt');
  Check('Mixed (DirsFirst=False): [3] = delta',     Arr[3].Name = 'delta');
end;

procedure TestNameAscDesc;
var
  Arr: THostEntryArray;
  T0: TDateTime;
begin
  WriteLn('--- TestNameAscDesc ---');
  T0 := Now;

  Arr := MakeArr(
    MakeEntry(rkHostFile, 'Zebra', 1, T0),
    MakeEntry(rkHostFile, 'Apple', 2, T0),
    MakeEntry(rkHostFile, 'Mango', 3, T0)
  );
  SortHostEntryArray(Arr, hsName, True, False);
  Check('Name asc: [0]=Apple', Arr[0].Name = 'Apple');
  Check('Name asc: [1]=Mango', Arr[1].Name = 'Mango');
  Check('Name asc: [2]=Zebra', Arr[2].Name = 'Zebra');

  SortHostEntryArray(Arr, hsName, False, False);
  Check('Name desc: [0]=Zebra', Arr[0].Name = 'Zebra');
  Check('Name desc: [1]=Mango', Arr[1].Name = 'Mango');
  Check('Name desc: [2]=Apple', Arr[2].Name = 'Apple');
end;

procedure TestSizeAscDesc;
var
  Arr: THostEntryArray;
  T0: TDateTime;
begin
  WriteLn('--- TestSizeAscDesc ---');
  T0 := Now;

  Arr := MakeArr(
    MakeEntry(rkHostFile, 'big',    9000, T0),
    MakeEntry(rkHostFile, 'tiny',   1,    T0),
    MakeEntry(rkHostFile, 'medium', 500,  T0)
  );
  SortHostEntryArray(Arr, hsSize, True, False);
  Check('Size asc: [0].Size=1',    Arr[0].Size = 1);
  Check('Size asc: [1].Size=500',  Arr[1].Size = 500);
  Check('Size asc: [2].Size=9000', Arr[2].Size = 9000);

  SortHostEntryArray(Arr, hsSize, False, False);
  Check('Size desc: [0].Size=9000', Arr[0].Size = 9000);
  Check('Size desc: [1].Size=500',  Arr[1].Size = 500);
  Check('Size desc: [2].Size=1',    Arr[2].Size = 1);
end;

procedure TestTimeAscDesc;
var
  Arr: THostEntryArray;
  T1, T2, T3: TDateTime;
begin
  WriteLn('--- TestTimeAscDesc ---');
  T1 := EncodeDateTime(2020, 1, 1, 0, 0, 0, 0);
  T2 := EncodeDateTime(2022, 6, 15, 12, 0, 0, 0);
  T3 := EncodeDateTime(2025, 12, 31, 23, 59, 59, 0);

  Arr := MakeArr(
    MakeEntry(rkHostFile, 'newest', 1, T3),
    MakeEntry(rkHostFile, 'oldest', 2, T1),
    MakeEntry(rkHostFile, 'middle', 3, T2)
  );
  SortHostEntryArray(Arr, hsTime, True, False);
  Check('Time asc: [0]=oldest', Arr[0].Name = 'oldest');
  Check('Time asc: [1]=middle', Arr[1].Name = 'middle');
  Check('Time asc: [2]=newest', Arr[2].Name = 'newest');

  SortHostEntryArray(Arr, hsTime, False, False);
  Check('Time desc: [0]=newest', Arr[0].Name = 'newest');
  Check('Time desc: [1]=middle', Arr[1].Name = 'middle');
  Check('Time desc: [2]=oldest', Arr[2].Name = 'oldest');
end;

procedure TestSingleElement;
var
  Arr: THostEntryArray;
  T0: TDateTime;
begin
  WriteLn('--- TestSingleElement ---');
  T0 := Now;

  SetLength(Arr, 1);
  Arr[0] := MakeEntry(rkHostFile, 'solo.txt', 42, T0);
  SortHostEntryArray(Arr, hsName, True, False);
  Check('Single element: no crash, name unchanged', Arr[0].Name = 'solo.txt');
  Check('Single element: size unchanged',           Arr[0].Size = 42);

  SetLength(Arr, 1);
  Arr[0] := MakeEntry(rkParent, '..', 0, T0);
  SortHostEntryArray(Arr, hsSize, False, True);
  Check('Single parent: no crash, kind unchanged', Arr[0].Kind = rkParent);
end;

procedure TestEmptyArray;
var
  Arr: THostEntryArray;
begin
  WriteLn('--- TestEmptyArray ---');
  SetLength(Arr, 0);
  SortHostEntryArray(Arr, hsName, True, False);
  Check('Empty array: no crash, still empty', Length(Arr) = 0);

  SortHostEntryArray(Arr, hsSize, False, True);
  Check('Empty array (size desc): no crash', Length(Arr) = 0);
end;

begin
  WriteLn('=== test_gui_sort ===');

  TestParentAlwaysFirst;
  TestDirsFirst;
  TestDirsMixedWithFiles;
  TestNameAscDesc;
  TestSizeAscDesc;
  TestTimeAscDesc;
  TestSingleElement;
  TestEmptyArray;

  WriteLn;
  WriteLn('Passed: ', PassCount, '  Failed: ', FailCount);
  if FailCount > 0 then
    Halt(1);
end.
