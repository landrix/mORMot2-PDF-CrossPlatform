/// Android host of the PDF test suites: an FMX app, since Android starts
// no console program - see test_runner_android_form.pas
program test_runner_android;

uses
  System.StartUpCopy,
  FMX.Forms,
  test_runner_android_form in 'test_runner_android_form.pas';

begin
  Application.Initialize;
  Application.CreateForm(TTestForm, TestForm);
  Application.Run;
end.
