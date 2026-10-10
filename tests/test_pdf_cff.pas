/// the CFF reader of the engine (PdfCffParse), on tables built here
// - each table is made by CffTable below, so its every byte is known: no
// font file is checked in
// - the system faces are only read: Hiragino Sans GB on macOS, Noto Sans
// CJK on Linux, a glyf face everywhere
unit test_pdf_cff;

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
  mormot.pdf,
  test_pdf_subset,      // DrawUtf8Text, PDF_DEFAULT_CHARSET
  pdf_inspect;          // InflatePdf

type
  /// PdfCffParse test cases
  TPdfCffTests = class(TSynTestCase)
  protected
    procedure CheckCids(const Info: TPdfCffInfo; const Cids: array of integer;
      const Msg: string);
  published
    procedure CidKeyedCharsets;
    procedure NameKeyed;
    procedure Malformed;
    procedure EveryPrefixRefused;
    procedure FlippedBytes;
    procedure FaceTables;
    procedure SystemFaces;
    procedure Type0Codes;
    procedure Type0CodesOfAFace;
  end;

/// a bare 'CFF ' table of Glyphs glyphs
// - CidKeyed: its Top DICT begins with ROS RosReg RosOrd Supplement; the
// String INDEX holds 'Adobe' (SID 391) and 'Identity' (SID 392)
// - Charset: the bytes of the charset, '' for the predefined charset 0
// - Extra: DICT bytes put before the ROS when RosFirst is false, after it
// otherwise
// - OffSize: of the CharStrings INDEX, 0 for the smallest that fits
function CffTable(CidKeyed: boolean; Glyphs: integer;
  const Charset: RawByteString; RosReg: integer = 391; RosOrd: integer = 392;
  const Extra: RawByteString = ''; RosFirst: boolean = true;
  OffSize: integer = 0): RawByteString;

/// a charset of format 0 for the CIDs of glyphs 1, 2, ...
function CffCharset0(const Cids: array of integer): RawByteString;

/// a charset of format 1 or 2 from (first, nLeft) pairs
function CffCharsetRanges(Format: integer; const Ranges: array of integer): RawByteString;


implementation

function Card16(v: integer): RawByteString;
begin
  result := AnsiChar((v shr 8) and 255) + AnsiChar(v and 255);
end;

function Card32(v: cardinal): RawByteString;
begin
  result := AnsiChar(v shr 24) + AnsiChar((v shr 16) and 255) +
            AnsiChar((v shr 8) and 255) + AnsiChar(v and 255);
end;

// a DICT integer of 5 bytes, so that the size of the DICT is known before
// the offsets it holds
function DictInt(v: integer): RawByteString;
begin
  result := #29 + AnsiChar(v shr 24) + AnsiChar((v shr 16) and 255) +
            AnsiChar((v shr 8) and 255) + AnsiChar(v and 255);
end;

// an INDEX - OffSize 0 for the smallest that fits
function IndexOf(const Items: array of RawByteString;
  OffSize: integer = 0): RawByteString;
var
  i, o, b: integer;
  data: RawByteString;

  procedure AddOffset(v: integer);
  var
    k: integer;
  begin
    for k := OffSize - 1 downto 0 do
      result := result + AnsiChar((v shr (k * 8)) and 255);
  end;

begin
  result := Card16(length(Items));
  if length(Items) = 0 then
    exit;
  data := '';
  for i := 0 to high(Items) do
    data := data + Items[i];
  if OffSize = 0 then
  begin
    OffSize := 1;
    b := length(data) + 1;
    while b > 255 do
    begin
      b := b shr 8;
      inc(OffSize);
    end;
  end;
  result := result + AnsiChar(OffSize);
  o := 1;
  for i := 0 to high(Items) do
  begin
    AddOffset(o);
    inc(o, length(Items[i]));
  end;
  AddOffset(o);
  result := result + data;
end;

function CffTable(CidKeyed: boolean; Glyphs: integer;
  const Charset: RawByteString; RosReg, RosOrd: integer;
  const Extra: RawByteString; RosFirst: boolean; OffSize: integer): RawByteString;
var
  ros, dict, head, strings, glyph: RawByteString;
  charstrings: array of RawByteString;
  i, topsize, charsetpos: integer;
