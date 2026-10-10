/// golden files of the image and metafile paths of the engine
// - TBitmap in every pixel format, reuse, color key, both JPEG ways and
// TPdfDocumentGdi/RenderMetaFile, as they are before they leave the engine
// for an adapter: the baseline recorded on the commit before the move proves
// the move changed nothing
// - assertions do not depend on the platform; the metafile cases are Windows
// only and count as skips elsewhere
unit test_pdf_images;

interface

{$I mormot.defines.inc}
{$I test_defines.inc}

{$ifdef PDF_HASVCLCANVAS}

uses
  {$ifdef OSWINDOWS}
  Windows,
  {$endif OSWINDOWS}
  Classes,
  SysUtils,
  Types,                // Point, Rect of the canvas, not the engine's
  Graphics,             // TBitmap, TPixelFormat
  {$ifdef OSWINDOWS}
  {$ifdef FPC}
  mormot.ui.core,       // TMetaFile, TMetaFileCanvas for FPC
  {$endif FPC}
  mormot.ui.gdiplus,    // TJpegImage, as the engine uses it on Windows
  {$endif OSWINDOWS}
  mormot.core.base,
  mormot.core.os,
  mormot.core.test,
  mormot.core.text,
  mormot.core.unicode,
  mormot.ui.pdf,
  pdf_inspect,
  test_pdf_golden;

type
  /// images and metafiles through the engine, recorded as golden files
  TPdfImageGoldenTests = class(TPdfGoldenTestCase)
  protected
    function SaveDoc(Doc: TPdfDocument): RawByteString;
  published
    procedure BitmapFormats;
    procedure BitmapReuse;
    procedure BitmapJpeg;
    procedure MetaFileCanvas;
    procedure MetaFileRender;
  end;

{$endif PDF_HASVCLCANVAS}


implementation

{$ifdef PDF_HASVCLCANVAS}

const
  // every row a multiple of four bytes, even at one bit per pixel: the reuse
  // hash reads padded rows, a shorter LCL row would be read past its end
  IMG_W = 32;
  IMG_H = 4;

// the pixel bytes of each row, from Seed - set after the palette, which the
// VCL may apply by remapping the pixels already there
procedure FillBitmap(B: TBitmap; Seed: byte);
var
  x, y, n, W: integer;
  p: PByteArray;
begin
  W := B.Width;
  case B.PixelFormat of
    pf1bit:
      n := W shr 3;
    pf4bit:
      n := W shr 1;
    pf8bit:
      n := W;
    pf24bit:
      n := W * 3;
  else
    n := W * 4;
  end;
  {$ifdef FPC}
  B.BeginUpdate(true);
  {$endif FPC}
  for y := 0 to B.Height - 1 do
  begin
    p := B.ScanLine[y];
    for x := 0 to n - 1 do
      p[x] := byte(Seed + x * 37 + y * 101);
  end;
  {$ifdef FPC}
  B.EndUpdate;
  {$endif FPC}
end;

function NewBitmap(Format: TPixelFormat; Seed: byte; W: integer = IMG_W): TBitmap;
begin
  result := TBitmap.Create;
  result.PixelFormat := Format;
  result.Width := W;
  result.Height := IMG_H;
  FillBitmap(result, Seed);
end;

function CountOf(const Sub, Text: RawUtf8): integer;
var
  i: PtrInt;
begin
  result := 0;
  i := PosEx(Sub, Text);
  while i > 0 do
  begin
    inc(result);
    i := PosEx(Sub, Text, i + length(Sub));
  end;
end;

function Box(L, B, W, H: single): TPdfBox;
begin
  result.Left := L;
  result.Top := B;
  result.Width := W;
  result.Height := H;
end;


{ TPdfImageGoldenTests }

function TPdfImageGoldenTests.SaveDoc(Doc: TPdfDocument): RawByteString;
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

procedure TPdfImageGoldenTests.BitmapFormats;
var
  doc: TPdfDocument;
  bmp: array[0..5] of TBitmap;
  names: array[0..6] of PdfString;
  b, c: TPdfBox;
  pdf: RawByteString;
  txt, err: RawUtf8;
  i, raised: integer;
