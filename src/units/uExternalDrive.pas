unit uExternalDrive;

{$mode objfpc}{$H+}

{ Thin wrapper around the Greaseweazle 'gw' host tool.
  DiskBender contains NO hardware code — it shells out to gw and
  consumes the .dsk (or .scp) image that gw produces. }

interface

function FindGwExecutable: string;
{ '' when gw cannot be found on this system. }

function RunGw(const AGwPath: string; const AArgs: array of string;
               out ALog: string): Boolean;
{ Execute AGwPath with AArgs.  Returns True on exit code 0.
  Stdout and stderr are merged into ALog. }

function GwReadDisc(const AGwPath, ADrive, AImagePath: string;
                    out ALog: string): Boolean;
{ Read a disc to AImagePath.  ADrive may be '' to omit --drive.
  gw infers the output format from the file extension: .dsk decodes
  to a standard image; .scp writes raw flux.  Pass the appropriate
  extension in AImagePath — no separate flag is needed. }

function GwWriteDisc(const AGwPath, ADrive, AImagePath: string;
                     out ALog: string): Boolean;
{ Write AImagePath to the drive. ADrive may be '' to omit --drive. }

function GwDriveInfo(const AGwPath: string; out ALog: string): Boolean;
{ Run 'gw info' and return its output. }

const
  GW_NOT_FOUND_HINT =
    'Greaseweazle tool ''gw'' not found.'#10 +
    'Install with:  pipx install greaseweazle'#10 +
    '  (or set DISKBENDER_GW=/path/to/gw)';

implementation

uses
  SysUtils, Classes, Process;

{ ── FindGwExecutable ─────────────────────────────────────────── }

function FindGwExecutable: string;
var
  EnvPath, Candidate: string;
  CandidateList: array[0..2] of string;
  I: Integer;
begin
  { 1. Explicit override via env var }
  EnvPath := GetEnvironmentVariable('DISKBENDER_GW');
  if (EnvPath <> '') and FileExists(EnvPath) then
  begin
    Result := EnvPath;
    Exit;
  end;

  { 2. Search PATH via FPC's FileSearch }
  Result := FileSearch('gw', GetEnvironmentVariable('PATH'));
  if Result <> '' then Exit;

  { 3. Well-known literal paths }
  CandidateList[0] := '/opt/homebrew/bin/gw';
  CandidateList[1] := '/usr/local/bin/gw';
  CandidateList[2] := GetEnvironmentVariable('HOME') + '/.local/bin/gw';
  for I := 0 to High(CandidateList) do
  begin
    Candidate := CandidateList[I];
    if (Candidate <> '') and FileExists(Candidate) then
    begin
      Result := Candidate;
      Exit;
    end;
  end;

  Result := '';
end;

{ ── RunGw ────────────────────────────────────────────────────── }

function RunGw(const AGwPath: string; const AArgs: array of string;
               out ALog: string): Boolean;
const
  BUF_SIZE = 4096;
var
  Proc: TProcess;
  I, BytesRead: Integer;
  Buf: array[0..BUF_SIZE - 1] of Byte;
  SS: TStringStream;
begin
  ALog := '';
  Result := False;

  Proc := TProcess.Create(nil);
  try
    Proc.Executable := AGwPath;
    for I := 0 to High(AArgs) do
      Proc.Parameters.Add(AArgs[I]);
    Proc.Options := [poUsePipes, poStderrToOutPut];
    try
      Proc.Execute;
    except
      on E: Exception do
      begin
        ALog := 'Failed to launch gw: ' + E.Message;
        Exit;
      end;
    end;

    { Drain stdout (which also carries stderr) while the process runs.
      Never use poWaitOnExit with poUsePipes — it deadlocks once the pipe
      buffer fills.  Read in a loop instead. }
    SS := TStringStream.Create('');
    try
      repeat
        BytesRead := Proc.Output.Read(Buf[0], BUF_SIZE);
        if BytesRead > 0 then
          SS.WriteBuffer(Buf[0], BytesRead);
      until (BytesRead = 0) and (not Proc.Running);

      { One final drain after the process exits.  Wrapped in try/except so a
        pipe-close exception does not escape and skip Proc.Free below. }
      try
        repeat
          BytesRead := Proc.Output.Read(Buf[0], BUF_SIZE);
          if BytesRead > 0 then
            SS.WriteBuffer(Buf[0], BytesRead);
        until BytesRead = 0;
      except
        on E: Exception do
          SS.WriteString(LineEnding + '[drain error: ' + E.Message + ']');
      end;

      ALog := SS.DataString;
    finally
      SS.Free;
    end;

    Proc.WaitOnExit;
    Result := (Proc.ExitStatus = 0);
  finally
    Proc.Free;
  end;
end;

{ ── GwReadDisc ───────────────────────────────────────────────── }

function GwReadDisc(const AGwPath, ADrive, AImagePath: string;
                    out ALog: string): Boolean;
var
  Args: array of string;
begin

  { Build: gw read [--drive <d>] <image> }
  if ADrive <> '' then
  begin
    SetLength(Args, 4);
    Args[0] := 'read';
    Args[1] := '--drive';
    Args[2] := ADrive;
    Args[3] := AImagePath;
  end
  else
  begin
    SetLength(Args, 2);
    Args[0] := 'read';
    Args[1] := AImagePath;
  end;

  Result := RunGw(AGwPath, Args, ALog);
end;

{ ── GwWriteDisc ──────────────────────────────────────────────── }

function GwWriteDisc(const AGwPath, ADrive, AImagePath: string;
                     out ALog: string): Boolean;
var
  Args: array of string;
begin
  { Build: gw write [--drive <d>] <image> }
  if ADrive <> '' then
  begin
    SetLength(Args, 4);
    Args[0] := 'write';
    Args[1] := '--drive';
    Args[2] := ADrive;
    Args[3] := AImagePath;
  end
  else
  begin
    SetLength(Args, 2);
    Args[0] := 'write';
    Args[1] := AImagePath;
  end;

  Result := RunGw(AGwPath, Args, ALog);
end;

{ ── GwDriveInfo ──────────────────────────────────────────────── }

function GwDriveInfo(const AGwPath: string; out ALog: string): Boolean;
var
  Args: array[0..0] of string;
begin
  Args[0] := 'info';
  Result := RunGw(AGwPath, Args, ALog);
end;

end.
