program DiskBenderTUI;

{$mode objfpc}{$H+}

uses
  uTUI_Custom, uDSK, SysUtils;

var
  App: TDiskBenderTUI;
  Disk: TDiskBenderDSK;

begin
  if ParamCount < 1 then
  begin
    WriteLn('Usage: DiskBenderTUI <path_to_dsk>');
    Exit;
  end;

  Disk := TDiskBenderDSK.Create(ParamStr(1));
  try
    Disk.Load;
    App := TDiskBenderTUI.Create(ParamStr(1), Disk);
    App.Run;
    App.Destroy;
  finally
    Disk.Free;
  end;
end.