begin
  raised := 0;
  FillCharFast(bmp, SizeOf(bmp), 0);
  FillCharFast(names, SizeOf(names), 0);
  doc := TPdfDocument.Create;
  try
    doc.Info.CreationDate := GOLDEN_DATE;
    doc.StandardFontsReplace := true;
    doc.AddPage;
    bmp[0] := NewBitmap(pf24bit, 1);
    bmp[1] := NewBitmap(pf32bit, 2);
    bmp[2] := NewBitmap(pf8bit, 3);
    bmp[3] := NewBitmap(pf4bit, 4);
    bmp[4] := NewBitmap(pf1bit, 5);
    // a fixed transparent color: /Mask with the color as its range
    bmp[5] := NewBitmap(pf24bit, 6);
    bmp[5].TransparentColor := $0000FF;
    bmp[5].TransparentMode := tmFixed;
    for i := 0 to 5 do
    begin
      b := Box(40, 700 - i * 60, IMG_W * 4, IMG_H * 8);
      try
        names[i] := doc.CreateOrGetImage(bmp[i], @b);
      except
        // the LCL gives a palette bitmap no 256 palette entries
        on EPdfInvalidValue do
          inc(raised);
      end;
    end;
    // the same pixels again, drawn clipped: one image, two draws
    b := Box(300, 700, IMG_W * 4, IMG_H * 8);
    c := Box(310, 700, IMG_W * 2, IMG_H * 8);
    names[6] := doc.CreateOrGetImage(bmp[0], @b, @c);
    pdf := SaveDoc(doc);
  finally
    doc.Free;
    for i := 0 to 5 do
      bmp[i].Free;
  end;
  Check(names[6] = names[0], 'same bitmap, same image');
  Check((names[0] <> names[1]) and (names[1] <> names[5]), 'one image per bitmap');
  txt := NormalizePdf(pdf, err);
  CheckEqual(err, '');
  {$ifdef FPC}
  CheckEqual(raised, 3, 'pf1bit, pf4bit, pf8bit raise with the LCL');
  CheckEqual(CountOf('/Subtype/Image', txt), 3, 'three images');
  CheckEqual(CountOf('/Indexed', txt), 0, 'no palette image');
  {$else}
  CheckEqual(raised, 0, 'every format embedded with the VCL');
  CheckEqual(CountOf('/Subtype/Image', txt), 6, 'six images');
  CheckEqual(CountOf('/Indexed', txt), 3, 'palette formats stay indexed');
  {$endif FPC}
  CheckEqual(CountOf('/Mask', txt), 1, 'the color key');
  CheckGolden('images_bitmap', pdf);
end;

{$ifndef FPC}
// a 256 entry palette: a gray ramp, or the same ramp reversed
function NewPalette(Reversed: boolean): HPALETTE;
var
  pal: TMaxLogPalette;
  i: integer;
  v: byte;
begin
  pal.palVersion := $300;
  pal.palNumEntries := 256;
  for i := 0 to 255 do
  begin
    v := i;
    if Reversed then
      v := 255 - i;
    pal.palPalEntry[i].peRed := v;
    pal.palPalEntry[i].peGreen := v;
    pal.palPalEntry[i].peBlue := v;
    pal.palPalEntry[i].peFlags := 0;
  end;
  result := CreatePalette(PLogPalette(@pal)^);
end;
{$endif FPC}

// what the reuse hash covers: the palette, and the padding of each row - the
// VCL only, as the LCL has no palette for an indexed bitmap and its rows of a
// width not a multiple of four need not be padded
procedure TPdfImageGoldenTests.BitmapReuse;
var
  {$ifndef FPC}
  doc: TPdfDocument;
  bmp: array[0..4] of TBitmap;
  names: array[0..4] of PdfString;
  {$endif FPC}
  i: integer;
