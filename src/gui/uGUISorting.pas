unit uGUISorting;

{$mode objfpc}{$H+}

{ Host-directory entry types and sort algorithm, extracted from uMainForm so
  they can be used in standalone tests without any LCL dependency.

  Only depends on: SysUtils, Math, DateUtils, uVFS (for TRowKind). }

interface

uses
  SysUtils, Math, DateUtils, uCPMTypes;

type
  THostEntry = record
    Kind: TRowKind;
    Name: string;
    Size: Int64;
    Time: TDateTime;
  end;
  THostEntryArray = array of THostEntry;

  THostSortField = (hsName, hsSize, hsTime);

{ In-place insertion sort for host directory listings.
  Invariant: rkParent entries always sort before everything else regardless
  of Field or Asc.  When DirsFirst is True, directories (rkHostDir) sort
  before files (rkHostFile) within each tier. }
procedure SortHostEntryArray(var Arr: THostEntryArray;
                              Field: THostSortField; Asc, DirsFirst: Boolean);

implementation

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

end.
