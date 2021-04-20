program ConflictPatchHelperApp;

uses
  Vcl.Forms,
  xEditAPI in 'Edit Scripts\xEditAPI.pas',
  mteFunctions in 'Edit Scripts\mteFunctions.pas',
  ConflictPatchHelper in 'Edit Scripts\Conflict Patch Helper.pas';

{$R *.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.Run;
end.
