/// Font subsetting unit tests (ROADMAP R-12)
// - tests IFontSubsetter in isolation, on raw sfnt bytes
// - POSIX only: Windows subsets through CreateFontPackage, not this interface
// - every test skips when libharfbuzz-subset is not installed
unit test_pdf_subset;

interface

{$I mormot.defines.inc}

uses
  Classes,
  SysUtils,
  mormot.core.base,
  mormot.core.os,
  mormot.core.text,
  mormot.core.unicode,
  mormot.core.test,
  mormot.lib.core,
  mormot.pdf.types,
  {$ifndef OSWINDOWS}
  mormot.lib.harfbuzz,
  {$endif OSWINDOWS}
  mormot.ui.pdf;

type
  /// IFontSubsetter test cases
  TPdfSubsetTests = class(TSynTestCase)
  protected
    fFace: RawByteString;
    fFaceName: RawUtf8;
    // load the whole face of a common glyf-based font through the platform
    // backend; false (and a SKIP check) when no subsetter or no font exists
    function PrepareFace: boolean;
    // the same for a CFF-flavoured ('OTTO') face, which not every system has
    function LoadCffFace(out aFace: RawByteString): boolean;
    function SubsetOf(const Unicodes, Glyphs: array of integer;
      out Sub: RawByteString): boolean;
  published
    procedure TestSubsetterRegistered;
    procedure TestSubsetRetainsGids;
    procedure TestSubsetKeepsCmapForUnicodes;
    procedure TestSubsetKeepsNotdef;
    procedure TestSubsetIsSmaller;
    procedure TestSubsetAcceptsCff;
    procedure TestSubsetRejectsGarbage;
  end;

  /// font subsetting through TPdfDocument, on the saved PDF
  TPdfSubsetEngineTests = class(TSynTestCase)
  protected
    // render aText with aFont (regular, and bold if aBold) into an
    // uncompressed PDF; aWhole = EmbeddedWholeTtf
    // - drawn through TPdfCanvas, not the TCanvas bridge, so that the suite
    // runs on Delphi too (R-19): what it checks is the output, not the bridge
    function BuildPdf(const aFont: string; const aText: RawUtf8;
      aWhole, aTagged, aBold: boolean;
      aPdfA: TPdfALevel = pdfaNone): RawByteString;
    function SansFont: string;
  published
    procedure TestSubsetEmbeddedIsSmaller;
    procedure TestSubsetSharedStreamAndTag;
    procedure TestSubsetUnionOfStyles;
    procedure TestSubsetTagIsDeterministic;
    procedure TestSubsetFallbackWithoutSubsetter;
    procedure TestTaggedSubsetKeepsToUnicode;
    procedure TestPdfA1StillWholeFace;
    procedure TestPdfA3Subsets;
    procedure TestShapedGlyphKeys;
  end;

const
  /// the charset TPdfVclCanvas passes to TPdfCanvas.SetFont (LCL default)
  // - DEFAULT_CHARSET: without it, Windows falls back to the document charset
  // (ANSI_CHARSET on a Western system) and exposes only the ANSI part of the
  // cmap - see fonts.md 10
  PDF_DEFAULT_CHARSET = 1;

/// draw UTF-8 bytes held in a string, decoded as TPdfVclCanvas.TextOut does
// - X, Y in PDF points from the bottom-left corner
procedure DrawUtf8Text(PDF: TPdfDocument; X, Y: single; const aText: RawUtf8);
/// number of non-overlapping occurrences of Sub in s
function CountOf(const Sub, s: RawByteString): integer;
/// the bytes of the first /FontFile2 stream of an uncompressed PDF
function FirstFontFile(const Pdf: RawByteString): RawByteString;
/// the first '/ABCDEF+' subset tag of a PDF name, as 'ABCDEF+', or ''
function FirstSubsetTag(const Pdf: RawByteString): RawByteString;

// minimal sfnt readers, shared with the engine-level tests

/// offset and length of an sfnt table, false if absent
function SfntFindTable(const Face: RawByteString; const Tag: RawUtf8;
  out Offset, Len: cardinal): boolean;
/// maxp.numGlyphs of an sfnt face, -1 on error
function SfntNumGlyphs(const Face: RawByteString): integer;
/// byte length of a glyph in the glyf table (0 = empty glyph), -1 on error
function SfntGlyphLength(const Face: RawByteString; Glyph: integer): integer;
/// glyph ID for a BMP code point from the (3,1) format 4 cmap, 0 if unmapped
function SfntCmapLookup(const Face: RawByteString; CodePoint: cardinal): integer;

