program keytest;
{$mode objfpc}{$H+}
uses Keyboard, Video;

var
  K: TKeyEvent;
  Code: LongWord;
begin
  InitVideo;
  InitKeyboard;
  WriteLn('Press keys to see codes. Press Q to quit.');
  WriteLn('Format: Raw=$XXXX  Translated=$XXXX  ScanHi=$XX  CharLo=$XX');
  WriteLn;
  repeat
    K := GetKeyEvent;
    Code := GetKeyEventCode(K);
    Write('Raw=$', HexStr(Code, 8));
    K := TranslateKeyEvent(K);
    Code := GetKeyEventCode(K);
    WriteLn('  Trans=$', HexStr(Code, 8),
            '  Hi=$', HexStr(Code shr 8, 2),
            '  Lo=$', HexStr(Code and $FF, 2));
  until (Code and $FF = ord('q')) or (Code and $FF = ord('Q'));
  DoneKeyboard;
  DoneVideo;
end.
