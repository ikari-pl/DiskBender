unit uTUI;

{$mode objfpc}{$H+}

interface

uses
  App, Drivers, Views, Menus, Dialogs, Objects, uDSK, uCPM, SysUtils;

const
  cmDiskInfo = 1001;
  cmSectorView = 1002;
  cmFileView = 1003;

type
  TDiskBenderApp = class(TApplication)
  private
    FDisk: TDiskBenderDSK;
    FCPM: TDiskBenderCPM;
    FDSKPath: string;
  public
    constructor Create(const ADSKPath: string);
    procedure InitStatusLine; override;
    procedure InitMenuBar; override;
    procedure HandleEvent(var Event: TEvent); override;
    procedure ShowDiskInfo;
    procedure ShowSectorView;
    procedure ShowFileView;
  end;

implementation

constructor TDiskBenderApp.Create(const ADSKPath: string);
begin
  inherited Create;
  FDSKPath := ADSKPath;
  FDisk := TDiskBenderDSK.Create(FDSKPath);
  try
    FDisk.Load;
    FCPM := TDiskBenderCPM.Create(FDisk);
    FCPM.AutoDetectFormat;
  except
    on E: Exception do
      PrintStr('Error loading disk: ' + E.Message);
  end;
end;

procedure TDiskBenderApp.InitStatusLine;
var
  R: TRect;
begin
  GetExtent(R);
  R.A.Y := R.B.Y - 1;
  StatusLine := New(PStatusLine, Init(R,
    NewStatusDef(0, $FFFF,
      NewStatusKey('~Alt-X~ Exit', kbAltX, cmQuit,
      NewStatusKey('~F10~ Menu', kbF10, cmMenu,
      nil)),
    nil)
  ));
end;

procedure TDiskBenderApp.InitMenuBar;
var
  R: TRect;
begin
  GetExtent(R);
  R.B.Y := R.A.Y + 1;
  MenuBar := New(PMenuBar, Init(R, NewMenu(
    NewSubMenu('~F~ile', hcNoContext, NewMenu(
      NewItem('~I~nfo', 'F2', kbF2, cmDiskInfo, hcNoContext,
      NewItem('~S~ector View', 'F3', kbF3, cmSectorView, hcNoContext,
      NewItem('~L~ist Files', 'F4', kbF4, cmFileView, hcNoContext,
      NewLine(
      NewItem('E~x~it', 'Alt-X', kbAltX, cmQuit, hcNoContext,
      nil)))))),
    nil)
  )));
end;

procedure TDiskBenderApp.HandleEvent(var Event: TEvent);
begin
  inherited HandleEvent(Event);
  if Event.What = evCommand then
  begin
    case Event.Command of
      cmDiskInfo: ShowDiskInfo;
      cmSectorView: ShowSectorView;
      cmFileView: ShowFileView;
    else
      Exit;
    end;
    ClearEvent(Event);
  end;
end;

procedure TDiskBenderApp.ShowDiskInfo;
var
  D: PDialog;
  R: TRect;
begin
  R.Assign(0, 0, 40, 10);
  D := New(PDialog, Init(R, 'Disk Information'));
  D^.Insert(New(PStaticText, Init(R, 
    #13'  File: ' + ExtractFileName(FDSKPath) + 
    #13'  Type: ' + (if FDisk.DSKType = dtExtended then 'Extended' else 'Standard') +
    #13'  Tracks: ' + IntToStr(FDisk.NumTracks) +
    #13'  Sides: ' + IntToStr(FDisk.NumSides))));
  ExecuteDialog(D, nil);
end;

procedure TDiskBenderApp.ShowSectorView;
begin
  { TODO: Implement Hex Viewer Window }
  MessageBox('Sector Viewer coming soon! Use CLI for now.', nil, mfInformation or mfOKButton);
end;

procedure TDiskBenderApp.ShowFileView;
begin
  { TODO: Implement File List Window }
  MessageBox('File Browser coming soon! Use CLI for now.', nil, mfInformation or mfOKButton);
end;

end.
