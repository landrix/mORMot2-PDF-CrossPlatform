/// ZUGFeRD / Factur-X Demo — mORMot2 PDF Cross-Platform
// Reads the invoice data from factur-x.xml, draws the invoice with TGDIPages
// and embeds the same file into the PDF/A-3 it exports: a tagged hybrid
// invoice of the profile EN 16931, for Germany (ZUGFeRD) and France
// (Factur-X). Invoices to German authorities take pure XML, not a PDF.
//
// Worth noting:
// - factur-x.xml is third-party test data: test case 01.01a of the KoSIT
//   xrechnung-testsuite, Apache-2.0, with its specification identifier changed
//   to EN 16931 (see THIRD_PARTY.md). The page is drawn from what ReadInvoice
//   finds in it, so the page and the embedded data cannot differ
// - ReadInvoice is a demo reader, not an XML parser: fixed paths and
//   prefixes, no entities, no validation. TInvoice is where the data of your
//   own application - a database, an ERP export - would go in instead
// - the labels are ASCII; every umlaut on the page comes from the UTF-8 XML,
//   so this source builds unchanged with FPC, Delphi 7 and Delphi 2010
// - ExportPdfLevel, ExportPdfTagged and the font mode are set before the first
//   NewPage: the font flags decide which metrics the layout is measured with
// - AddExportPdfAttachment and ExportPdfMetadataExtension give the export the
//   associated file and the fx: XMP properties ZUGFeRD / Factur-X require
//
// Switches, to tell the sources of a checker failure apart:
//   --no-attachment   leave factur-x.xml out (the page is still read from it)
//   --untagged        no structure tree (PDF/A without PDF/UA)
program zugferd_demo;

{$I mormot.defines.inc}
{$APPTYPE CONSOLE}

uses
  {$ifdef FPC}
  Interfaces,   // registers the widgetset (Win32 on Windows, GTK2/Cocoa on Unix)
  {$endif FPC}
  SysUtils,
  Classes,
  Graphics,
  mormot.core.base,
  mormot.core.os,
  mormot.core.unicode,
  mormot.ui.report;

const
  XML_NAME = 'factur-x.xml';
  PROFILE = 'EN 16931';

type
  /// one invoice line, the values as the XML holds them
  TInvoiceItem = record
    Name, SellerId, Description, ClassCode, Note, OrderLine: RawUtf8;
    PeriodStart, PeriodEnd: RawUtf8;
    Quantity, Price, VatRate, Total: RawUtf8;
  end;

  /// the invoice as the page shows it - amounts with a decimal point, dates
  // as yyyymmdd, formatted only when drawn
  TInvoice = record
    Number, IssueDate, Note, BuyerReference: RawUtf8;
    SellerName, SellerTradingName, SellerDescription, SellerVatId: RawUtf8;
    SellerStreet, SellerPostcode, SellerCity, SellerCountry: RawUtf8;
    SellerContact, SellerPhone, SellerEmail: RawUtf8;
    BuyerId, BuyerName, BuyerEmail: RawUtf8;
    BuyerStreet, BuyerPostcode, BuyerCity, BuyerCountry: RawUtf8;
    Currency, Iban, PaymentTerms: RawUtf8;
    NetTotal, TaxBasis, TaxRate, TaxAmount, GrandTotal: RawUtf8;
    Items: array of TInvoiceItem;
  end;

var
  WithAttachment, WithTags: boolean;
  Xml: RawUtf8;
  Invoice: TInvoice;
  i: integer;

{ ---------- reading factur-x.xml ---------- }

// the content of the next <Tag>...</Tag> from From on, which then points
// behind it; '' when there is none. <Tag/> and <TagMore> do not match
function NextElement(const Xml, Tag: RawUtf8; var From: PtrInt): RawUtf8;
var
  p, q, e: PtrInt;
