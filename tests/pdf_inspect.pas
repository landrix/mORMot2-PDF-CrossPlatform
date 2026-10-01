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

implementation

uses
  mormot.lib.z;

function InflatePdf(const s: RawUtf8): RawUtf8;
var
  p, q, body, e: integer;
  z: RawUtf8;
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
    if PosEx('/FlateDecode', copy(s, p, q - p)) > 0 then
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

end.