begin
  {$ifdef FPC}
  for i := 1 to 5 do
    Check(true, 'SKIP: the LCL gives indexed bitmaps no palette');
  {$else}
  FillCharFast(bmp, SizeOf(bmp), 0);
  doc := TPdfDocument.Create;
  try
    doc.AddPage;
    // the same indices: with the same palette, then with the reversed one
    for i := 0 to 2 do
    begin
      bmp[i] := NewBitmap(pf8bit, 0);
      bmp[i].Palette := NewPalette(i = 2);
      FillBitmap(bmp[i], 11);
    end;
    Check(CompareMem(bmp[0].ScanLine[1], bmp[2].ScanLine[1], IMG_W),
      'the same indices under both palettes');
    // a width of 30 pixels: 90 bytes of a row, then 2 of padding
    bmp[3] := NewBitmap(pf24bit, 12, 30);
    bmp[4] := NewBitmap(pf24bit, 12, 30);
    PByteArray(bmp[4].ScanLine[0])[90] := $55;
    for i := 0 to 4 do
      names[i] := doc.CreateOrGetImage(bmp[i]);
  finally
    doc.Free;
    for i := 0 to 4 do
      bmp[i].Free;
  end;
  Check(names[1] = names[0], 'same indices, same palette: one image');
  Check(names[2] <> names[0], 'another palette: another image');
  Check(names[3] <> '', 'padded rows');
  Check(names[4] <> names[3], 'the padding is hashed');
  {$endif FPC}
end;

procedure TPdfImageGoldenTests.BitmapJpeg;
var
  doc: TPdfDocument;
  bmp: TBitmap;
  jpg: TJpegImage;
  ms: TMemoryStream;
  img: TPdfImage;
  b: TPdfBox;
  pdf: RawByteString;
  txt, err: RawUtf8;
begin
  ms := TMemoryStream.Create;
  bmp := NewBitmap(pf24bit, 7);
  doc := TPdfDocument.Create;
  try
    // encoded once, then fed back: the passthrough and the direct way
    jpg := TJpegImage.Create;
    try
      jpg.Assign(bmp);
      jpg.SaveToStream(ms);
    finally
      jpg.Free;
    end;
    doc.Info.CreationDate := GOLDEN_DATE;
    doc.StandardFontsReplace := true;
    doc.AddPage;
    // CreateOrGetImage with ForceJPEGCompression: the bitmap recompressed,
    // with a quality other than TJpegImage's default of 80
    doc.ForceJPEGCompression := 37;
    b := Box(40, 700, IMG_W * 4, IMG_H * 8);
    doc.CreateOrGetImage(bmp, @b);
    // a TJpegImage without ForceJPEGCompression: its bytes as they are
    doc.ForceJPEGCompression := 0;
    ms.Position := 0;
    jpg := TJpegImage.Create;
    try
      jpg.LoadFromStream(ms);
      img := TPdfImage.Create(doc, jpg, false);
    finally
      jpg.Free;
    end;
    doc.RegisterXObject(img, 'JpgPass');
    doc.Canvas.DrawXObject(40, 600, IMG_W * 4, IMG_H * 8, 'JpgPass');
    // CreateJpegDirect: no graphics unit involved
    img := TPdfImage.CreateJpegDirect(doc, ms, false);
    doc.RegisterXObject(img, 'JpgDirect');
    doc.Canvas.DrawXObject(40, 500, IMG_W * 4, IMG_H * 8, 'JpgDirect');
    pdf := SaveDoc(doc);
  finally
    doc.Free;
    bmp.Free;
    ms.Free;
  end;
  txt := NormalizePdf(pdf, err);
  CheckEqual(err, '');
  CheckEqual(CountOf('/DCTDecode', txt), 3, 'three JPEG images');
  CheckGolden('images_jpeg', pdf);
end;

{$ifdef OSWINDOWS}

// drawn the same into a TPdfDocumentGdi page and into a TMetaFile
procedure DrawSample(C: TCanvas);
var
  bmp: TBitmap;
