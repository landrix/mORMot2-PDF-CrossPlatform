/// Cross-Platform PDF Engine: VCL/LCL Canvas Adapter
// - this unit is a part of the Open Source Synopse mORMot framework 2,
// licensed under a MPL/GPL/LGPL three license - see LICENSE.md
unit mormot.pdf.canvas;

{
  *****************************************************************************

    VCL/LCL Adapter of the PDF Engine
    - TPdfVclCanvas: the TCanvas bridge
    - TPdfDocumentGdi for GDI/TCanvas rendering support
    (the bridge with TPdfDocumentVcl and the TBitmap/TGraphic images on every
    platform; TPdfDocumentGdi and the paper size and resolution of the
    current printer on Windows; needs the VCL or the LCL: not for Delphi on
    Linux or Android)

  *****************************************************************************
}

interface

{$I mormot.defines.inc}

{$I mormot.pdf.defines.inc} // the same switches as mormot.pdf

// the LCL declares the TCanvas drawing methods virtual, Delphi 7's VCL does
// not: there they are reintroduced, and only a TPdfVclCanvas reference
// reaches them - a call through TCanvas draws on the measuring DC
{$ifdef FPC}
  {$define PDF_CANVASVIRTUAL}
{$endif FPC}

uses
  {$ifdef OSWINDOWS}
  windows,
  winspool,
  {$endif OSWINDOWS}
  {$ifdef OSWINDOWS}
  mormot.lib.uniscribe, // GdiScreenLogPixels; the engine uses it as well
  {$endif OSWINDOWS}
  mormot.lib.core,
  {$ifdef FPC}
  lcltype,
  lclproc,
  lclintf,
  graphtype,    // TRawImageDescription
  intfgraphics, // TLazIntfImage: the LCL's reader of any raw image layout
  fpimage,      // TFPColor
  {$ifdef USE_METAFILE}
  mormot.ui.core, // for TMetaFile definition
  {$endif USE_METAFILE}
  {$endif FPC}
  {$ifdef NEEDVCLPREFIX}
  vcl.graphics,
  {$else}
  graphics,
  {$endif NEEDVCLPREFIX}
  sysutils,
  types,
  classes,
  math,
  {$ifdef USE_SYNGDIPLUS}
  mormot.ui.gdiplus,
  {$else}
  {$ifdef OSWINDOWS}
  jpeg,
  {$endif OSWINDOWS}
  {$endif USE_SYNGDIPLUS}
  mormot.core.base,
  mormot.core.os,
  mormot.core.unicode,
  mormot.core.text,
  mormot.core.buffers,
  mormot.pdf.types,
  mormot.pdf;


{ ************ TPdfVclCanvas: the TCanvas bridge }

{$ifdef USE_GRAPHICS_UNIT}

type
  /// coordinate scaling state used by TPdfVclCanvas
  TPdfVclScale = record
    // origin offset in PDF points
    OriginX, OriginY: single;
    // pixels-per-point ratio (screen DPI / 72)
    ScaleX, ScaleY: single;
  end;

  // forward declaration
  TPdfDocumentVcl = class;

  /// TCanvas descendant that records draw operations directly into a TPdfCanvas
  // - replaces TMetaFileCanvas + TPdfEnum for cross-platform use
  // - synchronizes Pen/Brush/Font state to PDF graphics state before each draw
  TPdfVclCanvas = class(TCanvas)
  private
    fPdfCanvas: TPdfCanvas;
    fPdfDoc: TPdfDocumentVcl;
    fScale: TPdfVclScale;
    fMeasureDC: HDC; // dummy DC so the LCL fallback works without a widget
    fMeasurer: TPdfFontMeasurer; // metrics of the font the PDF really uses
    // cached state for SetFont (expensive) and SetRGBStrokeColor
    fLastPenColor: TColor;
    fLastPenWidth: integer;
    fLastFontName: string;
    fLastFontSize: integer;
    fLastFontStyle: TFontStyles;
    fLastFontColor: TColor;
    fStateValid: boolean;
    /// convert pixel X coordinate to PDF point
    function PxToPtX(AX: integer): single;
    /// convert pixel Y coordinate to PDF point (flips Y axis)
    function PxToPtY(AY: integer): single;
    /// sync pen state to PDF if changed
    procedure SyncPen;
    /// sync brush state to PDF if changed
    procedure SyncBrush;
    /// sync font state to PDF if changed
    procedure SyncFont;
    /// select the current Font on fMeasurer; false = fall back to the LCL
    function SetupMeasureFace: boolean;
    /// apply the PDF fill+stroke operation based on current brush/pen
    procedure FillAndStroke;
    /// draw already decoded text at a sub-pixel position
    procedure TextOutDecoded(X, Y: single; const AText: SynUnicode);
  protected
    {$ifdef PDF_CANVASVIRTUAL}
    procedure DoMoveTo(X, Y: integer); override; // TCanvas.MoveTo calls this
    procedure DoLineTo(X, Y: integer); override; // TCanvas.LineTo calls this
    {$else}
    procedure DoLineTo(X, Y: integer);
  public
    /// move the pen to X, Y, in canvas pixels - static in Delphi 7's TCanvas
    procedure MoveTo(X, Y: integer); reintroduce;
    /// draw a line with the current Pen to X, Y, in canvas pixels
    procedure LineTo(X, Y: integer); reintroduce;
    {$endif PDF_CANVASVIRTUAL}
  public
    /// draw AText at X, Y in canvas pixels, with the current Font
    procedure TextOut(X, Y: integer; const AText: string);
      {$ifdef PDF_CANVASVIRTUAL}override{$else}reintroduce{$endif};
    /// TextOut at a sub-pixel position
    // - TCanvas.TextOut only takes integers, so a caller that knows its layout
    // more precisely than whole screen pixels would lose that precision at the
    // 0.75 pt (1 px @ 96 DPI) grid; TGDIPages uses this overload to place text
    // at the position it actually computed
    procedure TextOutFrac(X, Y: single; const AText: string);
    /// TextOutFrac for UTF-8 text, the same on every compiler
    // - string is UTF-8 under FPC but ANSI under Delphi 7: RawUtf8 callers
    // such as TGDIPages use this method and need no conversion
    procedure TextOutUtf8(X, Y: single; const AText: RawUtf8);
    /// width of AText in canvas pixels, measured with the font the PDF uses
    // - TCanvas.TextWidth measures with the widgetset's own resolution of
    // Font.Name and rounds to whole screen pixels (0.75 pt @ 96 DPI), while
    // the glyphs are placed with the PDF font metrics: a bounding box derived
    // from it was up to 27% too narrow, and differed per platform
    // - falls back to the LCL when no PDF face resolves for Font.Name
    function TextWidthFrac(const AText: string): single;
    /// TextWidthFrac for UTF-8 text, see TextOutUtf8
    function TextWidthUtf8(const AText: RawUtf8): single;
    /// height of AText in canvas pixels, measured with the PDF font metrics
    // - matches where TextOut/TextOutFrac put the baseline, i.e. Font.Size
    // below the requested top, plus the descender of the current face
    function TextHeightFrac(const AText: string): single;
    /// integer TextExtent, rounded from TextWidthFrac/TextHeightFrac
    // - TextWidth and TextHeight below do not call it: they round
    // TextWidthFrac and TextHeightFrac themselves
    function TextExtent(const AText: string): TSize;
      {$ifdef PDF_CANVASVIRTUAL}override{$else}reintroduce{$endif};
    /// TextWidthFrac, rounded
    function TextWidth(const AText: string): integer;
      {$ifdef PDF_CANVASVIRTUAL}override{$else}reintroduce{$endif};
    /// TextHeightFrac, rounded
    function TextHeight(const AText: string): integer;
      {$ifdef PDF_CANVASVIRTUAL}override{$else}reintroduce{$endif};
    /// draw a rectangle with the current Pen and Brush, in canvas pixels
    procedure Rectangle(X1, Y1, X2, Y2: integer);
      {$ifdef PDF_CANVASVIRTUAL}override{$else}reintroduce{$endif};
    /// Rectangle at sub-pixel coordinates
    // - TCanvas.Rectangle only takes integers, so an edge derived from
    // TextWidthFrac would be snapped back to the 1 px grid
    procedure RectangleFrac(X1, Y1, X2, Y2: single);
    /// draw the ellipse inside a rectangle with the current Pen and Brush
    procedure Ellipse(X1, Y1, X2, Y2: integer);
      {$ifdef PDF_CANVASVIRTUAL}override{$else}reintroduce{$endif};
    /// draw a rectangle with corners rounded by an X3 x Y3 ellipse
    procedure RoundRect(X1, Y1, X2, Y2, X3, Y3: integer);
      {$ifdef PDF_CANVASVIRTUAL}override{$else}reintroduce{$endif};
    /// fill ARect with the current Brush, without border
    procedure FillRect(const ARect: TRect); reintroduce;
    /// draw the connected lines through Points with the current Pen
    procedure Polyline(const Points: array of TPoint); reintroduce;
    /// draw the closed polygon of Points with the current Pen and Brush
    procedure Polygon(const Points: array of TPoint); reintroduce;
    /// draw AGraphic at X, Y in its own size, as a PDF image
    procedure Draw(X, Y: integer; AGraphic: TGraphic);
      {$ifdef PDF_CANVASVIRTUAL}override{$else}reintroduce{$endif};
    /// draw AGraphic scaled into ARect, as a PDF image
    procedure StretchDraw(const ARect: TRect; AGraphic: TGraphic); reintroduce;
  public
    /// create the bridge drawing on APdfCanvas, at the resolution of APdfDoc
    constructor Create(APdfDoc: TPdfDocumentVcl; APdfCanvas: TPdfCanvas);
    destructor Destroy; override;
    /// reset all cached state (call when switching to a new page)
    procedure ResetState;
    /// the underlying TPdfCanvas this recording canvas writes to
    property PdfCanvas: TPdfCanvas read fPdfCanvas;
  end;

  /// TPdfDocument descendant that exposes a TCanvas-compatible interface
  // - use instead of TPdfDocumentGdi on non-Windows systems
  // - API is identical: AddPage returns a page, VclCanvas returns the canvas
  TPdfDocumentVcl = class(TPdfDocument)
  private
    fVclCanvas: TPdfVclCanvas;
    fCurrentPage: TPdfPage;
    function GetVclCanvas: TPdfVclCanvas;
  public
    /// create the document (same parameters as TPdfDocument.Create)
    constructor Create(AUseOutlines: boolean = false;
      ACodePage: integer = 0; APdfA: TPdfALevel = pdfaNone
      {$ifdef USE_PDFSECURITY}; AEncryption: TPdfEncryption = nil{$endif});
    destructor Destroy; override;
    /// add a new page and prepare the VclCanvas for drawing on it
    function AddPage: TPdfPage; reintroduce;
    /// open a marked content sequence for Tagged PDF (ISO 32000-1 14)
    // - call before drawing content, EndStructContent must follow
    // - no-op when Tagged = false
    // - AAltText is written as /Alt for Figure elements (image accessibility)
    procedure BeginStructContent(ARole: TPdfStructRole;
      const AAltText: RawUtf8 = '');
    /// open a struct element without any marked-content region
    // - a plain inline run then adds one via ContinueStructContent, a styled
    // run becomes a nested Span
    procedure BeginStructGroup(ARole: TPdfStructRole);
    /// open one more marked-content region for the innermost open element
    procedure ContinueStructContent;
    /// close the region of the innermost open element, which stays open as
    // the parent of the elements nested next
    procedure SuspendStructContent;
    /// close the marked content sequence opened by BeginStructContent
    procedure EndStructContent;
    /// index of the struct element opened by the last BeginStructContent
    // - to be passed to ResumeStructContent, -1 when Tagged = false
    function LastStructContent: integer;
    /// reopen an already closed struct element on the current page
    // - lets one logical block interrupted by a page break stay one tag
    // - must be paired with EndStructContent
    procedure ResumeStructContent(AStructIndex: integer;
      AOpenRegion: boolean = true);
    /// open an /Artifact sequence for content a reader has to skip
    // - e.g. a table header row repeated on a continuation page
    // - decoration paths are wrapped automatically, see TPdfCanvas.BeginArtifact
    procedure BeginArtifact;
    /// close the sequence opened by BeginArtifact
    procedure EndArtifact;
    /// set the fill (non-stroking) opacity for subsequent drawing operations
    // - Value is clamped to [0..1]: 0=fully transparent, 1=fully opaque
    procedure SetFillAlpha(Value: single);
    /// set the stroke opacity for subsequent drawing operations
    // - Value is clamped to [0..1]: 0=fully transparent, 1=fully opaque
    procedure SetStrokeAlpha(Value: single);
    /// the recording canvas - use this to draw on the current page
    // - identical API to TPdfDocumentGdi.VclCanvas
    // - keep the TPdfVclCanvas type: under Delphi, a call through a plain
    // TCanvas reference bypasses the bridge and writes nothing into the PDF
    property VclCanvas: TPdfVclCanvas read GetVclCanvas;
  end;

{$endif USE_GRAPHICS_UNIT}


{$ifdef USE_GRAPHICS_UNIT}

/// create an image from a VCL/LCL bitmap, or reuse the same bitmap added before
// - returns the internal XObject name of the resulting TPdfImage
// - if you specify a PPdfBox to draw the image at the given position/size
// - if the same bitmap content is sent more than once, the TPdfImage will
// be reused (it will therefore spare resulting pdf file space) - if the
// Doc.ForceNoBitmapReuse is false
// - if Doc.ForceJPEGCompression is set, the picture will be stored as a JPEG
// - you can specify a clipping rectangle region as ClipRc parameter
// - an empty bitmap (no width or no height) gives no image: returns ''
// - replaces TPdfDocument.CreateOrGetImage(TBitmap); raw pixels go through
// TPdfDocument.CreateOrGetImage(TPdfImagePixels)
function CreateOrGetBitmapImage(Doc: TPdfDocument; B: TBitmap;
  DrawAt: PPdfBox = nil; ClipRc: PPdfBox = nil): PdfString;

/// the key CreateOrGetBitmapImage reuses an image by: four CRC32C lanes over
// the rows of B - as a DIB pads them on the VCL, BytesPerLine of its raw image
// on the LCL - after its palette entries and the color key of a pf24bit
// bitmap with TransparentMode = tmFixed, which writes a /Mask
// - a device or custom PixelFormat is converted to pf24bit first
function BitmapHash(B: TBitmap): THash128Rec;

/// create the image of a VCL/LCL TGraphic instance
// - handle TBitmap and SynGdiPlus picture types, i.e. TJpegImage
// (stored as jpeg), and TGifImage/TPngImage (stored as bitmap)
// - use TPdfForm to handle TMetafile in vectorial format
// - an optional DontAddToFXref is available, if you don't want to add
// this object to the main XRef list of the PDF file
// - raises EPdfInvalidValue for an empty graphic (no width or no height)
// - replaces the TPdfImage.Create(TGraphic) constructor
function CreateGraphicImage(Doc: TPdfDocument; Graphic: TGraphic;
  DontAddToFXref: boolean): TPdfImage;

{$endif USE_GRAPHICS_UNIT}


{$ifdef OSWINDOWS}
/// retrieve the paper size used by the current selected printer
function CurrentPrinterPaperSize: TPdfPaperSize;

/// retrieve the current printer resolution
function CurrentPrinterRes: TPoint;
{$endif OSWINDOWS}


{ ************ TPdfDocumentGdi for GDI/TCanvas rendering support }


{$ifdef USE_METAFILE}


/// append a EMR_GDICOMMENT message for handling PDF bookmarks
// - will create a PDF destination at the current position (i.e. the last Y
// parameter of a Move), with some text supplied as bookmark name
procedure GdiCommentBookmark(MetaHandle: HDC; const aBookmarkName: RawUtf8);

/// append a EMR_GDICOMMENT message for handling PDF outline
// - used to add an outline at the current position (i.e. the last Y parameter of
// a Move): the text is the associated title, UTF-8 encoded and the outline tree
// is created from the specified numerical level (0=root)
procedure GdiCommentOutline(MetaHandle: HDC;
  const aTitle: RawUtf8; aLevel: integer);

/// append a EMR_GDICOMMENT message for creating a Link into a specified bookmark
procedure GdiCommentLink(MetaHandle: HDC; const aBookmarkName: RawUtf8;
  const aRect: TRect; NoBorder: boolean);

/// append a EMR_GDICOMMENT message for adding jpeg direct
procedure GdiCommentJpegDirect(MetaHandle: HDC; const aFileName: RawUtf8;
  const aRect: TRect);

/// append a EMR_GDICOMMENT message mapping BeginMarkedContent
// - associate optionally a CreateOptionalContentGroup() instance from the
// current PDF document
procedure GdiCommentBeginMarkContent(MetaHandle: HDC;
  Group: TPdfOptionalContentGroup = nil);

/// append a EMR_GDICOMMENT message mapping EndMarkedContent
procedure GdiCommentEndMarkContent(MetaHandle: HDC);

type
  /// a PDF page, with its corresponding Meta File and Canvas
  TPdfPageGdi = class(TPdfPage)
  private
    // don't use these fVCL* properties directly, but via TPdfDocumentGdi.VclCanvas
    fVclMetaFileCompressed: RawByteString;
    fVclCanvasSize: TSize;
    // it is in fact a TMetaFileCanvas instance from fVclCurrentMetaFile
    fVclCurrentCanvas: TCanvas;
    fVclCurrentMetaFile: TMetaFile;
    // allow to create the meta file and its canvas only if necessary, and
    // compress the page content using SynLZ to reduce memory usage
    procedure CreateVclCanvas;
    procedure SetVclCurrentMetaFile;
    procedure FlushVclCanvas;
  public
    /// release associated memory
    destructor Destroy; override;
  end;

  /// class handling PDF document creation using GDI commands
  // - this class allows using a VCL/LCL standard Canvas class
  // - handles also PDF creation directly from TMetaFile content
  TPdfDocumentGdi = class(TPdfDocument)
  private
    fUseMetaFileTextPositioning: TPdfCanvasRenderMetaFileTextPositioning;
    fUseMetaFileTextClipping: TPdfCanvasRenderMetaFileTextClipping;
    fKerningHScaleTop: single;
    fKerningHScaleBottom: single;
    // not inline: they reach the canvas through TPdfCanvasAccess, which is
    // local to the implementation (Delphi E2441)
    function GetVclCanvas: TCanvas;
    function GetVclCanvasSize: TSize;
  public
    /// create the PDF document instance, with a VCL/LCL Canvas property
    // - see TPdfDocument.Create connstructor for the arguments expectations
    constructor Create(AUseOutlines: boolean = false; ACodePage: integer = 0;
      APdfA: TPdfALevel = pdfaNone
      {$ifdef USE_PDFSECURITY}; AEncryption: TPdfEncryption = nil {$endif});
    /// add a Page to the current PDF document
    function AddPage: TPdfPage; override;
    /// save the PDF file content into a specified Stream
    // - this overridden method draw first the all VclCanvas content into the PDF
    procedure SaveToStream(AStream: TStream; ForceModDate: TDateTime = 0); override;
    /// save the current page content to the PDF file
    // - this overridden method flush the content from the VclCanvas into the PDF
    // - it will reduce the used memory as much as possible, by-passing page
    // content compression
    // - typical use may be:
    // ! with TPdfDocumentGdi.Create do
    // !   try
    // !     Stream := TFileStreamEx.Create(FileName, fmCreate);
    // !     try
    // !       SaveToStreamDirectBegin(Stream);
    // !       for i := 1 to 9 do
    // !       begin
    // !         AddPage;
    // !         with VclCanvas do
    // !         begin
    // !           Font.Name := 'Times new roman';
    // !           Font.Size := 150;
    // !           Font.Style := [fsBold, fsItalic];
    // !           Font.Color := clNavy;
    // !           TextOut(100, 100, 'Page ' + IntToStr(i));
    // !         end;
    // !         SaveToStreamDirectPageFlush; // direct writing
    // !       end;
    // !       SaveToStreamDirectEnd;
    // !     finally
    // !       Stream.Free;
    // !     end;
    // !   finally
    // !     Free;
    // !   end;
    procedure SaveToStreamDirectPageFlush(
      FlushCurrentPageNow: boolean = false); override;
    /// the VCL/LCL Canvas of the current page
    property VclCanvas: TCanvas
      read GetVclCanvas;
    /// the VCL/LCL Canvas size of the current page
    // - useful to calculate coordinates for the current page
    // - filled with (0,0) before first call to VclCanvas property
    property VclCanvasSize: TSize
      read GetVclCanvasSize;
    /// defines how TMetaFile text positioning is rendered
    // - default is tpSetTextJustification
    // - tpSetTextJustification if content used SetTextJustification() API calls
    // - tpExactTextCharacterPositining for exact font kerning, but resulting
    // in bigger pdf size
    // - tpKerningFromAveragePosition will compute average pdf Horizontal Scaling
    // in association with KerningHScaleBottom/KerningHScaleTop properties
    // - replace deprecated property UseSetTextJustification
    property UseMetaFileTextPositioning: TPdfCanvasRenderMetaFileTextPositioning
      read fUseMetaFileTextPositioning write fUseMetaFileTextPositioning;
    /// defines how TMetaFile text clipping should be applied
    // - tcNeverClip has been reported to work better e.g. when app is running
    // on Wine (wsWine in WindowsSpecs)
    property UseMetaFileTextClipping: TPdfCanvasRenderMetaFileTextClipping
      read fUseMetaFileTextClipping write fUseMetaFileTextClipping;
    /// the % limit below which Font Kerning is transformed into PDF Horizontal
    // Scaling commands (when text positioning is tpKerningFromAveragePosition)
    // - set to 99.0 by default
    property KerningHScaleBottom: single
      read fKerningHScaleBottom write fKerningHScaleBottom;
    /// the % limit over which Font Kerning is transformed into PDF Horizontal
    // Scaling commands (when text positioning is tpKerningFromAveragePosition)
    // - set to 101.0 by default
    property KerningHScaleTop: single
      read fKerningHScaleTop write fKerningHScaleTop;
  end;

  /// handle any form XObject
  // - A form XObject (see Section 4.9, of PDF reference 1.3) is a self-contained
  // description of an arbitrary sequence of graphics objects, defined as a
  // PDF content stream
  TPdfForm = class(TPdfFormXObject)
  public
    /// create a form XObject from a supplied TMetaFile
    constructor Create(aDoc: TPdfDocumentGdi; aMetaFile: TMetafile); reintroduce;
  end;