begin
  ros := '';
  if CidKeyed then
    ros := DictInt(RosReg) + DictInt(RosOrd) + DictInt(0) + #12#30;
  if RosFirst then
    dict := ros + Extra
  else
    dict := Extra + ros;
  // charset and CharStrings: 5 + 1 bytes each
  topsize := length(dict) + 12;
  if Charset = '' then
    dec(topsize, 6);
  head := #1#0#4#1 + IndexOf(['Test']);
  strings := IndexOf(['Adobe', 'Identity']);
  // the Top DICT INDEX: 2 + 1 + 2 offsets + topsize
  charsetpos := length(head) + 5 + topsize + length(strings) + 2;
  if Charset <> '' then
    dict := dict + DictInt(charsetpos) + #15;
  dict := dict + DictInt(charsetpos + length(Charset)) + #17;
  SetLength(charstrings, Glyphs);
  glyph := #14; // endchar
  for i := 0 to Glyphs - 1 do
    charstrings[i] := glyph;
  result := head + IndexOf([dict]) + strings + #0#0 + Charset +
            IndexOf(charstrings, OffSize);
end;

function CffCharset0(const Cids: array of integer): RawByteString;
var
  i: integer;
begin
  result := #0;
  for i := 0 to high(Cids) do
    result := result + Card16(Cids[i]);
end;

function CffCharsetRanges(Format: integer; const Ranges: array of integer): RawByteString;
var
  i: integer;
begin
  result := AnsiChar(Format);
  i := 0;
  while i < high(Ranges) do
  begin
    result := result + Card16(Ranges[i]);
    if Format = 1 then
      result := result + AnsiChar(Ranges[i + 1])
    else
      result := result + Card16(Ranges[i + 1]);
    inc(i, 2);
  end;
end;

type
  // a face of the given sfnt tables and nothing else
  TFakeFace = class(TInterfacedObject, IFontFace)
  protected
    fTags: array of cardinal;
    fTables: array of RawByteString;
    fWhole: RawByteString;
  public
    procedure AddTable(const Tag: RawByteString; const Data: RawByteString);
    // the sfnt of the tables added, as GetFontData(0) and GetFaceFile give it
    procedure Seal(const Signature: RawByteString);
    function Handle: TFontHandle;
    function GetTextMetrics(out Metrics: TFontMetrics): boolean;
    function GetOutlineMetrics(out Metrics: TFontOutlineMetrics): boolean;
    function GetCharAbcWidths(FirstChar, LastChar: cardinal;
      out Widths: TFontCharAbcArray): boolean;
    function GetGlyphAdvance(Glyph: cardinal; out Advance: integer): boolean;
    function GetFontData(TableTag, Offset: cardinal; Buffer: pointer;
      BufferSize: cardinal): cardinal;
    function GetFaceFile(out Face: RawByteString): boolean;
  end;

procedure TFakeFace.AddTable(const Tag: RawByteString; const Data: RawByteString);
var
  n: integer;
begin
  n := length(fTags);
  SetLength(fTags, n + 1);
  SetLength(fTables, n + 1);
  fTags[n] := PCardinal(Tag)^; // little-endian, as GetFontData takes it
  fTables[n] := Data;
end;

function TFakeFace.Handle: TFontHandle;
begin
  result := nil;
end;

procedure TFakeFace.Seal(const Signature: RawByteString);
var
  i, n, off: integer;
  dir, data, t, tag: RawByteString;
begin
  n := length(fTags);
  dir := Signature + Card16(n) + Card16(0) + Card16(0) + Card16(0);
  off := 12 + 16 * n;
  data := '';
  for i := 0 to n - 1 do
  begin
    t := fTables[i];
    SetString(tag, PAnsiChar(@fTags[i]), 4);
    dir := dir + tag + Card32(0) + Card32(off + length(data)) +
      Card32(length(t));
    while length(t) and 3 <> 0 do
      t := t + #0;
    data := data + t;
  end;
  fWhole := dir + data;
end;

// metrics of an em of 1000 units, advances of 500 for WinAnsi
function TFakeFace.GetTextMetrics(out Metrics: TFontMetrics): boolean;
begin
  FillChar(Metrics, SizeOf(Metrics), 0);
  Metrics.tmHeight := 1000;
  Metrics.tmAscent := 800;
  Metrics.tmDescent := 200;
  Metrics.tmAveCharWidth := 500;
  Metrics.tmMaxCharWidth := 510;
  Metrics.tmWeight := 400;
  Metrics.tmPitchAndFamily := 1; // TMPF_FIXED_PITCH set: proportional (GDI)
  result := true;
