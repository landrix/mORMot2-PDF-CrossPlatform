/// Reading a written PDF back for checks: shared by the tests and pdfcheck
// - text-level only, no object model: a test tool, not a PDF reader
unit pdf_inspect;

interface

{$I mormot.defines.inc}

uses
  mormot.core.base;

/// the file with every FlateDecode stream inflated in place
// - PDF 1.5+ object streams hide the catalog, fonts and file specifications;
// the /Length entries keep their compressed values
function InflatePdf(const s: RawUtf8): RawUtf8;

/// the file inflated, with what changes from run to run masked
// - masked: dates, /ID, XMP uuids, subset prefixes, the stream lengths, and the
// offsets of the cross-reference stream and startxref, which move with any
// length change
// - two runs of one program on one platform give the same text
function NormalizePdf(const s: RawUtf8): RawUtf8;

/// the roles of the structure tree with their counts, one 'Role count' per
// line, sorted by role; '' for an untagged file
function PdfStructRoles(const s: RawUtf8): RawUtf8;

/// compare two normalized files: true when equal, otherwise Diff names the
// first differing line of each
function ComparePdfText(const a, b: RawUtf8; out Diff: RawUtf8): boolean;

implementation

uses
  mormot.core.text, // Int32ToUtf8
  mormot.lib.z;

function InflateStreams(const s: RawUtf8; MaskXref: boolean): RawUtf8;
var
  p, q, body, e: integer;
  z, dict: RawUtf8;