begin
  result := '';
  p := From - 1;
  repeat
    p := PosEx('<' + Tag, Xml, p + 1);
    if p = 0 then
    begin
      From := length(Xml) + 1;
      exit;
    end;
    q := p + length(Tag) + 1;
  until (q <= length(Xml)) and (Xml[q] in ['>', ' ']);
  q := PosEx('>', Xml, q);
  e := PosEx('</' + Tag + '>', Xml, q);
  if (q = 0) or (e = 0) then
  begin
    From := length(Xml) + 1;
    exit;
  end;
  result := copy(Xml, q + 1, e - q - 1);
  From := e + length(Tag) + 3;
end;

// the text at the end of a path of nested elements, '' when one is missing
function XmlText(const Xml: RawUtf8; const Path: array of RawUtf8): RawUtf8;
var
  n: integer;
  From: PtrInt;
begin
  result := Xml;
  for n := 0 to high(Path) do
  begin
    From := 1;
    result := NextElement(result, Path[n], From);
  end;
  result := TrimU(result);
end;

function ReadItem(const Line: RawUtf8): TInvoiceItem;
begin
  result.Name := XmlText(Line, ['ram:SpecifiedTradeProduct', 'ram:Name']);
  result.SellerId := XmlText(Line, ['ram:SpecifiedTradeProduct',
    'ram:SellerAssignedID']);
  result.Description := XmlText(Line, ['ram:SpecifiedTradeProduct',
    'ram:Description']);
  result.ClassCode := XmlText(Line, ['ram:SpecifiedTradeProduct',
    'ram:DesignatedProductClassification', 'ram:ClassCode']);
  result.Note := XmlText(Line, ['ram:AssociatedDocumentLineDocument',
    'ram:IncludedNote', 'ram:Content']);
  result.OrderLine := XmlText(Line, ['ram:SpecifiedLineTradeAgreement',
    'ram:BuyerOrderReferencedDocument', 'ram:LineID']);
  result.Price := XmlText(Line, ['ram:SpecifiedLineTradeAgreement',
    'ram:NetPriceProductTradePrice', 'ram:ChargeAmount']);
  result.Quantity := XmlText(Line, ['ram:SpecifiedLineTradeDelivery',
    'ram:BilledQuantity']);
  result.VatRate := XmlText(Line, ['ram:SpecifiedLineTradeSettlement',
    'ram:ApplicableTradeTax', 'ram:RateApplicablePercent']);
  result.PeriodStart := XmlText(Line, ['ram:SpecifiedLineTradeSettlement',
    'ram:BillingSpecifiedPeriod', 'ram:StartDateTime', 'udt:DateTimeString']);
  result.PeriodEnd := XmlText(Line, ['ram:SpecifiedLineTradeSettlement',
    'ram:BillingSpecifiedPeriod', 'ram:EndDateTime', 'udt:DateTimeString']);
  result.Total := XmlText(Line, ['ram:SpecifiedLineTradeSettlement',
    'ram:SpecifiedTradeSettlementLineMonetarySummation', 'ram:LineTotalAmount']);
end;

// fills TInvoice from a CII invoice of the profile EN 16931 - only the fields
// this page shows, and only one VAT rate
function ReadInvoice(const Xml: RawUtf8): TInvoice;
var
  Doc, Trade, Agreement, Seller, Buyer, Settlement, Line: RawUtf8;
  From: PtrInt;
  n: integer;
