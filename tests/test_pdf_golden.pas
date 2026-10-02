/// golden file tests: generated PDFs compared with a recorded baseline
// - the baseline is per machine, not versioned: embedded and subset faces come
// from the fonts installed, so the same document differs between systems
// - record it with "test_runner --golden-record" on the commit to compare
// against; without a baseline the cases are skipped
// - compared in the form pdf_inspect.NormalizePdf() gives: decoded, with what
// changes between runs blanked - the /ID, subset tags, dates, and the stream
// lengths and offsets that move with them - after checking that they are right
// - two assertions per case, recorded, skipped or compared: the count does not
// depend on a baseline
unit test_pdf_golden;

interface

{$I mormot.defines.inc}
{$I test_defines.inc}

uses
  Classes,
  SysUtils,
  {$ifdef PDF_HASVCLCANVAS}
  Graphics,             // TCanvas.Font, colors
  mormot.ui.pdfcanvas,  // TPdfDocumentVcl, TPdfVclCanvas
  {$endif PDF_HASVCLCANVAS}
  mormot.core.base,
  mormot.core.os,
  mormot.core.test,
  mormot.core.text,     // FormatUtf8, FormatString
  mormot.core.unicode,  // StringToUtf8
  mormot.pdf.types,     // TPdfStructRole, GetPdfFonts
  mormot.ui.pdf,
  pdf_inspect,          // NormalizePdf, ComparePdfText
  test_pdf_subset;      // DrawUtf8Text

var
  /// set by the runner from --golden-record: write the baseline, compare nothing
  GoldenRecord: boolean;

const
  /// creation and modification date of every golden document
  // - the dates are blanked before comparing anyway; a fixed date keeps the
  // recorded files themselves reproducible where the API allows it
  GOLDEN_DATE = 46000.5;

type
  /// base class of the golden file test cases
  TPdfGoldenTestCase = class(TSynTestCase)
  protected
    /// record or compare Pdf as the golden file Name
    procedure CheckGolden(const Name: RawUtf8; const Pdf: RawByteString);
  end;

  /// golden files of documents drawn through TPdfDocument/TPdfCanvas (layer 1)
  TPdfGoldenTests = class(TPdfGoldenTestCase)
  protected
    function SaveDoc(Doc: TPdfDocument): RawByteString;
  published
    procedure Base14Untagged;
    procedure Base14Compressed;
    procedure TaggedEmbedded;
    procedure PdfA3UAttachment;
    procedure CjkSubset;
    procedure ArabicShaped;
    {$ifdef PDF_HASVCLCANVAS}
    procedure CanvasBridge;
    {$endif PDF_HASVCLCANVAS}
  end;

/// the folder of this machine's baseline, below the executable
function GoldenFolder: TFileName;


implementation

function GoldenFolder: TFileName;
var
  key: RawUtf8;
begin
  key := StringReplaceAll(COMPILER_VERSION, [' 32 bit', '', ' 64 bit', '']);
  key := LowerCase(ShortStringToAnsi7String(OS_NAME[OS_KIND]) + '_' +
    CPU_ARCH_TEXT + '_' + StringReplaceAll(key, ' ', '-'));
  result := Executable.ProgramFilePath + 'golden' + PathDelim +
    Utf8ToString(key) + PathDelim;
end;

{ TPdfGoldenTestCase }

procedure TPdfGoldenTestCase.CheckGolden(const Name: RawUtf8;
  const Pdf: RawByteString);
var
  fn: TFileName;
  expected, actual, err, diff: RawUtf8;
