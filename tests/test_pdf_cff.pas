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
  mormot.pdf;

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
  result := AnsiChar(v shr 8) + AnsiChar(v and 255);
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
  public
    procedure AddTable(const Tag: RawByteString; const Data: RawByteString);
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

function TFakeFace.GetTextMetrics(out Metrics: TFontMetrics): boolean;
begin
  FillChar(Metrics, SizeOf(Metrics), 0);
  result := false;
end;

function TFakeFace.GetOutlineMetrics(out Metrics: TFontOutlineMetrics): boolean;
begin
  FillChar(Metrics, SizeOf(Metrics), 0);
  result := false;
end;

function TFakeFace.GetCharAbcWidths(FirstChar, LastChar: cardinal;
  out Widths: TFontCharAbcArray): boolean;
begin
  Widths := nil;
  result := false;
end;

function TFakeFace.GetGlyphAdvance(Glyph: cardinal; out Advance: integer): boolean;
begin
  Advance := 0;
  result := false;
end;

function TFakeFace.GetFontData(TableTag, Offset: cardinal; Buffer: pointer;
  BufferSize: cardinal): cardinal;
var
  i: integer;
begin
  result := FONT_DATA_ERROR;
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
  Face := '';
  result := false;
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

end.