implementation

function BE16(const s: RawByteString; ofs: cardinal): cardinal;
begin
  result := (ord(s[ofs + 1]) shl 8) or ord(s[ofs + 2]);
end;

function BE32(const s: RawByteString; ofs: cardinal): cardinal;
begin
  result := (BE16(s, ofs) shl 16) or BE16(s, ofs + 2);
end;

function SfntFindTable(const Face: RawByteString; const Tag: RawUtf8;
  out Offset, Len: cardinal): boolean;
var
  i, n, rec: cardinal;
begin
  result := false;
  if length(Face) < 12 then
    exit;
  n := BE16(Face, 4);
  for i := 0 to n - 1 do
  begin
    rec := 12 + i * 16;
    if rec + 16 > cardinal(length(Face)) then
      exit;
    if copy(Face, rec + 1, 4) = Tag then
    begin
      Offset := BE32(Face, rec + 8);
      Len := BE32(Face, rec + 12);
      result := Offset + Len <= cardinal(length(Face));
      exit;
    end;
  end;
end;

function SfntNumGlyphs(const Face: RawByteString): integer;
var
  ofs, len: cardinal;
begin
  if SfntFindTable(Face, 'maxp', ofs, len) then
    result := BE16(Face, ofs + 4)
  else
    result := -1;
end;

function SfntGlyphLength(const Face: RawByteString; Glyph: integer): integer;
var
  hofs, hlen, lofs, llen: cardinal;
begin
  result := -1;
  if not SfntFindTable(Face, 'head', hofs, hlen) or
     not SfntFindTable(Face, 'loca', lofs, llen) then
    exit;
  if (Glyph < 0) or
     (Glyph >= SfntNumGlyphs(Face)) then
    exit;
  if BE16(Face, hofs + 50) = 0 then // indexToLocFormat: short offsets
    result := integer(BE16(Face, lofs + cardinal(Glyph + 1) * 2) -
                      BE16(Face, lofs + cardinal(Glyph) * 2)) * 2
  else
    result := integer(BE32(Face, lofs + cardinal(Glyph + 1) * 4) -
                      BE32(Face, lofs + cardinal(Glyph) * 4));
end;

function SfntCmapLookup(const Face: RawByteString; CodePoint: cardinal): integer;
var
  cofs, clen, n, i, sub, segX2, s, e, delta, range, p: cardinal;
begin
  result := 0;
  if not SfntFindTable(Face, 'cmap', cofs, clen) then
    exit;
  n := BE16(Face, cofs + 2);
  sub := 0;
  for i := 0 to n - 1 do
    if (BE16(Face, cofs + 4 + i * 8) = 3) and
       (BE16(Face, cofs + 6 + i * 8) = 1) then
    begin
      sub := cofs + BE32(Face, cofs + 8 + i * 8);
      break;
    end;
  if (sub = 0) or
     (BE16(Face, sub) <> 4) then
    exit;
  segX2 := BE16(Face, sub + 6);
  for i := 0 to segX2 shr 1 - 1 do
  begin
    e := BE16(Face, sub + 14 + i * 2);
    if e < CodePoint then
      continue;
    s := BE16(Face, sub + 16 + segX2 + i * 2);
    if s > CodePoint then
      exit;
    delta := BE16(Face, sub + 16 + segX2 * 2 + i * 2);
    p := sub + 16 + segX2 * 3 + i * 2; // address of idRangeOffset[i]
    range := BE16(Face, p);
    if range = 0 then
      result := (CodePoint + delta) and $ffff
    else
    begin
      result := BE16(Face, p + range + (CodePoint - s) * 2);
      if result <> 0 then
        result := (cardinal(result) + delta) and $ffff;
    end;
    exit;
  end;
end;


function CountOf(const Sub, s: RawByteString): integer;
var
  p: PtrInt;
begin
  result := 0;
  p := PosEx(Sub, s, 1);
  while p > 0 do
  begin
    inc(result);
    p := PosEx(Sub, s, p + length(Sub));
  end;
end;

function FirstFontFile(const Pdf: RawByteString): RawByteString;
var
  p, q, len: PtrInt;