begin
  Doc := XmlText(Xml, ['rsm:CrossIndustryInvoice', 'rsm:ExchangedDocument']);
  result.Number := XmlText(Doc, ['ram:ID']);
  result.IssueDate := XmlText(Doc, ['ram:IssueDateTime', 'udt:DateTimeString']);
  result.Note := XmlText(Doc, ['ram:IncludedNote', 'ram:Content']);
  Trade := XmlText(Xml, ['rsm:CrossIndustryInvoice',
    'rsm:SupplyChainTradeTransaction']);
  // the parties
  Agreement := XmlText(Trade, ['ram:ApplicableHeaderTradeAgreement']);
  result.BuyerReference := XmlText(Agreement, ['ram:BuyerReference']);
  Seller := XmlText(Agreement, ['ram:SellerTradeParty']);
  result.SellerName := XmlText(Seller, ['ram:Name']);
  result.SellerTradingName := XmlText(Seller, ['ram:SpecifiedLegalOrganization',
    'ram:TradingBusinessName']);
  result.SellerDescription := XmlText(Seller, ['ram:Description']);
  result.SellerVatId := XmlText(Seller, ['ram:SpecifiedTaxRegistration', 'ram:ID']);
  result.SellerStreet := XmlText(Seller, ['ram:PostalTradeAddress', 'ram:LineOne']);
  result.SellerPostcode := XmlText(Seller, ['ram:PostalTradeAddress',
    'ram:PostcodeCode']);
  result.SellerCity := XmlText(Seller, ['ram:PostalTradeAddress', 'ram:CityName']);
  result.SellerCountry := XmlText(Seller, ['ram:PostalTradeAddress',
    'ram:CountryID']);
  result.SellerContact := XmlText(Seller, ['ram:DefinedTradeContact',
    'ram:PersonName']);
  result.SellerPhone := XmlText(Seller, ['ram:DefinedTradeContact',
    'ram:TelephoneUniversalCommunication', 'ram:CompleteNumber']);
  result.SellerEmail := XmlText(Seller, ['ram:DefinedTradeContact',
    'ram:EmailURIUniversalCommunication', 'ram:URIID']);
  Buyer := XmlText(Agreement, ['ram:BuyerTradeParty']);
  result.BuyerId := XmlText(Buyer, ['ram:ID']);
  result.BuyerName := XmlText(Buyer, ['ram:Name']);
  result.BuyerStreet := XmlText(Buyer, ['ram:PostalTradeAddress', 'ram:LineOne']);
  result.BuyerPostcode := XmlText(Buyer, ['ram:PostalTradeAddress',
    'ram:PostcodeCode']);
  result.BuyerCity := XmlText(Buyer, ['ram:PostalTradeAddress', 'ram:CityName']);
  result.BuyerCountry := XmlText(Buyer, ['ram:PostalTradeAddress', 'ram:CountryID']);
  result.BuyerEmail := XmlText(Buyer, ['ram:URIUniversalCommunication',
    'ram:URIID']);
  // payment and totals
  Settlement := XmlText(Trade, ['ram:ApplicableHeaderTradeSettlement']);
  result.Currency := XmlText(Settlement, ['ram:InvoiceCurrencyCode']);
  result.Iban := XmlText(Settlement, ['ram:SpecifiedTradeSettlementPaymentMeans',
    'ram:PayeePartyCreditorFinancialAccount', 'ram:IBANID']);
  result.PaymentTerms := XmlText(Settlement, ['ram:SpecifiedTradePaymentTerms',
    'ram:Description']);
  result.TaxBasis := XmlText(Settlement, ['ram:ApplicableTradeTax',
    'ram:BasisAmount']);
  result.TaxRate := XmlText(Settlement, ['ram:ApplicableTradeTax',
    'ram:RateApplicablePercent']);
  result.TaxAmount := XmlText(Settlement, ['ram:ApplicableTradeTax',
    'ram:CalculatedAmount']);
  result.NetTotal := XmlText(Settlement,
    ['ram:SpecifiedTradeSettlementHeaderMonetarySummation', 'ram:LineTotalAmount']);
  result.GrandTotal := XmlText(Settlement,
    ['ram:SpecifiedTradeSettlementHeaderMonetarySummation', 'ram:GrandTotalAmount']);
  // the lines
  result.Items := nil;
  n := 0;
  From := 1;
  repeat
    Line := NextElement(Trade, 'ram:IncludedSupplyChainTradeLineItem', From);
    if Line = '' then
      break;
    SetLength(result.Items, n + 1);
    result.Items[n] := ReadItem(Line);
    inc(n);
  until false;
end;

{ ---------- formatting for a German invoice ---------- }

// 336.9 -> 336,90 and 1234.5 -> 1.234,50
function Amount(const Value: RawUtf8): RawUtf8;
var
  Sign, Int, Frac: RawUtf8;
  p: PtrInt;
  n: integer;
