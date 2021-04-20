program ConflictPatchHelperApp;

uses
  Vcl.Forms,
  xEditAPI in 'xEditAPI.pas',
  mteFunctions in 'mteFunctions.pas',
  ConflictPatchHelper in 'ConflictPatchHelper.pas';

{$R *.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.Run;
end.