begin
  result := '';
  p := Pos(RawByteString('/Length1 '), Pdf);
  if p = 0 then
    exit;
  inc(p, 9);
  len := 0;
  while Pdf[p] in ['0'..'9'] do
  begin
    len := len * 10 + ord(Pdf[p]) - 48;
    inc(p);
  end;
  q := PosEx(RawByteString(#10'stream'#10), Pdf, p);
  if q > 0 then
    result := copy(Pdf, q + 8, len);
end;


function FirstSubsetTag(const Pdf: RawByteString): RawByteString;
var
  p, i: PtrInt;
  ok: boolean;
begin
  result := '';
  p := PosEx('+', Pdf, 8);
  while p > 0 do
  begin
    ok := Pdf[p - 7] = '/';
    for i := p - 6 to p - 1 do
      ok := ok and (Pdf[i] in ['A'..'Z']);
    if ok then
    begin
      result := copy(Pdf, p - 6, 7);
      exit;
    end;
    p := PosEx('+', Pdf, p + 1);
  end;
end;


{ an empty request - Default() does not exist in Delphi 7 }
procedure ClearRequest(out req: TFontSubsetRequest);
begin
  req.Unicodes := nil;
  req.Glyphs := nil;
end;

{ TPdfSubsetTests }

function TPdfSubsetTests.PrepareFace: boolean;
const
  FONTS: array[0..3] of RawUtf8 = (
    'Liberation Sans', 'Arial', 'DejaVu Sans', 'Verdana');
var
  dc: TFontDC;
  lf: TFontRequest;
  font, prev: TFontHandle;
  size: cardinal;
  f: PtrInt;
begin
  result := false;
  if FontSubsetter = nil then
  begin
    Check(true, 'SKIP: no IFontSubsetter registered (libharfbuzz-subset absent)');
    exit;
  end;
  if fFace <> '' then
  begin
    result := true;
    exit;
  end;
  dc := FontDC.CreateDC;
  try
    for f := 0 to high(FONTS) do
    begin
      FillChar(lf, SizeOf(lf), 0);
      lf.FaceName := SynUnicode(FONTS[f]);
      lf.Height := -1000;
      lf.Weight := 400;
      font := FontProvider.CreateFont(lf);
      if font = nil then
        continue;
      prev := FontProvider.SelectFont(dc, font);
      size := FontProvider.GetFontData(dc, 0, 0, nil, 0);
      if size <> FontProvider.FontDataError then
      begin
        SetLength(fFace, size);
        if FontProvider.GetFontData(dc, 0, 0, pointer(fFace), size) <> size then
          fFace := '';
      end;
      FontProvider.SelectFont(dc, prev);
      FontProvider.DeleteFont(font);
      if (fFace <> '') and
         (copy(fFace, 1, 4) = #0#1#0#0) and
         (SfntCmapLookup(fFace, ord('A')) <> 0) then
      begin
        fFaceName := FONTS[f];
        break;
      end;
      fFace := '';
    end;
  finally
    FontDC.DeleteDC(dc);
  end;
  result := fFace <> '';
  if not result then
    Check(true, 'SKIP: no glyf-based test font found on this system');
end;

function TPdfSubsetTests.LoadCffFace(out aFace: RawByteString): boolean;
const
  // CFF system faces: macOS ships its CJK families as OpenType/CFF
  CFF_FONTS: array[0..2] of RawUtf8 = (
    'Hiragino Sans GB', 'Hiragino Mincho ProN', 'Source Han Sans');
var
  dc: TFontDC;
  lf: TFontRequest;
  font, prev: TFontHandle;
  size: cardinal;
  f: PtrInt;
begin
  aFace := '';
  dc := FontDC.CreateDC;
  try
    for f := 0 to high(CFF_FONTS) do
    begin
      FillChar(lf, SizeOf(lf), 0);
      lf.FaceName := SynUnicode(CFF_FONTS[f]);
      lf.Height := -1000;
      lf.Weight := 400;
      font := FontProvider.CreateFont(lf);
      if font = nil then
        continue;
      prev := FontProvider.SelectFont(dc, font);
      size := FontProvider.GetFontData(dc, 0, 0, nil, 0);
      if size <> FontProvider.FontDataError then
      begin
        SetLength(aFace, size);
        if FontProvider.GetFontData(dc, 0, 0, pointer(aFace), size) <> size then
          aFace := '';
      end;
      FontProvider.SelectFont(dc, prev);
      FontProvider.DeleteFont(font);
      if copy(aFace, 1, 4) = 'OTTO' then
        break;
      aFace := '';
    end;
  finally
    FontDC.DeleteDC(dc);
  end;
  result := aFace <> '';
  if not result then
    Check(true, 'SKIP: no CFF face installed on this system');
end;

function TPdfSubsetTests.SubsetOf(const Unicodes, Glyphs: array of integer;
  out Sub: RawByteString): boolean;
var
  req: TFontSubsetRequest;
  i: PtrInt;
begin
  SetLength(req.Unicodes, length(Unicodes));
  for i := 0 to high(Unicodes) do
    req.Unicodes[i] := Unicodes[i];
  SetLength(req.Glyphs, length(Glyphs));
  for i := 0 to high(Glyphs) do
    req.Glyphs[i] := Glyphs[i];
  result := FontSubsetter.Subset(fFace, req, nil, Sub);
end;

procedure TPdfSubsetTests.TestSubsetterRegistered;
begin
  {$ifdef OSWINDOWS}
  Check(FontSubsetter = nil, 'Windows subsets via CreateFontPackage');
  {$else}
  if LoadHarfBuzzSubset then
    Check(FontSubsetter <> nil, 'libharfbuzz-subset loaded but not registered')
  else
    Check(true, 'SKIP: libharfbuzz-subset not installed');
  {$endif OSWINDOWS}
end;

procedure TPdfSubsetTests.TestSubsetRetainsGids;
var
  sub: RawByteString;
  ga, gb: integer;
begin
  if not PrepareFace then
    exit;
  ga := SfntCmapLookup(fFace, ord('A'));
  gb := SfntCmapLookup(fFace, ord('B'));
  Check((ga > 0) and (gb > 0) and (ga <> gb), fFaceName + ': no A/B glyphs');
  Check(SubsetOf([ord('A')], [], sub), 'Subset failed');
  // retain-gids keeps every ID up to the highest one kept: glyphs after it are
  // cut off, so numGlyphs shrinks but never below the retained IDs
  Check(SfntNumGlyphs(sub) > ga, 'A beyond numGlyphs: glyph IDs renumbered');
  Check(SfntNumGlyphs(sub) <= SfntNumGlyphs(fFace), 'numGlyphs grew');
  CheckEqual(SfntCmapLookup(sub, ord('A')), ga, 'A moved to another glyph ID');
  Check(SfntGlyphLength(sub, ga) > 0, 'A lost its outline');
  Check(SfntGlyphLength(sub, gb) <= 0, 'B was not requested but kept');
end;

procedure TPdfSubsetTests.TestSubsetKeepsCmapForUnicodes;
var
  sub: RawByteString;
  ga, gb: integer;
begin
  if not PrepareFace then
    exit;
  ga := SfntCmapLookup(fFace, ord('A'));
  gb := SfntCmapLookup(fFace, ord('B'));
  // A by code point (WinAnsi instance), B by glyph ID only (CID instance) -
  // hb-subset may add a cmap entry for B too, which is harmless
  Check(SubsetOf([ord('A')], [gb], sub), 'Subset failed');
  CheckEqual(SfntCmapLookup(sub, ord('A')), ga, 'cmap entry for A dropped');
  Check(SfntGlyphLength(sub, gb) > 0, 'glyph of B dropped');
end;

procedure TPdfSubsetTests.TestSubsetKeepsNotdef;
var
  sub: RawByteString;
begin
  if not PrepareFace then
    exit;
  Check(SubsetOf([ord('A')], [], sub), 'Subset failed');
  Check(SfntGlyphLength(sub, 0) > 0, '.notdef lost its outline');
end;

procedure TPdfSubsetTests.TestSubsetIsSmaller;
var
  sub: RawByteString;
begin
  if not PrepareFace then
    exit;
  Check(SubsetOf([ord('H'), ord('e'), ord('l'), ord('o'), ord(' '),
    ord('W'), ord('r'), ord('d'), ord('!')], [], sub), 'Subset failed');
  Check(length(sub) * 10 < length(fFace), FormatUtf8('% subset is % of % bytes',
    [fFaceName, length(sub), length(fFace)]));
end;

procedure TPdfSubsetTests.TestSubsetAcceptsCff;
var
  face, sub: RawByteString;
  req: TFontSubsetRequest;
begin
  if FontSubsetter = nil then
  begin
    Check(true, 'SKIP: no IFontSubsetter registered');
    exit;
  end;
  // a malformed OTTO header is still refused, like any other garbage
  ClearRequest(req);
  Check(not FontSubsetter.Subset('OTTO' + StringOfChar(#0, 60), req, nil, sub),
    'a truncated CFF face must not be subset');
  CheckEqual(sub, '', 'no output expected');
  // a real CFF face is subset like any other: it goes to /FontFile3 with
  // /Subtype /OpenType, which the engine picks through PdfFontFileKey()
  if not LoadCffFace(face) then
    exit;
  ClearRequest(req);
  SetLength(req.Glyphs, 2);
  req.Glyphs[0] := 1;
  req.Glyphs[1] := 2;
  Check(FontSubsetter.Subset(face, req, nil, sub), 'a CFF face must be subset');
  Check(sub <> '', 'subset output expected');
  CheckEqual(copy(sub, 1, 4), 'OTTO', 'a CFF subset stays CFF');
  Check(length(sub) < length(face) div 2, 'the subset must be much smaller');
end;

procedure TPdfSubsetTests.TestSubsetRejectsGarbage;
var
  sub, junk: RawByteString;
  req: TFontSubsetRequest;
  i: PtrInt;
begin
  if FontSubsetter = nil then
  begin
    Check(true, 'SKIP: no IFontSubsetter registered');
    exit;
  end;
  SetLength(junk, 4096);
  for i := 1 to length(junk) do
    junk[i] := AnsiChar(Random32 and 255);
  PCardinal(junk)^ := $00000100; // looks like a TrueType sfnt header
  ClearRequest(req);
  SetLength(req.Unicodes, 1);
  req.Unicodes[0] := ord('A');
  // must not crash; whatever comes back, it must not claim to hold glyph A
  if FontSubsetter.Subset(junk, req, nil, sub) then
    Check(SfntGlyphLength(sub, 1) <= 0, 'garbage produced a glyph')
  else
    CheckEqual(sub, '', 'failure must not return data');
end;


{ TPdfSubsetEngineTests }

function TPdfSubsetEngineTests.SansFont: string;
var
  serif, mono: string;
begin
  GetPdfFonts(true, result, serif, mono);
end;

procedure DrawUtf8Text(PDF: TPdfDocument; X, Y: single; const aText: RawUtf8);
var
  W: SynUnicode;
begin
  W := Utf8ToSynUnicode(aText);
  PDF.Canvas.TextOutW(X, Y, pointer(W));
end;

function TPdfSubsetEngineTests.BuildPdf(const aFont: string;
  const aText: RawUtf8; aWhole, aTagged, aBold: boolean;
  aPdfA: TPdfALevel): RawByteString;
var
  PDF: TPdfDocument;
  Stream: TMemoryStream;
begin
  Stream := TMemoryStream.Create;
  try
    PDF := TPdfDocument.Create(false, 0, aPdfA);
    try
      PDF.CompressionMethod := cmNone; // keep the font file readable
      if aTagged then
        PDF.Tagged := true
      else
      begin
        PDF.EmbeddedTTF := true;
        PDF.EmbeddedWholeTtf := aWhole;
      end;
      PDF.AddPage;
      if aTagged then
        PDF.Canvas.BeginStructContent(psrP);
      PDF.Canvas.SetFont(StringToUtf8(aFont), 12, [], PDF_DEFAULT_CHARSET);
      DrawUtf8Text(PDF, 15, 800, aText);
      if aBold then
      begin
        PDF.Canvas.SetFont(StringToUtf8(aFont), 12, [pfsBold], PDF_DEFAULT_CHARSET);
        DrawUtf8Text(PDF, 15, 770, aText + '!');
      end;
      if aTagged then
        PDF.Canvas.EndStructContent;
      PDF.SaveToStream(Stream);
    finally
      PDF.Free;
    end;
    SetLength(result, Stream.Size);
    Stream.Position := 0;
    Stream.Read(pointer(result)^, Stream.Size);
  finally
    Stream.Free;
  end;
end;

procedure TPdfSubsetEngineTests.TestSubsetEmbeddedIsSmaller;
var
  whole, sub: RawByteString;
begin
  if FontSubsetter = nil then
  begin
    Check(true, 'SKIP: no IFontSubsetter registered');
    exit;
  end;
  whole := BuildPdf(SansFont, 'Hello World', true, false, false);
  sub := BuildPdf(SansFont, 'Hello World', false, false, false);
  Check(length(sub) * 4 < length(whole), FormatUtf8('subset PDF % bytes, whole %',
    [length(sub), length(whole)]));
  Check(copy(FirstFontFile(sub), 1, 4) = #0#1#0#0, 'embedded subset is an sfnt');
end;

procedure TPdfSubsetEngineTests.TestSubsetSharedStreamAndTag;
var
  pdf, ttf, tag: RawByteString;
begin
  if FontSubsetter = nil then
  begin
    Check(true, 'SKIP: no IFontSubsetter registered');
    exit;
  end;
  // Latin runs through the WinAnsi instance, Omega through the Type0 one
  pdf := BuildPdf(SansFont,
    'Hello ' + {$ifdef HASCODEPAGE} #$03A9 {$else} #$CE#$A9 {$endif}, false, false, false);
  CheckEqual(CountOf('/Length1 ', pdf), 1, 'one font file for both instances');
  CheckEqual(CountOf('/FontFile2 ', pdf), 1, 'one shared /FontDescriptor');
  // TrueType + Type0 /BaseFont, CIDFontType2 /BaseFont, /FontName
  tag := FirstSubsetTag(pdf);
  Check(tag <> '', 'subset tag present');
  CheckEqual(CountOf('/' + tag, pdf), 4,
    'the same tag on all fonts and the descriptor');
  ttf := FirstFontFile(pdf);
  Check(SfntGlyphLength(ttf, SfntCmapLookup(ttf, ord('H'))) > 0, 'H kept');
  Check(SfntGlyphLength(ttf, SfntCmapLookup(ttf, $03A9)) > 0, 'Omega kept');
  CheckEqual(SfntCmapLookup(ttf, ord('Z')), 0, 'Z dropped from the cmap');
end;

procedure TPdfSubsetEngineTests.TestSubsetUnionOfStyles;
const
  ZHONG: RawUtf8 = {$ifdef HASCODEPAGE} #$4E2D {$else} #$E4#$B8#$AD {$endif};
var
  pdf, ttf: RawByteString;
begin
  if FontSubsetter = nil then
  begin
    Check(true, 'SKIP: no IFontSubsetter registered');
    exit;
  end;
  // Droid Sans Fallback has no bold face: Bold resolves to the same file, so
  // the Regular and Bold fonts share one face and must share one subset
  pdf := BuildPdf('Droid Sans Fallback', ZHONG, false, false, true);
  if Pos(RawByteString('DroidSansFallback'), pdf) = 0 then
  begin
    Check(true, 'SKIP: Droid Sans Fallback not installed');
    exit;
  end;
  CheckEqual(CountOf('/Length1 ', pdf), 1, 'Regular and Bold share one file');
  ttf := FirstFontFile(pdf);
  Check(SfntGlyphLength(ttf, SfntCmapLookup(ttf, $4E2D)) > 0, 'CJK glyph kept');
  Check(SfntGlyphLength(ttf, SfntCmapLookup(ttf, ord('!'))) > 0,
    '! drawn only in Bold, yet kept in the shared subset');
end;

procedure TPdfSubsetEngineTests.TestSubsetTagIsDeterministic;
var
  a, b: RawByteString;
begin
  if FontSubsetter = nil then
  begin
    Check(true, 'SKIP: no IFontSubsetter registered');
    exit;
  end;
  a := BuildPdf(SansFont, 'Same input', false, false, false);
  b := BuildPdf(SansFont, 'Same input', false, false, false);
  Check(FirstSubsetTag(a) <> '', 'tag present');
  CheckEqual(FirstSubsetTag(a), FirstSubsetTag(b), 'same input, same tag');
  Check(FirstFontFile(a) = FirstFontFile(b), 'same input, same subset bytes');
end;

procedure TPdfSubsetEngineTests.TestSubsetFallbackWithoutSubsetter;
var
  saved: IFontSubsetter;
  whole, sub: RawByteString;
begin
  saved := FontSubsetter;
  FontSubsetter := nil;
  try
    whole := BuildPdf(SansFont, 'Hello', true, false, false);
    sub := BuildPdf(SansFont, 'Hello', false, false, false);
  finally
    FontSubsetter := saved;
  end;
  {$ifdef OSWINDOWS}
  Check(true, 'Windows subsets through CreateFontPackage, not through this');
  {$else}
  Check(FirstFontFile(sub) = FirstFontFile(whole),
    'without a subsetter the whole face is embedded, as before R-12');
  CheckEqual(FirstSubsetTag(sub), '', 'and no subset tag is written');
  {$endif OSWINDOWS}
end;

procedure TPdfSubsetEngineTests.TestTaggedSubsetKeepsToUnicode;
var
  tagged, whole: RawByteString;
begin
  tagged := BuildPdf(SansFont, 'Hello', false, true, false);
  whole := BuildPdf(SansFont, 'Hello', true, false, false);
  if not PdfCanSubsetRetainingGids then
  begin
    Check(FirstFontFile(tagged) = FirstFontFile(whole),
      'without a retain-GID subsetter Tagged embeds the whole face (P-6)');
    exit;
  end;
  // PDF/UA allows subsets, and retained glyph IDs keep the round-trip
  Check(FirstSubsetTag(tagged) <> '', 'tagged output is subset');
  Check(length(FirstFontFile(tagged)) * 10 < length(FirstFontFile(whole)),
    'and much smaller');
  Check(Pos(RawByteString('/ToUnicode'), tagged) > 0,
    'WinAnsi ToUnicode CMap still written (pdffonts: uni=yes)');
end;

procedure TPdfSubsetEngineTests.TestPdfA1StillWholeFace;
var
  pdfa1, whole: RawByteString;
begin
  // PDF/A-1 would need a /CIDSet for a subset, which is not written
  pdfa1 := BuildPdf(SansFont, 'Hello', false, false, false, pdfa1B);
  whole := BuildPdf(SansFont, 'Hello', true, false, false);
  Check(FirstFontFile(pdfa1) = FirstFontFile(whole),
    'PDF/A-1 embeds the whole face');
  // R-15 gave the Windows CreateFontPackage path the same guard, so this
  // now holds on every platform
  CheckEqual(FirstSubsetTag(pdfa1), '', 'no subset tag');
end;

procedure TPdfSubsetEngineTests.TestPdfA3Subsets;
var
  pdfa3, whole: RawByteString;
begin
  // the /CIDSet guard is PDF/A-1 only: A-2 and A-3 subset like any document
  pdfa3 := BuildPdf(SansFont, 'Hello', false, false, false, pdfa3U);
  whole := BuildPdf(SansFont, 'Hello', true, false, false);
  if not PdfCanSubsetRetainingGids then
  begin
    Check(FirstFontFile(pdfa3) = FirstFontFile(whole),
      'without a retain-GID subsetter PDF/A-3 embeds the whole face');
    exit;
  end;
  Check(FirstSubsetTag(pdfa3) <> '', 'PDF/A-3 output is subset');
  Check(length(FirstFontFile(pdfa3)) * 10 < length(FirstFontFile(whole)),
    'and much smaller');
end;

type
  // reaches the glyph bookkeeping of a font
  TPdfFontTrueTypeAccess = class(TPdfFontTrueType);

procedure TPdfSubsetEngineTests.TestShapedGlyphKeys;
const
  // faces with more than 4096 glyphs, enough of them out of the cmap (CJK
  // faces map almost all of theirs: Microsoft YaHei has no such pair)
  BIG_FONTS: array[0..8] of RawUtf8 = (
    'Segoe UI', 'Yu Gothic', 'Arial', 'DejaVu Sans', 'Noto Sans',
    'Noto Sans CJK JP', 'Hiragino Sans', 'Hiragino Sans GB',
    'Arial Unicode MS');
var
  PDF: TPdfDocument;
  Stream: TMemoryStream;
  fnt, uni: TPdfFontTrueTypeAccess;
  mapped: array of boolean;
  f, g, h, i, k, gid, maxg: integer;
  req: TFontSubsetRequest;
  s: RawByteString;

  procedure Mark(aGlyph: integer);
  begin
    {$ifdef OSWINDOWS}
    fnt.GetAndMarkGlyphAsUsed(aGlyph);
    {$else}
    fnt.GetAndMarkGlyphAsUsedWithWidth(aGlyph, 500);
    {$endif OSWINDOWS}
  end;

  function Unmapped(aGlyph: integer): boolean;
  begin
    result := (aGlyph > 0) and
              (aGlyph <= maxg) and
              not mapped[aGlyph];
  end;

  function Has(const Values: TIntegerDynArray; Value: integer): boolean;
  var
    j: PtrInt;
  begin
    result := true;
    for j := 0 to high(Values) do
      if Values[j] = Value then
        exit;
    result := false;
  end;

begin
  { a glyph without a code point (a shaped one, out of the cmap) was stored
    under the key $E000 + its index mod 4096, among the characters: two such
    glyphs 4096 apart, or such a glyph and a real character of that key,
    overwrote each other in /W, /ToUnicode and the subset keep list }
  Stream := TMemoryStream.Create;
  try
    PDF := TPdfDocument.Create(false, 0, pdfaNone);
    try
      PDF.CompressionMethod := cmNone;
      PDF.EmbeddedTTF := true;
      PDF.AddPage;
      maxg := 0;
      g := 0;
      h := 0;
      for f := 0 to high(BIG_FONTS) do
      begin
        fnt := TPdfFontTrueTypeAccess(PDF.Canvas.SetFont(BIG_FONTS[f], 12, [],
          PDF_DEFAULT_CHARSET));
        if not fnt.InheritsFrom(TPdfFontTrueType) then
          continue;
        fnt := TPdfFontTrueTypeAccess(fnt.WinAnsiFont);
        if fnt.UnicodeFont = nil then
          fnt.CreateAssociatedUnicodeFont;
        uni := TPdfFontTrueTypeAccess(fnt.UnicodeFont);
        // the glyphs the cmap reaches
        maxg := 0;
        for i := 0 to uni.fUsedWideChar.Count - 1 do
          if uni.fUsedWide[i].Glyph > maxg then
            maxg := uni.fUsedWide[i].Glyph;
        mapped := nil;
        SetLength(mapped, maxg + 1);
        for i := 0 to uni.fUsedWideChar.Count - 1 do
          mapped[uni.fUsedWide[i].Glyph] := true;
        // g and g + 4096 out of the cmap, h with other low bits
        g := 1;
        while (g + 4096 <= maxg) and
              not (Unmapped(g) and Unmapped(g + 4096)) do
          inc(g);
        h := g + 1;
        while (h <= maxg) and
              not (Unmapped(h) and
                   ((h and $0FFF) <> (g and $0FFF))) do
          inc(h);
        if (g + 4096 <= maxg) and
           (h <= maxg) then
          break;
      end;
      if (g + 4096 > maxg) or
         (h > maxg) then
      begin
        Check(true, 'SKIP: no font with two glyphs 4096 apart out of the cmap');
        exit;
      end;
      PDF.Canvas.SetPdfFont(uni, 12); // the font goes into the page
      // a real character under the key of g first, then the two glyphs
      k := $E000 or (g and $0FFF);
      i := fnt.FindOrAddUsedWideChar(WideChar(k));
      gid := fnt.fUsedWide[i].Glyph;
      Mark(g);
      Mark(g + 4096);
      Mark(h);
      CheckEqual(fnt.fUsedWide[fnt.fUsedWideChar.IndexOf(k)].Glyph, gid,
        'a real character keeps its glyph after a shaped one of its key');
      // the subset request: every glyph, and no key standing for one
      req.Unicodes := nil;
      req.Glyphs := nil;
      fnt.AddToSubsetRequest(req);
      Check(Has(req.Glyphs, g) and Has(req.Glyphs, g + 4096) and Has(req.Glyphs, h),
        'all shaped glyphs are kept by the subset');
      Check(not Has(req.Unicodes, $E000 or (h and $0FFF)),
        'a shaped glyph adds no code point to the request');
      // and the other order: the shaped glyph h first, then a real character
      k := $E000 or (h and $0FFF);
      i := uni.fUsedWideChar.IndexOf(k);
      if i >= 0 then
        gid := uni.fUsedWide[i].Glyph
      else
        gid := 0;
      i := fnt.FindOrAddUsedWideChar(WideChar(k));
      CheckEqual(fnt.fUsedWide[i].Glyph, gid,
        'a real character after a shaped one of its key gets its own glyph');
      PDF.SaveToStream(Stream);
    finally
      PDF.Free;
    end;
    SetLength(s, Stream.Size);
    Stream.Position := 0;
    Stream.Read(pointer(s)^, Stream.Size);
  finally
    Stream.Free;
  end;
  // both glyphs reach /W and /ToUnicode
  Check(Pos(RawByteString(IntToStr(g) + '['), s) > 0, '/W lists the first glyph');
  Check(Pos(RawByteString(IntToStr(g + 4096) + '['), s) > 0,
    '/W lists the glyph 4096 further');
  Check(Pos(RawByteString('<' + IntToHex(g + 4096, 4) + '> <'), s) > 0,
    '/ToUnicode lists the glyph 4096 further');
end;

end.