begin
  C.Font.Name := 'Arial';
  C.Font.Size := 14;
  C.Font.Style := [fsBold];
  C.Font.Color := clNavy;
  C.TextOut(40, 30, 'Metafile text');
  C.Font.Style := [];
  C.Font.Size := 10;
  C.TextOut(40, 60, 'Second line, plain');
  C.Pen.Color := clRed;
  C.Pen.Width := 2;
  C.Brush.Color := clYellow;
  C.Rectangle(40, 90, 200, 160);
  C.Brush.Color := clAqua;
  C.Ellipse(220, 90, 380, 160);
  C.Pen.Width := 1;
  C.Pen.Color := clBlack;
  C.Polygon([Types.Point(40, 200), Types.Point(120, 180),
    Types.Point(200, 230)]);
  C.MoveTo(40, 250);
  C.LineTo(380, 250);
  bmp := NewBitmap(pf24bit, 9);
  try
    C.StretchDraw(Types.Rect(40, 270, 168, 302), bmp);
  finally
    bmp.Free;
  end;
end;

procedure TPdfImageGoldenTests.MetaFileCanvas;
var
  doc: TPdfDocumentGdi;
  pdf: RawByteString;
  txt, err: RawUtf8;
begin
  doc := TPdfDocumentGdi.Create(true);
  try
    doc.Info.CreationDate := GOLDEN_DATE;
    doc.EmbeddedTTF := false;
    doc.StandardFontsReplace := true;
    doc.AddPage;
    DrawSample(doc.VclCanvas);
    GdiCommentOutline(doc.VclCanvas.Handle, 'First page', 0);
    GdiCommentBookmark(doc.VclCanvas.Handle, 'page1');
    doc.AddPage;
    DrawSample(doc.VclCanvas);
    GdiCommentLink(doc.VclCanvas.Handle, 'page1',
      {$ifdef FPC}mormot.ui.pdf.{$else}Types.{$endif}Rect(40, 30, 200, 50), false);
    pdf := SaveDoc(doc);
  finally
    doc.Free;
  end;
  txt := NormalizePdf(pdf, err);
  CheckEqual(err, '');
  CheckEqual(CountOf('/Type/Page/', txt) + CountOf('/Type/Page>>', txt), 2,
    'two pages');
  Check(PosEx('/Outlines', txt) > 0, 'the outline comment');
  CheckEqual(CountOf('/Subtype/Image', txt), 1, 'the same bitmap on both pages');
  CheckGolden('emf_canvas', pdf);
end;

procedure TPdfImageGoldenTests.MetaFileRender;
var
  doc: TPdfDocumentGdi;
  mf: TMetaFile;
  mc: TMetaFileCanvas;
  pdf: RawByteString;
  txt, err: RawUtf8;
begin
  mf := TMetaFile.Create;
  doc := TPdfDocumentGdi.Create;
  try
    mf.Width := 400;
    mf.Height := 320;
    mc := TMetaFileCanvas.Create(mf, 0);
    try
      DrawSample(mc);
    finally
      mc.Free;
    end;
    doc.Info.CreationDate := GOLDEN_DATE;
    doc.EmbeddedTTF := false;
    doc.StandardFontsReplace := true;
    // RenderMetaFile into the page, twice - TPdfForm.Create(metafile) is not
    // covered: it raises an access violation (a page without a MediaBox)
    doc.AddPage;
    RenderMetaFile(doc.Canvas, mf, 1, 1, 20, 0);
    doc.AddPage;
    RenderMetaFile(doc.Canvas, mf, 0.5, 0.5, 40, 200);
    pdf := SaveDoc(doc);
  finally
    doc.Free;
    mf.Free;
  end;
  txt := NormalizePdf(pdf, err);
  CheckEqual(err, '');
  CheckEqual(CountOf('/Type/Page/', txt) + CountOf('/Type/Page>>', txt), 2,
    'two pages');
  CheckEqual(CountOf('/Subtype/Image', txt), 1, 'the bitmap, reused');
  CheckGolden('emf_render', pdf);
end;

{$else}

procedure TPdfImageGoldenTests.MetaFileCanvas;
var
  i: integer;
begin
  for i := 1 to 6 do
    Check(true, 'SKIP: metafiles are Windows only');
end;

procedure TPdfImageGoldenTests.MetaFileRender;
var
  i: integer;
begin
  for i := 1 to 5 do
    Check(true, 'SKIP: metafiles are Windows only');
end;

{$endif OSWINDOWS}

{$endif PDF_HASVCLCANVAS}

end.