begin
  Int := Value;
  Sign := '';
  if (Int <> '') and (Int[1] = '-') then
  begin
    Sign := '-';
    delete(Int, 1, 1);
  end;
  Frac := '';
  p := PosEx('.', Int);
  if p > 0 then
  begin
    Frac := copy(Int, p + 1, maxInt);
    Int := copy(Int, 1, p - 1);
  end;
  Frac := copy(Frac + '00', 1, 2);
  result := '';
  n := length(Int);
  while n > 3 do
  begin
    result := '.' + copy(Int, n - 2, 3) + result;
    dec(n, 3);
  end;
  result := Sign + copy(Int, 1, n) + result + ',' + Frac;
end;

// a quantity or a rate: 1 -> 1, 2.5 -> 2,5
function Decimal(const Value: RawUtf8): RawUtf8;
begin
  result := StringReplaceAll(Value, '.', ',');
end;

// 20160404 -> 04.04.2016
function GermanDate(const Value: RawUtf8): RawUtf8;
begin
  if length(Value) = 8 then
    result := copy(Value, 7, 2) + '.' + copy(Value, 5, 2) + '.' +
      copy(Value, 1, 4)
  else
    result := Value;
end;

// DE79000000001234567890 -> DE79 0000 0000 1234 5678 90
function IbanGroups(const Iban: RawUtf8): RawUtf8;
var
  n: integer;
begin
  result := '';
  for n := 1 to length(Iban) do
  begin
    if (n > 1) and ((n - 1) mod 4 = 0) then
      result := result + ' ';
    result := result + copy(Iban, n, 1); // Iban[n], a char, would convert on Unicode Delphi
  end;
end;

// "a, b, c" from the parts that are not empty
function Join(const Parts: array of RawUtf8): RawUtf8;
var
  n: integer;
begin
  result := '';
  for n := 0 to high(Parts) do
    if Parts[n] <> '' then
      if result = '' then
        result := Parts[n]
      else
        result := result + ', ' + Parts[n];
end;

{ ---------- the page ---------- }

// the item columns; 18000 = A4 (21000) minus the two 15 mm margins.
// Built at runtime: Delphi 7 has no constants for dynamic array fields
function ItemTableLayout: TTableLayout;
begin
  Finalize(result);
  FillChar(result, SizeOf(result), 0);
  SetLength(result.ColumnWidths, 5);
  result.ColumnWidths[0] := 8400;  // Bezeichnung
  result.ColumnWidths[1] := 1800;  // Menge
  result.ColumnWidths[2] := 2800;  // Einzelpreis
  result.ColumnWidths[3] := 1600;  // USt
  result.ColumnWidths[4] := 3400;  // Betrag
  SetLength(result.ColumnAligns, 5);
  result.ColumnAligns[0] := tcaLeft;
  result.ColumnAligns[1] := tcaRight;
  result.ColumnAligns[2] := tcaRight;
  result.ColumnAligns[3] := tcaRight;
  result.ColumnAligns[4] := tcaRight;
  result.HeaderFontStyle := [fsBold];
  result.HeaderBkColor := $F0E0D8;       // light blue (BGR)
  result.BodyBkColor := clWhite;
  result.AlternateRowColor := $FAF4F0;
  // the totals: bold on white, not in the header's colour
  result.FooterFontStyle := [fsBold];
  result.FooterBkColor := clWhite;
  result.GridColor := clSilver;          // quieter than the default black
end;

procedure DefineFormat(Report: TGDIPages; const Name, FontName: RawUtf8;
  Size: integer; Style: TFontStyles; Color: TColor; Before, After: integer);
var
  Fmt: TReportFormat;
begin
  Finalize(Fmt);
  FillChar(Fmt, SizeOf(Fmt), 0);
  Fmt.FontName := FontName;
  Fmt.FontSize := Size;
  Fmt.FontStyle := Style;
  Fmt.Color := Color;
  Fmt.SpaceBefore := Before;
  Fmt.SpaceAfter := After;
  Report.DefineFormat(Name, Fmt);
end;

procedure DrawInvoice(Report: TGDIPages; const Inv: TInvoice; const Sans: RawUtf8);
var
  n: integer;
  Item: TInvoiceItem;
  Name, Period: RawUtf8;
