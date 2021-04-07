{
  Generate a Conflict Resolution Patch
  Hotkey: Ctrl+Shift+P
}
unit ConflictPatchHelper;

interface

implementation

uses xEditAPI, Classes, SysUtils, StrUtils, Windows;

var
  sCurrentPlugin: string;
  gfPatch: IwbFile;
  gslMappings, gslPlugins: TStringList;

  // ============================================================================
  // Select a plugin to work on
procedure SelectPlugin(slPlugin: TStringList);
var
  frm: TForm;
  clb: TCheckListBox;
  i: integer;
begin
  frm := frmFileSelect;
  try
    frm.Caption := 'Select the Plugins to Patch';
    clb := TCheckListBox(frm.FindComponent('CheckListBox1'));
    clb.items.Assign(slPlugin);
    if frm.ShowModal <> mrOk then
      exit;
    for i := 0 to Pred(clb.items.Count) do
      if clb.Checked[i] then
      begin
        AddMessage('Selected ' + slPlugin[i]);
        gslPlugins.AddObject(slPlugin[i], slPlugin.Objects[i]);
      end;
  finally
    frm.Free;
  end;
end;

function IsSubrecord(e: IInterface): boolean;
begin
  Result :=
    (ElementType(e) = etSubRecord) or
    (ElementType(e) = etSubRecordStruct) or
    (ElementType(e) = etSubRecordArray) or
    (ElementType(e) = etSubRecordUnion);
end;

procedure FormatMessage(s: string; args: IInterface);
begin
  AddMessage(Format(s, args));
end;

procedure InfoDlg(msg: string);
begin
  MessageDlg(msg, mtInformation, [mbOk], 0);
end;

function AddToPatch(e: IwbElement; abAsNew: boolean):
  IwbElement;
var
  i: integer;
  r: IwbMainRecord; 
begin
  // create a new patch plugin if needed
  if not Assigned(gfPatch) then begin
    gfPatch := AddNewFile;
    if not Assigned(gfPatch) then
      abort;

    for i := 0 to Pred(gslPlugins.Count) do
      AddMasterIfMissing(gfPatch, gslPlugins.Names[i]);
  end;

  // FormatMessage('Adding to patch: %s', [Name(e)]);
  AddRequiredElementMasters(e, gfPatch, false);
  r := ContainingMainRecord(e);

  if not Equals(r, e) then
  begin
    AddRequiredElementMasters(r, gfPatch, false);
    wbCopyElementToFile(r, gfPatch, abAsNew, true);
    Result := wbCopyElementToRecord(r, e, true, true);    
  end
  else
  begin
    Result := wbCopyElementToFile(e, gfPatch, abAsNew, true);
  end;
end;

function Initialize: integer;
var
  s: string;
  i: integer;
  f: IwbFile;
  baseRecord, plug: IInterface;
  slPlugin: TStringList;
begin
  gslMappings := TStringList.Create;
  gslPlugins := TStringList.Create;

  if not FilterApplied then begin
    InfoDlg('You need to "Apply filter to show Conflicts" for this script to work properly');
    Result := 1;
    Exit;
  end;

  slPlugin := TStringList.Create;
  
  // Loop across all loaded plugins making a list to select from.
  for i := 0 to Pred(FileCount) do
  begin
    f := FileByIndex(i);
    slPlugin.AddObject(Name(f), f);
  end;

  SelectPlugin(slPlugin);
  if gslPlugins.Count < 2 then
  begin
    FormatMessage('%d selected', [gslPlugins.Count]);
    InfoDlg('You need to select at least two plugins to generate a patch between');
    Result := 1;
    slPlugin.Free;
    Exit;
  end;

  // gfPatch := AddNewFile;
  // if not Assigned(gfPatch) then
  // abort;

  slPlugin.Free;
end;

function Process(e: IInterface): integer;
var
  i, lo1, lo2, ovc: integer;
  f1, f2: IwbFile;
  s: string;
  m, ovr: IInterface;
begin
  if ConflictAllForNode(e) < caOverride then
    Exit;
  
  f1 := GetFile(e);
  lo1 := GetLoadOrder(f1);
  if lo1 = 0 then
    Exit;

  AddToPatch(e, false);
  // m := MasterOrSelf(e);
  // ovc := OverrideCount(m);
  // for i := 0 to Pred(ovc) do begin
  //   ovr := OverrideByIndex(m, i);
  //   f2 := GetFile(ovr);
  //   s := Name(f2);
  //   lo2 := GetLoadOrder(f2);
  //   if lo2 <> 0 then
  //     if lo2 > lo1 then slLose.Add(s) else
  //       if lo2 < lo1 then slWin.Add(s) else
  //         if (lo2 = lo1) and (i < Pred(ovc)) and GetIsDeleted(ovr) then
  //           slWarn.Add('Warning: Deleted record ' + Name(ovr) + ' is overridden by later loaded plugins which can lead to a crash in game!');
  // end;
end;

function Finalize: integer;
begin
  gslMappings.Free;
  gslPlugins.Free;
end;

end.
