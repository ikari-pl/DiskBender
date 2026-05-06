unit uTestRunner;

{$mode objfpc}{$H+}

interface

uses
  SysUtils;

procedure AssertTrue(Condition: Boolean; const Msg: string);
procedure AssertEquals(Expected, Actual: Int64; const Msg: string);
procedure AssertStrEquals(const Expected, Actual: string; const Msg: string);
procedure RunTest(const Name: string; TestProc: TProcedure);

implementation

var
  TestsPassed: Integer = 0;
  TestsFailed: Integer = 0;

procedure AssertTrue(Condition: Boolean; const Msg: string);
begin
  if not Condition then
  begin
    WriteLn('  [FAIL] ', Msg);
    Inc(TestsFailed);
  end
  else
    Inc(TestsPassed);
end;

procedure AssertEquals(Expected, Actual: Int64; const Msg: string);
begin
  if Expected <> Actual then
  begin
    WriteLn(Format('  [FAIL] %s: Expected %d, got %d', [Msg, Expected, Actual]));
    Inc(TestsFailed);
  end
  else
    Inc(TestsPassed);
end;

procedure AssertStrEquals(const Expected, Actual: string; const Msg: string);
begin
  if Expected <> Actual then
  begin
    WriteLn(Format('  [FAIL] %s: Expected "%s", got "%s"', [Msg, Expected, Actual]));
    Inc(TestsFailed);
  end
  else
    Inc(TestsPassed);
end;

procedure RunTest(const Name: string; TestProc: TProcedure);
begin
  Write('Running ', Name, '... ');
  try
    TestProc();
    WriteLn('Done.');
  except
    on E: Exception do
    begin
      WriteLn('CRASHED!');
      WriteLn('  Exception: ', E.Message);
      Inc(TestsFailed);
    end;
  end;
end;

initialization
  TestsPassed := 0;
  TestsFailed := 0;

finalization
  WriteLn('----------------------------------');
  WriteLn(Format('Tests Completed: %d passed, %d failed.', [TestsPassed, TestsFailed]));
  if TestsFailed > 0 then
    Halt(1);
end.