/// draw a metafile content into the PDF page
procedure RenderMetaFile(C: TPdfCanvas; MF: TMetaFile; ScaleX: single = 1.0;
  ScaleY: single = 0.0; XOff: single = 0.0; YOff: single = 0.0;
  TextPositioning: TPdfCanvasRenderMetaFileTextPositioning = tpSetTextJustification;
  KerningHScaleBottom: single = 99.0; KerningHScaleTop: single = 101.0;
  TextClipping: TPdfCanvasRenderMetaFileTextClipping = tcAlwaysClip);

{$endif USE_METAFILE}


implementation

{$ifdef FPC}
  // ScanLine[] is the pixel access of TBitmap on the VCL and the LCL alike
  {$WARN 5044 off : Symbol "$1" is not portable }
{$endif FPC}

type
  // reach the protected state of the engine classes, as TORHook does in
  // mormot.core.json: no field, no override - only a cast of an instance
  TPdfCanvasAccess = class(TPdfCanvas);
  TPdfDocumentAccess = class(TPdfDocument);
  TPdfObjectAccess = class(TPdfObject);
  TPdfFontTrueTypeAccess = class(TPdfFontTrueType);

{$ifdef FPC}
{$ifdef USE_METAFILE}
type
  TEMRExtTextOut = TEMREXTTEXTOUTW;
  PEMRExtTextOut = ^TEMRExtTextOut;
  PEMRExtCreateFontIndirect = PEMRExtCreateFontIndirectW;
{$endif USE_METAFILE}
{$endif FPC}


{ ************ TPdfVclCanvas: the TCanvas bridge }

{$ifdef USE_GRAPHICS_UNIT}

// ---------------------------------------------------------------------------
// TPdfVclCanvas
// ---------------------------------------------------------------------------

constructor TPdfVclCanvas.Create(APdfDoc: TPdfDocumentVcl;
  APdfCanvas: TPdfCanvas);
begin
  inherited Create;
  fPdfDoc := APdfDoc;
  fPdfCanvas := APdfCanvas;
  // one canvas pixel in PDF points; ScreenLogPixels is never 0, its setter raises
  fScale.ScaleX := 72.0 / APdfDoc.ScreenLogPixels;
  fScale.ScaleY := 72.0 / APdfDoc.ScreenLogPixels;
  fScale.OriginX := 0;
  fScale.OriginY := 0;
  // Create a memory DC so that TCanvas.TextWidth/TextHeight (which call
  // RequiredState([csHandleValid])) work without a visible window.
  // All actual drawing is intercepted by our overrides and goes to fPdfCanvas.
  fMeasureDC := CreateCompatibleDC(0);
  Handle := fMeasureDC;
  ResetState;
end;

destructor TPdfVclCanvas.Destroy;
begin
  Handle := 0;
  FreeAndNil(fMeasurer);
  if fMeasureDC <> 0 then
  begin
    DeleteDC(fMeasureDC);
    fMeasureDC := 0;
  end;
  inherited;
end;

procedure TPdfVclCanvas.ResetState;
begin
  fLastPenColor := clBlack;
  fLastPenWidth := 1;
  fLastFontName := 'Helvetica';
  fLastFontSize := 10;
  fLastFontStyle := [];
  fLastFontColor := clBlack;
  fStateValid := false;
end;

function TPdfVclCanvas.PxToPtX(AX: integer): single;
begin
  result := (AX + fScale.OriginX) * fScale.ScaleX;
end;

function TPdfVclCanvas.PxToPtY(AY: integer): single;
var
  pageH: single;
begin
  // PDF Y=0 is at the bottom; screen Y=0 is at the top
  pageH := fPdfDoc.DefaultPageHeight;
  if pageH <= 0 then
    pageH := 841; // A4 fallback
  result := pageH - (AY + fScale.OriginY) * fScale.ScaleY;
end;

procedure TPdfVclCanvas.SyncPen;
begin
  if fStateValid and (Pen.Color = fLastPenColor) and
     (Pen.Width = fLastPenWidth) then
    exit;
  fLastPenColor := Pen.Color;
  fLastPenWidth := Pen.Width;
  fPdfCanvas.SetRGBStrokeColor(ColorToRGB(Pen.Color));
  fPdfCanvas.SetLineWidth(Pen.Width * fScale.ScaleX);
end;

procedure TPdfVclCanvas.SyncBrush;
begin
  // Always reapply fill color: SyncFont may have overwritten it for text
  if Brush.Style <> bsClear then
    fPdfCanvas.SetRGBFillColor(ColorToRGB(Brush.Color));
end;

procedure TPdfVclCanvas.SyncFont;
var
  style: TPdfFontStyles;
begin
  // Always reapply fill color for text: SyncBrush may have overwritten it
  if fStateValid and (Font.Name = fLastFontName) and
     (Font.Size = fLastFontSize) and (Font.Style = fLastFontStyle) then
  begin
    // SetFont is expensive - skip it when font attributes are unchanged,
    // but always reapply the fill color because shape draws may have changed it
    if Font.Color <> fLastFontColor then
      fLastFontColor := Font.Color;
    fPdfCanvas.SetRGBFillColor(ColorToRGB(Font.Color));
    exit;
  end;
  fLastFontName := Font.Name;
  fLastFontSize := Font.Size;
  fLastFontStyle := Font.Style;
  fLastFontColor := Font.Color;
  byte(style) := 0;
  if fsBold in Font.Style then
    include(style, pfsBold);
  if fsItalic in Font.Style then
    include(style, pfsItalic);
  if fsUnderline in Font.Style then
    include(style, pfsUnderline);
  if fsStrikeOut in Font.Style then
    include(style, pfsStrikeOut);
  fPdfCanvas.SetFont(StringToUtf8(Font.Name), abs(Font.Size), style, Font.Charset);
  fPdfCanvas.SetRGBFillColor(ColorToRGB(Font.Color));
  fStateValid := true;
end;

procedure TPdfVclCanvas.FillAndStroke;
begin
  if Brush.Style = bsClear then
    fPdfCanvas.Stroke
  else if Pen.Style = psClear then
    fPdfCanvas.Fill
  else
    fPdfCanvas.FillStroke;
end;

// --- Text ---

procedure TPdfVclCanvas.TextOut(X, Y: integer; const AText: string);
begin
  TextOutFrac(X, Y, AText);
end;

procedure TPdfVclCanvas.TextOutDecoded(X, Y: single; const AText: SynUnicode);
var
  pageH: single;
begin
  SyncFont;
  pageH := fPdfDoc.DefaultPageHeight;
  if pageH <= 0 then
    pageH := 841; // A4 fallback
  // TPdfCanvas.TextOutW handles the Unicode to WinAnsi/CID mapping
  fPdfCanvas.TextOutW((X + fScale.OriginX) * fScale.ScaleX,
    pageH - (Y + Font.Size + fScale.OriginY) * fScale.ScaleY, pointer(AText));
end;

procedure TPdfVclCanvas.TextOutFrac(X, Y: single; const AText: string);
begin
  // string as the compiler holds it: UTF-8 under FPC, ANSI under Delphi 7
  if AText <> '' then
    TextOutDecoded(X, Y, StringToSynUnicode(AText));
end;

procedure TPdfVclCanvas.TextOutUtf8(X, Y: single; const AText: RawUtf8);
begin
  if AText <> '' then
    TextOutDecoded(X, Y, Utf8ToSynUnicode(AText));
end;

function TPdfVclCanvas.SetupMeasureFace: boolean;
begin
  if fMeasurer = nil then
    fMeasurer := TPdfFontMeasurer.Create;
  { the export flag decides which font the PDF will really use, so it decides
    which metrics a measurement has to use - same rule as TGDIPages }
  result := fMeasurer.SetFont(StringToUtf8(Font.Name),
    fsBold in Font.Style, fsItalic in Font.Style, fPdfDoc.StandardFontsReplace);
end;

function TPdfVclCanvas.TextWidthFrac(const AText: string): single;
begin
  result := TextWidthUtf8(StringToUtf8(AText));
end;

function TPdfVclCanvas.TextWidthUtf8(const AText: RawUtf8): single;
begin
  if AText = '' then
    result := 0
  else if not SetupMeasureFace then
    // no PDF metrics for this font: the LCL is all there is - inherited
    // TextExtent, not inherited TextWidth, which would call back into our
    // TextExtent override and recurse
    result := inherited TextExtent(Utf8ToString(AText)).cx
  else
    // TPdfFontMeasurer works in PDF points, this canvas in screen pixels
    result := fMeasurer.TextWidth(AText, abs(Font.Size)) / fScale.ScaleX;
end;

function TPdfVclCanvas.TextHeightFrac(const AText: string): single;
var
  descent: single;
begin
  if not SetupMeasureFace then
  begin
    result := inherited TextExtent(AText).cy; // see TextWidthFrac
    exit;
  end;
  { TextOutFrac puts the baseline Font.Size below the requested top, so the box
    of that text is Font.Size plus the descender of the face - the ascender is
    not added, it is already covered by the (larger) Font.Size offset }
  descent := abs(fMeasurer.Current.Descent) / 1000 * abs(Font.Size);
  result := abs(Font.Size) + descent / fScale.ScaleX;
end;

function TPdfVclCanvas.TextExtent(const AText: string): TSize;
begin
  result.cx := round(TextWidthFrac(AText));
  result.cy := round(TextHeightFrac(AText));
end;

function TPdfVclCanvas.TextWidth(const AText: string): integer;
begin
  result := round(TextWidthFrac(AText));
end;

function TPdfVclCanvas.TextHeight(const AText: string): integer;
begin
  result := round(TextHeightFrac(AText));
end;

// --- Shapes ---

procedure TPdfVclCanvas.Rectangle(X1, Y1, X2, Y2: integer);
var
  x, y, w, h: single;
begin
  SyncPen;
  SyncBrush;
  x := PxToPtX(X1);
  y := PxToPtY(Y2); // bottom in PDF coords
  w := (X2 - X1) * fScale.ScaleX;
  h := (Y2 - Y1) * fScale.ScaleY;
  fPdfCanvas.Rectangle(x, y, w, h);
  FillAndStroke;
end;

procedure TPdfVclCanvas.RectangleFrac(X1, Y1, X2, Y2: single);
var
  x, y, w, h, pageH: single;
begin
  SyncPen;
  SyncBrush;
  pageH := fPdfDoc.DefaultPageHeight;
  if pageH <= 0 then
    pageH := 841; // A4 fallback
  x := (X1 + fScale.OriginX) * fScale.ScaleX;
  y := pageH - (Y2 + fScale.OriginY) * fScale.ScaleY; // bottom in PDF coords
  w := (X2 - X1) * fScale.ScaleX;
  h := (Y2 - Y1) * fScale.ScaleY;
  fPdfCanvas.Rectangle(x, y, w, h);
  FillAndStroke;
end;

procedure TPdfVclCanvas.Ellipse(X1, Y1, X2, Y2: integer);
var
  cx, cy, rx, ry: single;
begin
  SyncPen;
  SyncBrush;
  cx := PxToPtX((X1 + X2) div 2);
  cy := PxToPtY((Y1 + Y2) div 2);
  rx := (X2 - X1) * fScale.ScaleX / 2;
  ry := (Y2 - Y1) * fScale.ScaleY / 2;
  fPdfCanvas.Ellipse(cx, cy, rx, ry);
  FillAndStroke;
end;

procedure TPdfVclCanvas.FillRect(const ARect: TRect);
begin
  Brush.Style := bsSolid;
  Pen.Style := psClear;
  Rectangle(ARect.Left, ARect.Top, ARect.Right, ARect.Bottom);
  Pen.Style := psSolid;
end;

// --- Lines ---

{$ifdef PDF_CANVASVIRTUAL}
procedure TPdfVclCanvas.DoMoveTo(X, Y: integer);
begin
  // nothing to write: TFPCustomCanvas.MoveTo already stores PenPos, and an
  // 'm' written here would open a path which the pen settings of the next
  // LineTo end up inside - PAC: "Operator 'RG' not allowed"
end;
{$else}
procedure TPdfVclCanvas.MoveTo(X, Y: integer);
begin
  inherited MoveTo(X, Y); // PenPos only, on the measuring DC - see DoMoveTo
end;

procedure TPdfVclCanvas.LineTo(X, Y: integer);
begin
  DoLineTo(X, Y);
  inherited MoveTo(X, Y); // PenPos to the end point, nothing drawn on the DC
end;
{$endif PDF_CANVASVIRTUAL}

procedure TPdfVclCanvas.DoLineTo(X, Y: integer);
begin
  // one complete path object per segment, in the order ISO 32000-1 8.2
  // requires: graphics state first, then m + l, then the painting operator
  // - PenPos is still the start point here, TFPCustomCanvas.LineTo moves it
  // afterwards, so a chained MoveTo/LineTo/LineTo stays connected
  // - psClear draws nothing: TFPCustomCanvas.LineTo does not even call us
  // then, our Delphi LineTo does
  if Pen.Style = psClear then
    exit;
  SyncPen;
  fPdfCanvas.MoveTo(PxToPtX(PenPos.X), PxToPtY(PenPos.Y));
  fPdfCanvas.LineTo(PxToPtX(X), PxToPtY(Y));
  fPdfCanvas.Stroke;
end;

// --- Rounded Rectangle ---

procedure TPdfVclCanvas.RoundRect(X1, Y1, X2, Y2, X3, Y3: integer);
begin
  SyncPen;
  SyncBrush;
  // TPdfCanvas.RoundRect(x1, y1, x2, y2, cx, cy) where y1=bottom, y2=top in PDF coords
  // X3, Y3 are the corner ellipse dimensions (GDI convention); pass them directly
  // as cx/cy - this matches the existing EMF handler (TPdfCanvas.RoundRectI) behavior
  fPdfCanvas.RoundRect(
    PxToPtX(X1), PxToPtY(Y2),
    PxToPtX(X2), PxToPtY(Y1),
    X3 * fScale.ScaleX,
    Y3 * fScale.ScaleY);
  FillAndStroke;
end;

// --- Polyline / Polygon ---

procedure TPdfVclCanvas.Polyline(const Points: array of TPoint);
var
  i: integer;
begin
  if length(Points) < 2 then
    exit;
  SyncPen;
  fPdfCanvas.MoveTo(PxToPtX(Points[0].X), PxToPtY(Points[0].Y));
  for i := 1 to high(Points) do
    fPdfCanvas.LineTo(PxToPtX(Points[i].X), PxToPtY(Points[i].Y));
  fPdfCanvas.Stroke;
end;

procedure TPdfVclCanvas.Polygon(const Points: array of TPoint);
var
  i: integer;
begin
  if length(Points) < 2 then
    exit;
  SyncPen;
  SyncBrush;
  fPdfCanvas.MoveTo(PxToPtX(Points[0].X), PxToPtY(Points[0].Y));
  for i := 1 to high(Points) do
    fPdfCanvas.LineTo(PxToPtX(Points[i].X), PxToPtY(Points[i].Y));
  // close the path and apply fill/stroke based on current Brush/Pen style
  if Brush.Style = bsClear then
    fPdfCanvas.ClosePathStroke
  else if Pen.Style = psClear then
    fPdfCanvas.Fill // Fill implicitly closes the path per PDF spec
  else
    fPdfCanvas.ClosepathFillStroke;
end;

// --- Bitmap drawing ---

procedure TPdfVclCanvas.Draw(X, Y: integer; AGraphic: TGraphic);
var
  bmp: TBitmap;
  owned: boolean;
  xObj: PdfString;
begin
  if (AGraphic = nil) or AGraphic.Empty then
    exit;
  owned := not (AGraphic is TBitmap);
  if owned then
  begin
    bmp := TBitmap.Create;
    bmp.Width := AGraphic.Width;
    bmp.Height := AGraphic.Height;
    bmp.Canvas.Draw(0, 0, AGraphic);
  end
  else
    bmp := TBitmap(AGraphic);
  try
    xObj := CreateOrGetBitmapImage(fPdfDoc, bmp);
    if xObj = '' then
      exit;
    fPdfCanvas.DrawXObject(
      PxToPtX(X),
      PxToPtY(Y + AGraphic.Height), // bottom-left in PDF coords
      AGraphic.Width * fScale.ScaleX,
      AGraphic.Height * fScale.ScaleY,
      xObj);
  finally
    if owned then
      bmp.Free;
  end;
end;

procedure TPdfVclCanvas.StretchDraw(const ARect: TRect; AGraphic: TGraphic);
var
  bmp: TBitmap;
  owned: boolean;
  xObj: PdfString;
begin
  if (AGraphic = nil) or AGraphic.Empty then
    exit;
  owned := not (AGraphic is TBitmap);
  if owned then
  begin
    bmp := TBitmap.Create;
    bmp.Width := AGraphic.Width;
    bmp.Height := AGraphic.Height;
    bmp.Canvas.Draw(0, 0, AGraphic);
  end
  else
    bmp := TBitmap(AGraphic);
  try
    xObj := CreateOrGetBitmapImage(fPdfDoc, bmp);
    if xObj = '' then
      exit;
    fPdfCanvas.DrawXObject(
      PxToPtX(ARect.Left),
      PxToPtY(ARect.Bottom), // bottom-left in PDF coords
      (ARect.Right - ARect.Left) * fScale.ScaleX,
      (ARect.Bottom - ARect.Top) * fScale.ScaleY,
      xObj);
  finally
    if owned then
      bmp.Free;
  end;
end;

// ---------------------------------------------------------------------------
// TPdfDocumentVcl
// ---------------------------------------------------------------------------

constructor TPdfDocumentVcl.Create(AUseOutlines: boolean; ACodePage: integer;
  APdfA: TPdfALevel
  {$ifdef USE_PDFSECURITY}; AEncryption: TPdfEncryption{$endif});
begin
  inherited Create(AUseOutlines, ACodePage, APdfA
    {$ifdef USE_PDFSECURITY}, AEncryption{$endif});
  {$ifdef OSWINDOWS}
  ScreenLogPixels := GdiScreenLogPixels; // the screen this canvas stands for
  {$endif OSWINDOWS}
  // fVclCanvas is created on first AddPage call
end;

destructor TPdfDocumentVcl.Destroy;
begin
  fVclCanvas.Free;
  inherited;
end;

function TPdfDocumentVcl.GetVclCanvas: TPdfVclCanvas;
begin
  result := fVclCanvas;
end;

function TPdfDocumentVcl.AddPage: TPdfPage;
begin
  result := inherited AddPage;
  fCurrentPage := result;
  // (Re-)create or reinitialize the recording canvas for this page
  if fVclCanvas = nil then
    fVclCanvas := TPdfVclCanvas.Create(self, fCanvas)
  else
    fVclCanvas.ResetState;
  // Switch the underlying PDF canvas to the new page
  // (TPdfDocument.AddPage already calls SetPage internally, so fCanvas
  // is pointing at the new page's content stream)
end;

procedure TPdfDocumentVcl.BeginStructContent(ARole: TPdfStructRole;
  const AAltText: RawUtf8);
begin
  Canvas.BeginStructContent(ARole, AAltText);
