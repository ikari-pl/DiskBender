unit uExternalDriveAsync;

{$mode objfpc}{$H+}

{ Background wrapper around the Greaseweazle 'gw' host tool.
  TGwTask runs gw in a TThread, draining its merged stdout/stderr pipe
  continuously so the UI can show live progress.  Cancel() sends SIGTERM
  to the child process; the caller must wait for IsFinished before
  calling Free. }

interface

uses
  Classes, SysUtils, Process;

type
  TGwOp = (gopRead, gopWrite, gopInfo);

  TGwTask = class(TThread)
  private
    FOp: TGwOp;
    FGwPath: string;
    FDrive: string;
    FImagePath: string;
    FProc: TProcess;
    FLog: string;
    FOk: Boolean;
    FLock: TRTLCriticalSection;
    FFinished: Boolean;
    FCancelRequested: Boolean;
    procedure AppendLog(const S: string);
  protected
    procedure Execute; override;
  public
    constructor Create(AOp: TGwOp; const AGwPath, ADrive, AImagePath: string);
    destructor Destroy; override;
    { Sends SIGTERM to the child; safe to call from any thread. }
    procedure Cancel;
    function IsFinished: Boolean;
    function WasOk: Boolean;
    function GetLogSnapshot: string;
    function GetCancelRequested: Boolean;
  end;

implementation

const
  BUF_SIZE = 4096;

{ ── TGwTask ──────────────────────────────────────────────────── }

constructor TGwTask.Create(AOp: TGwOp; const AGwPath, ADrive,
                            AImagePath: string);
begin
  inherited Create(True);   { suspended; caller calls Start }
  FreeOnTerminate := False;
  InitCriticalSection(FLock);
  FOp := AOp;
  FGwPath := AGwPath;
  FDrive := ADrive;
  FImagePath := AImagePath;
  FLog := '';
  FOk := False;
  FFinished := False;
  FCancelRequested := False;
  FProc := nil;
end;

destructor TGwTask.Destroy;
begin
  if FProc <> nil then
    FProc.Free;
  DoneCriticalSection(FLock);
  inherited;
end;

procedure TGwTask.AppendLog(const S: string);
begin
  EnterCriticalSection(FLock);
  try
    FLog := FLog + S;
  finally
    LeaveCriticalSection(FLock);
  end;
end;

function TGwTask.IsFinished: Boolean;
begin
  EnterCriticalSection(FLock);
  try
    Result := FFinished;
  finally
    LeaveCriticalSection(FLock);
  end;
end;

function TGwTask.WasOk: Boolean;
begin
  EnterCriticalSection(FLock);
  try
    Result := FOk;
  finally
    LeaveCriticalSection(FLock);
  end;
end;

function TGwTask.GetLogSnapshot: string;
begin
  EnterCriticalSection(FLock);
  try
    Result := FLog;
  finally
    LeaveCriticalSection(FLock);
  end;
end;

function TGwTask.GetCancelRequested: Boolean;
begin
  EnterCriticalSection(FLock);
  try
    Result := FCancelRequested;
  finally
    LeaveCriticalSection(FLock);
  end;
end;

procedure TGwTask.Cancel;
begin
  EnterCriticalSection(FLock);
  try
    FCancelRequested := True;
    if (FProc <> nil) and FProc.Running then
    begin
      try
        FProc.Terminate(143);  { SIGTERM = 128+15; ignore errors }
      except
      end;
    end;
  finally
    LeaveCriticalSection(FLock);
  end;
end;

procedure TGwTask.Execute;
var
  Buf: array[0..BUF_SIZE - 1] of Byte;
  BytesRead: Integer;
  Args: array of string;
  I: Integer;
  Tmp: string;
begin
  try
    FProc := TProcess.Create(nil);
    FProc.Executable := FGwPath;

    { Build argument list based on operation. }
    case FOp of
      gopInfo:
        begin
          SetLength(Args, 1);
          Args[0] := 'info';
        end;
      gopRead:
        if FDrive <> '' then
        begin
          SetLength(Args, 4);
          Args[0] := 'read';
          Args[1] := '--drive';
          Args[2] := FDrive;
          Args[3] := FImagePath;
        end
        else
        begin
          SetLength(Args, 2);
          Args[0] := 'read';
          Args[1] := FImagePath;
        end;
      gopWrite:
        if FDrive <> '' then
        begin
          SetLength(Args, 4);
          Args[0] := 'write';
          Args[1] := '--drive';
          Args[2] := FDrive;
          Args[3] := FImagePath;
        end
        else
        begin
          SetLength(Args, 2);
          Args[0] := 'write';
          Args[1] := FImagePath;
        end;
    end;

    for I := 0 to High(Args) do
      FProc.Parameters.Add(Args[I]);

    FProc.Options := [poUsePipes, poStderrToOutPut];

    try
      FProc.Execute;
    except
      on E: Exception do
      begin
        AppendLog('Failed to launch gw: ' + E.Message);
        FOk := False;
        EnterCriticalSection(FLock);
        try FFinished := True; finally LeaveCriticalSection(FLock); end;
        Exit;
      end;
    end;

    { Drain stdout+stderr while process runs.  Bail early if Cancel fired. }
    repeat
      BytesRead := FProc.Output.Read(Buf[0], BUF_SIZE);
      if BytesRead > 0 then
      begin
        SetString(Tmp, PAnsiChar(@Buf[0]), BytesRead);
        AppendLog(Tmp);
      end;
      if GetCancelRequested and not FProc.Running then
        Break;
    until (BytesRead = 0) and not FProc.Running;

    { Final drain after process exits. }
    try
      repeat
        BytesRead := FProc.Output.Read(Buf[0], BUF_SIZE);
        if BytesRead > 0 then
        begin
          SetString(Tmp, PAnsiChar(@Buf[0]), BytesRead);
          AppendLog(Tmp);
        end;
      until BytesRead = 0;
    except
      on E: Exception do
        AppendLog(LineEnding + '[drain error: ' + E.Message + ']');
    end;

    try
      FProc.WaitOnExit;
    except
    end;

    FOk := (FProc.ExitStatus = 0) and not GetCancelRequested;
  finally
    EnterCriticalSection(FLock);
    try
      FFinished := True;
    finally
      LeaveCriticalSection(FLock);
    end;
  end;
end;

end.