end;

function TFakeFace.GetOutlineMetrics(out Metrics: TFontOutlineMetrics): boolean;
begin
  FillChar(Metrics, SizeOf(Metrics), 0);
  Metrics.otmAscent := 800;
  Metrics.otmDescent := -200;
  Metrics.otmrcFontBox.Right := 1000;
  Metrics.otmrcFontBox.Top := 800;
  Metrics.otmrcFontBox.Bottom := -200;
  Metrics.otmEMSquare := 1000;
  result := true;
end;

function TFakeFace.GetCharAbcWidths(FirstChar, LastChar: cardinal;
  out Widths: TFontCharAbcArray): boolean;
var
  i: integer;
begin
  SetLength(Widths, LastChar - FirstChar + 1);
  for i := 0 to high(Widths) do
  begin
    Widths[i].abcA := 0;
    Widths[i].abcB := 500;
    Widths[i].abcC := 0;
  end;
  result := true;
end;

function TFakeFace.GetGlyphAdvance(Glyph: cardinal; out Advance: integer): boolean;
begin
  Advance := 100 + integer(Glyph) * 10; // as FakeHmtx
  result := true;
end;

function TFakeFace.GetFontData(TableTag, Offset: cardinal; Buffer: pointer;
  BufferSize: cardinal): cardinal;
var
  i: integer;
begin
  result := FONT_DATA_ERROR;
  if (TableTag = 0) and
     (fWhole <> '') then
  begin
    if Offset > cardinal(length(fWhole)) then
      exit;
    result := cardinal(length(fWhole)) - Offset;
    if Buffer <> nil then
    begin
      if result > BufferSize then
        result := BufferSize;
      MoveFast(PByteArray(fWhole)[Offset], Buffer^, result);
    end;
    exit;
  end;
  for i := 0 to high(fTags) do
    if fTags[i] = TableTag then
    begin
      if Offset > cardinal(length(fTables[i])) then
        exit;
      result := cardinal(length(fTables[i])) - Offset;
      if Buffer <> nil then
      begin
        if result > BufferSize then
          result := BufferSize;
        MoveFast(PByteArray(fTables[i])[Offset], Buffer^, result);
      end;
      exit;
    end;
end;

function TFakeFace.GetFaceFile(out Face: RawByteString): boolean;
begin
  Face := fWhole;
  result := Face <> '';
end;

type
  // CreateFace gives Face for Name, and asks the provider before it otherwise
  TFakeProvider = class(TInterfacedObject, IFontProvider)
  protected
    fPrevious: IFontProvider;
    fFace: IFontFace;
    fName: SynUnicode;
  public
    constructor Create(const Previous: IFontProvider; const Face: IFontFace;
      const Name: RawUtf8);
    function CreateFace(const Request: TFontRequest): IFontFace;
  end;

constructor TFakeProvider.Create(const Previous: IFontProvider;
  const Face: IFontFace; const Name: RawUtf8);
begin
  inherited Create;
  fPrevious := Previous;
  fFace := Face;
  fName := Utf8ToSynUnicode(Name);
end;

function TFakeProvider.CreateFace(const Request: TFontRequest): IFontFace;
begin
  if Request.FaceName = fName then
    result := fFace
  else
    result := fPrevious.CreateFace(Request);
end;

const
  FAKE_FACE = 'CffTestFace';
  FAKE_GLYPHS = 42;

