/// Report Engine Demo — mORMot2 PDF Cross-Platform
// A Lazarus GUI around TGDIPages: WYSIWYG preview, print and tagged PDF export
// from the form in uMainForm.pas; the report itself is built in uReport.pas.
//
// Worth noting:
// - the report is built once and rendered twice, to the preview and to the PDF,
//   because TGDIPages records draw commands instead of painting directly
// - TTableLayout with DrawTableHeader/DrawTableRow/DrawTableFooter produces a
//   real Table > THead|TBody|TFoot structure; the totals line is the TFoot row
// - SetHeader/SetFooter repeat on continuation pages and are tagged as artifacts
// - report_demo --export [<file.pdf>] builds and exports without showing the
//   window; on Linux the LCL still needs a display for it
// - Delphi 7 builds the batch export only, until the VCL form follows
//   (roadmap R-20 step 8)
program report_demo;

{$I mormot.defines.inc}

// the form is LCL-only for now, see above
{$ifdef FPC}
  {$define REPORTDEMO_FORM}
{$endif FPC}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  {$ifdef REPORTDEMO_FORM}
  Interfaces, // LCL
  Forms,
  uMainForm,
  {$endif REPORTDEMO_FORM}
  SysUtils,
  uReport;

{$R *.res}

var
  PdfFile: TFileName;
begin
  {$ifdef REPORTDEMO_FORM}
  RequireDerivedFormResource := True;
  Application.Title:=REPORT_CREATOR;
  Application.Scaled:=True;
  Application.Initialize;
  {$endif REPORTDEMO_FORM}
  // report_demo --export [<file.pdf>]: build and export, then quit
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
  {$ifdef REPORTDEMO_FORM}
  Application.CreateForm(TMainForm, MainForm);
  Application.Run;
  {$else}
  if IsConsole then
    WriteLn('usage: report_demo --export [<file.pdf>]');
  {$endif REPORTDEMO_FORM}
end.
