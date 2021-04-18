{
  Generate a Conflict Resolution Patch
  Hotkey: Ctrl+Shift+P
}
unit ConflictPatchHelper;

interface

implementation

uses xEditAPI, Classes, SysUtils, StrUtils, CheckLst, Dialogs, Forms, Windows, mteFunctions;

var
  sCurrentPlugin: string;
  gfPatch: IwbFile;
  glFiles: TList;
  gslFileNames, gslPatchPlugins, gslSubrecordMappings: TStringList;

procedure FormatMessage(s: string; args: IInterface);
begin
  AddMessage(Format(s, args));
end;

procedure BuildFileLists();
var
  i: integer;
  f: IwbFile;
begin
  glFiles := TList.Create;
  gslFileNames := TStringList.Create;
  for i := 0 to Pred(FileCount) do
  begin
    f := FileByIndex(i);
    glFiles.Add(TObject(f));
    gslFileNames.Add(Name(f));
  end;
end;

{ Look up a file based upon its name. }
function NameToFile(s: string): IwbFile;
var
  i: integer;
begin
  i := gslFileNames.IndexOf(s);
  if i >= 0 then
    Result := ObjectToElement(glFiles[i]);
end;

procedure AddOnlyPluginFilesToList(var r: IwbMainRecord; lst: TStringList);
var
  i: integer;
  s: string;
begin
  s := Name(GetFile(r));
  i := gslPatchPlugins.IndexOf(s);
  if i >= 0 then
    lst.Add(s);
end;

// ============================================================================
// Select a plugin
function SelectPlugin(var prompt: string; slInput: TStringList): IwbFile;
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
        Result := slInput[i];
        exit;
      end;
  finally
    frm.Free;
  end;
end;

// Select multiple plugins
procedure SelectPlugins(var prompt: string; lst: TStringList; slSelected: TStringList);
var
  frm: TForm;
  clb: TCheckListBox;
  i: integer;
begin
  frm := frmFileSelect;
  try
    frm.Caption := prompt;
    clb := TCheckListBox(frm.FindComponent('CheckListBox1'));
    clb.items.Assign(lst);
    if frm.ShowModal <> mrOk then
      exit;
    for i := 0 to Pred(clb.items.Count) do
      if clb.Checked[i] then
      begin
        slSelected.Add(lst[i]);
      end;
  finally
    frm.Free;
  end;
end;

function SelectPluginForElementType(var r: IwbMainRecord; elementType: string): string;
var
  i, ovc: integer;
  f: IwbFile;
  slCurrentPlugins: TStringList;
  m, ovr: IInterface;
begin
  slCurrentPlugins := TStringList.Create;

  // Build a list of files in slCurrentPlugins that contain this record
  try
    m := MasterOrSelf(r);
    AddOnlyPluginFilesToList(m, slCurrentPlugins);
    ovc := OverrideCount(m);
    for i := 0 to Pred(ovc) do begin
      ovr := OverrideByIndex(m, i);
      AddOnlyPluginFilesToList(ovr, slCurrentPlugins);
    end;

    Result := SelectPlugin(Format('Plugin for "%s"', [elementType]), slCurrentPlugins);
  finally
    slCurrentPlugins.Free;
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

procedure InfoDlg(msg: string);
begin
  MessageDlg(msg, mtInformation, [mbOk], 0);
end;

//-------------------------------------------------------------------------------
// Set Flags - Copied from WiZkiD's Lootable Firewood Piles script
//-------------------------------------------------------------------------------
procedure SetFlag(element: IInterface; index: Integer; state: boolean);
var
  mask: Integer;
begin
  mask := 1 shl index;
  if state then
    SetNativeValue(element, GetNativeValue(element) or mask)
  else
    SetNativeValue(element, GetNativeValue(element) and not mask);
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

    for i := 0 to Pred(gslPatchPlugins.Count) do
      AddMasterIfMissing(gfPatch, GetFileName(NameToFile(gslPatchPlugins[i])));

    // Patch will be an ESL
    SetFlag(ElementByPath(ElementByIndex(gfPatch, 0), 'Record Header\Record Flags'), 9, true);
  end;

  AddRequiredElementMasters(e, gfPatch, false);
  r := ContainingMainRecord(e);

  if not Equals(r, e) then
  begin
    AddRequiredElementMasters(r, gfPatch, false);
    wbCopyElementToFile(r, gfPatch, abAsNew, true);
    Result := wbCopyElementToRecord(r, e, true, true);    
  end
  else
    Result := wbCopyElementToFile(e, gfPatch, abAsNew, true);
end;

function RecordByLoadOrderFormID(f: IwbFile; loadOrderFormID: integer;
                                 allowInjected: boolean): IwbMainRecord;
begin
  try
    Result := RecordByFormID(f, LoadOrderFormIDtoFileFormID(f, loadOrderFormID),
                             allowInjected);
  except
  end;
end;

function RecordInFile(f: IwbFile; loadOrderFormID: integer): IwbMainRecord;
begin
  if ElementType(f) <> etFile then
    abort;
  Result := RecordByLoadOrderFormID(f, loadOrderFormID, false);
  if not Equals(f, GetFile(Result)) then
    Result := nil;
end;

function Initialize: integer;
begin
  gslPatchPlugins := TStringList.Create;
  gslSubrecordMappings := TStringList.Create;

  if not FilterApplied then begin
    InfoDlg('You need to "Apply filter to show Conflicts" for this script to work properly');
    Result := 1;
    exit;
  end;

  // Creates glFiles and gslFileNames
  BuildFileLists;

  SelectPlugins('Select the Plugins to Patch', gslFileNames, gslPatchPlugins);
  if gslPatchPlugins.Count < 2 then
  begin
    InfoDlg('You need to select at least two plugins to generate a patch between');
    Result := 1;
    exit;
  end;
end;

function Process(r: IInterface): integer;
var
  fid: cardinal;
  i: integer;
  f: IwbFile;
  path, t: string;
  e, r1, r2: IInterface;
begin
  if ElementType(r) <> etMainRecord then
  begin
    FormatMessage('%s is not a main record', Name(r));
    exit;
  end;

  if ConflictAllForNode(r) < caOverride then
    exit;

  // Skip records that have already been processed.
  if Assigned(gfPatch) then
  begin
    fid := GetLoadOrderFormID(r);
    if Assigned(RecordInFile(gfPatch, fid)) then
      exit;
  end;

  // Copy the record to the patch
  r1 := AddToPatch(r, false);

  for i := 0 to Pred(ElementCount(r)) do
  begin
    e := ElementByIndex(r, i);
    path := ElementPath(e);

    // The record header and ownership are not editable
    if (path = 'Record Header') or (path = 'Ownership') then
      continue;

    if gslSubrecordMappings.IndexOfName(path) = -1 then
    begin
      t := SelectPluginForElementType(r, path);
      FormatMessage('Using %s for %s', [t, path]);
      gslSubrecordMappings.Values[path] := t;
    end;
    f := NameToFile(gslSubrecordMappings.Values[path]);
    r2 := RecordInFile(f, fid);
    if Assigned(ElementByPath(r2, path)) then
      seev(r1, path, geev(r2, path));
  end;
end;

function Finalize: integer;
begin
  SortMasters(gfPatch);

  glFiles.Free;
  gslFileNames.Free;
  gslPatchPlugins.Free;
  gslSubrecordMappings.Free;
end;

end.
