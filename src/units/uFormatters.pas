unit uFormatters;

{$mode delphi}{$H+}

interface

uses
  SysUtils, Classes, uInterfaces, fpjson;

type
  TOutputFormat = (ofTable, ofJSON);

  TDiskFormatter = class
  public
    class function FormatFiles(Filesystem: IFilesystem; Formatter: TOutputFormat): string;
    class function FormatMap(const Map: TBytes; Formatter: TOutputFormat): string;
    class function FormatDiskInfo(Disk: IVirtualDisk; Formatter: TOutputFormat): string;
  end;

implementation

class function TDiskFormatter.FormatFiles(Filesystem: IFilesystem; Formatter: TOutputFormat): string;
var
  I: Integer;
  VFile: IVirtualFile;
  SL: TStringList;
  JArray: TJSONArray;
  JObj: TJSONObject;
begin
  SL := TStringList.Create;
  try
    if Formatter = ofTable then
    begin
      SL.Add(SysUtils.Format('%-4s %-12s %-4s %8s', ['User', 'Name', 'Ext', 'Size']));
      SL.Add('----------------------------------------------');
      for I := 0 to Filesystem.GetFileCount - 1 do
      begin
        VFile := Filesystem.GetFile(I);
        SL.Add(SysUtils.Format('%-4d %-12s %-4s %8d', 
          [VFile.User, VFile.Name, VFile.Extension, VFile.SizeKB]));
      end;
    end
    else if Formatter = ofJSON then
    begin
      JArray := TJSONArray.Create;
      for I := 0 to Filesystem.GetFileCount - 1 do
      begin
        VFile := Filesystem.GetFile(I);
        JObj := TJSONObject.Create;
        JObj.Add('user', VFile.User);
        JObj.Add('name', VFile.Name);
        JObj.Add('ext', VFile.Extension);
        JObj.Add('size_kb', VFile.SizeKB);
        JObj.Add('is_deleted', VFile.IsDeleted);
        JArray.Add(JObj);
      end;
      SL.Text := JArray.FormatJSON;
      JArray.Free;
    end;
    Result := SL.Text;
  finally
    SL.Free;
  end;
end;

class function TDiskFormatter.FormatMap(const Map: TBytes; Formatter: TOutputFormat): string;
var
  I: Integer;
  S: string;
  JArray: TJSONArray;
begin
  Result := '';
  if Formatter = ofTable then
  begin
    S := '';
    for I := 0 to Length(Map) - 1 do
    begin
      case Map[I] of
        0: S := S + '.';
        1: S := S + 'D';
        2: S := S + '#';
        3: S := S + 'x';
      end;
      if (I + 1) mod 64 = 0 then S := S + sLineBreak;
    end;
    Result := S;
  end
  else if Formatter = ofJSON then
  begin
    JArray := TJSONArray.Create;
    for I := 0 to Length(Map) - 1 do JArray.Add(Map[I]);
    Result := JArray.FormatJSON;
    JArray.Free;
  end;
end;

class function TDiskFormatter.FormatDiskInfo(Disk: IVirtualDisk; Formatter: TOutputFormat): string;
var
  JObj: TJSONObject;
begin
  if Formatter = ofJSON then
  begin
    JObj := TJSONObject.Create;
    JObj.Add('path', Disk.FilePath);
    JObj.Add('tracks', Disk.NumTracks);
    JObj.Add('sides', Disk.NumSides);
    JObj.Add('modified', Disk.Modified);
    Result := JObj.FormatJSON;
    JObj.Free;
  end
  else
  begin
    Result := SysUtils.Format('Path: %s, Tracks: %d, Sides: %d, Modified: %v', 
      [Disk.FilePath, Disk.NumTracks, Disk.NumSides, Disk.Modified]);
  end;
end;

end.
