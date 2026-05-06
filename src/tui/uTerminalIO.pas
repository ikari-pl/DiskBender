unit uTerminalIO;

{$mode objfpc}{$H+}

interface

type
  TKeyAction = (
    kaUp, kaDown, kaLeft, kaRight,
    kaEnter, kaEsc, kaTab, kaBackspace,
    kaF1, kaF2, kaF3, kaF4, kaF5,
    kaF6, kaF7, kaF8, kaF9, kaF10,
    kaChar,
    kaNone
  );

  TInputEvent = record
    Action: TKeyAction;
    CharValue: Char;
  end;

  ITerminalInput = interface
    ['{DB100001-0001-4E49-8E00-000000000001}']
    function WaitForKey: TInputEvent;
  end;

  ITerminalOutput = interface
    ['{DB100001-0002-4E49-8E00-000000000002}']
    function GetWidth: Integer;
    function GetHeight: Integer;
    procedure PutText(X, Y: Integer; const AText: string; AAttr: Byte);
    procedure Clear;
    procedure Flush;
    procedure Init;
    procedure Done;
    property Width: Integer read GetWidth;
    property Height: Integer read GetHeight;
  end;

function InputEvent(AAction: TKeyAction; AChar: Char = #0): TInputEvent;

implementation

function InputEvent(AAction: TKeyAction; AChar: Char = #0): TInputEvent;
begin
  Result.Action := AAction;
  Result.CharValue := AChar;
end;

end.
