{
  Generate a Conflict Resolution Patch
  Hotkey: Ctrl+Shift+P
  Version 1.0.1 by Renngar
}
unit ConflictPatchHelper;

interface

implementation

uses xEditAPI, Classes, SysUtils, StrUtils, CheckLst, Dialogs, Forms, Windows, mteFunctions;

var
  sCurrentPlugin: string;
  gfPatch: IwbFile;
  gslFiles: TStringList;
  gslSubrecordMappings: TStringList;

procedure FormatMessage(s: string; args: IInterface);
begin
  AddMessage(Format(s, args));
end;

{ Look up a file based upon its index in gslFiles }
function IndexToFile(i: integer): IwbFile;
begin
    Result := ObjectToElement(gslFiles.Objects[i]);
end;

{ Look up a file based upon its name. }
function NameToFile(s: string): IwbFile;
var
  i: integer;
begin
  i := gslFiles.IndexOf(s);
  if i >= 0 then
    Result := IndexToFile(i);
end;

procedure AddOnlyPluginFilesToList(var r: IwbMainRecord; lst: TStringList);
var
  s: string;
begin
  s := Name(GetFile(r));
  if gslFiles.IndexOf(s) >= 0 then
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
procedure SelectPlugins(var prompt: string);
var
  frm: TForm;
  clb: TCheckListBox;
  i: integer;
  files: TStringList;
begin
  files := TStringList.Create;
  frm := frmFileSelect;
  try
    for i := 0 to Pred(FileCount) do
      files.Add(Name(FileByIndex(i)));

    frm.Caption := prompt;
    clb := TCheckListBox(frm.FindComponent('CheckListBox1'));
    clb.items.Assign(files);
    if frm.ShowModal <> mrOk then
      exit;
    for i := 0 to Pred(clb.items.Count) do
      if clb.Checked[i] then
        gslFiles.AddObject(files[i], TObject(FileByIndex(i)));
  finally
    files.Free;
    frm.Free;
  end;
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

    for i := 0 to Pred(gslFiles.Count) do
      AddMasterIfMissing(gfPatch, GetFileName(IndexToFile(i)));

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

{ Is the element a subrecord? }
function IsSubrecord(e: IInterface): boolean;
begin
  Result := (ElementType(e) = etSubRecord) or
            (ElementType(e) = etSubRecordStruct) or
            (ElementType(e) = etSubRecordArray) or
            (ElementType(e) = etSubRecordUnion);
end;

function PatchRecord(r: IInterface): integer;
var
  fid: cardinal;
  i: integer;
  f: IwbFile;
  path, plugin, values: string;
  e, baseRecord, patchRecord, definingRecord, subrecord: IInterface;
begin
  if ElementType(r) <> etMainRecord then
  begin
    FormatMessage('%s is not a main record', Name(r));
    exit;
  end;

  if ConflictAllForNode(r) < caOverride then
    exit;

  fid := GetLoadOrderFormID(r);

  // Skip records that have already been processed.
  if Assigned(gfPatch) then
    if Assigned(RecordInFile(gfPatch, fid)) then
      exit;

  // Loop through the record's subrecords
  for i := 0 to Pred(ElementCount(r)) do
  begin
    e := ElementByIndex(r, i);
    path := ElementPath(e);

    // Only handle subrecord conflicts, not things like Cells
    if not IsSubrecord(e) then
      continue;

    // Skip the record header and ownership. They are not editable.
    if (path = 'Record Header') or (path = 'Ownership') then
      continue;

    // Lookup or prompt for which plugin should define this type of subrecord
    if gslSubrecordMappings.IndexOfName(path) = -1 then
    begin
      plugin := SelectPlugin(Format('Plugin for "%s"', [path]), gslFiles);
      gslSubrecordMappings.Values[path] := plugin;
      FormatMessage('Using %s for %s %s', [plugin, ElementTypeString(e), path]);
    end;

    // Skip subrecords from the first plugin.  They are not overrides
    if gslFiles.IndexOfName(path) = 0 then
      continue;

    // If the defining plugin contains a subrecord, then copy it to the patch
    f := NameToFile(gslSubrecordMappings.Values[path]);
    definingRecord := RecordInFile(f, fid);
    subrecord := ElementByPath(definingRecord, path);
    if Assigned(subrecord) then
    begin
      // Making sure that the base plugin's record has first been copied into the patch
      if not Assigned(patchRecord) then
        patchRecord := AddToPatch(RecordInFile(IndexToFile(0), fid), false);

      // then override that with the defining plugin's subrecord
      wbCopyElementToRecord(subrecord, patchRecord, false, true);
    end;
  end;
end;

procedure GeneratePatch;
var
  i, j: integer;
  f: IwbFile;
begin
  // Loop through all the records in all but the first selected plugin
  // and patch them.  Skip the first one, it cannot override itself.
  for i := 1 to Pred(gslFiles.Count) do
  begin
    f := IndexToFile(i);
    for j := 0 to Pred(RecordCount(f)) do
      PatchRecord(RecordByIndex(f, j));
  end;
end;

function Initialize: integer;
var
  i: integer;
begin
  gslFiles := TStringList.Create;
  gslSubrecordMappings := TStringList.Create;

  if not FilterApplied then begin
    InfoDlg('You need to "Apply filter to show Conflicts" for this script to work properly');
    Result := 1;
    exit
  end;

  SelectPlugins('Select the Plugins to Patch');
  if gslFiles.Count < 2 then
  begin
    InfoDlg('You need to select at least two plugins to generate a patch between');
    Result := 1;
    exit
  end;

  GeneratePatch;
end;

function Finalize: integer;
begin
  if Assigned(gfPatch) then
    SortMasters(gfPatch);

  gslFiles.Free;
  gslSubrecordMappings.Free;
end;

end.