begin
  DefineFormat(Report, 'H1', Sans, 20, [fsBold], clBlack, 0, 600);
  DefineFormat(Report, 'P', Sans, 10, [], clBlack, 0, 250);
  Report.SetFont(Sans, 10);
  Report.DrawHeading(1, 'Rechnung ' + Inv.Number);
  // parties, dates and references
  Report.DrawParagraph('Von: ' + Join([Inv.SellerName + ' (' +
    Inv.SellerTradingName + ')', Inv.SellerStreet,
    Inv.SellerPostcode + ' ' + Inv.SellerCity, Inv.SellerCountry]));
  Report.DrawParagraph(Join(['USt-IdNr. ' + Inv.SellerVatId,
    Inv.SellerDescription]));
  Report.DrawParagraph('Kontakt: ' + Join([Inv.SellerContact,
    'Tel. ' + Inv.SellerPhone, Inv.SellerEmail]));
  Report.AddVerticalSpace(2);
  Report.DrawParagraph('An: ' + Join([Inv.BuyerName + ' (' + Inv.BuyerId + ')',
    Inv.BuyerStreet, Inv.BuyerPostcode + ' ' + Inv.BuyerCity, Inv.BuyerCountry,
    Inv.BuyerEmail]));
  Report.AddVerticalSpace(2);
  Report.DrawParagraph('Rechnungsdatum: ' + GermanDate(Inv.IssueDate));
  Report.DrawParagraph('Ihre Referenz: ' + Inv.BuyerReference);
  Report.AddVerticalSpace(4);
  // the items; the table breaks the page and repeats its header on its own
  Report.BeginTable(ItemTableLayout);
  Report.DrawTableHeader(['Bezeichnung', 'Menge', 'Einzelpreis', 'USt', 'Betrag']);
  for n := 0 to high(Inv.Items) do
  begin
    Item := Inv.Items[n];
    Name := Item.Name;
    if Item.SellerId <> '' then
      Name := Name + ', Art.-Nr. ' + Item.SellerId;
    Report.DrawTableRow([Name, Decimal(Item.Quantity), Amount(Item.Price),
      Decimal(Item.VatRate) + ' %', Amount(Item.Total)]);
  end;
  Report.DrawTableFooter(['Summe netto', '', '', '', Amount(Inv.NetTotal)]);
  Report.DrawTableFooter(['Umsatzsteuer ' + Decimal(Inv.TaxRate) + ' % auf ' +
    Amount(Inv.TaxBasis), '', '', '', Amount(Inv.TaxAmount)]);
  Report.DrawTableFooter(['Gesamtbetrag (' + Inv.Currency + ')', '', '', '',
    Amount(Inv.GrandTotal)]);
  Report.EndTable;
  Report.AddVerticalSpace(6);
  // what the items say beyond the table
  for n := 0 to high(Inv.Items) do
  begin
    Item := Inv.Items[n];
    Period := '';
    if Item.PeriodStart <> '' then
      Period := 'Abrechnungszeitraum ' + GermanDate(Item.PeriodStart) + ' bis ' +
        GermanDate(Item.PeriodEnd);
    if (Item.Description <> '') or (Item.Note <> '') then
      Report.DrawParagraph(Item.Name + ': ' + Join([Item.Description,
        'ISSN ' + Item.ClassCode, Period, 'Bestellposition ' + Item.OrderLine]) +
        '. ' + Item.Note);
  end;
  // payment and terms
  Report.DrawParagraph(Inv.PaymentTerms + ' Bankverbindung: IBAN ' +
    IbanGroups(Inv.Iban) + '.');
  if Inv.Note <> '' then
    Report.DrawParagraph(Inv.Note);
  // where the data comes from - also required by its license
  Report.AddVerticalSpace(10);
  DefineFormat(Report, 'P', Sans, 8, [], $505050, 0, 100);
  if WithAttachment then
    Report.DrawParagraph('Die Rechnungsdaten sind als ' + XML_NAME +
      ' (ZUGFeRD / Factur-X, Profil ' + PROFILE + ') in dieses PDF eingebettet.')
  else
    Report.DrawParagraph('Ohne eingebettete Rechnungsdaten erzeugt ' +
      '(--no-attachment), die Seite ist aus ' + XML_NAME + ' gelesen.');
  Report.DrawParagraph('Nach Testdatensatz 01.01a der KoSIT xrechnung-testsuite, ' +
    'Apache License 2.0, angepasst - siehe THIRD_PARTY.md der Demo.');