begin
  fn := GoldenFolder + Utf8ToString(Name) + '.pdf';
  // the first assertion: the new file itself - a broken one would also make
  // a baseline every later run fails against
  actual := NormalizePdf(Pdf, err);
  if CheckFailed(err = '', FormatString('%: %', [Name, err])) then
    exit;
  // the second: recorded, skipped or compared - a difference by Check(false),
  // not TestFailed(), so that it counts as an assertion like the others
  if GoldenRecord then
  begin
    EnsureDirectoryExists(GoldenFolder);
    Check(FileFromString(Pdf, fn), 'golden file written');
    AddConsole('recorded %', [fn]);
  end
  else if not FileExists(fn) then
    Check(true, 'SKIP: no golden baseline - run test_runner --golden-record')
  else
  begin
    expected := NormalizePdf(StringFromFile(fn), err);
    if err <> '' then
      Check(false, FormatString('% golden file: %', [Name, err]))
    else if ComparePdfText(expected, actual, diff) then
      Check(true)
    else
    begin
      // keep the new output beside the baseline for a viewer or a diff tool
      FileFromString(Pdf, GoldenFolder + Utf8ToString(Name) + '.actual.pdf');
      Check(false, FormatString('% differs from the golden file (a: golden, ' +
        'b: new)'#10'%', [Name, diff]));
    end;
  end;
end;


{ TPdfGoldenTests }

const
  CJK_TEXT: RawUtf8 = {$ifdef HASCODEPAGE}
    #$4F60#$597D#$FF0C#$4E16#$754C#$FF01 {$else}
    #$E4#$BD#$A0#$E5#$A5#$BD#$EF#$BC#$8C#$E4#$B8#$96#$E7#$95#$8C#$EF#$BC#$81 {$endif};
  ARABIC_TEXT: RawUtf8 = {$ifdef HASCODEPAGE}
    #$0645#$0631#$062D#$0628#$0627' '#$0643#$062A#$0627#$0628 {$else}
    #$D9#$85#$D8#$B1#$D8#$AD#$D8#$A8#$D8#$A7' '#$D9#$83#$D8#$AA#$D8#$A7#$D8#$A8 {$endif};
  UMLAUTS: RawUtf8 = 'Umlauts: ' + {$ifdef HASCODEPAGE}
    #$00E4#$00F6#$00FC#$00C4#$00D6#$00DC#$00DF' '#$20AC {$else}
    #$C3#$A4#$C3#$B6#$C3#$BC#$C3#$84#$C3#$96#$C3#$9C#$C3#$9F' '#$E2#$82#$AC {$endif};
  {$ifdef OSWINDOWS}
  CJK_FONT = 'Microsoft YaHei';
  ARABIC_FONT = 'Tahoma';
  {$else}
  {$ifdef OSDARWIN}
  CJK_FONT = 'Hiragino Sans GB';
  ARABIC_FONT = 'Geeza Pro';
  {$else}
  CJK_FONT = 'Droid Sans Fallback';
  ARABIC_FONT = 'Noto Naskh Arabic';
  {$endif OSDARWIN}
  {$endif OSWINDOWS}
  INVOICE_XML = '<?xml version="1.0" encoding="UTF-8"?>'#10 +
    '<rsm:CrossIndustryInvoice xmlns:rsm="urn:un:unece:uncefact:data:' +
    'standard:CrossIndustryInvoice:100"/>'#10;

function TPdfGoldenTests.SaveDoc(Doc: TPdfDocument): RawByteString;
var
  ms: TMemoryStream;
begin
  ms := TMemoryStream.Create;
  try
    Doc.SaveToStream(ms, GOLDEN_DATE);
    FastSetRawByteString(result, ms.Memory, ms.Size);
  finally
    ms.Free;
  end;
end;

procedure TPdfGoldenTests.Base14Untagged;
var
  doc: TPdfDocument;
  c: TPdfCanvas;
  i: integer;
begin
  doc := TPdfDocument.Create({AUseOutlines=}true);
  try
    doc.Info.CreationDate := GOLDEN_DATE;
    doc.Info.Title := 'Golden base-14';
    doc.CompressionMethod := cmNone;
    doc.StandardFontsReplace := true;
    doc.EmbeddedTTF := false;
    doc.DefaultPaperSize := psA4;
    doc.AddPage;
    c := doc.Canvas;
    c.SetFont('Helvetica', 20, [pfsBold], PDF_DEFAULT_CHARSET);
    c.TextOut(56, 780, 'Base-14 fonts, no embedding');
    doc.CreateOutline('Base-14 fonts', 1, 800);
    c.SetFont('Times New Roman', 12, [pfsItalic], PDF_DEFAULT_CHARSET);
    c.TextOut(56, 750, 'Times italic: The quick brown fox jumps over the lazy dog.');
    c.SetFont('Courier New', 11, [], PDF_DEFAULT_CHARSET);
    c.TextOut(56, 732, 'Courier: function Foo: integer;');
    c.SetRGBStrokeColor($5A2D14);
    c.SetRGBFillColor($E8C8B4);
    c.SetLineWidth(1.5);
    c.Rectangle(56, 600, 120, 80);
    c.FillStroke;
    c.Ellipse(200, 600, 120, 80);
    c.Stroke;
    c.MoveTo(340, 600);
    c.CurveToC(380, 700, 420, 580, 460, 680);
    c.Stroke;
    for i := 0 to 2 do
    begin
      c.SetLineWidth(0.5 + i);
      c.MoveTo(56, 560 - i * 20);
      c.LineTo(539, 560 - i * 20);
      c.Stroke;
    end;
    doc.AddPage;
    doc.Canvas.SetFont('Helvetica', 12, [], PDF_DEFAULT_CHARSET);
    doc.Canvas.TextOut(56, 780, 'Second page');
    doc.CreateOutline('Second page', 1, 800);
    CheckGolden('base14_untagged', SaveDoc(doc));
  finally
    doc.Free;
  end;
end;

procedure TPdfGoldenTests.Base14Compressed;
var
  doc: TPdfDocument;
begin
  doc := TPdfDocument.Create;
  try
    doc.Info.CreationDate := GOLDEN_DATE;
    doc.CompressionMethod := cmFlateDecode;
    doc.StandardFontsReplace := true;
    doc.EmbeddedTTF := false;
    doc.AddPage;
    doc.Canvas.SetFont('Helvetica', 12, [], PDF_DEFAULT_CHARSET);
    doc.Canvas.TextOut(56, 780, 'Deflated content stream');
    doc.Canvas.Rectangle(56, 700, 200, 50);
    doc.Canvas.Stroke;
    CheckGolden('base14_flate', SaveDoc(doc));
  finally
    doc.Free;
  end;
end;

procedure TPdfGoldenTests.TaggedEmbedded;
var
  doc: TPdfDocument;
  c: TPdfCanvas;
  sans, serif, mono: string;
  i: integer;
begin
  doc := TPdfDocument.Create({AUseOutlines=}true);
  try
    doc.Info.CreationDate := GOLDEN_DATE;
    doc.CompressionMethod := cmNone;
    doc.Tagged := true;
    doc.DefaultLanguage := 'en';
    doc.Info.Title := 'Golden tagged';
    GetPdfFonts(doc.EmbeddedTTF, sans, serif, mono);
    doc.AddPage;
    c := doc.Canvas;
    c.BeginStructContent(psrH1);
    c.SetFont(StringToUtf8(sans), 20, [pfsBold], PDF_DEFAULT_CHARSET);
    DrawUtf8Text(doc, 56, 780, 'Tagged document');
    c.EndStructContent;
    doc.CreateOutline('Tagged document', 1, 800);
    c.BeginStructContent(psrP);
    c.SetFont(StringToUtf8(serif), 12, [], PDF_DEFAULT_CHARSET);
    DrawUtf8Text(doc, 56, 750, 'A paragraph in the serif face.');
    c.SetFont(StringToUtf8(sans), 12, [], PDF_DEFAULT_CHARSET);
    DrawUtf8Text(doc, 56, 732, UMLAUTS);
    c.SetFont(StringToUtf8(mono), 11, [], PDF_DEFAULT_CHARSET);
    DrawUtf8Text(doc, 56, 714, 'function Foo: integer;');
    c.EndStructContent;
    c.BeginStructContent(psrFigure, 'A rectangle and an ellipse');
    c.Rectangle(56, 600, 120, 80);
    c.Stroke;
    c.Ellipse(200, 600, 120, 80);
    c.Stroke;
    c.EndStructContent;
    c.BeginStructContent(psrTable);
    c.BeginStructContent(psrTHead);
    c.BeginStructContent(psrTR);
    c.SetFont(StringToUtf8(sans), 11, [pfsBold], PDF_DEFAULT_CHARSET);
    for i := 0 to 1 do
    begin
      c.BeginStructContent(psrTH);
      DrawUtf8Text(doc, 56 + i * 150, 560, FormatUtf8('Head %', [i]));
      c.EndStructContent;
    end;
    c.EndStructContent; // TR
    c.EndStructContent; // THead
    c.BeginStructContent(psrTBody);
    c.SetFont(StringToUtf8(sans), 11, [], PDF_DEFAULT_CHARSET);
    for i := 1 to 3 do
    begin
      c.BeginStructContent(psrTR);
      c.BeginStructContent(psrTD);
      DrawUtf8Text(doc, 56, 560 - i * 18, FormatUtf8('Row %', [i]));
      c.EndStructContent;
      c.BeginStructContent(psrTD);
      DrawUtf8Text(doc, 206, 560 - i * 18, FormatUtf8('%', [i * 10]));
      c.EndStructContent;
      c.EndStructContent; // TR
    end;
    c.EndStructContent; // TBody
    c.BeginStructContent(psrTFoot);
    c.BeginStructContent(psrTR);
    c.BeginStructContent(psrTD);
    DrawUtf8Text(doc, 56, 470, 'Total');
    c.EndStructContent;
    c.BeginStructContent(psrTD);
    DrawUtf8Text(doc, 206, 470, '60');
    c.EndStructContent;
    c.EndStructContent; // TR
    c.EndStructContent; // TFoot
    c.EndStructContent; // Table
    c.BeginArtifact;
    c.SetFont(StringToUtf8(sans), 9, [], PDF_DEFAULT_CHARSET);
    DrawUtf8Text(doc, 56, 40, 'page 1');
    c.EndArtifact;
    CheckGolden('tagged_embedded', SaveDoc(doc));
  finally
    doc.Free;
  end;
end;

procedure TPdfGoldenTests.PdfA3UAttachment;
var
  doc: TPdfDocument;
  sans, serif, mono: string;
begin
  doc := TPdfDocument.Create(false, 0, pdfa3U);
  try
    doc.Info.CreationDate := GOLDEN_DATE;
    doc.CompressionMethod := cmNone;
    doc.Tagged := true;
    doc.DefaultLanguage := 'en';
    doc.Info.Title := 'Golden PDF/A-3U';
    GetPdfFonts(true, sans, serif, mono);
    doc.AddPage;
    doc.Canvas.BeginStructContent(psrP);
    doc.Canvas.SetFont(StringToUtf8(sans), 12, [], PDF_DEFAULT_CHARSET);
    DrawUtf8Text(doc, 56, 780, 'Invoice with its XML attached');
    doc.Canvas.EndStructContent;
    doc.CreateFileAttachmentFrom(INVOICE_XML, 'factur-x.xml',
      'Factur-X invoice data', 'text/xml', GOLDEN_DATE, GOLDEN_DATE, nil,
      afrAlternative);
    doc.PdfAMetadaExtension := PdfMetadataFacturX('EN 16931');
    CheckGolden('pdfa3u_attachment', SaveDoc(doc));
  finally
    doc.Free;
  end;
end;

procedure TPdfGoldenTests.CjkSubset;
var
  doc: TPdfDocument;
begin
  doc := TPdfDocument.Create;
  try
    doc.Info.CreationDate := GOLDEN_DATE;
    doc.CompressionMethod := cmNone;
    doc.EmbeddedTTF := true;
    doc.AddPage;
    doc.Canvas.SetFont(CJK_FONT, 24, [], PDF_DEFAULT_CHARSET);
    DrawUtf8Text(doc, 56, 760, CJK_TEXT);
    CheckGolden('cjk_subset', SaveDoc(doc));
  finally
    doc.Free;
  end;
end;

procedure TPdfGoldenTests.ArabicShaped;
var
  doc: TPdfDocument;
begin
  doc := TPdfDocument.Create;
  try
    doc.Info.CreationDate := GOLDEN_DATE;
    doc.CompressionMethod := cmNone;
    doc.EmbeddedTTF := true;
    doc.AddPage;
    doc.Canvas.SetFont(ARABIC_FONT, 24, [], PDF_DEFAULT_CHARSET);
    DrawUtf8Text(doc, 56, 760, ARABIC_TEXT); // isolated forms, no shaper
    doc.UseUniscribe := true;
    doc.Canvas.RightToLeftText := true;
    DrawUtf8Text(doc, 56, 700, ARABIC_TEXT); // shaped, right to left
    CheckGolden('arabic_shaped', SaveDoc(doc));
  finally
    doc.Free;
  end;
end;

{$ifdef PDF_HASVCLCANVAS}
procedure TPdfGoldenTests.CanvasBridge;
var
  doc: TPdfDocumentVcl;
  c: TPdfVclCanvas;
  ms: TMemoryStream;
  pdf: RawByteString;
begin
  ms := TMemoryStream.Create;
  doc := TPdfDocumentVcl.Create;
  try
    doc.Info.CreationDate := GOLDEN_DATE;
    doc.CompressionMethod := cmNone;
    doc.EmbeddedTTF := false;
    doc.StandardFontsReplace := true;
    doc.AddPage;
    c := doc.VclCanvas;
    c.Font.Name := 'Helvetica';
    c.Font.Size := 18;
    c.Font.Style := [fsBold];
    c.TextOut(40, 40, 'TCanvas bridge');
    c.Font.Size := 11;
    c.Font.Style := [];
    c.Font.Color := clNavy;
    c.TextOut(40, 80, 'Pixels at 96 DPI, Y from the top edge.');
    c.Pen.Color := clRed;
    c.Pen.Width := 2;
    c.Brush.Color := clYellow;
    c.Rectangle(40, 120, 200, 200);
    c.Brush.Color := clAqua;
    c.Ellipse(220, 120, 380, 200);
    c.Pen.Color := clBlack;
    c.Pen.Width := 1;
    c.MoveTo(40, 240);
    c.LineTo(500, 240);
    c.Brush.Color := clSilver;
    c.RoundRect(40, 260, 200, 320, 20, 20);
    doc.SaveToStream(ms, GOLDEN_DATE);
    FastSetRawByteString(pdf, ms.Memory, ms.Size);
    CheckGolden('canvas_bridge', pdf);
  finally
    doc.Free;
    ms.Free;
  end;
end;
{$endif PDF_HASVCLCANVAS}

end.