// 'head' of an em of 1000 units
function FakeHead: RawByteString;
begin
  result := Card32($00010000) + Card32($00010000) + Card32(0) +
    Card32($5F0F3CF5) + Card16(0) + Card16(1000) + StringOfChar(#0, 16) +
    Card16(0) + Card16(65336) + Card16(1000) + Card16(800) +
    Card16(0) + Card16(3) + Card16(2) + Card16(0) + Card16(0);
end;

// 'hhea' with FAKE_GLYPHS advances
function FakeHhea: RawByteString;
begin
  result := Card32($00010000) + Card16(800) + Card16(65336) + Card16(0) +
    Card16(510) + StringOfChar(#0, 22) + Card16(FAKE_GLYPHS);
end;

// 'hmtx': glyph g advances 100 + 10 * g units
function FakeHmtx: RawByteString;
var
  g: integer;
begin
  result := '';
  for g := 0 to FAKE_GLYPHS - 1 do
    result := result + Card16(100 + g * 10) + Card16(0);
end;

function FakeMaxp: RawByteString;
begin
  result := Card32($00005000) + Card16(FAKE_GLYPHS);
end;

// a (3,1) 'cmap' of format 4: Chars[i] -> Glyphs[i], one segment each
function FakeCmap(const Chars, Glyphs: array of integer): RawByteString;
var
  i, n: integer;
  ends, starts, deltas, ranges: RawByteString;
begin
  n := length(Chars) + 1; // and the final $FFFF segment
  ends := '';
  starts := '';
  deltas := '';
  ranges := '';
  for i := 0 to high(Chars) do
  begin
    ends := ends + Card16(Chars[i]);
    starts := starts + Card16(Chars[i]);
    deltas := deltas + Card16((Glyphs[i] - Chars[i]) and $ffff);
    ranges := ranges + Card16(0);
  end;
  ends := ends + Card16($ffff);
  starts := starts + Card16($ffff);
  deltas := deltas + Card16(1);
  ranges := ranges + Card16(0);
  result := Card16(4) + Card16(16 + n * 8) + Card16(0) + Card16(n * 2) +
    Card16(0) + Card16(0) + Card16(0) + ends + Card16(0) + starts + deltas +
    ranges;
  result := Card16(0) + Card16(1) + Card16(3) + Card16(1) + Card32(12) + result;
end;

// a face of the tables above, mapping Chars to Glyphs, with Cff if not ''
function FakeFace(const Chars, Glyphs: array of integer;
  const Cff: RawByteString): TFakeFace;
begin
  result := TFakeFace.Create;
  if Cff <> '' then
    result.AddTable('CFF ', Cff);
  result.AddTable('cmap', FakeCmap(Chars, Glyphs));
  result.AddTable('head', FakeHead);
  result.AddTable('hhea', FakeHhea);
  result.AddTable('hmtx', FakeHmtx);
  result.AddTable('maxp', FakeMaxp);
  if Cff <> '' then
    result.Seal('OTTO')
  else
    result.Seal(#0#1#0#0);
end;

const
  // Greek, Cyrillic and Latin Extended, out of the glyph order of most faces
  MIXED_TEXT: RawUtf8 = {$ifdef HASCODEPAGE}
    #$03C9#$03B1#$03B2' '#$0416#$0434' '#$0101#$0100#$0436#$03B3
    {$else}
    #$CF#$89#$CE#$B1#$CE#$B2' '#$D0#$96#$D0#$B4' '#$C4#$81#$C4#$80#$D0#$B6#$CE#$B3
    {$endif};

// the hex value of <XXXX> at s[i], -1 if there is none
function Hex4At(const s: RawUtf8; i: PtrInt): integer;
var
  k, v: integer;
begin
  result := -1;
  if (i < 1) or
     (i + 5 > length(s)) or
     (s[i] <> '<') or
     (s[i + 5] <> '>') then
    exit;
  v := 0;
  for k := i + 1 to i + 4 do
    case s[k] of
      '0'..'9':
        v := v * 16 + ord(s[k]) - ord('0');
      'A'..'F':
        v := v * 16 + ord(s[k]) - ord('A') + 10;
    else
      exit;
    end;
  result := v;
end;

function Parse(const Table: RawByteString; out Info: TPdfCffInfo): TPdfCffKind;
begin
  result := PdfCffParse(pointer(Table), length(Table), Info);
end;


{ TPdfCffTests }

procedure TPdfCffTests.CheckCids(const Info: TPdfCffInfo;
  const Cids: array of integer; const Msg: string);
var
  i: integer;
  ok: boolean;
begin
  ok := length(Info.Cid) = length(Cids);
  if ok then
    for i := 0 to high(Cids) do
      if Info.Cid[i] <> Cids[i] then
        ok := false;
  Check(ok, Msg);
end;

procedure TPdfCffTests.CidKeyedCharsets;
var
  info: TPdfCffInfo;
begin
  // format 0: glyphs 1, 2, 3 are CIDs 7, 2, 41
  CheckEqual(ord(Parse(CffTable(true, 4, CffCharset0([7, 2, 41])), info)),
    ord(pcCidKeyed), 'format 0');
  CheckEqual(info.GlyphCount, 4);
  CheckEqual(info.Registry, 'Adobe');
  CheckEqual(info.Ordering, 'Identity');
  CheckEqual(info.Supplement, 0);
  CheckCids(info, [0, 7, 2, 41], 'format 0 CIDs');
  // format 1: 10..11, then 5
  Check(Parse(CffTable(true, 4, CffCharsetRanges(1, [10, 1, 5, 0])), info) =
    pcCidKeyed, 'format 1');
  CheckCids(info, [0, 10, 11, 5], 'format 1 CIDs');
  // format 2: 100..102
  Check(Parse(CffTable(true, 4, CffCharsetRanges(2, [100, 2])), info) =
    pcCidKeyed, 'format 2');
  CheckCids(info, [0, 100, 101, 102], 'format 2 CIDs');
  // a last range beyond the glyphs ends with them
  Check(Parse(CffTable(true, 3, CffCharsetRanges(2, [1, 300])), info) =
    pcCidKeyed, 'long range');
  CheckCids(info, [0, 1, 2], 'long range CIDs');
  // the identity, written out
  Check(Parse(CffTable(true, 5, CffCharsetRanges(1, [1, 3])), info) =
    pcCidKeyed, 'identity');
  CheckCids(info, [0, 1, 2, 3, 4], 'identity CIDs');
  // 300 glyphs: CharStrings offsets of 2 bytes; then of 3 and 4 bytes
  Check(Parse(CffTable(true, 300, CffCharsetRanges(2, [1, 298])), info) =
    pcCidKeyed, '300 glyphs');
  CheckEqual(info.GlyphCount, 300);
  CheckEqual(info.Cid[299], 299);
  Check(Parse(CffTable(true, 4, CffCharset0([7, 2, 41]), 391, 392, '', true,
    3), info) = pcCidKeyed, 'offSize 3');
  CheckCids(info, [0, 7, 2, 41], 'offSize 3 CIDs');
  Check(Parse(CffTable(true, 4, CffCharset0([7, 2, 41]), 391, 392, '', true,
    4), info) = pcCidKeyed, 'offSize 4');
  CheckCids(info, [0, 7, 2, 41], 'offSize 4 CIDs');
  // reals and other operators after the ROS are skipped: FontMatrix
  Check(Parse(CffTable(true, 4, CffCharset0([7, 2, 41]),
    391, 392, #30#$0a#$00#$1f#$8b#$8b#30#$0a#$00#$1f#$8b#$8b#12#7), info) =
    pcCidKeyed, 'FontMatrix');
  CheckCids(info, [0, 7, 2, 41], 'FontMatrix CIDs');
end;

procedure TPdfCffTests.NameKeyed;
var
  info: TPdfCffInfo;
begin
  // FontMatrix 0.001 0 0 0.001 0 0, its reals skipped
  Check(Parse(CffTable(false, 3, CffCharset0([5, 6]), 0, 0,
    #30#$0a#$00#$1f#$8b#$8b#30#$0a#$00#$1f#$8b#$8b#12#7), info) =
    pcNameKeyed, 'name-keyed');
  CheckEqual(info.GlyphCount, 3);
  Check(info.Cid = nil, 'no CIDs: the glyph index is the code');
  CheckEqual(info.Registry, '');
  // the charset of glyph names is not read
  Check(Parse(CffTable(false, 3, #9#9), info) = pcNameKeyed, 'any charset');
  Check(PdfCffParse(nil, 0, info) = pcNone, 'no table');
  Check(info.Kind = pcNone, 'Kind');
end;

procedure TPdfCffTests.Malformed;
var
  info: TPdfCffInfo;
  t: RawByteString;
begin
  Check(Parse(CffTable(true, 4, CffCharset0([7, 2, 7])), info) = pcInvalid,
    'duplicate CID');
  Check(info.Kind = pcInvalid, 'Kind');
  Check(info.Cid = nil, 'no CIDs of a refused table');
  Check(Parse(CffTable(true, 3, CffCharset0([0, 2])), info) = pcInvalid,
    'CID 0 beyond glyph 0');
  Check(Parse(CffTable(true, 3, CffCharsetRanges(1, [65535, 1])), info) =
    pcInvalid, 'range beyond 65535');
  Check(Parse(CffTable(true, 3, CffCharsetRanges(3, [1, 1])), info) =
    pcInvalid, 'charset format 3');
  // a CIDFont has no predefined charset: none given, 1 (Expert) given
  Check(Parse(CffTable(true, 5, ''), info) = pcInvalid, 'charset 0');
  Check(Parse(CffTable(true, 5, '', 391, 392, DictInt(1) + #15), info) =
    pcInvalid, 'charset 1');
  Check(Parse(CffTable(true, 3, CffCharset0([1, 2]), 300), info) = pcInvalid,
    'standard string SID');
  Check(Parse(CffTable(true, 3, CffCharset0([1, 2]), 391, 393), info) =
    pcInvalid, 'SID out of the String INDEX');
  // ROS after another operator: version SID 0
  Check(Parse(CffTable(true, 3, CffCharset0([1, 2]), 391, 392, #$8b#0, false),
    info) = pcInvalid, 'ROS not first');
  // an operand too many, a reserved byte
  Check(Parse(CffTable(false, 3, '', 0, 0, #$8b), info) = pcInvalid,
    'CharStrings with two operands');
  Check(Parse(CffTable(false, 3, '', 0, 0, #255#0), info) = pcInvalid,
    'reserved byte');
  // the header and the INDEX structure
  t := CffTable(true, 4, CffCharset0([7, 2, 41]));
  t[1] := #2;
  Check(Parse(t, info) = pcInvalid, 'major version 2');
  t := CffTable(true, 4, CffCharset0([7, 2, 41]));
  t[7] := #5; // the offSize of the Name INDEX
  Check(Parse(t, info) = pcInvalid, 'offSize 5');
  t := CffTable(true, 4, CffCharset0([7, 2, 41]));
  t[8] := #2; // its first offset
  Check(Parse(t, info) = pcInvalid, 'first offset not 1');
  t := CffTable(true, 4, CffCharset0([7, 2, 41]));
  t[9] := #$ff; // its last offset
  Check(Parse(t, info) = pcInvalid, 'offset beyond the table');
end;

procedure TPdfCffTests.EveryPrefixRefused;
var
  info: TPdfCffInfo;
  t, cut: RawByteString;
  l: integer;
  ok: boolean;
begin
  // the CharStrings INDEX ends each table: no prefix is a whole one
  t := CffTable(true, 4, CffCharset0([7, 2, 41]));
  Check(Parse(t, info) = pcCidKeyed);
  ok := true;
  for l := 1 to length(t) - 1 do
  begin
    cut := copy(t, 1, l);
    if Parse(cut, info) <> pcInvalid then
      ok := false;
  end;
  Check(ok, 'every prefix of a CID-keyed table');
  t := CffTable(false, 4, '');
  ok := true;
  for l := 1 to length(t) - 1 do
  begin
    cut := copy(t, 1, l);
    if Parse(cut, info) <> pcInvalid then
      ok := false;
  end;
  Check(ok, 'every prefix of a name-keyed table');
end;

procedure TPdfCffTests.FlippedBytes;
var
  info: TPdfCffInfo;
  t, f: RawByteString;
  i, v: integer;
  k: TPdfCffKind;
  ok: boolean;
begin
  // whatever a byte becomes, the reader returns a kind and nothing else:
  // a CID-keyed answer still has one CID per glyph
  t := CffTable(true, 4, CffCharsetRanges(1, [10, 1, 5, 0]));
  ok := true;
  for i := 1 to length(t) do
    for v := 0 to 255 do
    begin
      f := t;
      f[i] := AnsiChar(v);
      k := Parse(f, info);
      if (k = pcCidKeyed) and
         (length(info.Cid) <> info.GlyphCount) then
        ok := false;
    end;
  Check(ok, 'every byte of a table, every value');
end;

procedure TPdfCffTests.FaceTables;
var
  info: TPdfCffInfo;
  face: TFakeFace;
  intf: IFontFace;
begin
  Check(PdfFaceCffInfo(nil, info) = pcNone, 'no face');
  face := TFakeFace.Create;
  intf := face;
  face.AddTable('glyf', #0#0);
  Check(PdfFaceCffInfo(intf, info) = pcNone, 'glyf face');
  face := TFakeFace.Create;
  intf := face;
  face.AddTable('CFF ', CffTable(true, 4, CffCharset0([7, 2, 41])));
  Check(PdfFaceCffInfo(intf, info) = pcCidKeyed, 'CFF face');
  CheckCids(info, [0, 7, 2, 41], 'its CIDs, read raw');
  face := TFakeFace.Create;
  intf := face;
  face.AddTable('CFF ', 'garbage');
  Check(PdfFaceCffInfo(intf, info) = pcInvalid, 'malformed CFF face');
  // CFF2 is no CFF a PDF 1.x font program allows, and no glyf face either
  face := TFakeFace.Create;
  intf := face;
  face.AddTable('CFF2', #2#0#5#0#0);
  Check(PdfFaceCffInfo(intf, info) = pcInvalid, 'CFF2 face');
end;

procedure TPdfCffTests.SystemFaces;
var
  lf: TFontRequest;
  info: TPdfCffInfo;
  i, diff: integer;
  identity: boolean;

  function Face(const Name: RawUtf8): IFontFace;
  begin
    FillChar(lf, SizeOf(lf), 0);
    lf.FaceName := SynUnicode(Name);
    lf.Height := -1000;
    lf.Weight := 400;
    result := FontProvider.CreateFace(lf);
  end;

begin
  // a glyf face has no 'CFF ' table
  if PdfFaceCffInfo(Face({$ifdef OSWINDOWS} 'Arial' {$else}
       {$ifdef OSDARWIN} 'Helvetica' {$else} 'DejaVu Sans' {$endif}
       {$endif}), info) = pcNone then
    Check(true)
  else
    Check(true, 'SKIP: the glyf face resolved to a CFF face');
  {$ifdef OSDARWIN}
  // the CJK face of the Mac tests: CID-keyed, 288 glyphs whose CID differs
  Check(PdfFaceCffInfo(Face('Hiragino Sans GB'), info) = pcCidKeyed,
    'Hiragino Sans GB');
  CheckEqual(info.Registry, 'Adobe');
  diff := 0;
  for i := 0 to high(info.Cid) do
    if info.Cid[i] <> i then
      inc(diff);
  CheckEqual(diff, 288, 'glyphs whose CID is not their index');
  {$else}
  {$ifdef OSLINUX}
  // Noto Sans CJK is Adobe-Identity-0: CID-keyed, every CID its index
  if PdfFaceCffInfo(Face('Noto Sans CJK JP'), info) = pcCidKeyed then
  begin
    CheckEqual(info.Registry, 'Adobe');
    CheckEqual(info.Ordering, 'Identity');
    identity := true;
    for i := 0 to high(info.Cid) do
      if info.Cid[i] <> i then
        identity := false;
    Check(identity, 'Noto Sans CJK: the identity');
  end
  else
    Check(true, 'SKIP: Noto Sans CJK JP not installed');
  {$else}
  Check(true, 'SKIP: no CFF system face known here');
  {$endif OSLINUX}
  {$endif OSDARWIN}
end;

procedure TPdfCffTests.Type0Codes;
var
  pdf: TPdfDocument;
  stream: TMemoryStream;
  sans, serif, mono: string;
  s: RawUtf8;
  i, j, e, code, last, runs, chars: PtrInt;
  sorted: boolean;
begin
  // /W and /ToUnicode of a Type0 font are keyed by the code, sorted, one
  // entry per code, under the codespace of every two-byte code
  stream := TMemoryStream.Create;
  try
    pdf := TPdfDocument.Create(false, 0, pdfaNone);
    try
      pdf.CompressionMethod := cmNone;
      pdf.EmbeddedTTF := true;
      pdf.AddPage;
      GetPdfFonts(true, sans, serif, mono);
      pdf.Canvas.SetFont(StringToUtf8(sans), 12, [], PDF_DEFAULT_CHARSET);
      DrawUtf8Text(pdf, 40, 700, MIXED_TEXT);
      pdf.SaveToStream(stream);
    finally
      pdf.Free;
    end;
    SetLength(s, stream.Size);
    stream.Position := 0;
    stream.Read(pointer(s)^, stream.Size);
  finally
    stream.Free;
  end;
  s := InflatePdf(s);
  // /W [c [w ...] c [w ...]]: each run starts after the end of the one before
  i := PosEx('/W [', s);
  Check(i > 0, '/W');
  inc(i, 4);
  last := -1;
  runs := 0;
  sorted := true;
  while (i <= length(s)) and
        (s[i] in ['0'..'9']) do
  begin
    code := 0;
    while s[i] in ['0'..'9'] do
    begin
      code := code * 10 + ord(s[i]) - ord('0');
      inc(i);
    end;
    if code <= last then
      sorted := false;
    e := PosEx(']', s, i);
    if (s[i] <> '[') or
       (e = 0) then
      break;
    last := code;
    for j := i + 1 to e - 1 do
      if s[j] = ' ' then
        inc(last); // one width more in this run
    inc(runs);
    i := e + 1;
  end;
  Check(runs > 0, 'runs of /W');
  Check(sorted, '/W sorted by code, no code twice');
  // /ToUnicode
  Check(PosEx('begincodespacerange'#10'<0000> <FFFF>'#10, s) > 0, 'codespace');
  i := PosEx('beginbfchar'#10, s);
  Check(i > 0, 'bfchar');
  inc(i, 12);
  last := -1;
  chars := 0;
  sorted := true;
  while Hex4At(s, i) >= 0 do
  begin
    code := Hex4At(s, i);
    if code <= last then
      sorted := false;
    last := code;
    inc(chars);
    i := PosEx(#10, s, i) + 1;
    if copy(s, i, 9) = 'endbfchar' then
      i := PosEx('beginbfchar'#10, s, i) + 12;
  end;
  CheckEqual(chars, 9, 'one code per character out of WinAnsi');
  Check(sorted, '/ToUnicode sorted by code, no code twice');
end;

// draw Text in the fake face, return the inflated PDF
function FakeFacePdf(const Face: IFontFace; const Text: RawUtf8): RawUtf8;
var
  pdf: TPdfDocument;
  stream: TMemoryStream;
  previous: IFontProvider;
begin
  previous := FontProvider;
  FontProvider := TFakeProvider.Create(previous, Face, FAKE_FACE);
  try
    stream := TMemoryStream.Create;
    try
      pdf := TPdfDocument.Create(false, 0, pdfaNone);
      try
        pdf.CompressionMethod := cmNone;
        pdf.AddTrueTypeFont(FAKE_FACE);
        pdf.AddPage;
        pdf.Canvas.SetFont(FAKE_FACE, 12, [], PDF_DEFAULT_CHARSET);
        DrawUtf8Text(pdf, 40, 700, Text);
        pdf.SaveToStream(stream);
      finally
        pdf.Free;
      end;
      SetLength(result, stream.Size);
      stream.Position := 0;
      stream.Read(pointer(result)^, stream.Size);
    finally
      stream.Free;
    end;
  finally
    FontProvider := previous;
  end;
  result := InflatePdf(result);
end;

procedure TPdfCffTests.Type0CodesOfAFace;
const
  // U+0100..U+0104: glyphs 7, 2, 3, 7, 41 - U+0103 an alias of U+0100
  ALIAS_TEXT: RawUtf8 = {$ifdef HASCODEPAGE}
    #$0104#$0100#$0101#$0103#$0102
    {$else}
    #$C4#$84#$C4#$80#$C4#$81#$C4#$83#$C4#$82
    {$endif};
var
  s: RawUtf8;
begin
  // a face built here: the codes, their widths and their characters are
  // known whatever fonts are installed
  s := FakeFacePdf(FakeFace([$100, $101, $102, $103, $104], [7, 2, 3, 7, 41],
    ''), ALIAS_TEXT);
  Check(PosEx('/W [2[120 130]7[170]41[510]]', s) > 0,
    'runs of /W: sorted, code 7 once, widths of hmtx');
  Check(PosEx('4 beginbfchar'#10'<0002> <0101>'#10'<0003> <0102>'#10 +
    '<0007> <0100>'#10'<0029> <0104>'#10'endbfchar', s) > 0,
    '/ToUnicode: sorted, the smaller character of code 7');
  Check(PosEx('<00290007000200070003>', s) > 0, 'the text in glyph codes');
end;

end.
