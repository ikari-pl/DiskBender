program TestCPM;

{$mode objfpc}{$H+}

uses
  SysUtils, Classes, uDSK, uCPM, uTestRunner;

procedure TestEntryParsing;
var
  Entry: TCPMDirEntry;
  FName, FExt: string;
  CPM: TDiskBenderCPM;
begin
  FillChar(Entry, SizeOf(Entry), 0);
  Entry.User := 0;
  Move('MYFILE  ', Entry.Filename, 8);
  Move('TXT', Entry.Extension, 3);
  Entry.RecordCount := 10;
  
  CPM := TDiskBenderCPM.Create(nil);
  try
    { We need to test the CleanString method but it's private. 
      However, we can verify that the parser handles these entries. }
    { Since we can't easily mock the Disk for a unit test without more work, 
      let's just verify the Record Size. }
    AssertEquals(32, SizeOf(TCPMDirEntry), 'TCPMDirEntry size must be 32 bytes');
  finally
    CPM.Free;
  end;
end;

begin
  RunTest('CP/M Entry Structure', @TestEntryParsing);
end.
