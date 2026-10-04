/// mORMot ORM Report Demo - mORMot2 PDF Cross-Platform
// A Lazarus GUI report whose data comes from a live SQLite database through
// the mORMot ORM: data.pas holds the TOrm classes, server.pas the service that
// returns the rows, uReport.pas the TGDIPages rendering, uMainForm.pas the form.
//
// Worth noting:
// - a service method returns a DTO array, so data retrieval and rendering stay
//   separate - the report never touches the ORM
// - the invoice table is a TTableLayout; DrawTableRow paginates and repeats
//   the header row on its own
// - tagged PDF/UA export, switched on before the first drawing command
// - mormot_demo --export [<file.pdf>] builds and exports without showing the
//   window; on Linux the LCL still needs a display for it
// - Delphi 7 builds the batch export only, until the VCL form follows
//   (roadmap R-20 step 8)
program mormot_demo;

{$I mormot.defines.inc}

// the form is LCL-only for now, see above
{$ifdef FPC}
  {$define MORMOTDEMO_FORM}
{$endif FPC}

uses
  // memory manager and cthreads for FPC; on Delphi 7 the file would only add
  // FastMM4, which this project does not depend on
  {$ifdef FPC}
  {$I mormot.uses.inc}
  {$endif FPC}
  {$ifdef MORMOTDEMO_FORM}
  Interfaces,
  Forms,
  uMainForm,
  {$endif MORMOTDEMO_FORM}
  SysUtils,
  uReport;

{$R *.res}

var
  PdfFile: TFileName;
begin
  {$ifdef MORMOTDEMO_FORM}
  RequireDerivedFormResource := True;
  Application.Scaled:=True;
  Application.Initialize;
  {$endif MORMOTDEMO_FORM}
  // mormot_demo --export [<file.pdf>]: build and export, then quit
  if BatchExportFile(PdfFile) then
  begin
    // a batch run must fail with an exit code: an unhandled exception would
    // end in the LCL's modal dialog and wait for a click that never comes
    try
      ExportReport(DefaultReportOptions, PdfFile);
    except
      on E: Exception do
      begin
        // a Windows GUI executable has no stdout: WriteLn raises I/O error 105
        if IsConsole then
          WriteLn(ErrOutput, 'Export failed: ', E.ClassName, ': ', E.Message);
        ExitCode := 1;
        exit;
      end;
    end;
    if IsConsole then
      WriteLn('PDF exported: ', PdfFile);
    exit;
  end;
  {$ifdef MORMOTDEMO_FORM}
  Application.CreateForm(TMainForm, MainForm);
  Application.Run;
  {$else}
  if IsConsole then
    WriteLn('usage: mormot_demo --export [<file.pdf>]');
  {$endif MORMOTDEMO_FORM}
end.
