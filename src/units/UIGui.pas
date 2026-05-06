unit UIGui;

{$mode objfpc}{$H+}

interface

{ GUI scaffolding ready for Lazarus LCL integration
  When LCL is available, this implements:
  - Two-pane layout (DSK/Host filesystem)
  - File operations (copy, delete, etc.)
  - Drag & drop support
  - Hex viewer for sectors
  - Disk creation/formatting dialogs
}
  
uses
  SysUtils, Classes, uDSK, uCPM, uInterfaces;

type
  { GUI mode selector - what type of interface to show }
  TGuiMode = (
    gmMain,       { Two-pane file browser }
    gmHexViewer,   { Sector hex viewer }
    gmDiskInfo,   { Disk information dialog }
    gmFormat     { Disk format dialog }
  );

  { Result from GUI operation }
  TGuiResult = record
    Success: Boolean;
    Message: string;
  end;

  { Stub implementation - runs when LCL unavailable }
  { Note: GUID syntax not supported in FPC mode objfpc - using class instead of interface }
  TDiskBenderGui = class
  private
    FDisk: IVirtualDisk;
    FFS: IFilesystem;
    FMode: TGuiMode;
  public
    procedure SetDisk(ADisk: IVirtualDisk);
    procedure SetFilesystem(AFS: IFilesystem);
    procedure SetMode(AMode: TGuiMode);
    function Run: Integer;
  end;

var
  Gui: TDiskBenderGui;

implementation

{ TDiskBenderGui }

procedure TDiskBenderGui.SetDisk(ADisk: IVirtualDisk);
begin
  FDisk := ADisk;
end;

procedure TDiskBenderGui.SetFilesystem(AFS: IFilesystem);
begin
  FFS := AFS;
end;

procedure TDiskBenderGui.SetMode(AMode: TGuiMode);
begin
  FMode := AMode;
end;

function TDiskBenderGui.Run: Integer;
begin
  { Stub: Print available modes when GUI not available }
  WriteLn('DiskBender GUI (Stub Mode)');
  WriteLn;
  WriteLn('Note: Lazarus LCL not available.');
  WriteLn('Install Lazarus from ~/src/lazarus for full GUI support.');
  WriteLn;
  WriteLn('Available GUI modes:');
  WriteLn('  gmMain       - Two-pane file browser (DSK/Host)');
  WriteLn('  gmHexViewer  - Sector hex viewer');
  WriteLn('  gmDiskInfo   - Disk information dialog');
  WriteLn('  gmFormat    - Disk format dialog');
  WriteLn;
  if Assigned(FDisk) then
  begin
    WriteLn('Current disk: ', FDisk.FilePath);
    WriteLn('  Tracks: ', FDisk.NumTracks);
    WriteLn('  Sides: ', FDisk.NumSides);
  end;
  Result := 0;
end;

initialization
  Gui := TDiskBenderGui.Create;

finalization
  Gui.Free;

end.