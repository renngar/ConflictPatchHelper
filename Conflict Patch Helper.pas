{
  Generate a Conflict Resolution Patch
  Hotkey: Ctrl+Shift+P
}
unit ConflictPatchHelper;

interface

implementation

uses xEditAPI, Classes, SysUtils, StrUtils, Windows, mteFunctions;

var
  sCurrentPlugin: string;
  gfPatch: IwbFile;
  gslMappings, gslPlugins, gslSubrecordMappings: TStringList;

// ============================================================================
// Select a plugin
function SelectPlugin(var prompt: string; slInput: TStringList;): string;
var
  frm: TForm;
  clb: TCheckListBox;
  i: integer;
begin
  frm := frmFileSelect;
  try
    frm.Caption := prompt;
    clb := TCheckListBox(frm.FindComponent('CheckListBox1'));
    clb.items.Assign(slInput);
    if frm.ShowModal <> mrOk then
      exit;
    for i := 0 to Pred(clb.items.Count) do
      if clb.Checked[i] then
      begin
        AddMessage('Selected ' + slInput[i]);
        Result := slInput[i];
        exit;
      end;
  finally
    frm.Free;
  end;
end;

// Select multiple plugins
procedure SelectPlugins(var prompt: string; slInput: TStringList; slOutput: TStringList;);
var
  frm: TForm;
  clb: TCheckListBox;
  i: integer;
begin
  frm := frmFileSelect;
  try
    frm.Caption := prompt;
    clb := TCheckListBox(frm.FindComponent('CheckListBox1'));
    clb.items.Assign(slInput);
    if frm.ShowModal <> mrOk then
      exit;
    for i := 0 to Pred(clb.items.Count) do
      if clb.Checked[i] then
      begin
        AddMessage('Selected ' + slInput[i]);
        slOutput.AddObject(slInput[i], slInput.Objects[i]);
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

procedure AddOnlyPluginFilesToList(var r: IwbMainRecord; sl: TStringList);
var
  i: integer;
begin
  i := gslPlugins.IndexOf(Name(GetFile(r)));
  if i >= 0 then
    sl.AddObject(gslPlugins[i], gslPlugins.ValueFromIndex[i]);
end;

function SelectPluginForElementType(var r: IwbMainRecord; elementType: string): string;
var
  i, ovc: integer;
  f: IwbFile;
  slCurrentPlugins: TStringList;
  m, ovr: IInterface;
begin
  slCurrentPlugins := TStringList.Create;

  // Build a list of files in gslPlugins that contain this record
  try
    m := MasterOrSelf(r);
    AddOnlyPluginFilesToList(m, slCurrentPlugins);
    ovc := OverrideCount(m);
    FormatMessage('%d overrides', [ovc]);
    for i := 0 to Pred(ovc) do begin
      ovr := OverrideByIndex(m, i);
      AddOnlyPluginFilesToList(ovr, slCurrentPlugins);
    end;

    // If an element is not overriden, pick from all the plugins, otherwise only
    // the ones that contain it.
    if slCurrentPlugins.Count = 0 then
      Result := SelectPlugin(Format('1 Plugin for "%s"', [elementType]), gslPlugins)
    else
      Result := SelectPlugin(Format('2 Plugin for "%s"', [elementType]), slCurrentPlugins);
  finally
    slCurrentPlugins.Free;
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
  gslSubrecordMappings := TStringList.Create;

  if not FilterApplied then begin
    InfoDlg('You need to "Apply filter to show Conflicts" for this script to work properly');
    Result := 1;
    exit;
  end;

  slPlugin := TStringList.Create;

  // Loop across all loaded plugins making a list to select from.
  for i := 0 to Pred(FileCount) do
  begin
    f := FileByIndex(i);
    slPlugin.AddObject(Name(f), f);
  end;

  SelectPlugins('Select the Plugins to Patch', slPlugin, gslPlugins);
  if gslPlugins.Count < 2 then
  begin
    FormatMessage('%d selected', [gslPlugins.Count]);
    InfoDlg('You need to select at least two plugins to generate a patch between');
    Result := 1;
    slPlugin.Free;
    exit;
  end;

  // GetRecords for each plugin after the first to find possible overwrites

  slPlugin.Free;
end;

function Process(r: IInterface): integer;
var
  i, j, lo1, lo2, n, ovc: integer;
  f1, f2: IwbFile;
  s: string;
  e, m, ovr: IInterface;
  slCurrentPlugins: TStringList;
begin
  if ElementType(r) <> etMainRecord then
  begin
    FormatMessage('%s is not a main record', Name(r));
    exit;
  end;

  if ConflictAllForNode(r) < caOverride then
    exit;

  // // Do nothing with records in the first plugin.  Process them in the
  // // files that may overwrite it.
  // f1 := GetFile(r);
  // if Name(f1) = gslPlugins.Names[0] then
  //   exit;

  // Skip records that have already been processed.
  if Assigned(gfPatch) then
  begin
    n := FormID(r);
    if RecordByFormID(gfPatch, FormID(r)) <> Nil then
      exit;
  end;

  n := ElementCount(r);
  FormatMessage('%s contains %d subrecords:', [Name(r), n]);
  for i := 0 to Pred(n) do
  begin
    e := ElementByIndex(r, i);
    s := Name(e);
    if gslSubrecordMappings.IndexOf(s) = -1 then
       gslSubrecordMappings.AddObject(s, SelectPluginForElementType(r, s));
  end;

  // lo1 := GetLoadOrder(f1);
  // if lo1 = 0 then
  //   exit;

  // AddToPatch(e, false);
end;

function Finalize: integer;
begin
  gslMappings.Free;
  gslPlugins.Free;
  gslSubrecordMappings.Free;
end;

end.