end;

procedure TPdfDocumentVcl.BeginStructGroup(ARole: TPdfStructRole);
begin
  Canvas.BeginStructGroup(ARole);
end;

procedure TPdfDocumentVcl.ContinueStructContent;
begin
  Canvas.ContinueStructContent;
end;

procedure TPdfDocumentVcl.SuspendStructContent;
begin
  Canvas.SuspendStructContent;
end;

procedure TPdfDocumentVcl.EndStructContent;
begin
  Canvas.EndStructContent;
end;

function TPdfDocumentVcl.LastStructContent: integer;
begin
  result := Canvas.LastStructContent;
end;

procedure TPdfDocumentVcl.ResumeStructContent(AStructIndex: integer;
  AOpenRegion: boolean);
begin
  Canvas.ResumeStructContent(AStructIndex, AOpenRegion);
end;

procedure TPdfDocumentVcl.BeginArtifact;
begin
  Canvas.BeginArtifact;
end;

procedure TPdfDocumentVcl.EndArtifact;
begin
  Canvas.EndArtifact;
end;

procedure TPdfDocumentVcl.SetFillAlpha(Value: single);
begin
  Canvas.SetFillAlpha(Value);
end;

procedure TPdfDocumentVcl.SetStrokeAlpha(Value: single);
begin
  Canvas.SetStrokeAlpha(Value);
end;

{$endif USE_GRAPHICS_UNIT}


{$ifdef OSWINDOWS}

function PrinterDriverExists: boolean;
var
  flags, count, dummy: dword;
  level: byte;
begin
  // avoid using fPrinter.printers.count as this will raise an
  // exception if no printer driver is installed...
  count := 0;
  flags := PRINTER_ENUM_CONNECTIONS or PRINTER_ENUM_LOCAL;
  level := 4;
  {$ifdef FPC}
  EnumPrinters(flags, nil, level, nil, 0, @count, @dummy);
  {$else}
  EnumPrinters(flags, nil, level, nil, 0, count, dummy);
  {$endif FPC}
  result := (count > 0);
end;

function ParseFetchedPrinterStr(Str: PChar): PChar;
var
  P: PChar;
