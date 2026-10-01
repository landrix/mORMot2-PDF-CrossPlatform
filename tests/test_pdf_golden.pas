/// golden file tests: generated PDFs compared with a recorded baseline
// - the baseline is per machine, not versioned: embedded and subset faces come
// from the fonts installed, so the same document differs between systems
// - record it with "test_runner --golden-record" on the commit to compare
// against; without a baseline the cases are skipped
// - compared in the form GoldenNormalize() gives: decoded, with what changes
// between runs blanked - the /ID, subset tags, dates, and the stream lengths
// and offsets that move with them - after checking that they are right
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
  mormot.core.text,     // FormatUtf8
  mormot.core.unicode,  // StringToUtf8
  mormot.lib.z,         // UncompressZipString
  mormot.pdf.types,     // TPdfStructRole, GetPdfFonts
  mormot.ui.pdf,
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

/// the form in which two PDFs are compared
// - parsed token by token: streams decoded (FlateDecode inflated, XRef streams
// as one text line per object), the /ID, '/ABCDEF+' subset tags, the
// /CreationDate and /ModDate values, XMP dates, stream lengths and file offsets
// replaced by placeholders
// - the structure is checked before anything is blanked: each /Length has to
// end at endstream, each offset has to point to its object; Error tells the
// first violation
function GoldenNormalize(const Pdf: RawByteString; out Error: RawUtf8): RawByteString;


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

type
  // walks the PDF syntax token by token, so strings, comments and stream data
  // are never mistaken for structure; checks what it blanks before blanking it
  TGoldenNormalizer = class
  protected
    fPdf: RawByteString;
    fOut: TRawByteStringStream;
    fError: RawUtf8;
    // file offsets of the xref tables and XRef stream objects parsed so far
    fXRefOffsets: TInt64DynArray;
    procedure Fail(const Fmt: RawUtf8; const Args: array of const);
    procedure Emit(const s: RawByteString; b, e: PtrInt); overload;
    procedure Emit(const s: RawByteString); overload;
    function ObjectAtOffset(Offset, Num, Gen: Int64): boolean;
    procedure Syntax(const s: RawByteString; TopLevel: boolean);
    function Stream(const Dict, Data: RawByteString; ObjNum: Int64): RawByteString;
    function XRefStream(const Dict, Data: RawByteString): RawByteString;
    procedure XRefTable(const s: RawByteString; var i: PtrInt);
  public
    function Normalize(const Pdf: RawByteString; out Error: RawUtf8): RawByteString;
  end;