begin
  result := '';
  p := 1;
  q := PosEx('stream', s, 1);
  while q > 0 do
  begin
    if (q > 3) and (copy(s, q - 3, 3) = 'end') then
    begin
      q := PosEx('stream', s, q + 6);
      continue;
    end;
    body := q + 6;
    if (body <= length(s)) and (s[body] = #13) then
      inc(body);
    if (body <= length(s)) and (s[body] = #10) then
      inc(body);
    e := PosEx('endstream', s, body);
    if e = 0 then
      break;
    result := result + copy(s, p, body - p);
    z := '';
    // only a stream dictionary carries a /Filter, so the text since the
    // previous stream names this stream's filter
    dict := copy(s, p, q - p);
    if MaskXref and (PosEx('/Type/XRef', dict) > 0) then
      z := '*'
    else if PosEx('/FlateDecode', dict) > 0 then
      try
        z := UncompressZipString(@s[body], e - body, nil, true);
      except
        z := '';
      end;
    if z = '' then
      z := copy(s, body, e - body);
    result := result + z;
    p := e;
    q := PosEx('stream', s, e + 9);
  end;
  result := result + copy(s, p, maxInt);
end;

function InflatePdf(const s: RawUtf8): RawUtf8;
begin
  result := InflateStreams(s, false);
end;

function IsDigit(c: AnsiChar): boolean;
begin
  result := (c >= '0') and (c <= '9');
end;

function IsUpper(c: AnsiChar): boolean;
begin
  result := (c >= 'A') and (c <= 'Z');
end;

function Matches(const s: RawUtf8; i: integer; const sub: RawUtf8): boolean;
begin
  result := (i + length(sub) - 1 <= length(s)) and
            (copy(s, i, length(sub)) = sub);
end;

// yyyy-mm-ddT as XMP writes its dates
function IsXmpDate(const s: RawUtf8; i: integer): boolean;
begin
  result := (i + 10 <= length(s)) and IsDigit(s[i]) and IsDigit(s[i + 1]) and
    IsDigit(s[i + 2]) and IsDigit(s[i + 3]) and (s[i + 4] = '-') and
    IsDigit(s[i + 5]) and IsDigit(s[i + 6]) and (s[i + 7] = '-') and
    IsDigit(s[i + 8]) and IsDigit(s[i + 9]) and (s[i + 10] = 'T');
end;

// /ABCDEF+ before a subset font name
function IsSubsetPrefix(const s: RawUtf8; i: integer): boolean;
var
  k: integer;
begin
  result := false;
  if (i + 7 > length(s)) or (s[i] <> '/') or (s[i + 7] <> '+') then
    exit;
  for k := i + 1 to i + 6 do
    if not IsUpper(s[k]) then
      exit;
  result := true;
end;

function NormalizePdf(const s: RawUtf8): RawUtf8;
var
  t: RawUtf8;
  i, n: integer;

  procedure Put(const v: RawUtf8);
  begin
    if n + length(v) > length(result) then
      SetLength(result, length(result) * 2 + 64);
    MoveFast(pointer(v)^, PByteArray(result)[n], length(v));
    inc(n, length(v));
  end;

begin
  t := InflateStreams(s, true);
  SetLength(result, length(t) + 64); // masks are rarely longer than the text
  n := 0;
  i := 1;
  while i <= length(t) do
    if Matches(t, i, '(D:') then
    begin
      Put('(D:*)');
      while (i <= length(t)) and (t[i] <> ')') do
        inc(i);
      inc(i);
    end
    else if Matches(t, i, '/ID[') then
    begin
      Put('/ID[*]');
      while (i <= length(t)) and (t[i] <> ']') do
        inc(i);
      inc(i);
    end
    else if Matches(t, i, 'uuid:') then
    begin
      Put('uuid:*');
      inc(i, 5);
      while (i <= length(t)) and (IsDigit(t[i]) or (t[i] = '-') or
            ((t[i] >= 'a') and (t[i] <= 'f')) or
            ((t[i] >= 'A') and (t[i] <= 'F'))) do
        inc(i);
    end
    else if Matches(t, i, 'startxref') then
    begin
      Put('startxref *');
      inc(i, 9);
      while (i <= length(t)) and (t[i] in [#10, #13, ' ', '0'..'9']) do
        inc(i);
    end
    else if IsXmpDate(t, i) then
    begin
      Put('*');
      while (i <= length(t)) and (t[i] in ['0'..'9', '-', ':', '.', 'T', 'Z', '+']) do
        inc(i);
    end
    else if Matches(t, i, '/Length') and (i + 7 <= length(t)) and
            (t[i + 7] in [' ', '0'..'9']) then
    begin
      // the compressed length, stale once the stream is inflated
      Put('/Length *');
      inc(i, 7);
      while (i <= length(t)) and (t[i] in [' ', '0'..'9']) do
        inc(i);
    end
    else if IsSubsetPrefix(t, i) then
    begin
      Put('/SUBSET+');
      inc(i, 8);
    end
    else
    begin
      if n >= length(result) then
        SetLength(result, length(result) * 2 + 64);
      PByteArray(result)[n] := ord(t[i]);
      inc(n);
      inc(i);
    end;
  SetLength(result, n);
end;

function PdfStructRoles(const s: RawUtf8): RawUtf8;
var
  t, role: RawUtf8;
  names: TRawUtf8DynArray;
  counts: TIntegerDynArray;
  p, d, e, r, k, j, tmp: integer;
  found: boolean;
begin
  result := '';
  t := InflatePdf(s);
  names := nil;
  counts := nil;
  p := PosEx('/StructElem', t, 1);
  while p > 0 do
  begin
    // the role is the /S of the dictionary that names itself a StructElem
    d := p;
    while (d > 1) and not Matches(t, d, '<<') do
      dec(d);
    e := PosEx('/StructElem', t, p + 11);
    if e = 0 then
      e := length(t) + 1;
    r := PosEx('/S/', t, d);
    if (r > 0) and (r < e) then
    begin
      inc(r, 3);
      k := r;
      while (k <= length(t)) and not (t[k] in
            ['/', '<', '>', '[', ']', '(', ')', ' ', #10, #13]) do
        inc(k);
      role := copy(t, r, k - r);
      found := false;
      for j := 0 to high(names) do
        if names[j] = role then
        begin
          inc(counts[j]);
          found := true;
          break;
        end;
      if not found then
      begin
        SetLength(names, length(names) + 1);
        SetLength(counts, length(counts) + 1);
        names[high(names)] := role;
        counts[high(counts)] := 1;
      end;
    end;
    p := PosEx('/StructElem', t, p + 11);
  end;
  // a handful of roles: an insertion sort is enough
  for k := 1 to high(names) do
  begin
    j := k;
    while (j > 0) and (names[j - 1] > names[j]) do
    begin
      role := names[j];
      names[j] := names[j - 1];
      names[j - 1] := role;
      tmp := counts[j];
      counts[j] := counts[j - 1];
      counts[j - 1] := tmp;
      dec(j);
    end;
  end;
  for k := 0 to high(names) do
    result := result + names[k] + ' ' + Int32ToUtf8(counts[k]) + #10;
end;

// the line of s that holds position i, at most 120 characters, the bytes
// outside ASCII shown as dots
function LineAt(const s: RawUtf8; i: integer; out LineNo: integer): RawUtf8;
var
  b, e, k: integer;
begin
  LineNo := 1;
  for k := 1 to i - 1 do
    if s[k] = #10 then
      inc(LineNo);
  b := i;
  while (b > 1) and (s[b - 1] <> #10) do
    dec(b);
  e := i;
  while (e <= length(s)) and (s[e] <> #10) do
    inc(e);
  if e - b > 120 then
  begin
    b := MaxPtrInt(b, i - 60);
    e := b + 120;
  end;
  result := copy(s, b, e - b);
  for k := 1 to length(result) do
    if (result[k] < ' ') or (result[k] > #126) then
      result[k] := '.';
end;

function ComparePdfText(const a, b: RawUtf8; out Diff: RawUtf8): boolean;
var
  i, n, la, lb: integer;
  ta, tb: RawUtf8;
begin
  Diff := '';
  result := a = b;
  if result then
    exit;
  n := length(a);
  if length(b) < n then
    n := length(b);
  i := 1;
  while (i <= n) and (a[i] = b[i]) do
    inc(i);
  ta := LineAt(a, i, la);
  tb := LineAt(b, i, lb);
  Diff := '  a, line ' + Int32ToUtf8(la) + ': ' + ta + #10 +
          '  b, line ' + Int32ToUtf8(lb) + ': ' + tb;
end;

end.
