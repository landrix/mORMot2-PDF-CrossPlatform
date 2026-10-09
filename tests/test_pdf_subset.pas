/// Font subsetting unit tests (ROADMAP R-12)
// - tests IFontSubsetter in isolation, on raw sfnt bytes and the font handle
// they were read from: hb-subset on Linux/macOS, FontSub (CreateFontPackage)
// on Windows
// - every test skips when no subsetter is registered (libharfbuzz-subset
// missing, or NO_USE_UNISCRIBE)
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
  {$ifdef OSWINDOWS}
  mormot.lib.uniscribe,
  {$else}
  mormot.lib.harfbuzz,
  {$endif OSWINDOWS}
  mormot.ui.pdf;

type
  /// IFontSubsetter test cases
  TPdfSubsetTests = class(TSynTestCase)
  protected
    fFace: RawByteString;
    fFaceName: RawUtf8;
    // the font fFace was read from: FontSub resolves code points through it
    fFont: TFontHandle;
    // load the whole face of a common glyf-based font through the platform
    // backend; false (and a SKIP check) when no subsetter or no font exists
    function PrepareFace: boolean;
    // the same for a CFF-flavoured ('OTTO') face, which not every system has
    // - the caller deletes aFont
    function LoadCffFace(out aFace: RawByteString; out aFont: TFontHandle): boolean;
    function SubsetOf(const Unicodes, Glyphs: array of integer;
      out Sub: RawByteString): boolean;
  public
    destructor Destroy; override;
  published
    procedure TestSubsetterRegistered;
    procedure TestSubsetRetainsGids;
    procedure TestSubsetKeepsCmapForUnicodes;
    procedure TestSubsetKeepsNotdef;
    procedure TestSubsetIsSmaller;
    procedure TestSubsetAcceptsCff;
    procedure TestSubsetRejectsGarbage;
    procedure TestTtcFaceIndex;
  end;

  /// font subsetting through TPdfDocument, on the saved PDF
  TPdfSubsetEngineTests = class(TSynTestCase)
  protected
    // render aText with aFont (regular, and bold if aBold) into an
    // uncompressed PDF; aWhole = EmbeddedWholeTtf
    // - drawn through TPdfCanvas, not the TCanvas bridge, so that the suite
    // runs on Delphi too (R-19): what it checks is the output, not the bridge
    // - aCharSet as TPdfCanvas.SetFont takes it: 1 = DEFAULT_CHARSET,
    // 2 = SYMBOL_CHARSET
    function BuildPdf(const aFont: string; const aText: RawUtf8;
      aWhole, aTagged, aBold: boolean;
      aPdfA: TPdfALevel = pdfaNone; aCharSet: integer = 1): RawByteString;
    function SansFont: string;
    // check the font file of every installed .ttc face of a list against the
    // face the platform selects: cmap and hhea
    procedure CheckTtcFaces(aWholeTtf: boolean; aPdfA: TPdfALevel;
      aSubset: boolean; const aWhat: string);
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
    procedure TestSubsetTtcFace;
    procedure TestWholeTtcFace;
    procedure TestSubsetSymbolFont;
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
/// glyph ID for a BMP code point from the (3,1) format 4 cmap, or the (3,0)
// one of a symbol font, 0 if unmapped
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
    if BE16(Face, cofs + 4 + i * 8) = 3 then
      case BE16(Face, cofs + 6 + i * 8) of
        1:
          begin
            sub := cofs + BE32(Face, cofs + 8 + i * 8);
            break;
          end;
        0:
          // a symbol font: its codes are U+F0xx
          sub := cofs + BE32(Face, cofs + 8 + i * 8);
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
      if (fFace <> '') and
         (copy(fFace, 1, 4) = #0#1#0#0) and
         (SfntCmapLookup(fFace, ord('A')) <> 0) then
      begin
        fFaceName := FONTS[f];
        fFont := font; // kept for the subsetter, deleted in Destroy
        break;
      end;
      FontProvider.DeleteFont(font);
      fFace := '';
    end;
  finally
    FontDC.DeleteDC(dc);
  end;
  result := fFace <> '';
  if not result then
    Check(true, 'SKIP: no glyf-based test font found on this system');
end;

destructor TPdfSubsetTests.Destroy;
begin
  if fFont <> nil then
    FontProvider.DeleteFont(fFont);
  inherited Destroy;
end;

function TPdfSubsetTests.LoadCffFace(out aFace: RawByteString;
  out aFont: TFontHandle): boolean;
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
  aFont := nil;
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
      if copy(aFace, 1, 4) = 'OTTO' then
      begin
        aFont := font;
        break;
      end;
      FontProvider.DeleteFont(font);
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
  result := FontSubsetter.Subset(fFace, req, fFont, Sub);
end;

procedure TPdfSubsetTests.TestSubsetterRegistered;
begin
  {$ifdef OSWINDOWS}
  // mormot.lib.uniscribe registers FontSub, unless NO_USE_UNISCRIBE
  Check(FontSubsetter <> nil, 'FontSub not registered on Windows');
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
  Check((ga > 0) and (gb > 0) and (ga <> gb), Utf8ToString(fFaceName) + ': no A/B glyphs');
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
  Check(length(sub) * 10 < length(fFace), FormatString('% subset is % of % bytes',
    [fFaceName, length(sub), length(fFace)]));
end;

procedure TPdfSubsetTests.TestSubsetAcceptsCff;
var
  face, sub: RawByteString;
  req: TFontSubsetRequest;
  font: TFontHandle;
begin
  if FontSubsetter = nil then
  begin
    Check(true, 'SKIP: no IFontSubsetter registered');
    exit;
  end;
  // a malformed OTTO header is still refused, like any other garbage - with
  // the handle of a real font, so that FontSub gets as far as the bytes
  ClearRequest(req);
  SetLength(req.Unicodes, 1);
  req.Unicodes[0] := ord('A');
  if PrepareFace then
    font := fFont
  else
    font := nil;
  Check(not FontSubsetter.Subset(RawByteString('OTTO' + StringOfChar(#0, 60)), req, font, sub),
    'a truncated CFF face must not be subset');
  CheckEqual(sub, '', 'no output expected');
  // a real CFF face is subset like any other: it goes to /FontFile3 with
  // /Subtype /OpenType, which the engine picks through PdfFontFileKey()
  if not LoadCffFace(face, font) then
    exit;
  try
    ClearRequest(req);
    SetLength(req.Glyphs, 2);
    req.Glyphs[0] := 1;
    req.Glyphs[1] := 2;
    {$ifdef OSWINDOWS}
    // CreateFontPackage takes TrueType outlines only (it returns 1035 for a
    // CFF face): the engine embeds such a face whole
    Check(not FontSubsetter.Subset(face, req, font, sub),
      'FontSub refuses a CFF face');
    CheckEqual(sub, '', 'no output expected');
    {$else}
    Check(FontSubsetter.Subset(face, req, font, sub), 'a CFF face must be subset');
    Check(sub <> '', 'subset output expected');
    CheckEqual(copy(sub, 1, 4), 'OTTO', 'a CFF subset stays CFF');
    Check(length(sub) < length(face) div 2, 'the subset must be much smaller');
    {$endif OSWINDOWS}
  finally
    FontProvider.DeleteFont(font);
  end;
end;

procedure TPdfSubsetTests.TestSubsetRejectsGarbage;
var
  sub, junk: RawByteString;
  req: TFontSubsetRequest;
  i: PtrInt;
  font: TFontHandle;
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
  // the handle of a real font, so that FontSub gets as far as the bytes
  if PrepareFace then
    font := fFont
  else
    font := nil;
  // must not crash; whatever comes back, it must not claim to hold glyph A
  if FontSubsetter.Subset(junk, req, font, sub) then
    Check(SfntGlyphLength(sub, 1) <= 0, 'garbage produced a glyph')
  else
    CheckEqual(sub, '', 'failure must not return data');
  {$ifdef OSWINDOWS}
  // FontSub resolves the code points through the font: it needs the handle
  if font <> nil then
    Check(not FontSubsetter.Subset(fFace, req, nil, sub),
      'FontSub without a font handle');
  {$endif OSWINDOWS}
end;

// big-endian bytes of a 32-bit and a 16-bit value
function BE32Bytes(v: cardinal): RawByteString;
begin
  result := AnsiChar(v shr 24) + AnsiChar((v shr 16) and 255) +
            AnsiChar((v shr 8) and 255) + AnsiChar(v and 255);
end;

function BE16Bytes(v: cardinal): RawByteString;
begin
  result := AnsiChar((v shr 8) and 255) + AnsiChar(v and 255);
end;

// a table directory of one table, told apart by its offset
function OneTableDir(TableOffset: cardinal): RawByteString;
begin
  result := BE32Bytes($00010000) + BE16Bytes(1) + BE16Bytes(16) +
            BE16Bytes(0) + BE16Bytes(0) + 'glyf' + BE32Bytes(0) +
            BE32Bytes(TableOffset) + BE32Bytes(4);
end;

// a .ttc collection of the directories, in this order
function Collection(const Dirs: array of RawByteString): RawByteString;
var
  i, ofs: integer;
  body: RawByteString;
begin
  result := 'ttcf' + BE32Bytes($00010000) + BE32Bytes(length(Dirs));
  ofs := 12 + 4 * length(Dirs);
  body := '';
  for i := 0 to high(Dirs) do
  begin
    result := result + BE32Bytes(ofs + length(body));
    body := body + Dirs[i];
  end;
  result := result + body;
end;

procedure TPdfSubsetTests.TestTtcFaceIndex;
var
  a, b, c: RawByteString;
begin
  { FontSub and GetFaceFile find the face of a .ttc by its table directory
    in the collection header (mormot.lib.core): the family-name list it replaces (GetTtcIndex) is
    wrong for 14 of 30 collections of Windows 11 (MS UI Gothic is face 1,
    not 2) }
  a := OneTableDir(100);
  b := OneTableDir(200);
  c := OneTableDir(300);
  CheckEqual(TtcFaceIndex(Collection([a, b, c]), b + 'tail'), 1, 'second face');
  CheckEqual(TtcFaceIndex(Collection([a, b, c]), a), 0, 'first face');
  CheckEqual(TtcFaceIndex(Collection([a, b, c]), c), 2, 'last face');
  CheckEqual(TtcFaceIndex(Collection([a, b, b]), b), -1,
    'two faces alike: no reliable index');
  CheckEqual(TtcFaceIndex(Collection([a, c]), b), -1, 'face not in it');
  CheckEqual(TtcFaceIndex(OneTableDir(100), a), -1, 'not a collection');
  CheckEqual(TtcFaceIndex(copy(Collection([a, b]), 1, 30), b), -1,
    'truncated collection');
  // a face count whose offset table would overflow 32 bits
  CheckEqual(TtcFaceIndex('ttcf' + BE32Bytes($00010000) + BE32Bytes($40000001) +
    BE32Bytes(16) + a, a), -1, 'oversized face count');
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
  aPdfA: TPdfALevel; aCharSet: integer): RawByteString;
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
      PDF.Canvas.SetFont(StringToUtf8(aFont), 12, [], aCharSet);
      DrawUtf8Text(PDF, 15, 800, aText);
      if aBold then
      begin
        PDF.Canvas.SetFont(StringToUtf8(aFont), 12, [pfsBold], aCharSet);
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
  Check(length(sub) * 4 < length(whole), FormatString('subset PDF % bytes, whole %',
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
  Check(FirstFontFile(sub) = FirstFontFile(whole),
    'without a subsetter the whole face is embedded, as before R-12');
  CheckEqual(FirstSubsetTag(sub), '', 'and no subset tag is written');
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

{ one table of the face the platform selects for a family, regular weight,
  wrapped in an sfnt of its own so that the readers above take it }
function PlatformFontTable(const aFont: RawUtf8; const Tag: RawUtf8): RawByteString;
var
  dc: TFontDC;
  req: TFontRequest;
  font, prev: TFontHandle;
  gdiTag, size: cardinal;
  table: RawByteString;
begin
  result := '';
  FillChar(req, SizeOf(req), 0);
  req.FaceName := Utf8ToSynUnicode(aFont);
  req.Height := -1000;
  req.Weight := 400;
  req.CharSet := PDF_DEFAULT_CHARSET;
  // the tag as GDI reads it: the four characters little-endian
  gdiTag := ord(Tag[1]) or (ord(Tag[2]) shl 8) or
            (ord(Tag[3]) shl 16) or (cardinal(ord(Tag[4])) shl 24);
  dc := FontDC.CreateDC;
  try
    font := FontProvider.CreateFont(req);
    if font = nil then
      exit;
    prev := FontProvider.SelectFont(dc, font);
    size := FontProvider.GetFontData(dc, gdiTag, 0, nil, 0);
    if (size <> FontProvider.FontDataError) and
       (size > 0) then
    begin
      SetLength(table, size);
      if FontProvider.GetFontData(dc, gdiTag, 0, pointer(table), size) = size then
        // sfnt header, one table record at offset 28 (checksum left 0)
        result := BE32Bytes($00010000) + BE16Bytes(1) + BE16Bytes(16) +
          BE32Bytes(0) + Tag + BE32Bytes(0) + BE32Bytes(28) +
          BE32Bytes(size) + table;
    end;
    FontProvider.SelectFont(dc, prev);
    FontProvider.DeleteFont(font);
  finally
    FontDC.DeleteDC(dc);
  end;
end;

procedure TPdfSubsetEngineTests.CheckTtcFaces(aWholeTtf: boolean;
  aPdfA: TPdfALevel; aSubset: boolean; const aWhat: string);
const
  // faces of a .ttc collection: the first four are not face 0 of their file
  // on Windows, and the family-name list used before knew none of them right
  TTC_FONTS: array[0..5] of RawUtf8 = (
    'MS UI Gothic', 'Yu Gothic UI', 'Microsoft YaHei UI',
    'Microsoft JhengHei UI', 'MS Gothic', 'Microsoft YaHei');
  SAMPLE = 'Hello';
var
  dc: TFontDC;
  fonts: TRawUtf8DynArray;
  f, i, g, found: integer;
  name: string;
  pdf, face, cmap, hhea: RawByteString;
  o, l, ho, hl: cardinal;
  same: boolean;
begin
  dc := FontDC.CreateDC;
  try
    fonts := nil;
    FontEnumerator.EnumTrueTypeFonts(dc, fonts);
  finally
    FontDC.DeleteDC(dc);
  end;
  found := 0;
  for f := 0 to high(TTC_FONTS) do
  begin
    if FindRawUtf8(fonts, TTC_FONTS[f]) < 0 then
      continue;
    cmap := PlatformFontTable(TTC_FONTS[f], 'cmap');
    hhea := PlatformFontTable(TTC_FONTS[f], 'hhea');
    inc(found);
    name := Utf8ToString(TTC_FONTS[f]) + ', ' + aWhat;
    if (cmap = '') or
       (hhea = '') then
    begin
      Check(false, name + ': cmap and hhea of the installed face');
      continue;
    end;
    pdf := BuildPdf(Utf8ToString(TTC_FONTS[f]), SAMPLE, aWholeTtf, false, false,
      aPdfA);
    face := FirstFontFile(pdf);
    Check((FirstSubsetTag(pdf) <> '') = aSubset, name + ': subset or whole');
    Check(copy(face, 1, 4) = #0#1#0#0, name + ': one face, not a collection');
    same := true;
    for i := 1 to length(SAMPLE) do
    begin
      // 0 is also what an unreadable cmap gives: never a match
      g := SfntCmapLookup(cmap, ord(SAMPLE[i]));
      same := same and
              (g > 0) and
              (SfntCmapLookup(face, ord(SAMPLE[i])) = g);
    end;
    Check(same, name + ': the font file maps the text as the face does');
    // hhea up to numberOfHMetrics, which a subset may lower
    Check(SfntFindTable(face, 'hhea', o, l) and
          SfntFindTable(hhea, 'hhea', ho, hl) and
          (l >= 34) and (hl >= 34) and
          (copy(face, o + 1, 34) = copy(hhea, ho + 1, 34)),
      name + ': the font file has the hhea of the face');
  end;
  if found = 0 then
    Check(true, 'SKIP: none of the .ttc faces installed');
end;

procedure TPdfSubsetEngineTests.TestSubsetTtcFace;
begin
  { FontSub subsets a face of a .ttc from the whole collection, at the index
    TtcFaceIndex finds from the bytes: before W2 the index came from a list
    of family names, and MS UI Gothic was subset from MS PGothic
    - the subset has no name table left (ReduceTtf): the faces of these
    collections share their glyphs, and differ in cmap (MS UI Gothic maps
    'H' to another glyph than MS PGothic) or hhea (the UI faces) }
  if not PdfCanSubsetRetainingGids then
  begin
    Check(true, 'SKIP: no subsetter keeping glyph IDs');
    exit;
  end;
  CheckTtcFaces(false, pdfaNone, true, 'subset');
end;

procedure TPdfSubsetEngineTests.TestWholeTtcFace;
var
  saved: IFontSubsetter;
begin
  { a face of a .ttc embedded whole is extracted from its collection
    (FontProvider.GetFaceFile): Windows used to write the whole collection
    to /FontFile2, which is no font program - with EmbeddedWholeTtf, for
    PDF/A-1 and without a subsetter }
  CheckTtcFaces(true, pdfaNone, false, 'EmbeddedWholeTtf');
  CheckTtcFaces(false, pdfa1B, false, 'PDF/A-1b');
  saved := FontSubsetter;
  FontSubsetter := nil;
  try
    CheckTtcFaces(false, pdfaNone, false, 'no subsetter');
  finally
    FontSubsetter := saved;
  end;
end;

procedure TPdfSubsetEngineTests.TestSubsetSymbolFont;
const
  SYMBOL_FONTS: array[0..2] of RawUtf8 = ('Wingdings', 'Webdings', 'Symbol');
  SAMPLE = 'abc';
var
  dc: TFontDC;
  fonts: TRawUtf8DynArray;
  f, i, g: integer;
  name: string;
  whole, sub: RawByteString;
  kept: boolean;
begin
  { a symbol font reaches its glyphs through a (3,0) cmap at U+F0xx: FontSub
    resolves them through the font and subsets it (SupportsSymbolic), the
    hb-subset path embeds it whole }
  if FontSubsetter = nil then
  begin
    Check(true, 'SKIP: no IFontSubsetter registered');
    exit;
  end;
  {$ifdef OSWINDOWS}
  Check(FontSubsetter.SupportsSymbolic, 'FontSub keeps the glyphs of a symbol font');
  {$else}
  Check(not FontSubsetter.SupportsSymbolic, 'hb-subset leaves symbol fonts whole');
  {$endif OSWINDOWS}
  dc := FontDC.CreateDC;
  try
    fonts := nil;
    FontEnumerator.EnumTrueTypeFonts(dc, fonts);
  finally
    FontDC.DeleteDC(dc);
  end;
  f := 0;
  while (f <= high(SYMBOL_FONTS)) and
        (FindRawUtf8(fonts, SYMBOL_FONTS[f]) < 0) do
    inc(f);
  if f > high(SYMBOL_FONTS) then
  begin
    Check(true, 'SKIP: no symbol font installed');
    exit;
  end;
  name := Utf8ToString(SYMBOL_FONTS[f]);
  // SYMBOL_CHARSET makes the font symbolic (/Flags)
  whole := FirstFontFile(BuildPdf(name, SAMPLE, true, false, false, pdfaNone, 2));
  sub := FirstFontFile(BuildPdf(name, SAMPLE, false, false, false, pdfaNone, 2));
  Check(whole <> '', name + ': embedded');
  if not FontSubsetter.SupportsSymbolic then
  begin
    Check(sub = whole, name + ': embedded whole without SupportsSymbolic');
    exit;
  end;
  Check(length(sub) * 2 < length(whole), name + ': subset with SupportsSymbolic');
  kept := true;
  for i := 1 to length(SAMPLE) do
  begin
    g := SfntCmapLookup(whole, $F000 + ord(SAMPLE[i]));
    kept := kept and
            (g > 0) and
            (SfntGlyphLength(sub, g) > 0);
  end;
  Check(kept, name + ': the glyphs of the text are kept');
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
      uni := nil;
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
  // /W has no spaces: an entry is preceded by ']' or by the opening '['
  Check((Pos(RawByteString(']' + IntToStr(g) + '['), s) > 0) or
        (Pos(RawByteString('[' + IntToStr(g) + '['), s) > 0),
    '/W lists the first glyph');
  Check((Pos(RawByteString(']' + IntToStr(g + 4096) + '['), s) > 0) or
        (Pos(RawByteString('[' + IntToStr(g + 4096) + '['), s) > 0),
    '/W lists the glyph 4096 further');
  Check(Pos(RawByteString('<' + IntToHex(g + 4096, 4) + '> <'), s) > 0,
    '/ToUnicode lists the glyph 4096 further');
end;

end.