const
  PDF_WHITE = [#0, #9, #10, #12, #13, ' '];
  PDF_DELIM = ['(', ')', '<', '>', '[', ']', '{', '}', '/', '%'];
  // longer digit runs are no offset or length of ours: refused, not wrapped
  MAX_DIGITS = 15;

function IsDigits(const s: RawByteString; b, n: PtrInt): boolean;
begin
  result := false;
  if (b < 1) or (n > length(s) - b + 1) then
    exit;
  while n > 0 do
  begin
    if not (s[b] in ['0'..'9']) then
      exit;
    inc(b);
    dec(n);
  end;
  result := true;
end;

// the unsigned integer at s[i], i moved after it; -1 if none or too long
function ReadInt(const s: RawByteString; var i: PtrInt): Int64;
var
  n: integer;
begin
  result := -1;
  if (i > length(s)) or not (s[i] in ['0'..'9']) then
    exit;
  result := 0;
  n := 0;
  while (i <= length(s)) and (s[i] in ['0'..'9']) do
  begin
    inc(n);
    if n > MAX_DIGITS then
    begin
      result := -1;
      exit;
    end;
    result := result * 10 + ord(s[i]) - 48;
    inc(i);
  end;
end;

// the whole of Value as an unsigned integer, or -1
function ReadIntValue(const Value: RawByteString): Int64;
var
  i: PtrInt;
begin
  i := 1;
  result := ReadInt(Value, i);
  if i <= length(Value) then
    result := -1;
end;

procedure SkipWhite(const s: RawByteString; var i: PtrInt);
begin
  while (i <= length(s)) and (s[i] in PDF_WHITE) do
    inc(i);
end;

// i after the string, hex string, array or dictionary starting at s[i];
// false if it is not closed
function SkipValue(const s: RawByteString; var i: PtrInt): boolean;
var
  depth: integer;
begin
  result := false;
  case s[i] of
    '(':
      begin
        depth := 0;
        repeat
          if i > length(s) then
            exit;
          case s[i] of
            '\':
              inc(i);
            '(':
              inc(depth);
            ')':
              dec(depth);
          end;
          inc(i);
        until depth = 0;
      end;
    '<':
      if (i < length(s)) and (s[i + 1] = '<') then
      begin
        inc(i, 2);
        depth := 1;
        while depth > 0 do
        begin
          if i > length(s) then
            exit;
          if s[i] in ['(', '['] then
          begin
            if not SkipValue(s, i) then
              exit;
            continue;
          end;
          if (s[i] = '<') and (i < length(s)) and (s[i + 1] = '<') then
          begin
            inc(depth);
            inc(i);
          end
          else if (s[i] = '>') and (i < length(s)) and (s[i + 1] = '>') then
          begin
            dec(depth);
            inc(i);
          end
          else if s[i] = '<' then
          begin
            if not SkipValue(s, i) then
              exit;
            continue;
          end;
          inc(i);
        end;
      end
      else
      begin
        while (i <= length(s)) and (s[i] <> '>') do
          inc(i);
        if i > length(s) then
          exit;
        inc(i);
      end;
    '[':
      begin
        inc(i);
        repeat
          SkipWhite(s, i);
          if i > length(s) then
            exit;
          if s[i] = ']' then
            break;
          if s[i] in ['(', '<', '['] then
          begin
            if not SkipValue(s, i) then
              exit;
          end
          else
            inc(i);
        until false;
        inc(i);
      end;
  else
    inc(i);
  end;
  result := true;
end;

// the position of the value of Key in the outermost dictionary of Dict
// - nested dictionaries, arrays and strings are skipped, so a key inside them
// is not taken; the value is Dict[b..e-1], maybe with trailing white space
function DictValuePos(const Dict, Key: RawByteString; out b, e: PtrInt): boolean;
var
  i, j: PtrInt;
  name: RawByteString;
begin
  result := false;
  i := PosEx('<<', Dict);
  if i = 0 then
    exit;
  inc(i, 2);
  repeat
    SkipWhite(Dict, i);
    if (i > length(Dict)) or (Dict[i] = '>') then
      exit;
    if Dict[i] <> '/' then
      exit; // not a key: malformed, the caller sees no value
    j := i + 1;
    while (j <= length(Dict)) and not (Dict[j] in PDF_WHITE + PDF_DELIM) do
      inc(j);
    name := copy(Dict, i, j - i);
    i := j;
    SkipWhite(Dict, i);
    if i > length(Dict) then
      exit;
    b := i;
    if Dict[i] in ['(', '<', '['] then
    begin
      if not SkipValue(Dict, i) then
        exit;
    end
    else if Dict[i] = '/' then
    begin
      inc(i);
      while (i <= length(Dict)) and not (Dict[i] in PDF_WHITE + PDF_DELIM) do
        inc(i);
    end
    else
    begin
      // a number, possibly 'n g R', or a keyword
      while (i <= length(Dict)) and not (Dict[i] in PDF_DELIM) do
        inc(i);
    end;
    if name = Key then
    begin
      e := i;
      result := true;
      exit;
    end;
  until false;
end;

// the raw text of the value of Key in the outermost dictionary of Dict, or ''
function DictValue(const Dict, Key: RawByteString): RawByteString;
var
  b, e: PtrInt;
begin
  if DictValuePos(Dict, Key, b, e) then
    result := TrimU(copy(Dict, b, e - b))
  else
    result := '';
end;

// the integers of an array value like '[1 3 1]'; nil if it holds anything else
function IntArray(const Value: RawByteString): TInt64DynArray;
var
  i: PtrInt;
  v: Int64;
  n: integer;
begin
  result := nil;
  if (Value = '') or (Value[1] <> '[') then
    exit;
  i := 2;
  n := 0;
  repeat
    SkipWhite(Value, i);
    if i > length(Value) then
    begin
      result := nil;
      exit;
    end;
    if Value[i] = ']' then
      exit;
    v := ReadInt(Value, i);
    if v < 0 then
    begin
      result := nil;
      exit;
    end;
    SetLength(result, n + 1);
    result[n] := v;
    inc(n);
  until false;
end;

procedure TGoldenNormalizer.Fail(const Fmt: RawUtf8; const Args: array of const);
begin
  if fError = '' then // the first error is the one that explains the others
    fError := FormatUtf8(Fmt, Args);
end;

procedure TGoldenNormalizer.Emit(const s: RawByteString; b, e: PtrInt);
begin
  if e > b then
    fOut.WriteBuffer(PAnsiChar(pointer(s))[b - 1], e - b);
end;

procedure TGoldenNormalizer.Emit(const s: RawByteString);
begin
  if s <> '' then
    fOut.WriteBuffer(pointer(s)^, length(s));
end;

// true if "Num Gen obj" starts at the 0-based file offset Offset
function TGoldenNormalizer.ObjectAtOffset(Offset, Num, Gen: Int64): boolean;
var
  head: RawUtf8;
begin
  head := FormatUtf8('% % obj', [Num, Gen]);
  result := (Offset >= 0) and
            (Offset <= length(fPdf) - length(head)) and
            CompareMem(@fPdf[Offset + 1], pointer(head), length(head));
end;

procedure ZeroDigits(var s: RawByteString; b, n: PtrInt);
begin
  while n > 0 do
  begin
    if s[b] in ['0'..'9'] then
      s[b] := '0';
    inc(b);
    dec(n);
  end;
end;

// the dates the engine writes into an XMP packet, 'YYYY-MM-DDTHH:MM:SS';
// any other date in it is the caller's and stays
function BlankXmpDates(const Xmp: RawByteString): RawByteString;
const
  TAGS: array[0..2] of RawUtf8 = (
    '<xmp:CreateDate>', '<xmp:ModifyDate>', '<xmp:MetadataDate>');
var
  t: integer;
  i: PtrInt;
begin
  result := Xmp;
  SetLength(result, length(result)); // a copy of our own to write to
  for t := 0 to high(TAGS) do
  begin
    i := PosEx(TAGS[t], result);
    while i > 0 do
    begin
      inc(i, length(TAGS[t]));
      if (i + 18 <= length(result)) and
         (result[i + 4] = '-') and (result[i + 7] = '-') and
         (result[i + 10] = 'T') and (result[i + 13] = ':') and
         (result[i + 16] = ':') and IsDigits(result, i, 4) and
         IsDigits(result, i + 5, 2) and IsDigits(result, i + 8, 2) and
         IsDigits(result, i + 11, 2) and IsDigits(result, i + 14, 2) and
         IsDigits(result, i + 17, 2) then
        ZeroDigits(result, i, 19);
      i := PosEx(TAGS[t], result, i);
    end;
  end;
end;

// an XRef stream as text, one "type field2 field3" line per object; the
// offsets of objects in use are checked, then written as 0, as their width
// in /W changes with the file size
function TGoldenNormalizer.XRefStream(const Dict, Data: RawByteString): RawByteString;
var
  w, index: TInt64DynArray;
  row, rows, seg, size: Int64;
  num, k, n: integer;
  f: array[0..2] of Int64;
  P: PByte;
begin
  result := '';
  w := IntArray(DictValue(Dict, '/W'));
  index := IntArray(DictValue(Dict, '/Index'));
  size := ReadIntValue(DictValue(Dict, '/Size'));
  if index = nil then
  begin
    SetLength(index, 2);
    index[0] := 0;
    index[1] := size;
  end;
  if (length(w) <> 3) or (w[0] > 8) or (w[1] > 8) or (w[2] > 8) or
     (w[0] + w[1] + w[2] = 0) or odd(length(index)) or
     (size < 0) or (size > MaxInt) then
  begin
    Fail('XRef stream: unusable /W, /Index or /Size', []);
    exit;
  end;
  row := w[0] + w[1] + w[2];
  rows := 0;
  seg := 0;
  while seg < length(index) do
  begin
    if index[seg] + index[seg + 1] > size then
    begin
      Fail('XRef stream: /Index beyond /Size %', [size]);
      exit;
    end;
    inc(rows, index[seg + 1]);
    inc(seg, 2);
  end;
  if rows * row <> length(Data) then
  begin
    Fail('XRef stream: % bytes for % rows of %', [length(Data), rows, row]);
    exit;
  end;
  P := pointer(Data);
  seg := 0;
  while seg < length(index) do
  begin
    for num := index[seg] to index[seg] + index[seg + 1] - 1 do // <= size
    begin
      for k := 0 to 2 do
      begin
        f[k] := 0;
        if (k = 0) and (w[0] = 0) then
          f[0] := 1; // the type defaults to 1 when its field is absent
        for n := 1 to w[k] do
        begin
          f[k] := f[k] shl 8 + P^;
          inc(P);
        end;
      end;
      if f[0] = 1 then
      begin
        if not ObjectAtOffset(f[1], num, f[2]) then
          Fail('XRef stream: object % % is not at offset %', [num, f[2], f[1]]);
        f[1] := 0;
      end;
      result := result + FormatUtf8('% % %'#10, [f[0], f[1], f[2]]);
    end;
    inc(seg, 2);
  end;
end;

// a classic "xref" table from s[i], i after the keyword; offsets checked,
// then written as 0
procedure TGoldenNormalizer.XRefTable(const s: RawByteString; var i: PtrInt);
var
  first, count, k, off: Int64;
begin
  repeat
    SkipWhite(s, i);
    if (i > length(s)) or not (s[i] in ['0'..'9']) then
      exit; // 'trailer' follows
    first := ReadInt(s, i);
    SkipWhite(s, i);
    count := ReadInt(s, i);
    if (first < 0) or (count < 0) then
    begin
      Fail('xref table: bad subsection header', []);
      exit;
    end;
    Emit(FormatUtf8(#10'% %'#10, [first, count]));
    k := 0;
    while k < count do
    begin
      SkipWhite(s, i);
      if not (IsDigits(s, i, 10) and IsDigits(s, i + 11, 5) and
              (s[i + 10] = ' ') and (s[i + 16] = ' ') and
              (s[i + 17] in ['n', 'f'])) then
      begin
        Fail('xref table: bad entry for object %', [first + k]);
        exit;
      end;
      if s[i + 17] = 'n' then
      begin
        off := GetInt64(@s[i]);
        if not ObjectAtOffset(off, first + k, GetCardinal(@s[i + 11])) then
          Fail('xref table: object % is not at offset %', [first + k, off]);
        Emit('0000000000');
      end
      else
        Emit(s, i, i + 10);
      Emit(s, i + 10, i + 18);
      Emit(#10);
      inc(i, 18);
      inc(k);
    end;
  until false;
end;

// the content of one stream, decoded and with what varies blanked
function TGoldenNormalizer.Stream(const Dict, Data: RawByteString;
  ObjNum: Int64): RawByteString;
var
  sub: TGoldenNormalizer;
  filter, typ: RawByteString;
  err: RawUtf8;
begin
  result := Data;
  filter := DictValue(Dict, '/Filter');
  if ((filter = '/FlateDecode') or (filter = '[/FlateDecode]')) and
     (Data = '') then
    Fail('object %: empty FlateDecode stream', [ObjNum])
  else if (filter = '/FlateDecode') or (filter = '[/FlateDecode]') then
    try
      // an error raises: an empty result is an empty stream
      result := UncompressZipString(pointer(Data), length(Data), nil, true);
    except
      Fail('object %: FlateDecode stream does not inflate', [ObjNum]);
      result := Data;
      exit;
    end
  else if filter <> '' then
  begin
    Fail('object %: unexpected /Filter %', [ObjNum, filter]);
    exit;
  end;
  typ := DictValue(Dict, '/Type');
  if typ = '/XRef' then
    result := XRefStream(Dict, result)
  else if typ = '/ObjStm' then
  begin
    // the objects inside are dictionaries like the ones at top level
    sub := TGoldenNormalizer.Create;
    try
      sub.fPdf := fPdf;
      sub.fOut := TRawByteStringStream.Create;
      try
        sub.Syntax(result, {TopLevel=}false);
        result := sub.fOut.DataString;
        err := sub.fError;
      finally
        sub.fOut.Free;
      end;
    finally
      sub.Free;
    end;
    if err <> '' then
      Fail('object stream %: %', [ObjNum, err]);
  end
  else if typ = '/Metadata' then
    result := BlankXmpDates(result);
end;

procedure TGoldenNormalizer.Syntax(const s: RawByteString; TopLevel: boolean);
var
  i, j, b, objStart, dataEnd, after: PtrInt;
  len, num1, num2, objNum, objGen, off, objOut, num1Pos, num2Pos, objPos: Int64;
  k: integer;
  found: boolean;
  tok, lastKey, dict, data, head: RawByteString;
  inId: boolean;
begin
  i := 1;
  lastKey := '';
  inId := false;
  num1 := -1;
  num2 := -1;
  objNum := -1;
  objGen := 0;
  objStart := 1;
  objOut := 0;
  num1Pos := 0;
  num2Pos := 0;
  objPos := 0;
  while (i <= length(s)) and (fError = '') do
    case s[i] of
      '%':
        begin // a comment, to the end of the line
          j := i;
          while (j <= length(s)) and not (s[j] in [#10, #13]) do
            inc(j);
          Emit(s, i, j);
          i := j;
        end;
      '(':
        begin
          j := i;
          if not SkipValue(s, j) then
          begin
            Fail('object %: literal string not closed', [objNum]);
            exit;
          end;
          tok := copy(s, i, j - i);
          // a date: (D:YYYYMMDDHHMMSS...)
          if ((lastKey = '/CreationDate') or (lastKey = '/ModDate')) and
             (length(tok) >= 18) and (tok[2] = 'D') and (tok[3] = ':') and
             IsDigits(tok, 4, 14) then
            ZeroDigits(tok, 4, 14);
          Emit(tok);
          lastKey := '';
          i := j;
        end;
      '<':
        if (i < length(s)) and (s[i + 1] = '<') then
        begin
          Emit('<<');
          inc(i, 2);
        end
        else
        begin // a hex string
          j := i;
          if not SkipValue(s, j) then
          begin
            Fail('object %: hex string not closed', [objNum]);
            exit;
          end;
          tok := copy(s, i, j - i);
          if inId then // the file identifier, random per document
            for b := 2 to length(tok) - 1 do
              if not (tok[b] in PDF_WHITE) then
                tok[b] := '0';
          Emit(tok);
          i := j;
        end;
      '[':
        begin
          inId := lastKey = '/ID';
          Emit('[');
          inc(i);
        end;
      ']':
        begin
          inId := false;
          Emit(']');
          inc(i);
        end;
      '/':
        begin // a name
          j := i + 1;
          while (j <= length(s)) and
                not (s[j] in PDF_WHITE + PDF_DELIM) do
            inc(j);
          tok := copy(s, i, j - i);
          // '/ABCDEF+Name': the subset tag, six random capitals
          if (length(tok) > 8) and (tok[8] = '+') then
          begin
            b := 2;
            while (b <= 7) and (tok[b] in ['A'..'Z']) do
              inc(b);
            if b = 8 then
              FillCharFast(tok[2], 6, ord('A'));
          end;
          Emit(tok);
          lastKey := tok;
          i := j;
        end;
      '0'..'9', '+', '-', '.':
        begin
          j := i;
          while (j <= length(s)) and (s[j] in ['0'..'9', '+', '-', '.']) do
            inc(j);
          tok := copy(s, i, j - i);
          num1 := num2;
          num1Pos := num2Pos;
          num2 := ReadIntValue(tok);
          num2Pos := i - 1; // 0-based offset of the number
          if (lastKey = '/Length') and TopLevel then
            tok := '0'; // varies with the deflated dates: checked at 'stream'
          Emit(tok);
          lastKey := '';
          i := j;
        end;
      'a'..'z', 'A'..'Z':
        begin // a keyword
          j := i;
          while (j <= length(s)) and (s[j] in ['a'..'z', 'A'..'Z']) do
            inc(j);
          if (j <= length(s)) and not (s[j] in PDF_WHITE + PDF_DELIM) then
          begin
            Fail('object %: keyword % not delimited', [objNum, copy(s, i, j - i)]);
            exit;
          end;
          tok := copy(s, i, j - i);
          i := j;
          lastKey := '';
          if not TopLevel then
            Emit(tok)
          else if tok = 'obj' then
          begin
            objNum := num1;
            objGen := num2;
            objPos := num1Pos;
            objStart := i;
            objOut := fOut.Position;
            Emit(tok);
          end
          else if tok = 'stream' then
          begin
            // the stream dictionary is the text since 'obj'
            dict := copy(s, objStart, i - 6 - objStart);
            tok := DictValue(dict, '/Length');
            b := 1;
            len := ReadInt(tok, b);
            if (len < 0) or (b <= length(tok)) then
            begin
              Fail('object % %: /Length % is not a direct integer',
                [objNum, objGen, tok]);
              exit;
            end;
            if (i <= length(s)) and (s[i] = #13) then
              inc(i);
            if (i > length(s)) or (s[i] <> #10) then
            begin
              Fail('object % %: no end of line after stream', [objNum, objGen]);
              exit;
            end;
            inc(i);
            if len > length(s) - i + 1 then
            begin
              Fail('object % %: /Length % beyond the end of the file',
                [objNum, objGen, len]);
              exit;
            end;
            dataEnd := i + len;
            b := dataEnd;
            if (b <= length(s)) and (s[b] = #13) then
              inc(b);
            if (b <= length(s)) and (s[b] = #10) then
              inc(b);
            if (b > length(s) - 8) or
               not CompareMem(@s[b], PAnsiChar('endstream'), 9) then
            begin
              Fail('object % %: /Length % does not end at endstream',
                [objNum, objGen, len]);
              exit;
            end;
            after := b + 9; // after endstream
            data := Stream(dict, copy(s, i, len), objNum);
            if DictValue(dict, '/Type') = '/XRef' then
            begin
              AddInt64(fXRefOffsets, objPos);
              // /W follows the file size: written in its canonical form, as
              // the rows are written as text
              head := copy(fOut.DataString, objOut + 1, maxInt);
              fOut.Size := objOut;
              fOut.Position := objOut;
              // the pieces are emitted, not concatenated: FPC 3.2.2 i386 lost
              // a RawByteString of code page CP_RAWBYTESTRING in a concatenation
              if DictValuePos(head, '/W', b, j) then
              begin
                Emit(head, 1, b);
                Emit('[*]');
                Emit(head, j, length(head) + 1);
              end
              else
                Emit(head);
            end;
            Emit('stream'#10);
            Emit(data);
            Emit(#10'endstream');
            i := after;
          end
          else if tok = 'xref' then
          begin
            AddInt64(fXRefOffsets, i - 5); // 0-based offset of the keyword
            Emit(tok);
            XRefTable(s, i);
          end
          else if tok = 'startxref' then
          begin
            SkipWhite(s, i);
            off := ReadInt(s, i);
            found := false;
            for k := 0 to high(fXRefOffsets) do
              if fXRefOffsets[k] = off then
                found := true;
            if not found then
              Fail('startxref % points to neither xref nor an XRef stream', [off]);
            Emit(tok);
            Emit(#10'0');
          end
          else
            Emit(tok);
        end;
    else
      begin
        Emit(s, i, i + 1);
        inc(i);
      end;
    end;
end;

function TGoldenNormalizer.Normalize(const Pdf: RawByteString;
  out Error: RawUtf8): RawByteString;
begin
  fPdf := Pdf;
  fError := '';
  fOut := TRawByteStringStream.Create;
  try
    Syntax(Pdf, {TopLevel=}true);
    result := fOut.DataString;
  finally
    FreeAndNil(fOut);
  end;
  Error := fError;
end;

function GoldenNormalize(const Pdf: RawByteString; out Error: RawUtf8): RawByteString;
var
  n: TGoldenNormalizer;
begin
  n := TGoldenNormalizer.Create;
  try
    result := n.Normalize(Pdf, Error);
  finally
    n.Free;
  end;
end;

// the line around offset i of s, control characters as '.'
function Excerpt(const s: RawByteString; i: PtrInt): RawUtf8;
var
  b, e, k: PtrInt;
begin
  b := i - 40;
  if b < 1 then
    b := 1;
  e := i + 40;
  if e > length(s) then
    e := length(s);
  result := copy(s, b, e - b + 1);
  for k := 1 to length(result) do
    if (result[k] < ' ') or (result[k] > #126) then
      result[k] := '.';
end;

// the "N 0 obj" header before offset i of s, or ''
function ObjectAt(const s: RawByteString; i: PtrInt): RawUtf8;
var
  k, b: PtrInt;
begin
  result := '';
  k := i;
  while k > 4 do
  begin
    if (s[k] = 'j') and (s[k - 1] = 'b') and (s[k - 2] = 'o') and
       (s[k - 3] = ' ') then
    begin
      b := k - 3;
      while (b > 1) and (s[b - 1] in ['0'..'9', ' ']) do
        dec(b);
      result := TrimU(copy(s, b, k - b + 1));
      exit;
    end;
    dec(k);
  end;
end;


{ TPdfGoldenTestCase }

procedure TPdfGoldenTestCase.CheckGolden(const Name: RawUtf8;
  const Pdf: RawByteString);
var
  fn: TFileName;
  expected, actual: RawByteString;
  err: RawUtf8;
  i, n: PtrInt;
begin
  fn := GoldenFolder + Utf8ToString(Name) + '.pdf';
  if GoldenRecord then
  begin
    // a broken file would make a baseline every later run fails against
    GoldenNormalize(Pdf, err);
    if CheckFailed(err = '', FormatUtf8('%: %', [Name, err])) then
      exit;
    EnsureDirectoryExists(GoldenFolder);
    Check(FileFromString(Pdf, fn), 'golden file written');
    AddConsole('recorded %', [fn]);
    exit;
  end;
  actual := GoldenNormalize(Pdf, err);
  if CheckFailed(err = '', FormatUtf8('%: %', [Name, err])) then
    exit;
  if not FileExists(fn) then
  begin
    Check(true, 'SKIP: no golden baseline - run test_runner --golden-record');
    exit;
  end;
  expected := GoldenNormalize(StringFromFile(fn), err);
  if CheckFailed(err = '', FormatUtf8('% golden file: %', [Name, err])) then
    exit;
  if expected = actual then
  begin
    Check(true);
    exit;
  end;
  // keep the new output beside the baseline for a viewer or a diff tool
  FileFromString(Pdf, GoldenFolder + Utf8ToString(Name) + '.actual.pdf');
  n := length(expected);
  if length(actual) < n then
    n := length(actual);
  i := 1;
  while (i <= n) and
        (expected[i] = actual[i]) do
    inc(i);
  TestFailed('% differs from the golden file at byte % (object %, sizes % / %)' +
    #10'  expected: %'#10'  actual:   %', [Name, i, ObjectAt(expected, i),
    length(expected), length(actual), Excerpt(expected, i), Excerpt(actual, i)]);
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
