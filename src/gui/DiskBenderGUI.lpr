program DiskBenderGUI;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Interfaces, // this includes the LCL widgetset
  Forms,
  uMainForm,
  uDSK,
  uCPM,
  uInterfaces,
  uFormatters,
  CoreAPI;

{$R *.res}

begin
  RequireDerivedFormResource := True;
  Application.Scaled := True;
  Application.Initialize;
  Application.CreateForm(TMainForm, MainForm);
  Application.BringToFront;
  Application.Run;
end.