begin
  result := Str;
  if Str = nil then
    exit;
  P := Str;
  while P^ = ' ' do
    inc(P);
  result := P;
  while (P^ <> #0) and
        (P^ <> ',') do
    inc(P);
  if P^ = ',' then
    P^ := #0;
end;

function CurrentPrinterPaperSize: TPdfPaperSize;
var
  h: THandle;
  pt: TPoint;
  logical, physical: TSize;
  tmp: integer;
  name: array[0..1023] of char;
  PC: PChar;
begin
  result := psUserDefined;
  if not PrinterDriverExists then
    exit;
  GetProfileString('windows', 'device', nil, name, SizeOf(name) - 1);
  PC := ParseFetchedPrinterStr(name);
  if (PC = nil) or
     (PC^ = #0) then
    exit;
  try
    h := CreateDC(nil, PC, nil, nil);
    try
      pt.x := GetDeviceCaps(h, LOGPIXELSX);
      pt.y := GetDeviceCaps(h, LOGPIXELSY);
      physical.cx := GetDeviceCaps(h, PHYSICALWIDTH);
      physical.cy := GetDeviceCaps(h, PHYSICALHEIGHT);
      logical.cx := mulDiv(physical.cx, 254, pt.x * 10);
      logical.cy := mulDiv(physical.cy, 254, pt.y * 10);
    finally
      DeleteDC(h);
    end;
  except
    on Exception do // raised e.g. if no Printer is existing
      exit;
  end;
  if logical.cx < logical.cy then
  begin // handle landscape or portrait at once
    tmp := logical.cx;
    logical.cx := logical.cy;
    logical.cy := tmp;
  end;
  case logical.cy of
    148:
      result := psA5;
    210:
      result := psA4; // A4 (297 x 210mm)
    216:
      if logical.cx = 279 then
        result := psLetter
      else if logical.cx = 356 then
        result := psLegal;
    297:
      if logical.cx = 420 then
        result := psA3;
  end;
end;

function CurrentPrinterRes: TPoint;
var
  name: array[0..1023] of Char;
  PC: PChar;
  h: THandle;
begin
  result.X := 300;
  result.Y := 300; // default standard printer resolution
  if not PrinterDriverExists then
    exit;
  GetProfileString('windows', 'device', nil, name, SizeOf(name) - 1);
  PC := ParseFetchedPrinterStr(name);
  if (PC = nil) or
     (PC^ = #0) then
    exit;
  try
    h := CreateDC(nil, PC, nil, nil);
    try
      result.x := GetDeviceCaps(h, LOGPIXELSX);
      result.y := GetDeviceCaps(h, LOGPIXELSY);
    finally
      DeleteDC(h);
    end;
  except
    on Exception do // raised e.g. if no Printer is existing
      exit;
  end;
end;

function CombineTransform(xform1, xform2: XFORM): XFORM;
begin
  result.eM11 := xform1.eM11 * xform2.eM11 + xform1.eM12 * xform2.eM21;
  result.eM12 := xform1.eM11 * xform2.eM12 + xform1.eM12 * xform2.eM22;
  result.eM21 := xform1.eM21 * xform2.eM11 + xform1.eM22 * xform2.eM21;
  result.eM22 := xform1.eM21 * xform2.eM12 + xform1.eM22 * xform2.eM22;
  result.eDx := xform1.eDx * xform2.eM11 + xform1.eDy * xform2.eM21 + xform2.eDx;
  result.eDy := xform1.eDx * xform2.eM12 + xform1.eDy * xform2.eM22 + xform2.eDy;
end;

procedure InitTransformation(x: PXForm;
  var fIntFactorX, fIntFactorY, fIntOffsetX, fIntOffsetY: single);
begin
  if Assigned(x) then
  begin
    fIntFactorX := x^.eM11;
    fIntFactorY := x^.eM22;
    fIntOffsetX := x^.eDx;
    fIntOffsetY := x^.eDy;
  end
  else
  begin
    fIntFactorX := 1;
    fIntFactorY := 1;
    fIntOffsetX := 0;
    fIntOffsetY := 0;
  end;
end;

function DefaultIdentityMatrix: XFORM;
begin
  result.eM11 := 1;
  result.eM12 := 0;
  result.eM21 := 0;
  result.eM22 := 1;
  result.eDx := 0;
  result.eDy := 0;
end;

{$endif OSWINDOWS}

function ScaleRect(r: TRect; fScaleX, fScaleY: single): TRect;
begin
  result.Left   := trunc(r.Left * fScaleX);
  result.Top    := trunc(r.Top * fScaleY);
  result.Right  := trunc(r.Right * fScaleX);
  result.Bottom := trunc(r.Bottom * fScaleY);
end;

procedure NormalizeRect(var Rect: TRect); overload;
var
  tmp: integer;
begin // PDF can't draw twisted rects -> normalize such values
  if Rect.Right < Rect.Left then
  begin
    tmp := Rect.Left;
    Rect.Left := Rect.Right;
    Rect.Right := tmp;
  end;
  if Rect.Bottom < Rect.Top then
  begin
    tmp := Rect.Top;
    Rect.Top := Rect.Bottom;
    Rect.Bottom := tmp;
  end;
end;


{$ifdef OSWINDOWS}
function PrepareTransformation(
  fIntFactorX, fIntFactorY, fIntOffsetX, fIntOffsetY: single): XForm;
begin
  result.eM11 := fIntFactorX;
  result.eM12 := 0;
  result.eM21 := 0;
  result.eM22 := fIntFactorY;
  result.eDx := fIntOffsetX;
  result.eDy := fIntOffsetY;
end;
{$endif OSWINDOWS}

const
  MWT_IDENTITY      = 1;
  MWT_LEFTMULTIPLY  = 2;
  MWT_RIGHTMULTIPLY = 3;
  MWT_SET           = 4;
  {$ifdef USE_METAFILE}
  cPI: single = 3.141592654;
  cPIdiv180: single = 0.017453292;
  c180divPI: single = 57.29577951;
  {$endif USE_METAFILE}

function RGBA(r, g, b, a: cardinal): cardinal;
  {$ifdef HASINLINE} inline;{$endif}
begin
  result := ((r shr 8) or ((g shr 8) shl 8) or ((b shr 8) shl 16) or ((a shr 8) shl 24));
end;

{$ifdef USE_GRAPHICS_UNIT}
function BitmapHash(B: TBitmap): THash128Rec;
var
  y, w, h, row: integer;
  palcount: cardinal;
  pal: array of TPaletteEntry;
  key: integer;
const
  PERROW: array[TPixelFormat] of byte = (0, 1, 4, 8, 15, 16, 24, 32, 0);
begin
  FillZero(result.b);
  w := B.Width;
  h := B.Height;
  row := PERROW[B.PixelFormat];
  if row = 0 then
  begin
    B.PixelFormat := pf24bit; // convert any device or custom bitmap
    row := 24;
  end;
  if B.Palette <> 0 then
  begin
    palcount := 0;
    if (GetObject(B.Palette, SizeOf(palcount), @palcount) <> 0) and
       (palcount > 0) then
    begin
      SetLength(pal, palcount);
      if GetPaletteEntries(B.Palette, 0, palcount, pal[0]) = palcount then
        result.c0 := crc32c(result.c0, pointer(pal), palcount * SizeOf(pal[0]));
    end;
  end;
  if (B.PixelFormat = pf24bit) and
     (B.TransparentMode = tmFixed) then
  begin
    key := B.TransparentColor;
    result.c1 := crc32c(result.c1, @key, SizeOf(key));
  end;
  {$ifdef FPC}
  // the LCL's own row length, by which ScanLine[] steps: a DIB row may be
  // longer (a pf1bit row is byte- or word-aligned), the last one read past
  row := B.RawImage.Description.BytesPerLine;
  {$else}
  row := (((w * row) + 31) and (not 31)) shr 3; // inlined BytesPerScanLine
  {$endif FPC}
  for y := 0 to h - 1 do
    result.c[y and 3] := crc32c(result.c[y and 3], B.ScanLine[y], row);
end;

function CreateOrGetBitmapImage(Doc: TPdfDocument; B: TBitmap;
  DrawAt, ClipRc: PPdfBox): PdfString;
var
  jpg: TJpegImage;
  img: TPdfImage;
  hash: THash128Rec; // no DefaultHasher128() because AesNiHash128() makes GPF
begin
  result := '';
  // an empty bitmap gives no image: ScanLine[0] would raise
  if (Doc = nil) or
     (B = nil) or
     (B.Width <= 0) or
     (B.Height <= 0) then
    exit;
  FillZero(hash.b);
  if not Doc.ForceNoBitmapReuse then
  begin
    hash := BitmapHash(B);
    result := Doc.GetXObjectImageName(hash, B.Width, B.Height); // search for matching image
  end;
  if result = '' then
  begin
     // create new if no existing TPdfImage match
    if Doc.ForceJPEGCompression = 0 then
      img := CreateGraphicImage(Doc, B, true)
    else
    begin
      jpg := TJpegImage.Create;
      try
        jpg.Assign(B);
        img := CreateGraphicImage(Doc, jpg, false);
      finally
        jpg.Free;
      end;
    end;
    img.Hash := hash;
    result := Doc.RegisterImage(img);
  end;
  Doc.DrawImage(result, DrawAt, ClipRc);
end;
{$endif USE_GRAPHICS_UNIT}

{$ifdef USE_GRAPHICS_UNIT}
{$ifdef FPC}
// the rows of B, top first, Bytes bytes per pixel: Data, Stride, Size - the
// LCL's ScanLine[y] is Data + y * BytesPerLine whatever the LineOrder, so a
// bottom-up raw image starts at its last line
procedure ScanRows(B: TBitmap; Bytes: integer; var P: TPdfImagePixels);
var
  d: TRawImageDescription;
begin
  d := B.RawImage.Description;
  if d.LineOrder = riloBottomToTop then
  begin
    P.Data := B.ScanLine[B.Height - 1];
    P.Stride := -PtrInt(d.BytesPerLine);
  end
  else
  begin
    P.Data := B.ScanLine[0];
    P.Stride := d.BytesPerLine;
  end;
  P.Size := PtrInt(B.Height - 1) * PtrInt(d.BytesPerLine) +
            PtrInt(B.Width) * Bytes;
end;

// the pixels of an LCL bitmap as its raw image describes them - the LCL keeps
// no palette, a pf1bit/pf4bit/pf8bit bitmap is gray, and pf24bit/pf32bit are
// 32-bit B,G,R,x on GTK2, A,R,G,B on Cocoa: the layouts of a Windows DIB go
// through as they are, gray as the indexes of a gray ramp, any other layout
// is repacked to RGB through TLazIntfImage, the LCL's own reader
procedure LclPixels(B: TBitmap; var P: TPdfImagePixels; var Buf: RawByteString);
var
  d: TRawImageDescription;
  img: TLazIntfImage;
  x, y, i: integer;
  c: TFPColor;
  dst: PAnsiChar;
begin
  d := B.RawImage.Description;
  P.Width := B.Width;
  P.Height := B.Height;
  if d.Format = ricfGray then
  begin
    SetLength(P.Palette, 768);
    for i := 0 to 255 do
      FillCharFast(PByteArray(P.Palette)[i * 3], 3, i);
    P.Format := ipfIndexed8;
    if (d.BitsPerPixel = 8) and
       (d.Depth = 8) then
    begin
      ScanRows(B, 1, P);
      exit;
    end;
    // 1-bit: one gray level per pixel, read by the LCL from the raw image
    SetLength(Buf, P.Width * P.Height);
    dst := pointer(Buf);
    img := TLazIntfImage.Create(B.RawImage, {DataOwner=}false);
    try
      for y := 0 to P.Height - 1 do
        for x := 0 to P.Width - 1 do
        begin
          dst^ := AnsiChar(img.Colors[x, y].red shr 8);
          inc(dst);
        end;
    finally
      img.Free;
    end;
  end
  else if (d.Format = ricfRGBA) and
          (d.ByteOrder = riboLSBFirst) and
          (d.BitsPerPixel in [24, 32]) and
          (d.RedPrec = 8) and (d.RedShift = 16) and
          (d.GreenPrec = 8) and (d.GreenShift = 8) and
          (d.BluePrec = 8) and (d.BlueShift = 0) then
  begin
    // B, G, R (, x): a Windows DIB row
    if d.BitsPerPixel = 24 then
    begin
      P.Format := ipfBgr24;
      ScanRows(B, 3, P);
    end
    else
    begin
      P.Format := ipfBgrx32;
      ScanRows(B, 4, P);
    end;
    exit;
  end
  else
  begin
    SetLength(Buf, P.Width * P.Height * 3);
    dst := pointer(Buf);
    img := TLazIntfImage.Create(B.RawImage, {DataOwner=}false);
    try
      for y := 0 to P.Height - 1 do
        for x := 0 to P.Width - 1 do
        begin
          c := img.Colors[x, y];
          dst[0] := AnsiChar(c.red shr 8);
          dst[1] := AnsiChar(c.green shr 8);
          dst[2] := AnsiChar(c.blue shr 8);
          inc(dst, 3);
        end;
    finally
      img.Free;
    end;
    P.Format := ipfRgb24;
  end;
  P.Data := pointer(Buf);
  if P.Format = ipfRgb24 then
    P.Stride := P.Width * 3
  else
    P.Stride := P.Width;
  P.Size := length(Buf);
end;
{$endif FPC}

function CreateGraphicImage(Doc: TPdfDocument; Graphic: TGraphic;
  DontAddToFXref: boolean): TPdfImage;
var
  bmp: TBitmap;
  ms: TMemoryStream;
  px: TPdfImagePixels;
  jpg: TJpegImage;
  {$ifdef FPC}
  buf: RawByteString;
  {$else}
  entry: array of TPaletteEntry;
  i: integer;
  p: PAnsiChar;
  {$endif FPC}

  procedure NeedBitmap(PF: TPixelFormat);
  begin
    bmp := TBitmap.Create; // create a temp bitmap (pixelformat may change)
    bmp.PixelFormat := PF;
    bmp.Width := Graphic.Width;
    bmp.Height := Graphic.Height;
    bmp.Canvas.Draw(0, 0, Graphic);
  end;

begin
  if (Graphic.Width <= 0) or
     (Graphic.Height <= 0) then
    EPdfInvalidValue.RaiseUtf8('CreateGraphicImage: empty % (% x %)',
      [Graphic.ClassName, Graphic.Width, Graphic.Height]);
  if Graphic.InheritsFrom(TJpegImage) then
  begin
    ms := TMemoryStream.Create;
    try
      jpg := TJpegImage(Graphic);
      if Doc.ForceJPEGCompression <> 0 then
        jpg.CompressionQuality := Doc.ForceJPEGCompression;
      {$ifdef USE_SYNGDIPLUS}
      if Doc.ForceJPEGCompression = 0 then // recompression only if necessary
        jpg.SaveInternalToStream(ms)
      else
      {$endif USE_SYNGDIPLUS}
        jpg.SaveToStream(ms); // with CompressionQuality recompress
      result := TPdfImage.CreateJpeg(Doc, ms.Memory, ms.Size, Graphic.Width,
        Graphic.Height, DontAddToFXref);
    finally
      ms.Free;
    end;
    exit;
  end;
  if Graphic.InheritsFrom(TBitmap) then
    bmp := TBitmap(Graphic)
  else
    NeedBitmap(pf24bit);
  try
    FillCharFast(px, SizeOf(px), 0);
    {$ifdef FPC}
    if not (bmp.PixelFormat in [pf1bit, pf4bit, pf8bit, pf24bit, pf32bit]) then
      NeedBitmap(pf24bit);
    LclPixels(bmp, px, buf);
    // [ min1 max1 ... minn maxn ]: the color key of a pf24bit bitmap, as on
    // the VCL - whatever layout holds its pixels
    px.HasColorKey := (bmp.PixelFormat = pf24bit) and
                      (bmp.TransparentMode = tmFixed);
    if px.HasColorKey then
      px.ColorKey := bmp.TransparentColor;
    {$else}
    case bmp.PixelFormat of
      pf1bit,
      pf4bit,
      pf8bit:
        begin
          if bmp.PixelFormat <> pf8bit then
            NeedBitmap(pf8bit);
          SetLength(entry, 256);
          if GetPaletteEntries(bmp.Palette, 0, 256, entry[0]) <> 256 then
            // a call, not raise: Delphi 7/2010 then see result set (W1035)
            EPdfInvalidValue.RaiseU('CreateGraphicImage: no 256-color palette');
          SetLength(px.Palette, 768);
          p := pointer(px.Palette);
          for i := 0 to 255 do
          begin
            p[0] := AnsiChar(entry[i].peRed);
            p[1] := AnsiChar(entry[i].peGreen);
            p[2] := AnsiChar(entry[i].peBlue);
            inc(p, 3);
          end;
          px.Format := ipfIndexed8;
        end;
    else
      begin
        if not (bmp.PixelFormat in [pf24bit, pf32bit]) then
          NeedBitmap(pf24bit);
        if bmp.PixelFormat = pf24bit then
        begin
          px.Format := ipfBgr24;
          // [ min1 max1 ... minn maxn ]
          px.HasColorKey := bmp.TransparentMode = tmFixed;
          if px.HasColorKey then
            px.ColorKey := bmp.TransparentColor;
        end
        else
          px.Format := ipfBgrx32;
      end;
    end;
    // the rows as ScanLine[] gives them: a DIB is bottom-up
    px.Width := bmp.Width;
    px.Height := bmp.Height;
    px.Data := bmp.ScanLine[0];
    case px.Format of
      ipfIndexed8:
        px.Stride := px.Width;
      ipfBgr24:
        px.Stride := px.Width * 3;
    else
      px.Stride := px.Width * 4;
    end;
    px.Size := px.Stride;
    if px.Height > 1 then
    begin
      px.Stride := PAnsiChar(bmp.ScanLine[1]) - PAnsiChar(px.Data);
      px.Size := PtrInt(px.Height - 1) * abs(px.Stride) + px.Size;
    end;
    {$endif FPC}
    result := TPdfImage.CreatePixels(Doc, px, DontAddToFXref);
  finally
    if bmp <> Graphic then
      bmp.Free;
  end;
end;
{$endif USE_GRAPHICS_UNIT}

{ ************ TPdfDocumentGdi for GDI/TCanvas rendering support }

{$ifdef USE_METAFILE}

procedure SetGdiComment(h: HDC; pgc: TPdfGdiComment; data: pointer; len: PtrInt;
  const last: RawByteString = '');
var
  tmp: TSynTempAdder;
begin
  tmp.Init;
  tmp.AddDirect(AnsiChar(pgc));
  tmp.Add(data, len);
  tmp.Add(last);
  {$ifdef FPC}
  windows.GdiComment(h, tmp.Size, PByte(tmp.Buffer)^);
  {$else}
  windows.GdiComment(h, tmp.Size, tmp.Buffer);
  {$endif FPC}
  tmp.Store.Done;
end;

procedure GdiCommentBookmark(MetaHandle: HDC; const aBookmarkName: RawUtf8);
begin
  // high(TPdfGdiComment)<$47 so it will never begin with GDICOMMENT_IDENTIFIER
  SetGdiComment(MetaHandle, pgcBookmark, nil, 0, aBookMarkName);
end;

procedure GdiCommentOutline(MetaHandle: HDC; const aTitle: RawUtf8; aLevel: integer);
begin
  SetGdiComment(MetaHandle, pgcOutline, @aLevel, 4, aTitle);
end;

procedure GdiCommentLink(MetaHandle: HDC; const aBookmarkName: RawUtf8;
  const aRect: TRect; NoBorder: boolean);
const
  pgc: array[boolean] of TPdfGdiComment = (pgcLink, pgcLinkNoBorder);
begin
  SetGdiComment(MetaHandle, pgc[NoBorder], @aRect, SizeOf(aRect), aBookmarkName);
end;

procedure GdiCommentJpegDirect(MetaHandle: HDC; const aFileName: RawUtf8;
  const aRect: TRect);
begin
  SetGdiComment(MetaHandle, pgcJpegDirect, @aRect, SizeOf(aRect), aFileName);
end;

procedure GdiCommentBeginMarkContent(MetaHandle: HDC;
  Group: TPdfOptionalContentGroup);
begin
  SetGdiComment(MetaHandle, pgcBeginMarkContent, @Group, SizeOf(Group));
end;

procedure GdiCommentEndMarkContent(MetaHandle: HDC);
begin
  SetGdiComment(MetaHandle, pgcEndMarkContent, nil, 0);
end;


{ TPdfDocumentGdi }

function TPdfDocumentGdi.AddPage: TPdfPage;
begin
  if (fCanvas <> nil) and
     (TPdfCanvasAccess(fCanvas).fPage <> nil) then
    TPdfPageGdi(TPdfCanvasAccess(fCanvas).fPage).FlushVclCanvas;
  result := inherited AddPage;
  // as expected in SaveToStream() below
  TPdfObjectAccess(TPdfObject(TPdfCanvasAccess(fCanvas).fContents)).fSaveAtTheEnd := true;
end;

constructor TPdfDocumentGdi.Create(AUseOutlines: boolean; ACodePage: integer;
  APdfA: TPdfALevel
  {$ifdef USE_PDFSECURITY}; AEncryption: TPdfEncryption{$endif});
begin
  inherited;
  ScreenLogPixels := GdiScreenLogPixels; // the screen this canvas stands for
  fTPdfPageClass := TPdfPageGdi;
  fUseMetaFileTextPositioning := tpSetTextJustification;
  fKerningHScaleBottom := 99.0;
  fKerningHScaleTop := 101.0;
end;

function TPdfDocumentGdi.GetVclCanvas: TCanvas;
var
  page: TPdfPageGdi;
begin
  page := TPdfPageGdi(TPdfCanvasAccess(fCanvas).fPage);
  if page.fVclCurrentCanvas = nil then
    page.CreateVclCanvas;
  result := page.fVclCurrentCanvas;
end;

function TPdfDocumentGdi.GetVclCanvasSize: TSize;
var
  page: TPdfPageGdi;
begin
  if (fCanvas <> nil) and
     (TPdfCanvasAccess(fCanvas).fPage <> nil) then
  begin
    page := TPdfPageGdi(TPdfCanvasAccess(fCanvas).fPage);
    if page.fVclCurrentCanvas = nil then
      page.CreateVclCanvas;
    result := page.fVclCanvasSize;
  end
  else
    Int64(result) := 0;
end;

procedure TPdfDocumentGdi.SaveToStream(AStream: TStream; ForceModDate: TDateTime);
var
  i: PtrInt;
  P: TPdfPageGdi;
begin
  // write the file header
  SaveToStreamDirectBegin(AStream, ForceModDate);
  // then draw the pages VCL/LCL Canvas content on the fly (miminal memory use)
  for i := 0 to fRawPages.Count - 1 do
  begin
    P := fRawPages.List[i];
    P.FlushVclCanvas;
    if P.fVclMetaFileCompressed <> '' then
    begin
      P.SetVclCurrentMetaFile;
      try
        fCanvas.SetPage(P);
        RenderMetaFile(fCanvas, P.fVclCurrentMetaFile, 1, 1, 0, 0,
          fUseMetaFileTextPositioning, KerningHScaleBottom, KerningHScaleTop,
          fUseMetaFileTextClipping);
      finally
        FreeAndNil(P.fVclCurrentMetaFile);
      end;
      inherited SaveToStreamDirectPageFlush;
    end;
  end;
  // finish to write PDF content to destination stream
  SaveToStreamDirectEnd;
end;

procedure TPdfDocumentGdi.SaveToStreamDirectPageFlush(FlushCurrentPageNow: boolean);
var
  P: TPdfPageGdi;
begin
  if fRawPages.Count > 0 then
  begin
    P := fRawPages.List[fRawPages.Count - 1];
    if (P = TPdfCanvasAccess(fCanvas).fPage) and
       (P.fVclMetaFileCompressed = '') and
       (P.fVclCurrentMetaFile <> nil) and
       (P.fVclCurrentCanvas <> nil) then
    begin
      FreeAndNil(P.fVclCurrentCanvas); // manual P.SetVclCurrentMetaFile
      try
        // force flush NOW
        TPdfObjectAccess(TPdfObject(TPdfCanvasAccess(fCanvas).fContents)).fSaveAtTheEnd := false;
        RenderMetaFile(fCanvas, P.fVclCurrentMetaFile, 1, 1, 0, 0,
          fUseMetaFileTextPositioning, KerningHScaleBottom, KerningHScaleTop,
          fUseMetaFileTextClipping);
      finally
        FreeAndNil(P.fVclCurrentMetaFile);
      end;
    end;
  end;
  inherited SaveToStreamDirectPageFlush;
end;


{ TPdfPageGdi }

procedure TPdfPageGdi.SetVclCurrentMetaFile;
var
  tmp: RawByteString;
  str: TStream;
begin
  assert(fVclCurrentMetaFile = nil);
  fVclCurrentMetaFile := TMetaFile.Create;
  fVclCanvasSize.cx := MulDiv(PageWidth, fDoc.ScreenLogPixels, 72);
  fVclCanvasSize.cy := MulDiv(PageHeight, fDoc.ScreenLogPixels, 72);
  fVclCurrentMetaFile.Width := fVclCanvasSize.cx;
  fVclCurrentMetaFile.Height := fVclCanvasSize.cy;
  if fVclMetaFileCompressed <> '' then
  begin
    SetLength(tmp, SynLZdecompressdestlen(pointer(fVclMetaFileCompressed)));
    SynLZdecompress1(pointer(fVclMetaFileCompressed),
      length(fVclMetaFileCompressed), pointer(tmp));
    str := TRawByteStringStream.Create(tmp);
    try
      fVclCurrentMetaFile.LoadFromStream(str);
    finally
      str.Free;
    end;
  end;
end;

procedure TPdfPageGdi.CreateVclCanvas;
begin
  SetVclCurrentMetaFile;
  fVclCurrentCanvas := TMetaFileCanvas.Create(fVclCurrentMetaFile,
    TPdfDocumentAccess(fDoc).EmfDC);
end;

procedure TPdfPageGdi.FlushVclCanvas;
var
  str: TRawByteStringStream;
  len: integer;
begin
  if (self = nil) or
     (fVclCurrentCanvas = nil) then
    exit;
  FreeAndNil(fVclCurrentCanvas);
  assert(fVclCurrentMetaFile <> nil);
  str := TRawByteStringStream.Create;
  try
    fVclCurrentMetaFile.SaveToStream(str);
    len := length(str.DataString);
    SetLength(fVclMetaFileCompressed, SynLZcompressdestlen(len));
    SetLength(fVclMetaFileCompressed, SynLZcompress1(
      pointer(str.DataString), len, pointer(fVclMetaFileCompressed)));
  finally
    str.Free;
  end;
  FreeAndNil(fVclCurrentMetaFile);
end;

destructor TPdfPageGdi.Destroy;
begin
  FreeAndNil(fVclCurrentCanvas);
  FreeAndNil(fVclCurrentMetaFile);
  inherited;
end;


{ TPdfForm }

constructor TPdfForm.Create(aDoc: TPdfDocumentGdi; aMetaFile: TMetafile);
var
  P: TPdfPageGdi;
  res: TPdfDictionary;
  w, h: integer;
  c: TPdfCanvasAccess;
  oldPage: TPdfPage;
  oldFonts: TPdfDictionary;
  oldContents: TPdfStream;
  oldFactor, oldLineWidth: single;
  oldGState, oldCTM: integer;
  oldTextState: TPdfTextStateSavedDynArray;
  oldReselect: boolean;
  oldNewPath, oldArtifact, oldPathArtifact, oldRtl: boolean;
begin
  inherited Create(aDoc, true);
  w := aMetaFile.Width;
  h := aMetaFile.Height;
  P := TPdfPageGdi.Create(nil);
  try
    res := TPdfDictionary.Create(aDoc.fXRef);
    fFontList := TPdfDictionary.Create(nil);
    res.AddItem('Font', fFontList);
    res.AddItem('ProcSet',
      TPdfArray.CreateNames(nil, ['PDF', 'Text', 'ImageC']));
    // owned by the form from now on, also if the rendering raises
    fAttributes.AddItem('Type', 'XObject');
    fAttributes.AddItem('Subtype', 'Form');
    fAttributes.AddItem('BBox', TPdfArray.Create(nil, [0, 0, w, h]));
    fAttributes.AddItem('Matrix', TPdfRawText.Create('[1 0 0 1 0 0]'));
    fAttributes.AddItem('Resources', res);
    P.PageHeight := h; // the Y flip of the integer coordinates
    TPdfDocumentAccess(TPdfDocument(aDoc)).ShareFormResources(res, P);
    // the document's canvas draws into the form, then back where it was -
    // field by field: there may be no current page (SetPage needs one)
    c := TPdfCanvasAccess(TPdfDocumentAccess(TPdfDocument(aDoc)).fCanvas);
    oldPage := c.fPage;
    oldFonts := c.fPageFontList;
    oldContents := c.fContents;
    oldFactor := c.fFactor;
    oldLineWidth := c.fLineWidth;
    oldGState := c.fGStateDepth;
    oldTextState := c.fTextStateSaved;
    oldReselect := c.fFontReselect;
    oldCTM := c.fCTMDepth;
    oldNewPath := c.fNewPath;
    oldArtifact := c.fArtifactOpen;
    oldPathArtifact := c.fPathArtifact;
    oldRtl := c.RightToLeftText;
    try
      c.fPage := P;
      c.fPageFontList := fFontList;
      c.fContents := self;
      c.fFactor := 1;
      c.fLineWidth := 1;
      c.fGStateDepth := 0;
      c.fTextStateSaved := nil; // the form's q/Q, not the page's
      c.fFontReselect := false;
      c.fCTMDepth := 0;
      // a path or an artifact the page left open is not the form's to close
      c.fNewPath := false;
      c.fArtifactOpen := false;
      c.fPathArtifact := false;
      RenderMetaFile(c, aMetaFile);
    finally
      c.fPage := oldPage;
      c.fPageFontList := oldFonts;
      c.fContents := oldContents;
      c.fFactor := oldFactor;
      c.fLineWidth := oldLineWidth;
      c.fGStateDepth := oldGState;
      c.fTextStateSaved := oldTextState;
      c.fFontReselect := oldReselect;
      c.fCTMDepth := oldCTM;
      c.fNewPath := oldNewPath;
      c.fArtifactOpen := oldArtifact;
      c.fPathArtifact := oldPathArtifact;
      c.RightToLeftText := oldRtl; // the metafile's text sets it
    end;
  finally
    P.Free;
  end;
end;

type
  TFontSpec = packed record
    angle: SmallInt; // -360..+360
    ascent, descent, cell: SmallInt;
  end;

  TPdfEnumStatePen = record
    Null: boolean;
    Color, style: integer;
    Width: single;
  end;

  /// a state of the EMF enumeration engine, for the PDF canvas
  // - used also for the SaveDC/RestoreDC stack
  TPdfEnumState = record
    Position: TPoint;
    Moved: boolean;
    WinSize, ViewSize: TSize;
    WinOrg, ViewOrg: TPoint;
    //transformation and clipping
    WorldTransform: XFORM; //current
    MetaRgn: TPdfBox;      //clipping
    ClipRgn: TPdfBox;      //clipping
    ClipRgnNull: boolean;  //clipping
    MappingMode: integer;
    PolyFillMode: integer;
    StretchBltMode: integer;
    ArcDirection: integer;
    // current selected pen
    Pen: TPdfEnumStatePen;
    // current selected brush
    Brush: record
      Null: boolean;
      Color: integer;
      Style: integer;
    end;
    // current selected font
    Font: record
      Color: integer;
      Align: integer;
      BkMode, BkColor: integer;
      Spec: TFontSpec;
      LogFont: TLogFontW; // better be the last entry in TPdfEnumState record
    end;
  end;

  /// internal state machine used during EMF drawing
  // - contain the EMF enumeration engine state parameters
  TPdfEnum = class
  private
    fStrokeColor: integer;
    fFillColor: integer;
    fPenStyle: integer;
    fPenWidth: single;
    fInLined: boolean;
    fInitTransformMatrix: XFORM;
    fInitMetaRgn: TPdfBox;
    procedure SetFillColor(Value: integer);
    procedure SetStrokeColor(Value: integer);
  protected
    Canvas: TPdfCanvasAccess;
    // the pen/font/brush objects table, indexed like the THandleTable
    Obj: array of record
      case kind: integer of
        OBJ_PEN:
          (PenColor: integer;
           PenStyle: integer;
           PenWidth: single);
        OBJ_FONT:
          (FontSpec: TFontSpec;
           LogFont: TLogFontW);
        OBJ_BRUSH:
          (BrushColor: integer;
           BrushNull: boolean;
           BrushStyle: integer);
    end;
    // SaveDC/RestoreDC stack
    nDC: integer;
    DC: array[0..31] of TPdfEnumState;
  public
    constructor Create(ACanvas: TPdfCanvas);
    procedure SaveDC;
    procedure RestoreDC;
    procedure NeedPen;
    procedure NeedBrushAndPen;
    procedure FlushPenBrush;
    procedure SelectObjectFromIndex(iObject: integer);
    procedure TextOut(var r: TEMRExtTextOut);
    procedure ScaleMatrix(Custom: PXForm; iMode: integer);
    procedure HandleComment(Kind: TPdfGdiComment; P: PAnsiChar; Len: integer);
    procedure CreateFont(ALogFont: PEMRExtCreateFontIndirect);
    // if Canvas.Doc.JPEGCompression<>0, draw not as a bitmap but jpeg encoded
    procedure DrawBitmap(xs, ys, ws, hs, xd, yd, wd, hd, usage: integer;
      Bmi: PBitmapInfo; bits: pointer; clipRect: PRect; xSrcTransform: PXForm;
      dwRop: DWord; transparent: TPdfColorRGB = $FFFFFFFF);
    procedure FillRectangle(const Rect: TRect; ResetNewPath: boolean);
    // the current value set to SetRGBFillColor (rg)
    property FillColor: integer
      read fFillColor write SetFillColor;
    // the current value set to SetRGBStrokeColor (RG)
    property StrokeColor: integer
      read fStrokeColor write SetStrokeColor;
    // WorldTransform
    property InitTransformMatrix: XFORM
      read fInitTransformMatrix write fInitTransformMatrix;
    // MetaRgn - clipping
    procedure InitMetaRgn(const ClientRect: TRect);
    procedure SetMetaRgn;
    // intersect - clipping
    function IntersectClipRect(
      const ClpRect: TPdfBox; const CurrRect: TPdfBox): TPdfBox;
    procedure ExtSelectClipRgn(data: PEMRExtSelectClipRgn);
    // get current clipping area
    function GetClipRect: TPdfBox;
    procedure GradientFill(Data: PEMGradientFill);
    procedure PolyPoly(Data: PEMRPolyPolygon; iType: integer);
  end;

const
  STOCKBRUSHCOLOR: array[WHITE_BRUSH..BLACK_BRUSH] of integer = (
    clWhite, $AAAAAA, $808080, $666666, clBlack);
  STOCKPENCOLOR: array[WHITE_PEN..BLACK_PEN] of integer = (
    clWhite, clBlack);

function CenterPoint(const Rect: TRect): TPoint;
  {$ifdef HASINLINE} inline;{$endif}
begin
  result.X := (Rect.Right + Rect.Left) div 2;
  result.Y := (Rect.Bottom + Rect.Top) div 2;
end;

/// EMF enumeration callback function, called from GDI
// - draw most content on PDF canvas (do not render 100% GDI content yet)
function EnumEMFFunc(DC: HDC; var Table: THandleTable; R: PEnhMetaRecord;
  NumObjects: DWord; E: TPdfEnum): LongBool; stdcall;
var
  st: ^TPdfEnumState;
  box: TPdfBox;
  i: PtrInt;
  cp: TPoint;
  InitTransX: XForm;
  polytypes: PByteArray;
begin
  result := true;
  st := @E.DC[E.nDC];
  case R^.iType of
    EMR_HEADER:
      begin
        SetLength(E.obj, PEnhMetaHeader(R)^.nHandles);
        st^.WinOrg.X := 0;
        st^.WinOrg.Y := 0;
        st^.ViewOrg.X := 0;
        st^.ViewOrg.Y := 0;
        st^.MappingMode := GetMapMode(DC);
        st^.PolyFillMode := GetPolyFillMode(DC);
        st^.StretchBltMode := GetStretchBltMode(DC);
        st^.ArcDirection := AD_COUNTERCLOCKWISE;
        InitTransX := DefaultIdentityMatrix;
        E.InitTransformMatrix := InitTransX;
        E.ScaleMatrix(@InitTransX, MWT_SET); // keep init
        E.InitMetaRgn(TRect(PEnhMetaHeader(R)^.rclBounds));
      end;
    EMR_SETWINDOWEXTEX:
      st^.WinSize := PEMRSetWindowExtEx(R)^.szlExtent;
    EMR_SETWINDOWORGEX:
      st^.WinOrg := PEMRSetWindowOrgEx(R)^.ptlOrigin;
    EMR_SETVIEWPORTEXTEX:
      st^.ViewSize := PEMRSetViewPortExtEx(R)^.szlExtent;
    EMR_SETVIEWPORTORGEX:
      st^.ViewOrg := PEMRSetViewPortOrgEx(R)^.ptlOrigin;
    EMR_SETBKMODE:
      st^.Font.BkMode := PEMRSetBkMode(R)^.iMode;
    EMR_SETBKCOLOR:
      if PEMRSetBkColor(R)^.crColor = cardinal(clNone) then
        st^.Font.BkColor := 0
      else
        st^.Font.BkColor := PEMRSetBkColor(R)^.crColor;
    EMR_SETTEXTCOLOR:
      if PEMRSetTextColor(R)^.crColor = cardinal(clNone) then
        st^.Font.Color := 0
      else
        st^.Font.Color := PEMRSetTextColor(R)^.crColor;
    EMR_SETTEXTALIGN:
      st^.Font.Align := PEMRSetTextAlign(R)^.iMode;
    EMR_EXTTEXTOUTA,
    EMR_EXTTEXTOUTW:
      E.TextOut(PEMRExtTextOut(R)^);
    EMR_SAVEDC:
      E.SaveDC;
    EMR_RESTOREDC:
      E.RestoreDC;
    EMR_SETWORLDTRANSFORM:
      E.ScaleMatrix(@PEMRSetWorldTransform(R)^.xform, MWT_SET);
    EMR_CREATEPEN:
      if PEMRCreatePen(R)^.ihPen - 1 < cardinal(length(E.Obj)) then
      begin
        E.obj[PEMRCreatePen(R)^.ihPen - 1].kind := OBJ_PEN;
        E.obj[PEMRCreatePen(R)^.ihPen - 1].PenColor := PEMRCreatePen(R)^.lopn.lopnColor;
        E.obj[PEMRCreatePen(R)^.ihPen - 1].PenWidth := PEMRCreatePen(R)^.lopn.lopnWidth.X;
        E.obj[PEMRCreatePen(R)^.ihPen - 1].PenStyle := PEMRCreatePen(R)^.lopn.lopnStyle;
      end;
    EMR_CREATEBRUSHINDIRECT:
      if PEMRCreateBrushIndirect(R)^.ihBrush - 1 < cardinal(length(E.Obj)) then
      begin
        E.obj[PEMRCreateBrushIndirect(R)^.ihBrush - 1].kind := OBJ_BRUSH;
        E.obj[PEMRCreateBrushIndirect(R)^.ihBrush - 1].BrushColor := PEMRCreateBrushIndirect(R)^.lb.lbColor;
        E.obj[PEMRCreateBrushIndirect(R)^.ihBrush - 1].BrushNull := (PEMRCreateBrushIndirect(R)^.lb.lbStyle = BS_NULL);
        E.obj[PEMRCreateBrushIndirect(R)^.ihBrush - 1].BrushStyle := PEMRCreateBrushIndirect(R)^.lb.lbStyle;
      end;
    EMR_EXTCREATEFONTINDIRECTW:
      E.CreateFont(PEMRExtCreateFontIndirect(R));
    EMR_DELETEOBJECT:
      if PEMRDeleteObject(R)^.ihObject - 1 < cardinal(length(E.Obj)) then // avoid GPF
        E.obj[PEMRDeleteObject(R)^.ihObject - 1].kind := 0;
    EMR_SELECTOBJECT:
      E.SelectObjectFromIndex(PEMRSelectObject(R)^.ihObject);
    EMR_MOVETOEX:
      begin
        st^.position := PEMRMoveToEx(R)^.ptl; // temp var to ignore unused moves
        if E.Canvas.fNewPath then
        begin
          E.Canvas.MoveToI(st^.position.X, st^.position.Y);
          st^.Moved := true;
        end
        else
          st^.Moved := false;
      end;
    EMR_LINETO:
      begin
        E.NeedPen;
        if not E.Canvas.fNewPath and
           not st^.Moved then
          E.Canvas.MoveToI(st^.position.X, st^.position.Y);
        E.Canvas.LineToI(PEMRLineTo(R)^.ptl.X, PEMRLineTo(R)^.ptl.Y);
        st^.position := PEMRLineTo(R)^.ptl;
        st^.Moved := false;
        E.fInLined := true;
        if not E.Canvas.fNewPath then
          if not st^.pen.null then
            E.Canvas.Stroke
      end;
    EMR_RECTANGLE,
    EMR_ELLIPSE:
      begin
        E.NeedBrushAndPen;
        box := E.Canvas.BoxI(TRect(PEMRRectangle(R)^.rclBox), true);
        case R^.iType of
          EMR_RECTANGLE:
            E.Canvas.Rectangle(box.Left, box.Top, box.Width, box.Height);
          EMR_ELLIPSE:
            E.Canvas.Ellipse(box.Left, box.Top, box.Width, box.Height);
        end;
        E.FlushPenBrush;
      end;
    EMR_ROUNDRECT:
      begin
        NormalizeRect(PRect(@PEMRRoundRect(R)^.rclBox)^);
        E.NeedBrushAndPen;
        E.Canvas.RoundRectI(PEMRRoundRect(R)^.rclBox.left, PEMRRoundRect(R)^.rclBox.top, PEMRRoundRect(R)^.rclBox.right,
          PEMRRoundRect(R)^.rclBox.bottom, PEMRRoundRect(R)^.szlCorner.cx, PEMRRoundRect(R)^.szlCorner.cy);
        E.FlushPenBrush;
      end;
    EMR_ARC:
      begin
        NormalizeRect(PRect(@PEMRARC(R)^.rclBox)^);
        E.NeedPen;
        cp := CenterPoint(TRect(PEMRARC(R)^.rclBox));
        E.Canvas.ArcI(cp.X, cp.Y, PEMRARC(R)^.rclBox.Right - PEMRARC(R)^.rclBox.Left,
          PEMRARC(R)^.rclBox.Bottom - PEMRARC(R)^.rclBox.Top,
          PEMRARC(R)^.ptlStart.x, PEMRARC(R)^.ptlStart.y,
          PEMRARC(R)^.ptlEnd.x, PEMRARC(R)^.ptlEnd.y,
          E.dc[E.nDC].ArcDirection = AD_CLOCKWISE, acArc, st^.position);
        E.Canvas.Stroke;
      end;
    EMR_ARCTO:
      begin
        NormalizeRect(PRect(@PEMRARCTO(R)^.rclBox)^);
        E.NeedPen;
        if not E.Canvas.fNewPath and
           not st^.Moved then
          E.Canvas.MoveToI(st^.position.X, st^.position.Y);
        cp := CenterPoint(TRect(PEMRARC(R)^.rclBox));
        // E.Canvas.LineTo(ptlStart.x, ptlStart.y);
        E.Canvas.ArcI(cp.X, cp.Y, PEMRARC(R)^.rclBox.Right - PEMRARC(R)^.rclBox.Left,
          PEMRARC(R)^.rclBox.Bottom - PEMRARC(R)^.rclBox.Top,
          PEMRARC(R)^.ptlStart.x, PEMRARC(R)^.ptlStart.y,
          PEMRARC(R)^.ptlEnd.x, PEMRARC(R)^.ptlEnd.y,
          E.dc[E.nDC].ArcDirection = AD_CLOCKWISE, acArcTo, st^.position);
        st^.Moved := false;
        E.fInLined := true;
        if not E.Canvas.fNewPath then
          if not st^.pen.null then
            E.Canvas.Stroke;
      end;
    EMR_PIE:
      begin
        NormalizeRect(PRect(@PEMRPie(R)^.rclBox)^);
        E.NeedBrushAndPen;
        cp := CenterPoint(TRect(PEMRPie(R)^.rclBox));
        E.Canvas.ArcI(cp.X, cp.Y, PEMRPie(R)^.rclBox.Right - PEMRPie(R)^.rclBox.Left,
          PEMRPie(R)^.rclBox.Bottom - PEMRPie(R)^.rclBox.Top,
          PEMRPie(R)^.ptlStart.x, PEMRPie(R)^.ptlStart.y,
          PEMRPie(R)^.ptlEnd.x, PEMRPie(R)^.ptlEnd.y,
          E.dc[E.nDC].ArcDirection = AD_CLOCKWISE, acPie, st^.position);
        if st^.pen.null then
          E.Canvas.Fill
        else
          E.Canvas.FillStroke;
      end;
    EMR_CHORD:
      begin
        NormalizeRect(PRect(@PEMRChord(R)^.rclBox)^);
        E.NeedBrushAndPen;
        cp := CenterPoint(TRect(PEMRChord(R)^.rclBox));
        E.Canvas.ArcI(cp.X, cp.Y, PEMRChord(R)^.rclBox.Right - PEMRChord(R)^.rclBox.Left,
          PEMRChord(R)^.rclBox.Bottom - PEMRChord(R)^.rclBox.Top,
          PEMRChord(R)^.ptlStart.x, PEMRChord(R)^.ptlStart.y,
          PEMRChord(R)^.ptlEnd.x, PEMRChord(R)^.ptlEnd.y,
          E.dc[E.nDC].ArcDirection = AD_CLOCKWISE, acChoord, st^.position);
        if st^.pen.null then
          E.Canvas.Fill
        else
          E.Canvas.FillStroke;
      end;
    EMR_FILLRGN:
      begin
        E.SelectObjectFromIndex(PEMRFillRgn(R)^.ihBrush);
        E.NeedBrushAndPen;
        E.FillRectangle(
          TRect(PRgnDataHeader(@PEMRFillRgn(R)^.RgnData[0])^.rcBound), false);
      end;
    EMR_POLYGON,
    EMR_POLYLINE,
    EMR_POLYGON16,
    EMR_POLYLINE16:
      if not st^.brush.null or
         not st^.pen.null then
      begin
        if R^.iType in [EMR_POLYGON, EMR_POLYGON16] then
          E.NeedBrushAndPen
        else
          E.NeedPen;
        if R^.iType in [EMR_POLYGON, EMR_POLYLINE] then
        begin
          E.Canvas.MoveToI(PEMRPolyLine(R)^.aptl[0].x, PEMRPolyLine(R)^.aptl[0].Y);
          for i := 1 to PEMRPolyLine(R)^.cptl - 1 do
            E.Canvas.LineToI(PEMRPolyLine(R)^.aptl[i].x, PEMRPolyLine(R)^.aptl[i].Y);
          if PEMRPolyLine(R)^.cptl > 0 then
            st^.position := PEMRPolyLine(R)^.aptl[PEMRPolyLine(R)^.cptl - 1]
          else
            st^.position := PEMRPolyLine(R)^.aptl[0];
        end
        else
        begin
          E.Canvas.MoveToI(PEMRPolyLine16(R)^.apts[0].x, PEMRPolyLine16(R)^.apts[0].Y);
          if PEMRPolyLine16(R)^.cpts > 0 then
          begin
            for i := 1 to PEMRPolyLine16(R)^.cpts - 1 do
              E.Canvas.LineToI(
                PEMRPolyLine16(R)^.apts[i].x, PEMRPolyLine16(R)^.apts[i].Y);
            st^.position.X := PEMRPolyLine16(R)^.apts[PEMRPolyLine16(R)^.cpts - 1].x;
            st^.position.Y := PEMRPolyLine16(R)^.apts[PEMRPolyLine16(R)^.cpts - 1].Y;
          end
          else
          begin
            st^.position.X := PEMRPolyLine16(R)^.apts[0].x;
            st^.position.Y := PEMRPolyLine16(R)^.apts[0].Y;
          end;
        end;
        st^.Moved := false;
        if R^.iType in [EMR_POLYGON, EMR_POLYGON16] then
        begin
          E.Canvas.Closepath;
          E.FlushPenBrush;
        end
        else if not st^.pen.null then
          E.Canvas.Stroke
        else // for lines
          E.Canvas.NewPath;
      end;
    EMR_POLYPOLYGON,
    EMR_POLYPOLYGON16,
    EMR_POLYPOLYLINE,
    EMR_POLYPOLYLINE16:
      E.PolyPoly(PEMRPolyPolygon(R), R^.iType);
    EMR_POLYBEZIER:
      begin
        if not st^.pen.null then
          E.NeedPen;
        E.Canvas.MoveToI(
          PEMRPolyBezier(R)^.aptl[0].x, PEMRPolyBezier(R)^.aptl[0].Y);
        for i := 0 to (PEMRPolyBezier(R)^.cptl div 3) - 1 do
          E.Canvas.CurveToCI(
            PEMRPolyBezier(R)^.aptl[i * 3 + 1].X,
            PEMRPolyBezier(R)^.aptl[i * 3 + 1].Y,
            PEMRPolyBezier(R)^.aptl[i * 3 + 2].X,
            PEMRPolyBezier(R)^.aptl[i * 3 + 2].Y,
            PEMRPolyBezier(R)^.aptl[i * 3 + 3].X,
            PEMRPolyBezier(R)^.aptl[i * 3 + 3].Y);
        if PEMRPolyBezier(R)^.cptl > 0 then
          st^.position := PEMRPolyBezier(R)^.aptl[PEMRPolyBezier(R)^.cptl - 1]
        else
          st^.position := PEMRPolyBezier(R)^.aptl[0];
        st^.Moved := false;
        if not E.Canvas.fNewPath then
          if not st^.pen.null then
            E.Canvas.Stroke
          else
            E.Canvas.NewPath;
      end;
    EMR_POLYBEZIER16:
      begin
        if not st^.pen.null then
          E.NeedPen;
        E.Canvas.MoveToI(
          PEMRPolyBezier16(R)^.apts[0].x, PEMRPolyBezier16(R)^.apts[0].Y);
        if PEMRPolyBezier16(R)^.cpts > 0 then
        begin
          for i := 0 to (PEMRPolyBezier16(R)^.cpts div 3) - 1 do
            E.Canvas.CurveToCI(
              PEMRPolyBezier16(R)^.apts[i * 3 + 1].X,
              PEMRPolyBezier16(R)^.apts[i * 3 + 1].Y,
              PEMRPolyBezier16(R)^.apts[i * 3 + 2].X,
              PEMRPolyBezier16(R)^.apts[i * 3 + 2].Y,
              PEMRPolyBezier16(R)^.apts[i * 3 + 3].X,
              PEMRPolyBezier16(R)^.apts[i * 3 + 3].Y);
          st^.position.X := PEMRPolyBezier16(R)^.apts[PEMRPolyBezier16(R)^.cpts - 1].x;
          st^.position.Y := PEMRPolyBezier16(R)^.apts[PEMRPolyBezier16(R)^.cpts - 1].Y;
        end
        else
        begin
          st^.position.X := PEMRPolyBezier16(R)^.apts[0].x;
          st^.position.Y := PEMRPolyBezier16(R)^.apts[0].Y;
        end;
        st^.Moved := false;
        if not E.Canvas.fNewPath then
          if not st^.pen.null then
            E.Canvas.Stroke
          else
            E.Canvas.NewPath;
      end;
    EMR_POLYBEZIERTO:
      begin
        if not st^.pen.null then
          E.NeedPen;
        if not E.Canvas.fNewPath then
          if not st^.Moved then
            E.Canvas.MoveToI(st^.position.X, st^.position.Y);
        if PEMRPolyBezierTo(R)^.cptl > 0 then
        begin
          for i := 0 to (PEMRPolyBezierTo(R)^.cptl div 3) - 1 do
            E.Canvas.CurveToCI(
              PEMRPolyBezierTo(R)^.aptl[i * 3].X,
              PEMRPolyBezierTo(R)^.aptl[i * 3].Y,
              PEMRPolyBezierTo(R)^.aptl[i * 3 + 1].X,
              PEMRPolyBezierTo(R)^.aptl[i * 3 + 1].Y,
              PEMRPolyBezierTo(R)^.aptl[i * 3 + 2].X,
              PEMRPolyBezierTo(R)^.aptl[i * 3 + 2].Y);
          st^.position := PEMRPolyBezierTo(R)^.aptl[PEMRPolyBezierTo(R)^.cptl - 1];
        end;
        st^.Moved := false;
        if not E.Canvas.fNewPath then
          if not st^.pen.null then
            E.Canvas.Stroke
          else
            E.Canvas.NewPath;
      end;
    EMR_POLYBEZIERTO16:
      begin
        if not st^.pen.null then
          E.NeedPen;
        if not E.Canvas.fNewPath then
          if not st^.Moved then
            E.Canvas.MoveToI(st^.position.X, st^.position.Y);
        if PEMRPolyBezierTo16(R)^.cpts > 0 then
        begin
          for i := 0 to (PEMRPolyBezierTo16(R)^.cpts div 3) - 1 do
            E.Canvas.CurveToCI(
              PEMRPolyBezierTo16(R)^.apts[i * 3].X,
              PEMRPolyBezierTo16(R)^.apts[i * 3].Y,
              PEMRPolyBezierTo16(R)^.apts[i * 3 + 1].X,
              PEMRPolyBezierTo16(R)^.apts[i * 3 + 1].Y,
              PEMRPolyBezierTo16(R)^.apts[i * 3 + 2].X,
              PEMRPolyBezierTo16(R)^.apts[i * 3 + 2].Y);
          st^.position.X := PEMRPolyBezierTo16(R)^.apts[PEMRPolyBezierTo16(R)^.cpts - 1].x;
          st^.position.Y := PEMRPolyBezierTo16(R)^.apts[PEMRPolyBezierTo16(R)^.cpts - 1].Y;
        end;
        st^.Moved := false;
        if not E.Canvas.fNewPath then
          if not st^.pen.null then
            E.Canvas.Stroke
          else
            E.Canvas.NewPath;
      end;
    EMR_POLYLINETO,
    EMR_POLYLINETO16:
      begin
        if not st^.pen.null then
          E.NeedPen;
        if not E.Canvas.fNewPath then
        begin
          E.Canvas.NewPath;
          if not st^.Moved then
            E.Canvas.MoveToI(st^.position.X, st^.position.Y);
        end;
        if R^.iType = EMR_POLYLINETO then
        begin
          if PEMRPolyLineTo(R)^.cptl > 0 then
          begin
            for i := 0 to PEMRPolyLineTo(R)^.cptl - 1 do
              E.Canvas.LineToI(PEMRPolyLineTo(R)^.aptl[i].X, PEMRPolyLineTo(R)^.aptl[i].Y);
            st^.position := PEMRPolyLineTo(R)^.aptl[PEMRPolyLineTo(R)^.cptl - 1];
          end;
        end
        else
        // EMR_POLYLINETO16
        if PEMRPolyLineTo16(R)^.cpts > 0 then
        begin
          for i := 0 to PEMRPolyLineTo16(R)^.cpts - 1 do
            E.Canvas.LineToI(PEMRPolyLineTo16(R)^.apts[i].X, PEMRPolyLineTo16(R)^.apts[i].Y);
          st^.position.X := PEMRPolyLineTo16(R)^.apts[PEMRPolyLineTo16(R)^.cpts - 1].x;
          st^.position.Y := PEMRPolyLineTo16(R)^.apts[PEMRPolyLineTo16(R)^.cpts - 1].Y;
        end;
        st^.Moved := false;
        if not E.Canvas.fNewPath then
          if not st^.pen.null then
            E.Canvas.Stroke
          else
            E.Canvas.NewPath;
      end;
    EMR_POLYDRAW:
      if PEMRPolyDraw(R)^.cptl > 0 then
      begin
        if not st^.pen.null then
          E.NeedPen;
        polytypes := @PEMRPolyDraw(R)^.aptl[PEMRPolyDraw(R)^.cptl];
        i := 0;
        while i < integer(PEMRPolyDraw(R)^.cptl) do
        begin
          case polytypes^[i] and not PT_CLOSEFIGURE of
            PT_LINETO:
              begin
                E.Canvas.LineToI(PEMRPolyDraw(R)^.aptl[i].X, PEMRPolyDraw(R)^.aptl[i].Y);
                if polytypes^[i] and PT_CLOSEFIGURE <> 0 then
                begin
                  E.Canvas.LineToI(st^.position.X, st^.position.Y);
                  st^.position := PEMRPolyDraw(R)^.aptl[i];
                end;
              end;
            PT_BEZIERTO:
              begin
                E.Canvas.CurveToCI(
                  PEMRPolyDraw(R)^.aptl[i].X,
                  PEMRPolyDraw(R)^.aptl[i].Y,
                  PEMRPolyDraw(R)^.aptl[i + 1].X,
                  PEMRPolyDraw(R)^.aptl[i + 1].Y,
                  PEMRPolyDraw(R)^.aptl[i + 2].X,
                  PEMRPolyDraw(R)^.aptl[i + 2].Y);
                inc(i, 2); // eventual inc(i) below
                if polytypes^[i] and PT_CLOSEFIGURE <> 0 then
                begin
                  E.Canvas.LineToI(st^.position.X, st^.position.Y);
                  st^.position := PEMRPolyDraw(R)^.aptl[i];
                end;
              end;
            PT_MOVETO:
              begin
                E.Canvas.MoveToI(PEMRPolyDraw(R)^.aptl[i].X, PEMRPolyDraw(R)^.aptl[i].Y);
                st^.position := PEMRPolyDraw(R)^.aptl[i];
              end;
          else
            break; // invalid type
          end;
          inc(i);
        end;
        st^.position := PEMRPolyDraw(R)^.aptl[PEMRPolyDraw(R)^.cptl - 1];
        st^.Moved := false;
        if not E.Canvas.fNewPath then
          if not st^.pen.null then
            E.Canvas.Stroke
          else
            E.Canvas.NewPath;
      end;
    EMR_POLYDRAW16:
      if PEMRPolyDraw16(R)^.cpts > 0 then
      begin
        if not st^.pen.null then
          E.NeedPen;
        polytypes := @PEMRPolyDraw16(R)^.apts[PEMRPolyDraw16(R)^.cpts];
        i := 0;
        while i < integer(PEMRPolyDraw16(R)^.cpts) do
        begin
          case polytypes^[i] and not PT_CLOSEFIGURE of
            PT_LINETO:
              begin
                E.Canvas.LineToI(PEMRPolyDraw16(R)^.apts[i].X, PEMRPolyDraw16(R)^.apts[i].Y);
                if polytypes^[i] and PT_CLOSEFIGURE <> 0 then
                begin
                  E.Canvas.LineToI(st^.position.X, st^.position.Y);
                  st^.position.X := PEMRPolyDraw16(R)^.apts[i].x;
                  st^.position.Y := PEMRPolyDraw16(R)^.apts[i].Y;
                end;
              end;
            PT_BEZIERTO:
              begin
                E.Canvas.CurveToCI(
                  PEMRPolyDraw16(R)^.apts[i].X,
                  PEMRPolyDraw16(R)^.apts[i].Y,
                  PEMRPolyDraw16(R)^.apts[i + 1].X,
                  PEMRPolyDraw16(R)^.apts[i + 1].Y,
                  PEMRPolyDraw16(R)^.apts[i + 2].X,
                  PEMRPolyDraw16(R)^.apts[i + 2].Y);
                inc(i, 2); // eventual inc(i) below
                if polytypes^[i] and PT_CLOSEFIGURE <> 0 then
                begin
                  E.Canvas.LineToI(st^.position.X, st^.position.Y);
                  st^.position.X := PEMRPolyDraw16(R)^.apts[i].X;
                  st^.position.Y := PEMRPolyDraw16(R)^.apts[i].Y;
                end;
              end;
            PT_MOVETO:
              begin
                E.Canvas.MoveToI(PEMRPolyDraw16(R)^.apts[i].X, PEMRPolyDraw16(R)^.apts[i].Y);
                st^.position.X := PEMRPolyDraw16(R)^.apts[i].X;
                st^.position.Y := PEMRPolyDraw16(R)^.apts[i].Y;
              end;
          else
            break; // invalid type
          end;
          inc(i);
        end;
        st^.position.X := PEMRPolyDraw16(R)^.apts[PEMRPolyDraw16(R)^.cpts - 1].X;
        st^.position.Y := PEMRPolyDraw16(R)^.apts[PEMRPolyDraw16(R)^.cpts - 1].Y;
        st^.Moved := false;
        if not E.Canvas.fNewPath then
          if not st^.pen.null then
            E.Canvas.Stroke
          else
            E.Canvas.NewPath;
      end;
    EMR_BITBLT:
      begin
        if (PEMRBitBlt(R)^.offBmiSrc <> 0) and
           (PEMRBitBlt(R)^.offBitsSrc <> 0) then
          E.DrawBitmap(PEMRBitBlt(R)^.xSrc, PEMRBitBlt(R)^.ySrc, PEMRBitBlt(R)^.cxDest, PEMRBitBlt(R)^.cyDest, PEMRBitBlt(R)^.xDest, PEMRBitBlt(R)^.yDest,
            PEMRBitBlt(R)^.cxDest, PEMRBitBlt(R)^.cyDest, PEMRBitBlt(R)^.iUsageSrc, pointer(PtrUInt(R) + PEMRBitBlt(R)^.offBmiSrc),
            pointer(PtrUInt(R) + PEMRBitBlt(R)^.offBitsSrc), @PEMRBitBlt(R)^.rclBounds, @PEMRBitBlt(R)^.xformSrc, PEMRBitBlt(R)^.dwRop)
        else
          case PEMRBitBlt(R)^.dwRop of // we only handle PATCOPY = fillrect
            PATCOPY:
              E.FillRectangle(Rect(PEMRBitBlt(R)^.xDest, PEMRBitBlt(R)^.yDest,
                PEMRBitBlt(R)^.xDest + PEMRBitBlt(R)^.cxDest, PEMRBitBlt(R)^.yDest + PEMRBitBlt(R)^.cyDest), true);
          end;
      end;
    EMR_STRETCHBLT:
      begin
        if (PEMRStretchBlt(R)^.offBmiSrc <> 0) and
           (PEMRStretchBlt(R)^.offBitsSrc <> 0) then
          E.DrawBitmap(PEMRStretchBlt(R)^.xSrc, PEMRStretchBlt(R)^.ySrc, PEMRStretchBlt(R)^.cxSrc, PEMRStretchBlt(R)^.cySrc, PEMRStretchBlt(R)^.xDest, PEMRStretchBlt(R)^.yDest, PEMRStretchBlt(R)^.cxDest,
            PEMRStretchBlt(R)^.cyDest, PEMRStretchBlt(R)^.iUsageSrc, pointer(PtrUInt(R) + PEMRStretchBlt(R)^.offBmiSrc),
            pointer(PtrUInt(R) + PEMRStretchBlt(R)^.offBitsSrc), @PEMRStretchBlt(R)^.rclBounds, @PEMRStretchBlt(R)^.xformSrc, PEMRStretchBlt(R)^.dwRop)
        else
          case PEMRStretchBlt(R)^.dwRop of // we only handle PATCOPY = fillrect
            PATCOPY:
              E.FillRectangle(Rect(
                PEMRStretchBlt(R)^.xDest, PEMRStretchBlt(R)^.yDest, PEMRStretchBlt(R)^.xDest + PEMRStretchBlt(R)^.cxDest, PEMRStretchBlt(R)^.yDest + PEMRStretchBlt(R)^.cyDest), true);
          end;
      end;
    EMR_STRETCHDIBITS:
      if (PEMRStretchDIBits(R)^.offBmiSrc <> 0) and
         (PEMRStretchDIBits(R)^.offBitsSrc <> 0) then
      begin
        if st^.WorldTransform.eM22 < 0 then
          PBitmapInfo(PtrUInt(R) + PEMRStretchDIBits(R)^.offBmiSrc)^.bmiHeader.biHeight := -PBitmapInfo(PtrUInt(R) + PEMRStretchDIBits(R)^.offBmiSrc)^.bmiHeader.biHeight;
        E.DrawBitmap(PEMRStretchDIBits(R)^.xSrc, PEMRStretchDIBits(R)^.ySrc, PEMRStretchDIBits(R)^.cxSrc, PEMRStretchDIBits(R)^.cySrc, PEMRStretchDIBits(R)^.xDest, PEMRStretchDIBits(R)^.yDest, PEMRStretchDIBits(R)^.cxDest, PEMRStretchDIBits(R)^.cyDest,
          PEMRStretchDIBits(R)^.iUsageSrc, pointer(PtrUInt(R) + PEMRStretchDIBits(R)^.offBmiSrc),
          pointer(PtrUInt(R) + PEMRStretchDIBits(R)^.offBitsSrc), @PEMRStretchDIBits(R)^.rclBounds, nil, PEMRStretchDIBits(R)^.dwRop);
      end;
    EMR_TRANSPARENTBLT:
      if (PEMRTransparentBLT(R)^.offBmiSrc <> 0) and
         (PEMRTransparentBLT(R)^.offBitsSrc <> 0) then
        E.DrawBitmap(PEMRTransparentBLT(R)^.xSrc, PEMRTransparentBLT(R)^.ySrc, PEMRTransparentBLT(R)^.cxSrc, PEMRTransparentBLT(R)^.cySrc, PEMRTransparentBLT(R)^.xDest, PEMRTransparentBLT(R)^.yDest, PEMRTransparentBLT(R)^.cxDest, PEMRTransparentBLT(R)^.cyDest,
          PEMRTransparentBLT(R)^.iUsageSrc, pointer(PtrUInt(R) + PEMRTransparentBLT(R)^.offBmiSrc),
          pointer(PtrUInt(R) + PEMRTransparentBLT(R)^.offBitsSrc), @PEMRTransparentBLT(R)^.rclBounds, @PEMRTransparentBLT(R)^.xformSrc, SRCCOPY,
          PEMRTransparentBLT(R)^.dwRop); // dwRop stores the transparent color
    EMR_ALPHABLEND:
      if (PEMRAlphaBlend(R)^.offBmiSrc <> 0) and
         (PEMRAlphaBlend(R)^.offBitsSrc <> 0) then
        E.DrawBitmap (PEMRAlphaBlend(R)^.xSrc, PEMRAlphaBlend(R)^.ySrc, PEMRAlphaBlend(R)^.cxSrc, PEMRAlphaBlend(R)^.cySrc, PEMRAlphaBlend(R)^.xDest, PEMRAlphaBlend(R)^.yDest, PEMRAlphaBlend(R)^.cxDest, PEMRAlphaBlend(R)^.cyDest,
          PEMRAlphaBlend(R)^.iUsageSrc, pointer(PtrUInt(R) + PEMRAlphaBlend(R)^.offBmiSrc), pointer(
           PtrUInt(R) + PEMRAlphaBlend(R)^.offBitsSrc), @PEMRAlphaBlend(R)^.rclBounds, @PEMRAlphaBlend(R)^.xformSrc, SRCCOPY, PEMRAlphaBlend(R)^.dwRop)
      else
        case PEMRAlphaBlend(R)^.dwRop of // we only handle PATCOPY = fillrect
          PATCOPY:
            E.FillRectangle(Rect(PEMRAlphaBlend(R)^.xDest, PEMRAlphaBlend(R)^.yDest,
              PEMRAlphaBlend(R)^.xDest + PEMRAlphaBlend(R)^.cxDest, PEMRAlphaBlend(R)^.yDest + PEMRAlphaBlend(R)^.cyDest), true);
        end;
    EMR_GDICOMMENT:
      if PEMRGDIComment(R)^.cbData >= 1 then
        E.HandleComment(
          TPdfGdiComment(PEMRGDIComment(R)^.Data[0]), PAnsiChar(@PEMRGDIComment(R)^.Data) + 1, PEMRGDIComment(R)^.cbData - 1);
    EMR_MODIFYWORLDTRANSFORM:
      E.ScaleMatrix(@PEMRModifyWorldTransform(R)^.xform, PEMRModifyWorldTransform(R)^.iMode);
    EMR_EXTCREATEPEN: // approx. - fast solution
      if PEMRExtCreatePen(R)^.ihPen - 1 < cardinal(length(E.Obj)) then
      begin
        E.obj[PEMRExtCreatePen(R)^.ihPen - 1].kind := OBJ_PEN;
        E.obj[PEMRExtCreatePen(R)^.ihPen - 1].PenColor := PEMRExtCreatePen(R)^.elp.elpColor;
        E.obj[PEMRExtCreatePen(R)^.ihPen - 1].PenWidth := PEMRExtCreatePen(R)^.elp.elpWidth;
        E.obj[PEMRExtCreatePen(R)^.ihPen - 1].PenStyle := PEMRExtCreatePen(R)^.elp.elpPenStyle and (PS_STYLE_MASK or PS_ENDCAP_MASK);
      end;
    EMR_SETMITERLIMIT:
      if PEMRSetMiterLimit(R)^.eMiterLimit > 0.1 then
        E.Canvas.SetMiterLimit(PEMRSetMiterLimit(R)^.eMiterLimit);
    EMR_SETMETARGN:
      E.SetMetaRgn;
    EMR_EXTSELECTCLIPRGN:
      E.ExtSelectClipRgn(PEMRExtSelectClipRgn(R));
    EMR_INTERSECTCLIPRECT:
      st^.ClipRgn := E.IntersectClipRect(E.Canvas.BoxI(
        TRect(PEMRIntersectClipRect(R)^.rclClip), true), st^.ClipRgn);
    EMR_SETMAPMODE:
      st^.MappingMode := PEMRSetMapMode(R)^.iMode;
    EMR_BEGINPATH:
      begin
        E.Canvas.NewPath;
        if not st^.Moved then
        begin
          E.Canvas.MoveToI(st^.position.X, st^.position.Y);
          st^.Moved := true;
        end;
      end;
    EMR_ENDPATH:
      E.Canvas.fNewPath := false;
    EMR_ABORTPATH:
      begin
        E.Canvas.NewPath;
        E.Canvas.fNewPath := false;
      end;
    EMR_CLOSEFIGURE:
      E.Canvas.ClosePath;
    EMR_FILLPATH:
      begin
        if not st^.brush.Null then
        begin
          E.FillColor := st^.brush.color;
          E.Canvas.Fill;
        end;
        E.Canvas.NewPath;
        E.Canvas.fNewPath := false;
      end;
    EMR_STROKEPATH:
      begin
        if not st^.pen.null then
        begin
          E.NeedPen;
          E.Canvas.Stroke;
        end;
        E.Canvas.NewPath;
        E.Canvas.fNewPath := false;
      end;
    EMR_STROKEANDFILLPATH:
      begin
        if not st^.brush.Null then
        begin
          E.NeedPen;
          E.FillColor := st^.brush.color;
          if not st^.pen.null then
            if st^.PolyFillMode = ALTERNATE then
              E.Canvas.EofillStroke
            else
              E.Canvas.FillStroke
          else if st^.PolyFillMode = ALTERNATE then
            E.Canvas.EoFill
          else
            E.Canvas.Fill
        end
        else if not st^.pen.null then
        begin
          E.NeedPen;
          E.Canvas.Stroke;
        end;
        E.Canvas.NewPath;
        E.Canvas.fNewPath := false;
      end;
    EMR_SETPOLYFILLMODE:
      st^.PolyFillMode := PEMRSetPolyFillMode(R)^.iMode;
    EMR_GRADIENTFILL:
      E.GradientFill(PEMGradientFill(R));
    EMR_SETSTRETCHBLTMODE:
      st^.StretchBltMode := PEMRSetStretchBltMode(R)^.iMode;
    EMR_SETARCDIRECTION:
      st^.ArcDirection := PEMRSetArcDirection(R)^.iArcDirection;
    EMR_SETPIXELV:
      begin
        // prepare pixel size and color
        if st^.pen.width <> 1 then
        begin
          E.fPenWidth := E.Canvas.fWorldFactorX * E.Canvas.fDevScaleX;
          E.Canvas.SetLineWidth(E.fPenWidth * E.Canvas.fFactorX);
        end;
        if PEMRSetPixelV(R)^.crColor <> cardinal(st^.pen.color) then
          E.Canvas.SetRGBStrokeColor(PEMRSetPixelV(R)^.crColor);
        // draw point
        st^.position := TPoint(Point(PEMRSetPixelV(R)^.ptlPixel.X, PEMRSetPixelV(R)
          ^.ptlPixel.Y));
        E.Canvas.PointI(st^.position.X, st^.position.Y);
        E.Canvas.Stroke;
        st^.Moved := false;
        // rollback pixel size and color
        if st^.pen.width <> 1 then
        begin
          E.fPenWidth := st^.pen.width * E.Canvas.fWorldFactorX * E.Canvas.fDevScaleX;
          E.Canvas.SetLineWidth(E.fPenWidth * E.Canvas.fFactorX);
        end;
        if PEMRSetPixelV(R)^.crColor <> cardinal(st^.pen.color) then
          E.Canvas.SetRGBStrokeColor(st^.pen.color);
      end;
   // TBD
    EMR_SMALLTEXTOUT,
    EMR_SETROP2,
    EMR_ALPHADIBBLEND,
    EMR_SETBRUSHORGEX,
    EMR_SETICMMODE,
    EMR_SELECTPALETTE,
    EMR_CREATEPALETTE,
    EMR_SETPALETTEENTRIES,
    EMR_RESIZEPALETTE,
    EMR_REALIZEPALETTE,
    EMR_EOF:
      ; //do nothing
  else
    R^.iType := R^.iType; // for debug purpose (breakpoint)
  end;
  case R^.iType of
    EMR_RESTOREDC,
    EMR_SETWINDOWEXTEX,
    EMR_SETWINDOWORGEX,
    EMR_SETVIEWPORTEXTEX,
    EMR_SETVIEWPORTORGEX,
    EMR_SETMAPMODE:
      E.ScaleMatrix(nil, MWT_SET); //recalc new transformation
  end;
end;

procedure RenderMetaFile(C: TPdfCanvas; MF: TMetaFile; ScaleX, ScaleY,
  XOff, YOff: single; TextPositioning: TPdfCanvasRenderMetaFileTextPositioning;
  KerningHScaleBottom, KerningHScaleTop: single;
  TextClipping: TPdfCanvasRenderMetaFileTextClipping);
var
  A: TPdfCanvasAccess;
  E: TPdfEnum;
  R: TRect;
begin
  R.Left := 0;
  R.Top := 0;
  R.Right := MF.Width;
  R.Bottom := MF.Height;
  if ScaleY = 0 then
    ScaleY := ScaleX; // if ScaleY is ommited -> assume symmetric coordinates
  A := TPdfCanvasAccess(C);
  E := TPdfEnum.Create(C);
  try
    A.fOffsetXDef := XOff;
    A.fOffsetYDef := YOff;
    A.fDevScaleX := ScaleX * A.fFactor;
    A.fDevScaleY := ScaleY * A.fFactor;
    A.fEmfBounds := R; // keep device rect
    A.fUseMetaFileTextPositioning := TextPositioning;
    A.fUseMetaFileTextClipping := TextClipping;
    A.fKerningHScaleBottom := KerningHScaleBottom;
    A.fKerningHScaleTop := KerningHScaleTop;
    if TPdfDocumentAccess(A.fDoc).fPrinterPxPerInch.X = 0 then
      TPdfDocumentAccess(A.fDoc).fPrinterPxPerInch := CurrentPrinterRes; // caching for major speedup
    A.fPrinterPxPerInch := TPdfDocumentAccess(A.fDoc).fPrinterPxPerInch;
    Int64(E.DC[0].WinSize) := PInt64(@R.Right)^;
    E.DC[0].ViewSize := E.DC[0].WinSize;
    C.GSave;
    try
      {$ifdef FPC}
      EnumEnhMetaFile(TPdfDocumentAccess(A.fDoc).EmfDC, MF.Handle, @EnumEMFFunc, E, windows.RECT(R));
      {$else}
      EnumEnhMetaFile(TPdfDocumentAccess(A.fDoc).EmfDC, MF.Handle, @EnumEMFFunc, E, TRect(R));
      {$endif FPC}
    finally
      C.GRestore;
    end;
  finally
    E.Free;
  end;
end;



{ TPdfEnum }

constructor TPdfEnum.Create(ACanvas: TPdfCanvas);
begin
  Canvas := TPdfCanvasAccess(ACanvas);
  // set invalid colors or style -> force paint
  fFillColor := -1;
  fStrokeColor := -1;
  fPenStyle := -1;
  fPenWidth := -1;
  DC[0].brush.null := true;
  fInitTransformMatrix := DefaultIdentityMatrix;
  DC[0].WorldTransform := fInitTransformMatrix;
  fInitMetaRgn := PdfBox(0, 0, 0, 0);
  DC[0].ClipRgnNull := true;
  DC[0].MappingMode := MM_TEXT;
  DC[0].PolyFillMode := ALTERNATE;
  DC[0].StretchBltMode := STRETCH_DELETESCANS;
end;

procedure TPdfEnum.CreateFont(aLogFont: PEMRExtCreateFontIndirect);
var
  hf: HFONT;
  tm: TTextMetric;
  old: HGDIOBJ;
  dest: HDC;
begin
  dest := TPdfDocumentAccess(Canvas.fDoc).EmfDC;
  hf := CreateFontIndirectW(aLogFont.elfw.elfLogFont);
  old := SelectObject(dest, hf);
  GetTextMetrics(dest, tm);
  SelectObject(dest, old);
  DeleteObject(hf);
  if aLogFont^.ihFont - 1 < cardinal(length(Obj)) then
  begin
    Obj[aLogFont^.ihFont - 1].kind := OBJ_FONT;
    MoveFast(aLogFont^.elfw.elfLogFont, Obj[aLogFont^.ihFont - 1].LogFont, SizeOf(Obj[aLogFont^.ihFont - 1].LogFont));
    Obj[aLogFont^.ihFont - 1].LogFont.lfPitchAndFamily := tm.tmPitchAndFamily;
    if Obj[aLogFont^.ihFont - 1].LogFont.lfOrientation <> 0 then
      Obj[aLogFont^.ihFont - 1].FontSpec.angle := Obj[aLogFont^.ihFont - 1].LogFont.lfOrientation div 10 // -360..+360
    else
      Obj[aLogFont^.ihFont - 1].FontSpec.angle := Obj[aLogFont^.ihFont - 1].LogFont.lfEscapement div 10;
    Obj[aLogFont^.ihFont - 1].FontSpec.ascent := tm.tmAscent;
    Obj[aLogFont^.ihFont - 1].FontSpec.descent := tm.tmDescent;
    Obj[aLogFont^.ihFont - 1].FontSpec.cell := tm.tmHeight - tm.tmInternalLeading;
  end;
end;

procedure TPdfEnum.DrawBitmap(xs, ys, ws, hs, xd, yd, wd, hd, usage: integer;
  Bmi: PBitmapInfo; bits: pointer; clipRect: PRect; xSrcTransform: PXForm;
  dwRop: DWord; transparent: TPdfColorRGB);
var
  bmp: TBitmap;
  R: TRect;
  box, clp: TPdfBox;
  fx, fy, ox, oy: single;
begin
  bmp := TBitmap.Create;
  try
    InitTransformation(xSrcTransform, fx, fy, ox, oy);
    // create a TBitmap with (0,0,ws,hs) bounds from DIB bits and info
    if Bmi^.bmiHeader.biBitCount = 1 then
      bmp.Monochrome := true
    else
      bmp.PixelFormat := pf24bit;
    bmp.Width := ws;
    bmp.Height := hs;
    StretchDIBits(bmp.Canvas.Handle, 0, 0, ws, hs, trunc(xs + ox),
      trunc(ys + oy), trunc(ws * fx), trunc(hs * fy),
      bits, Bmi^, usage, dwRop);
    if transparent <> $FFFFFFFF then
    begin
      if integer(transparent) < 0 then
        transparent := GetSysColor(transparent and $ff);
      bmp.TransparentColor := transparent;
    end;
    // draw the bitmap on the PDF canvas
    R := TRect(Rect(xd, yd, wd + xd, hd + yd));
    NormalizeRect(R);
    inc(R.Bottom);
    inc(R.Right);
    box := Canvas.BoxI(R, true);
    clp := GetClipRect;
    if (clp.Width > 0) and
       (clp.Height > 0) then
      CreateOrGetBitmapImage(Canvas.Doc, bmp, @box, @clp) // use cliping
    else
      CreateOrGetBitmapImage(Canvas.Doc, bmp, @box, nil);
    // CreateOrGetBitmapImage() will reuse any matching TPdfImage
    // don't send bmi and bits parameters here, because of StretchDIBits above
  finally
    bmp.Free;
  end;
end;

// simulate gradient (not finished)
procedure TPdfEnum.GradientFill(data: PEMGradientFill);
type
  PTriVertex = ^TTriVertex;
  TTriVertex = packed record // circumvent some bug in older Delphi
    x: integer;
    Y: integer;
    Red: word; // COLOR16 wrongly defined in Delphi 6/7 e.g.
    Green: word;
    Blue: word;
    alpha: word;
  end;
  PTriVertexArray = ^TTriVertexArray;
  TTriVertexArray = array[word] of TTriVertex;
  PGradientTriArray = ^TGradientTriArray;
  TGradientTriArray = array[word] of TGradientTriangle;
  PGradientRectArray = ^TGradientRectArray;
  TGradientRectArray = array[word] of TGradientRect;
var
  i: integer;
  vertex: PTriVertexArray;
  tri: PGradientTriArray;
  r: PGradientRectArray;
  pt1, pt2: PTriVertex;
//    Direction: TGradientDirection;
begin
  if data^.nVer > 0 then
  begin
    vertex := @data.Ver;
    case data^.ulMode of
      GRADIENT_FILL_RECT_H,
      GRADIENT_FILL_RECT_V:
        begin
          Canvas.NewPath;
          r := @vertex[data^.nVer];
{         Direction := gdHorizontal;
          if data^.ulMode = GRADIENT_FILL_RECT_V then
            Direction := gdVertical; }
          for i := 1 to data^.nTri do
          begin
            pt1 := @vertex[r[i - 1].UpperLeft];
            pt2 := @vertex[r[i - 1].LowerRight];
            Canvas.MoveToI(pt1.X, pt1.Y);
            Canvas.LineToI(pt1.X, pt2.Y);
            Canvas.LineToI(pt2.X, pt2.Y);
            Canvas.LineToI(pt2.X, pt1.Y);
            Canvas.Closepath;
            Canvas.Fill;
          end;
        end;
      GRADIENT_FILL_TRIANGLE:
        begin
          Canvas.NewPath;
          tri := @vertex[data^.nVer];
          for i := 1 to data^.nTri do
          begin
            FillColor := RGBA(vertex[tri[i - 1].Vertex1].Red, vertex[tri[i - 1].Vertex1].Green, vertex[tri[i - 1].Vertex1].Blue, 0); // ignore Alpha
            Canvas.MoveToI(vertex[tri[i - 1].Vertex1].X, vertex[tri[i - 1].Vertex1].Y);
            Canvas.LineToI(vertex[tri[i - 1].Vertex2].X, vertex[tri[i - 1].Vertex2].Y);
            Canvas.LineToI(vertex[tri[i - 1].Vertex3].X, vertex[tri[i - 1].Vertex3].Y);
            Canvas.LineToI(vertex[tri[i - 1].Vertex1].X, vertex[tri[i - 1].Vertex1].Y);
            // DC[nDC].Moved := Point(pt1.X, pt1.Y);
            Canvas.Closepath;
            Canvas.Fill;
          end;
        end;
    end;
  end;
end;

procedure TPdfEnum.PolyPoly(data: PEMRPolyPolygon; iType: integer);
var
  i, j, o, f: DWord;
  a: PPointArray;
  a16: PSmallPointArray;
  data16: PEMRPolyPolygon16 absolute data;
begin
  NeedBrushAndPen;
  if not Canvas.fNewPath then
    Canvas.NewPath;
  case iType of
    EMR_POLYPOLYGON,
    EMR_POLYPOLYLINE:
      begin
        o := 0;
        a := {%H-}pointer(PtrUInt(data) +
             SizeOf(TEMRPolyPolyline) - SizeOf(TPoint) +
             (data^.nPolys - 1) * SizeOf(DWord));
        for i := 1 to data^.nPolys do
        begin
          f := o;
          Canvas.MoveToI(a[o].x, a[o].Y);
          inc(o);
          for j := 2 to data^.aPolyCounts[i - 1] do
          begin
            Canvas.LineToI(a[o].x, a[o].Y);
            DC[nDC].position := Point(a[o].x,
              a[o].Y);
            inc(o);
          end;
          Canvas.LineToI(a[f].x, a[f].Y);
          DC[nDC].Moved := false;
        end;
      end;
    EMR_POLYPOLYGON16,
    EMR_POLYPOLYLINE16:
      begin
        o := 0;
        a16 := {%H-}pointer(PtrUInt(data16) +
               SizeOf(TEMRPolyPolyline16) - SizeOf(TSmallPoint) +
               (data16^.nPolys - 1) * SizeOf(DWord));
        for i := 1 to data16^.nPolys do
        begin
          f := o;
          Canvas.MoveToI(a16[o].x, a16[o].Y);
          inc(o);
          for j := 2 to data16^.aPolyCounts[i - 1] do
          begin
            Canvas.LineToI(a16[o].x, a16[o].Y);
            DC[nDC].position := Point(a16[o].x,
              a16[o].Y);
            inc(o);
          end;
          Canvas.LineToI(a16[f].x, a16[f].Y);
          DC[nDC].Moved := false;
        end;
      end;
  end;
  if iType in [EMR_POLYPOLYLINE, EMR_POLYPOLYLINE16] then
  begin // stroke
    if not DC[nDC].pen.null then
      Canvas.Stroke
    else
      Canvas.NewPath;
  end
  else
  begin
    // fill
    if not DC[nDC].brush.null then
    begin
      if not DC[nDC].pen.null then
        if DC[nDC].PolyFillMode = ALTERNATE then
          Canvas.EofillStroke
        else
          Canvas.FillStroke
      else if DC[nDC].PolyFillMode = ALTERNATE then
        Canvas.EoFill
      else
        Canvas.Fill
    end
    else if not DC[nDC].pen.null then
      Canvas.Stroke
    else
      Canvas.NewPath;
  end;
end;

procedure TPdfEnum.FillRectangle(const Rect: TRect; ResetNewPath: boolean);
var
  box: TPdfBox;
begin
  if DC[nDC].brush.null then
    exit;
  Canvas.NewPath;
  FillColor := DC[nDC].brush.color;
  box := Canvas.BoxI(Rect, true);
  Canvas.Rectangle(box.Left, box.Top, box.Width, box.Height);
  Canvas.Fill;
  if ResetNewPath then
    Canvas.fNewPath := false;
end;

procedure TPdfEnum.FlushPenBrush;
begin
  if DC[nDC].brush.null then
  begin
    if not DC[nDC].pen.null then
      Canvas.Stroke
    else
      Canvas.NewPath;
  end
  else if DC[nDC].pen.null then
    Canvas.Fill
  else
    Canvas.FillStroke;
end;

procedure TPdfEnum.SelectObjectFromIndex(iObject: integer);
begin
  if iObject < 0 then
  begin // stock object?
    iObject := iObject and $7fffffff;
    case iObject of
      NULL_BRUSH:
        DC[nDC].brush.null := true;
      WHITE_BRUSH..BLACK_BRUSH:
        begin
          DC[nDC].brush.color := STOCKBRUSHCOLOR[iObject];
          DC[nDC].brush.null := false;
        end;
      NULL_PEN:
        begin
          if fInLined and
             ((DC[nDC].pen.style <> PS_NULL) or not DC[nDC].pen.null) then
          begin
            fInLined := false;
            if not DC[nDC].pen.null then
              Canvas.Stroke;
          end;
          DC[nDC].pen.style := PS_NULL;
          DC[nDC].pen.null := true;
        end;
      WHITE_PEN,
      BLACK_PEN:
        begin
          if fInLined and
             ((DC[nDC].pen.color <> STOCKPENCOLOR[iObject]) or not DC[nDC].pen.null) then
          begin
            fInLined := false;
            if not DC[nDC].pen.null then
              Canvas.Stroke;
          end;
          DC[nDC].pen.color := STOCKPENCOLOR[iObject];
          DC[nDC].pen.null := false;
        end;
    end;
  end
  else if cardinal(iObject - 1) < cardinal(length(Obj)) then // avoid GPF
    case Obj[iObject - 1].Kind of // ignore any invalid reference
      OBJ_PEN:
        begin
          if fInLined and
             ((DC[nDC].pen.color <> Obj[iObject - 1].PenColor) or
              (DC[nDC].pen.width <> Obj[iObject - 1].PenWidth) or
              (DC[nDC].pen.style <> Obj[iObject - 1].PenStyle)) then
          begin
            fInLined := false;
            if not DC[nDC].pen.null then
              Canvas.Stroke;
          end;
          DC[nDC].pen.null := (Obj[iObject - 1].PenWidth < 0) or
                      (Obj[iObject - 1].PenStyle = PS_NULL); // !! 0 means as thick as possible
          DC[nDC].pen.color := Obj[iObject - 1].PenColor;
          DC[nDC].pen.width := Obj[iObject - 1].PenWidth;
          DC[nDC].pen.style := Obj[iObject - 1].PenStyle;
        end;
      OBJ_BRUSH:
        begin
          DC[nDC].brush.null := Obj[iObject - 1].BrushNull;
          DC[nDC].brush.color := Obj[iObject - 1].BrushColor;
          DC[nDC].brush.style := Obj[iObject - 1].BrushStyle;
        end;
      OBJ_FONT:
        begin
          DC[nDC].Font.spec := Obj[iObject - 1].FontSpec;
          MoveFast(Obj[iObject - 1].LogFont, DC[nDC].Font.LogFont, SizeOf(Obj[iObject - 1].LogFont));
        end;
    end;
end;

procedure TPdfEnum.HandleComment(Kind: TPdfGdiComment; P: PAnsiChar; Len: integer);
var
  Text: RawUtf8;
  Img: TPdfImage;
  ImgName: PdfString;
  ImgRect: TPdfRect;
begin
  // a form is no page: its outlines, bookmarks and links have none to go to
  if (Kind in [pgcOutline, pgcBookmark, pgcLink, pgcLinkNoBorder]) and
     Canvas.fContents.InheritsFrom(TPdfFormXObject) then
    exit;
  try
    case Kind of
      pgcOutline: // pgcOutline, @aLevel, 4, aTitle
        if Len > 4 then
        begin
          FastSetString(Text, P + 4, Len - 4);
          Canvas.Doc.CreateOutline(Utf8ToString(Trim(Text)), PInteger(P)^,
            Canvas.I2Y(DC[nDC].position.Y));
        end;
      pgcBookmark: // pgcBookmark, nil, 0, aBookMarkName
        begin
          FastSetString(Text, P, Len);
          Canvas.Doc.CreateBookMark(Canvas.I2Y(DC[nDC].position.Y), Text);
        end;
      pgcLink,
      pgcLinkNoBorder: // pgc[NoBorder], @aRect, SizeOf(aRect), aBookmarkName
        if Len > SizeOf(TRect) then
        begin
          FastSetString(Text, P + SizeOf(TRect), Len - SizeOf(TRect));
          Canvas.Doc.CreateLink(
            Canvas.RectI(PRect(P)^, true), Text, abSolid, ord(Kind = pgcLink));
        end;
      pgcJpegDirect: // pgcJpegDirect, @aRect, SizeOf(aRect), aFileName
        if Len > SizeOf(TRect) then
        begin
          FastSetString(Text, P + SizeOf(TRect), Len - SizeOf(TRect));
          ImgName := 'SynImgJpg' + PdfString(crc32cUtf8ToHex(Text));
          if Canvas.Doc.GetXObject(ImgName) = nil then
          begin
            Img := TPdfImage.CreateJpegDirect(Canvas.Doc, Utf8ToString(Text));
            Canvas.Doc.RegisterXObject(Img, ImgName);
          end;
          ImgRect := Canvas.RectI(PRect(P)^, true);
          Canvas.DrawXObject(ImgRect.Left, ImgRect.Top,
            ImgRect.Right - ImgRect.Left, ImgRect.Bottom - ImgRect.Top, ImgName);
        end;
      pgcBeginMarkContent: // pgcBeginMarkContent, @Group, SizeOf(Group)
        if Len = SizeOf(pointer) then
          Canvas.BeginMarkedContent(PPointer(P)^);
      pgcEndMarkContent: // pgcEndMarkContent, nil, 0
        Canvas.EndMarkedContent;
    end;
  except
    on Exception do
      ; // ignore any error (continue EMF enumeration)
  end;
end;

procedure TPdfEnum.NeedBrushAndPen;
begin
  if fInlined then
  begin
    fInlined := false;
    Canvas.Stroke;
  end;
  NeedPen;
  if not DC[nDC].brush.null then
    FillColor := DC[nDC].brush.color;
end;

procedure TPdfEnum.NeedPen;
begin
  if not DC[nDC].pen.null then
  begin
    StrokeColor := DC[nDC].pen.color;
    if DC[nDC].pen.style <> fPenStyle then
    begin
      case DC[nDC].pen.style and PS_STYLE_MASK of
        PS_DASH:
          Canvas.SetDash([4, 4]);
        PS_DOT:
          Canvas.SetDash([1, 1]);
        PS_DASHDOT:
          Canvas.SetDash([4, 1, 1, 1]);
        PS_DASHDOTDOT:
          Canvas.SetDash([4, 1, 1, 1, 1, 1]);
      else
        Canvas.SetDash([]);
      end;
      case DC[nDC].Pen.style and PS_ENDCAP_MASK of
        PS_ENDCAP_ROUND:
          Canvas.SetLineCap(lcRound_End);
        PS_ENDCAP_SQUARE:
          Canvas.SetLineCap(lcProjectingSquareEnd);
        PS_ENDCAP_FLAT:
          Canvas.SetLineCap(lcButt_End);
      end;
      fPenStyle := DC[nDC].pen.style;
    end;
    if DC[nDC].pen.width * Canvas.fWorldFactorX * Canvas.fDevScaleX <> fPenWidth then
    begin
      if DC[nDC].pen.width = 0 then
        fPenWidth := Canvas.fWorldFactorX * Canvas.fDevScaleX
      else
        fPenWidth := DC[nDC].pen.width * Canvas.fWorldFactorX * Canvas.fDevScaleX;
      Canvas.SetLineWidth(fPenWidth * Canvas.fFactorX);
    end;
  end
  else
  begin
    // pen.null need reset values
    fStrokeColor := -1;
    fPenWidth := -1;
    fPenStyle := -1;
  end;
end;

procedure TPdfEnum.RestoreDC;
begin
  Assert(nDC > 0);
  dec(nDC);
end;

procedure TPdfEnum.SaveDC;
begin
  Assert(nDC < high(DC));
  DC[nDC + 1] := DC[nDC];
  inc(nDC);
end;

procedure TPdfEnum.ScaleMatrix(Custom: PXForm; iMode: integer);
var
  xf: XForm;
  xdim, ydim: single;
  mx, my: integer;
begin
  if fInlined then
  begin
    fInlined := false;
    if not DC[nDC].pen.null then
      Canvas.Stroke;
  end;
  Canvas.fViewSize := DC[nDC].ViewSize;
  Canvas.fViewOrg := DC[nDC].ViewOrg;
  Canvas.fWinSize := DC[nDC].WinSize;
  Canvas.fWinOrg := DC[nDC].WinOrg;
  case DC[nDC].MappingMode of
    MM_TEXT:
      begin
        Canvas.fViewSize.cx := 1;
        Canvas.fViewSize.cy := 1;
        Canvas.fWinSize.cx := 1;
        Canvas.fWinSize.cy := 1;
      end;
    MM_LOMETRIC:
      begin
        Canvas.fViewSize.cx := Canvas.fPrinterPxPerInch.X;
        Canvas.fViewSize.cy := -Canvas.fPrinterPxPerInch.Y;
        Canvas.fWinSize.cx := DC[nDC].WinSize.cx * 10;
        Canvas.fWinSize.cy := DC[nDC].WinSize.cy * 10;
      end;
    MM_HIMETRIC:
      begin
        Canvas.fViewSize.cx := Canvas.fPrinterPxPerInch.X;
        Canvas.fViewSize.cy := -Canvas.fPrinterPxPerInch.Y;
        Canvas.fWinSize.cx := DC[nDC].WinSize.cx * 100;
        Canvas.fWinSize.cy := DC[nDC].WinSize.cy * 100;
      end;
    MM_LOENGLISH:
      begin
        Canvas.fViewSize.cx := Canvas.fPrinterPxPerInch.X;
        Canvas.fViewSize.cy := -Canvas.fPrinterPxPerInch.Y;
        Canvas.fWinSize.cx := MulDiv(1000, DC[nDC].WinSize.cx, 254);
        Canvas.fWinSize.cy := MulDiv(1000, DC[nDC].WinSize.cy, 254);
      end;
    MM_HIENGLISH:
      begin
        Canvas.fViewSize.cx := Canvas.fPrinterPxPerInch.X;
        Canvas.fViewSize.cy := -Canvas.fPrinterPxPerInch.Y;
        Canvas.fWinSize.cx := MulDiv(10000, DC[nDC].WinSize.cx, 254);
        Canvas.fWinSize.cy := MulDiv(10000, DC[nDC].WinSize.cy, 254);
      end;
    MM_TWIPS:
      begin
        Canvas.fViewSize.cx := Canvas.fPrinterPxPerInch.X;
        Canvas.fViewSize.cy := -Canvas.fPrinterPxPerInch.Y;
        Canvas.fWinSize.cx := MulDiv(14400, DC[nDC].WinSize.cx, 254);
        Canvas.fWinSize.cy := MulDiv(14400, DC[nDC].WinSize.cy, 254);
      end;
    MM_ISOTROPIC:
      begin
        Canvas.fViewSize.cx := Canvas.fPrinterPxPerInch.X;
        Canvas.fViewSize.cy := -Canvas.fPrinterPxPerInch.Y;
        Canvas.fWinSize.cx := DC[nDC].WinSize.cx * 10;
        Canvas.fWinSize.cy := DC[nDC].WinSize.cy * 10;
        xdim := abs(Canvas.fViewSize.cx * DC[nDC].WinSize.cx / (Canvas.fPrinterPxPerInch.X * Canvas.fWinSize.cx));
        ydim := abs(Canvas.fViewSize.cy * DC[nDC].WinSize.cy / (Canvas.fPrinterPxPerInch.Y * Canvas.fWinSize.cy));
        if xdim > ydim then
        begin
          if Canvas.fViewSize.cx >= 0 then
            mx := 1
          else
            mx := -1;
          Canvas.fViewSize.cx := trunc(Canvas.fViewSize.cx * ydim / xdim + 0.5);
          if Canvas.fViewSize.cx = 0 then
            Canvas.fViewSize.cx := mx;
        end
        else
        begin
          if Canvas.fViewSize.cy >= 0 then
            my := 1
          else
            my := -1;
          Canvas.fViewSize.cy := trunc(Canvas.fViewSize.cy * xdim / ydim + 0.5);
          if Canvas.fViewSize.cy = 0 then
            Canvas.fViewSize.cy := my;
        end;
      end;
    MM_ANISOTROPIC:
      ;  // TBD
  end;
  if Canvas.fWinSize.cx = 0 then // avoid EZeroDivide
    Canvas.fFactorX := 1.0
  else
    Canvas.fFactorX := abs(Canvas.fViewSize.cx / Canvas.fWinSize.cx);
  if Canvas.fWinSize.cy = 0 then // avoid EZeroDivide
    Canvas.fFactorY := 1.0
  else
    Canvas.fFactorY := abs(Canvas.fViewSize.cy / Canvas.fWinSize.cy);
  if Custom <> nil then
  begin
    // S.eM11=fFactorX S.eM12=0 S.eM21=0 S.eM22=fFactorY multiplied by Custom^
    case iMode of
      MWT_IDENTITY: // reset identity matrix
        DC[nDC].WorldTransform := DefaultIdentityMatrix;
      MWT_LEFTMULTIPLY:
        DC[nDC].WorldTransform := CombineTransform(Custom^, DC[nDC].WorldTransform);
      MWT_RIGHTMULTIPLY:
        DC[nDC].WorldTransform := CombineTransform(DC[nDC].WorldTransform, Custom^);
      MWT_SET:
        DC[nDC].WorldTransform := Custom^;
    end;
  end;
  // use transformation
  xf := DC[nDC].WorldTransform;
  if (xf.eM11 > 0) and
     (xf.eM22 > 0) and
     (xf.eM12 = 0) and
     (xf.eM21 = 0) then
  begin // Scale
    Canvas.fWorldFactorX := xf.eM11;
    Canvas.fWorldFactorY := xf.eM22;
    Canvas.fWorldOffsetX := DC[nDC].WorldTransform.eDx;
    Canvas.fWorldOffsetY := DC[nDC].WorldTransform.eDy;
  end
  else if (xf.eM22 = xf.eM11) and
          (xf.eM21 = -xf.eM12) then
  begin // Rotate
    Canvas.fAngle := ArcSin(xf.eM12) * c180divPI;
    Canvas.fWorldOffsetCos := xf.eM11;
    Canvas.fWorldOffsetSin := xf.eM12;
  end
  else if (xf.eM11 = 0) and
          (xf.eM22 = 0) and
          ((xf.eM12 <> 0) or
           (xf.eM21 <> 0)) then
  begin //Shear

  end
  else if ((xf.eM11 < 0) or
           (xf.eM22 < 0)) and
          (xf.eM12 = 0) and
          (xf.eM21 = 0) then
  begin //Reflection

  end;
end;

procedure TPdfEnum.InitMetaRgn(const ClientRect: TRect);
begin
  fInitMetaRgn := Canvas.BoxI(ClientRect, true);
  DC[nDC].ClipRgnNull := true;
  DC[nDC].MetaRgn := fInitMetaRgn;
end;

procedure TPdfEnum.SetMetaRgn;
begin
  try
    if not DC[nDC].ClipRgnNull then
    begin
      DC[nDC].MetaRgn := IntersectClipRect(DC[nDC].ClipRgn, DC[nDC].MetaRgn);
      FillCharFast(DC[nDC].ClipRgn, SizeOf(DC[nDC].ClipRgn), 0);
      DC[nDC].ClipRgnNull := true;
    end;
  except
    on e: Exception do
      ; // ignore any error (continue EMF enumeration)
  end;
end;

function TPdfEnum.IntersectClipRect(const ClpRect: TPdfBox;
  const CurrRect: TPdfBox): TPdfBox;
begin
  result := CurrRect;
  if (ClpRect.Width <> 0) or
     (ClpRect.Height <> 0) then
  begin // ignore null clipping area
    if ClpRect.Left > result.Left then
      result.Left := ClpRect.Left;
    if ClpRect.Top > result.Top then
      result.Top := ClpRect.Top;
    if (ClpRect.Left + ClpRect.Width) < (result.Left + result.Width) then
      result.Width := (ClpRect.Left + ClpRect.Width) - result.Left;
    if (ClpRect.Top + ClpRect.Height) < (result.Top + result.Height) then
      result.Height := (ClpRect.Top + ClpRect.Height) - result.Top;
    // fix rect
    if result.Width < 0 then
      result.Width := 0;
    if result.Height < 0 then
      result.Height := 0;
  end;
end;

procedure TPdfEnum.ExtSelectClipRgn(data: PEMRExtSelectClipRgn);
var
  box: TPdfBox;
  i: integer;
  d: PRgnData;
  pr: PRect;
  r: TRect;
begin
  // see http://www.codeproject.com/Articles/1944/Guide-to-WIN-Regions
  if data^.iMode <> RGN_COPY then
    exit; // we are handling RGN_COPY (5) only
  if not DC[nDC].ClipRgnNull then // if current clip then finish
  begin
    Canvas.GRestore;
    Canvas.NewPath;
    Canvas.fNewPath := false;
    DC[nDC].ClipRgnNull := true;
    fFillColor := -1;
  end;
  if Data^.cbRgnData > 0 then
  begin
    Canvas.GSave;
    Canvas.NewPath;
    DC[nDC].ClipRgnNull := false;
    d := @Data^.RgnData;
    pr := @d^.Buffer;
    for i := 1 to d^.rdh.nCount do
    begin
      r := pr^;
      inc(r.Bottom);
      inc(r.Right);
      box := Canvas.BoxI(r, false);
      Canvas.Rectangle(box.Left, box.Top, box.Width, box.Height);
      inc(pr);
    end;
    Canvas.Closepath;
    Canvas.Clip;
    Canvas.NewPath;
    Canvas.FNewPath := false;
  end;
end;

function TPdfEnum.GetClipRect: TPdfBox;
begin // get current clip area
  if DC[nDC].ClipRgnNull then
    result := DC[nDC].MetaRgn
  else
    result := DC[nDC].ClipRgn;
end;

procedure TPdfEnum.SetFillColor(Value: integer);
begin
  if fFillColor = Value then
    exit;
  Canvas.SetRGBFillColor(Value);
  fFillColor := Value;
end;

procedure TPdfEnum.SetStrokeColor(Value: integer);
begin
  if fStrokeColor = Value then
    exit;
  Canvas.SetRGBStrokeColor(Value);
  fStrokeColor := Value;
end;

function DXTextWidth(DX: PIntegerArray; n: PtrInt): integer;
var
  i: PtrInt;
begin
  result := 0;
  for i := 0 to n - 1 do
    inc(result, DX^[i]);
end;

procedure TPdfEnum.TextOut(var R: TEMRExtTextOut);
var
  sx, sy, nspace, i: integer;
  cur: cardinal;
  ws, ss, xs, ys, ww, mw, w, h, hscale: single;
  a, acos, asin, fscaleX, fscaleY: single;
  dx: PIntegerArray; // not handled during drawing yet
  posi: TPoint;
  tmp: array of WideChar; // R.emrtext is not #0 terminated -> use tmp[]
  hasdx, clipped, isopaque: boolean;
  tmp2: array[0..1] of WideChar;
  clip: TPdfBox;
  back: TRect;
  po: TPdfCanvasRenderMetaFileTextPositioning;
  {$ifdef USE_UNISCRIBE}
  fnt: TPdfFont;
  dest: HDC;
  old: HGDIOBJ;
  siz: TSize;
  {$endif USE_UNISCRIBE}

  procedure DrawLine(var P: TPoint; aH: single);
  var
    tmp: TPdfEnumStatePen;
  begin
    tmp := DC[nDC].Pen;
    DC[nDC].pen.color := DC[nDC].Font.color;
    DC[nDC].pen.width := ss / (fscaleY * 15);
    DC[nDC].pen.style := PS_SOLID;
    DC[nDC].pen.null := false;
    NeedPen;
    if DC[nDC].Font.spec.angle = 0 then
    begin
      // P = textout original coords
      // (-w,-h) = delta to text start pos (at baseline)
      // ww = text width
      // aH = delta h for drawed line (from baseline)
      Canvas.MoveToS(P.X - w, (P.Y - (h - aH)));
      //  deltax := -w     deltaY := (-h+aH)
      Canvas.LineToS(P.X - w + ww, (P.Y - (h - aH)));
      //  deltax := -w+ww  deltaY := (-h+aH)
    end
    else
    begin
      // rotation pattern:
      //   rdx = deltax * acos + deltay * asin
      //   rdy = deltay * acos - deltax * asin
      Canvas.MoveToS(P.X + ((-w) * acos + (-h + aH) * asin),
                     P.Y + ((-h + aH) * acos - (-w) * asin));
      Canvas.LineToS(P.X + ((-w + ww) * acos + (-h + aH) * asin),
                     P.Y + ((-h + aH) * acos - (-w + ww) * asin));
    end;
    Canvas.Stroke;
    DC[nDC].Pen := tmp;
    NeedPen;
  end;

begin
  if R.emrtext.nChars > 0 then
  begin
    SetLength(tmp, R.emrtext.nChars + 1); // faster than WideString for our purpose
    MoveFast(pointer(PtrUInt(@R) + R.emrtext.offString)^, tmp[0], R.emrtext.nChars * 2);
    sy := 1;
    sx := 1;
    if (Canvas.fWorldFactorY) < 0 then
      sy := -1;
    if (Canvas.fWorldFactorX) < 0 then
      sx := -1;
    fscaleY := abs(Canvas.fFactorY * Canvas.fWorldFactorY * Canvas.fDevScaleY);
    fscaleX := abs(Canvas.fFactorX * Canvas.fWorldFactorX * Canvas.fDevScaleX);
    // guess the font size
    if DC[nDC].Font.LogFont.lfHeight < 0 then
      ss := abs(DC[nDC].Font.LogFont.lfHeight) * fscaleY
    else
      ss := abs(DC[nDC].Font.spec.cell) * fscaleY;
    // ensure this font is selected (very fast if was already selected)
    {$ifdef USE_UNISCRIBE}fnt :={$endif} Canvas.SetFont(TPdfDocumentAccess(Canvas.fDoc).EmfDC, DC[nDC].Font.LogFont, ss);
    // calculate coordinates
    po := Canvas.fUseMetaFileTextPositioning;
    if (R.emrtext.fOptions and ETO_GLYPH_INDEX <> 0) then
      mw := 0
    else
    begin
      ws := 0;
      {$ifdef USE_UNISCRIBE}
      if Assigned(fnt) and Canvas.fDoc.UseUniScribe and
         fnt.InheritsFrom(TPdfFontTrueType) then
      begin
        // the face's HFONT, selected for this measure only
        dest := TPdfDocumentAccess(Canvas.fDoc).EmfDC;
        old := SelectObject(dest,
          HGDIOBJ(TPdfFontTrueTypeAccess(fnt).fFace.Handle));
        if GetTextExtentPoint32W(dest, pointer(tmp), R.emrtext.nChars, siz) then
          ws := (siz.cX * Canvas.fPage.FontSize) / 1000;
        SelectObject(dest, old);
      end;
      {$endif USE_UNISCRIBE}
      if ws = 0 then
        ws := Canvas.UnicodeTextWidth(pointer(tmp));
      mw := round(ws / fscaleX);
    end;
    hasdx := R.emrtext.offDx > 0;
    {$ifdef USE_UNISCRIBE}
    if Canvas.fDoc.UseUniScribe then
      hasdx := hasdx and (R.emrtext.fOptions and ETO_GLYPH_INDEX <> 0);
    {$endif USE_UNISCRIBE}
    if hasdx then
    begin
      dx := pointer(PtrUInt(@R) + R.emrtext.offDx);
      w := DXTextWidth(dx, R.emrText.nChars);
      if w < trunc((R.rclBounds.Right - R.rclBounds.Left) / Canvas.fFactorX) then
        dx := nil; // offDX=0 or within box
    end
    else
      dx := nil;
    if dx = nil then
    begin
      w := mw;
      if po = tpExactTextCharacterPositining then
        po := tpSetTextJustification; // exact position expects dx
    end;
    nspace := 0;
    hscale := 100;
    if mw <> 0 then
    begin
      for i := 0 to R.emrtext.nChars - 1 do
        if tmp[i] = ' ' then
          inc(nspace);
      if (po = tpSetTextJustification) and
         ((nspace = 0) or (({%H-}w - mw) < nspace)) then
        po := tpKerningFromAveragePosition;
      if (po = tpExactTextCharacterPositining) and
         (DC[nDC].Font.spec.angle <> 0) then
        po := tpKerningFromAveragePosition;
      case po of
        tpSetTextJustification:
          // we should have had a SetTextJustification() call -> modify word space
          Canvas.SetWordSpace(((w - mw) * fscaleX) / nspace);
        tpKerningFromAveragePosition:
          begin
            // check if dx[] width differs from PDF width
            hscale := (w * 100) / mw;
            // implement some global kerning if needed (allow hysteresis around 100%)
            if (hscale < Canvas.fKerningHScaleBottom) or
               (hscale > Canvas.fKerningHScaleTop) then
              if DC[nDC].Font.spec.angle = 0 then
                Canvas.SetHorizontalScaling(hscale)
              else
                hscale := 100
            else
              hscale := 100;
          end;
      end;
    end
    else
      po := tpSetTextJustification;
    ww := w;                                    // right x
    // h Align Mask = TA_CENTER or TA_RIGHT or TA_LEFT = TA_CENTER
    if (DC[nDC].Font.Align and TA_CENTER) = TA_CENTER then
      w := w / 2  // center x
    else if (DC[nDC].Font.Align and TA_CENTER) = TA_LEFT then
      w := 0;     // left x
    // V Align mask = TA_BASELINE or TA_BOTTOM or TA_TOP = TA_BASELINE
    if (DC[nDC].Font.Align and TA_BASELINE) = TA_BASELINE then
    // always zero ?
      h := abs(DC[nDC].Font.LogFont.lfHeight) - abs(DC[nDC].Font.spec.cell)  // center y
    else if (DC[nDC].Font.Align and TA_BASELINE) = TA_BOTTOM then
      h := abs(DC[nDC].Font.spec.descent)  // bottom y
    else
      // needs - vertical coords of baseline from top
      h := -abs(DC[nDC].Font.spec.ascent); // top
    if sy < 0 then // inverted coordinates
      h := abs(DC[nDC].Font.LogFont.lfHeight) + h;
    if sx < 0 then
      w := w + ww;
    if (DC[nDC].Font.align and TA_UPDATECP) = TA_UPDATECP then
      posi := DC[nDC].position
    else
      posi := R.emrtext.ptlReference;
    // detect clipping
    if Canvas.fUseMetaFileTextClipping <> tcNeverClip then
    begin
      clipped := (R.emrtext.rcl.Right > R.emrtext.rcl.Left) and (R.emrtext.rcl.Bottom > R.emrtext.rcl.Top);
      if clipped then
        clip := Canvas.BoxI(TRect(R.emrtext.rcl), true)
      else
      begin
        if Canvas.fUseMetaFileTextClipping = tcClipExplicit then
          clipped := (R.rclBounds.Right > R.rclBounds.Left) and (R.rclBounds.Bottom > R.rclBounds.Top);
        if clipped then
          clip := Canvas.BoxI(TRect(R.rclBounds), true)
        else
        begin
          clipped := not DC[nDC].ClipRgnNull and
                      (Canvas.fUseMetaFileTextClipping = tcAlwaysClip);
          if clipped then
            clip := GetClipRect;
        end;
      end;
    end
    else
      clipped := false;
    isopaque := not DC[nDC].brush.null and
               (DC[nDC].brush.Color <> clWhite) and
               ((R.emrtext.fOptions and ETO_OPAQUE <> 0) or
                ((DC[nDC].Font.BkMode = OPAQUE) and
                 (DC[nDC].Font.BkColor = DC[nDC].brush.color)));
    if isopaque then
      if clipped then
        back := TRect(R.emrtext.rcl)
      else
      begin
        back.TopLeft := posi;
        back.BottomRight := posi;
        inc(back.Right, trunc(ww));
        inc(back.Bottom, abs(DC[nDC].Font.LogFont.lfHeight));
      end;
    NormalizeRect(back);
    if clipped then
    begin
      Canvas.GSave;
      Canvas.NewPath;
      Canvas.Rectangle({%H-}clip.Left, {%H-}clip.Top,
        {%H-}clip.Width, {%H-}clip.Height);
      Canvas.ClosePath;
      Canvas.Clip;
      if isopaque then
      begin
        FillRectangle(back, false);
        isopaque := false; //do not handle more
      end
      else
        Canvas.NewPath;
      Canvas.fNewPath := false;
    end;
    // draw background (if any)
    if isopaque then
      // don't handle BkMode, since global to the page, but only specific text
      // don't handle rotation here, since should not be used much
      FillRectangle(back, true);
    // draw text
    FillColor := DC[nDC].Font.color;
    {$ifdef USE_UNISCRIBE}
    Canvas.RightToLeftText := (R.emrtext.fOptions and ETO_RTLREADING) <> 0;
    {$endif USE_UNISCRIBE}
    Canvas.BeginText;
    if DC[nDC].Font.spec.angle <> 0 then
    begin
      a := DC[nDC].Font.spec.angle * cPIdiv180;
      acos := cos(a);
      asin := sin(a);
      xs := 0;
      ys := 0;
      Canvas.SetTextMatrix(acos, asin, -asin, acos,
        Canvas.I2X(posi.X - round(w * acos + h * asin)),
        Canvas.I2Y(posi.Y - round(h * acos - w * asin)));
    end
    else if (DC[nDC].WorldTransform.eM11 = DC[nDC].WorldTransform.eM22) and
            (DC[nDC].WorldTransform.eM12 = -DC[nDC].WorldTransform.eM21) and
            not SameValue(ArcCos(DC[nDC].WorldTransform.eM11), 0, 0.0001) then
    begin
      xs := 0;
      ys := 0;
      if SameValue(ArcCos(DC[nDC].WorldTransform.eM11), 0, 0.0001) or      // 0 grad
         SameValue(ArcCos(DC[nDC].WorldTransform.eM11), cPI, 0.0001) then  // 180 grad
        Canvas.SetTextMatrix(DC[nDC].WorldTransform.eM11, DC[nDC].WorldTransform.eM12,
          DC[nDC].WorldTransform.eM21, DC[nDC].WorldTransform.eM22,
          Canvas.S2X(posi.X * DC[nDC].WorldTransform.eM11 +
            posi.Y * DC[nDC].WorldTransform.eM21 + DC[nDC].WorldTransform.eDx),
          Canvas.S2Y(posi.X * DC[nDC].WorldTransform.eM12 +
            posi.Y * DC[nDC].WorldTransform.eM22 + DC[nDC].WorldTransform.eDy))
      else
        Canvas.SetTextMatrix(-DC[nDC].WorldTransform.eM11, -DC[nDC].WorldTransform.eM12, -
          DC[nDC].WorldTransform.eM21, -DC[nDC].WorldTransform.eM22,
          Canvas.S2X(posi.X * DC[nDC].WorldTransform.eM11 +
            posi.Y * DC[nDC].WorldTransform.eM21 + DC[nDC].WorldTransform.eDx),
          Canvas.S2Y(posi.X * DC[nDC].WorldTransform.eM12 +
            posi.Y * DC[nDC].WorldTransform.eM22 + DC[nDC].WorldTransform.eDy));
    end
    else
    begin
      acos := 0;
      asin := 0;
      if Canvas.fViewSize.cx > 0 then
        xs := posi.X - w   // zero point left
      else
        xs := posi.X + w;  // right
      if Canvas.fViewSize.cy > 0 then
        ys := posi.Y - h   // zero point beyond
      else
        ys := posi.Y + h;  // above
      Canvas.MoveTextPoint(Canvas.S2X(xs), Canvas.S2Y(ys));
    end;
    if (R.emrtext.fOptions and ETO_GLYPH_INDEX) <> 0 then
      Canvas.ShowGlyph(pointer(tmp), R.emrtext.nChars)
    else if po = tpExactTextCharacterPositining then
    begin
      cur := 0;
      tmp2[1] := #0;
      repeat
        tmp2[0] := tmp[cur];
        Canvas.ShowText(@tmp2, false);
        if cur = R.emrtext.nChars - 1 then
          break;
        xs := xs + dx^[cur];
        Canvas.EndText;
        Canvas.BeginText;
        Canvas.MoveTextPoint(Canvas.S2X(xs), Canvas.S2Y(ys));
        inc(cur);
      until false;
    end
    else
      Canvas.ShowText(pointer(tmp));
    Canvas.EndText;
    // handle underline or strike out styles (direct draw PDF lines on canvas)
    if DC[nDC].Font.LogFont.lfUnderline <> 0 then
      DrawLine(posi, ss / (fScaleY * 8));
    if DC[nDC].Font.LogFont.lfStrikeOut <> 0 then
      DrawLine(posi, -ss / (fScaleY * 4));
    // end any pending clipped TextRect() region
    if clipped then
    begin
      Canvas.GRestore;
      fFillColor := -1; // force set drawing color
    end;
    // restore previous text justification (after GRestore if clipped)
    case po of
      tpSetTextJustification:
        if nspace > 0 then
          Canvas.SetWordSpace(0);
      tpKerningFromAveragePosition:
        if hscale <> 100 then
          Canvas.SetHorizontalScaling(100); // reset horizontal scaling
    end;
    if not Canvas.fNewPath then
    begin
      if clipped then
        if not DC[nDC].ClipRgnNull then
        begin
          clip := GetClipRect;
          Canvas.GSave;
          Canvas.Rectangle(
            clip.Left, clip.Top, clip.Width, clip.Height);
          Canvas.Clip;
          Canvas.GRestore;
          Canvas.NewPath;
          Canvas.fNewPath := false;
        end;
    end
    else
      Canvas.fNewPath := false;
    if (DC[nDC].Font.align and TA_UPDATECP) = TA_UPDATECP then
    begin
      DC[nDC].position.X := posi.X + trunc(ww);
      DC[nDC].position.Y := posi.Y;
    end;
  end;
end;

{$endif USE_METAFILE}


end.