end;

{ ---------- the program ---------- }

{ <demo>_<os>_<cpu>_<compiler>.pdf next to the executable, e.g.
  zugferd_demo_windows_x64_free-pascal-3.2.2.pdf or ..._x86_delphi-7.pdf: the runs
  of all platforms and compilers can then share one folder for checking.
  OS_KIND names the distribution on Linux }
function PdfFileName: TFileName;
var
  compiler: RawUtf8;
begin
  compiler := StringReplaceAll(COMPILER_VERSION, [' 32 bit', '', ' 64 bit', '']);
  result := Executable.ProgramFilePath + Utf8ToString(LowerCase('zugferd_demo_' +
    ShortStringToAnsi7String(OS_NAME[OS_KIND]) + '_' + CPU_ARCH_TEXT + '_' +
    StringReplaceAll(compiler, ' ', '-') + '.pdf'));
end;

// factur-x.xml sits beside the .lpr; the executable is two levels below it
function LoadXml: RawUtf8;
begin
  result := StringFromFile(XML_NAME);
  if result = '' then
    result := StringFromFile(Executable.ProgramFilePath + '..' + PathDelim +
      '..' + PathDelim + XML_NAME);
end;

procedure ExportInvoice(const Inv: TInvoice; const FileName: TFileName);
var
  Report: TGDIPages;
  SansFont, SerifFont, MonoFont: RawUtf8;
  Stream: TFileStream;
begin
  Report := TGDIPages.Create(nil);
  try
    // all of this before the first NewPage - see the header
    Report.ExportPdfLevel := pdfa3U;
    Report.ExportPdfTagged := WithTags;
    Report.ExportPdfStandardFonts := false; // PDF/A embeds every font
    Report.ExportPdfEmbeddedTTF := true;
    Report.ExportPdfLanguage := 'de';
    Report.UseOutlines := true;             // PDF/UA: a bookmark per heading
    Report.GetExportFonts(SansFont, SerifFont, MonoFont);
    Report.PaperSize := psA4;
    Report.Orientation := poPortrait;
    Report.MarginLeft := 1500;
    Report.MarginRight := 1500;
    Report.MarginTop := 1500;
    Report.MarginBottom := 1500;
    Report.Title := 'Rechnung ' + Inv.Number;
    Report.Author := Inv.SellerName;
    Report.Subject := 'Rechnung mit eingebetteten ZUGFeRD / Factur-X-Daten (' +
      PROFILE + ')';
    Report.NewPage;
    DrawInvoice(Report, Inv, SansFont);
    Report.EndDoc;
    // the invoice data, under the file name ZUGFeRD and Factur-X prescribe,
    // and the XMP properties which point a reader at it
    if WithAttachment then
    begin
      Report.AddExportPdfAttachment(Xml, XML_NAME, 'Factur-X invoice data',
        'text/xml', afrAlternative);
      Report.ExportPdfMetadataExtension := PdfMetadataFacturX(PROFILE, XML_NAME);
    end;
    Stream := TFileStream.Create(FileName, fmCreate);
    try
      if not Report.ExportPdfStream(Stream) then
        raise Exception.Create('PDF export failed');
    finally
      Stream.Free;
    end;
  finally
    Report.Free;
  end;
end;

begin
  WithAttachment := true;
  WithTags := true;
  for i := 1 to ParamCount do
    if ParamStr(i) = '--no-attachment' then
      WithAttachment := false
    else if ParamStr(i) = '--untagged' then
      WithTags := false;
  Xml := LoadXml;
  if Xml = '' then
  begin
    writeln('Cannot find ', XML_NAME, ' - run from the demo folder');
    ExitCode := 1;
    exit;
  end;
  Invoice := ReadInvoice(Xml);
  ExportInvoice(Invoice, PdfFileName);
  writeln('PDF saved to ', PdfFileName);
end.
