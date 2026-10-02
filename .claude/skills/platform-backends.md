# Platform Backends — IPdfPlatformFont / IPdfSystemFonts / IPdfPlatformDC (+ optional IPdfFontSubsetter)

Source: `src/core/mormot.pdf.types.pas`
Windows backend: `src/platform/windows/mormot.pdf.gdi.pas`
Unix/macOS backend: `src/platform/unix/mormot.pdf.freetype.pas`

---

## Three Interfaces

On Linux/macOS all platform-specific operations run through these three interfaces.

**Windows bypasses them in `TPdfDocument`.** Under `{$ifdef OSWINDOWS}` the core
calls GDI directly: `CreateCompatibleDC`/`GetDeviceCaps` in the constructor,
`CreateFontIndirectW`, `GetTextMetrics`, `GetOutlineTextMetrics`,
`GetCharABCWidthsA`, `SelectObject` (`GetDCWithFont`), `windows.GetFontData`
for the tables and the embedded face, plus `CreateFontPackage` and Uniscribe
(`USE_UNISCRIBE`). The GDI backend's interfaces are used on Windows only by
`TPdfFontMeasurer`, i.e. the `TGDIPages` layout. A replacement backend (e.g. a
test stub) therefore reaches the PDF output on POSIX only; moving this path
behind `IPdfPlatformFont` is part of the refactoring (R-28).

### IPdfPlatformFont — Font Operations

```pascal
IPdfPlatformFont = interface
  // Create a font object from a logical font descriptor
  function  CreateFont(const ALogFont: TPdfLogFont): TPdfPlatformFontHandle;
  // Release a previously created font
  procedure DeleteFont(AFont: TPdfPlatformFontHandle);
  // Select font into DC; returns the previously selected font handle
  function  SelectFont(ADC: TPdfPlatformDC;
                       AFont: TPdfPlatformFontHandle): TPdfPlatformFontHandle;
  // Retrieve basic text metrics for the currently selected font
  function  GetTextMetrics(ADC: TPdfPlatformDC;
                           out AMetrics: TPdfTextMetrics): boolean;
  // Retrieve extended outline metrics (ascent, descent, em-square, etc.)
  function  GetOutlineMetrics(ADC: TPdfPlatformDC;
                              out AMetrics: TPdfOutlineMetrics): boolean;
  // Retrieve ABC advance widths for characters FirstChar..LastChar.
  // FirstChar/LastChar are WinAnsi (cp1252) BYTE values, not Unicode code
  // points - the engine calls (32, 255) and indexes the result by WinAnsi
  // byte. Bytes 128..159 are printable punctuation in WinAnsi but unassigned
  // C1 controls in Unicode, so a backend doing a Unicode lookup must
  // translate first (see U-1).
  function  GetCharABCWidths(ADC: TPdfPlatformDC;
                             FirstChar, LastChar: cardinal;
                             out AWidths: TPdfCharABCArray): boolean;
  // Read raw TrueType/OpenType table bytes (tag = 4-byte table name, e.g. 'cmap')
  // Returns bytes read, or FontDataError on failure
  function  GetFontData(ADC: TPdfPlatformDC;
                        ATableTag, AOffset: cardinal;
                        ABuffer: pointer; ABufferSize: cardinal): cardinal;
  // Sentinel value returned by GetFontData on error ($FFFFFFFF on all platforms)
  function  FontDataError: cardinal;
end;
```

### IPdfSystemFonts — Font Enumeration

```pascal
IPdfSystemFonts = interface
  // Fill List with UTF-8 encoded font family names available on the system
  procedure EnumTrueTypeFonts(ADC: TPdfPlatformDC;
                              var List: TRawUtf8DynArray);
end;
```

### IPdfPlatformDC — Device Context

```pascal
IPdfPlatformDC = interface
  // Create a compatible device context for font measurements
  // Windows: CreateCompatibleDC(0); Unix/macOS: returns non-nil dummy pointer
  function  CreateDC: TPdfPlatformDC;
  // Release a device context created by CreateDC
  procedure DeleteDC(ADC: TPdfPlatformDC);
  // Return screen DPI (Y axis); Unix/macOS always returns 96
  function  GetScreenLogPixels(ADC: TPdfPlatformDC): integer;
end;
```

---

## Registration

Each backend registers its implementations in the `initialization` section:

```pascal
// In mormot.pdf.gdi.pas (Windows):
initialization
  RegisterPdfPlatform(
    TPdfGdiFontProvider.Create,
    TPdfGdiSystemFonts.Create,
    TPdfGdiDCProvider.Create);

// In mormot.pdf.freetype.pas (Unix/macOS):
initialization
  RegisterPdfPlatform(
    TPdfFreeTypeFontProvider.Create,
    TPdfFreeTypeSystemFonts.Create,
    TPdfFreeTypeDCProvider.Create);
```

The global variables `PdfPlatformFont`, `PdfSystemFonts`, `PdfPlatformDCProvider` in `mormot.pdf.types.pas` are set. The core calls them directly.

```pascal
// Check whether a platform backend has been registered:
if not PdfPlatformRegistered then
  raise ESynException.Create('No PDF platform registered');
```

**Who pulls the units in — `mormot.ui.pdf`, never the application.** Its
interface `uses` takes `mormot.pdf.gdi` on Windows and `mormot.pdf.freetype`,
`mormot.pdf.harfbuzz` and `mormot.pdf.hbsubset` elsewhere. The two HarfBuzz
units load their library at run time and register only when it resolves, so
a missing library leaves shaping or subsetting off — no build dependency.
`hbsubset` opens the same `libharfbuzz` anyway, so the shaper costs nothing.
A program that names a platform unit itself (the tests use
`mormot.pdf.freetype` for `ExtractSfntFromTtc`) does no harm; no program
needs to. Before 2026-09-29 `mormot.pdf.harfbuzz` had to be added by the
application, `layer1_demo` listed the backends, and `rtl_demo` wrongly
required FreeType before HarfBuzz.

**One shaping switch, `UseUniscribe`, on every platform**
(`TPdfWrite.AddUnicodeHexText`):
- Windows: Uniscribe itemizes the run and shapes only complex items; the
  rest takes the simple font
- Linux/macOS: HarfBuzz shapes a run when `RightToLeftText` is set or
  `NeedsShaping` finds a character of a script that needs it (Hebrew, Arabic
  to Myanmar U+0590–109F, Khmer/Mongolian, U+A800–ABFF, presentation forms);
  Latin text keeps the simple font, as with Uniscribe
- `RightToLeftText` is the direction only. HarfBuzz gets RTL forced when it
  is set; otherwise `hb_buffer_guess_segment_properties` takes the direction
  from the script (a forced LTR shaped Arabic in the wrong order). Glyphs come
  back in visual order either way
- Limit: a run mixing Arabic and Latin in one `TextOut` is not bidi-reordered
  on Linux/macOS; HarfBuzz shapes, it does not itemize by direction
- Changed 2026-09-29: HarfBuzz used to run on `RightToLeftText` alone and
  ignore `UseUniscribe`. Code for Linux/macOS that sets only
  `RightToLeftText` now draws unshaped; guarded by `TestShapingSwitch`

---

## Data Types (mormot.pdf.types.pas)

### TPdfLogFont — Font Request Descriptor

```pascal
TPdfLogFont = record
  FaceName:       SynUnicode;  // font family name (e.g. 'Calibri')
  Height:         integer;     // character height in logical units (negative = cell height)
  Weight:         integer;     // FW_NORMAL=400, FW_BOLD=700
  Italic:         integer;     // 0 = upright, 1 = italic
  CharSet:        integer;     // 0 = ANSI_CHARSET
  PitchAndFamily: integer;     // FF_SWISS, FF_ROMAN, etc.
end;
```

### TPdfPlatformFontHandle / TPdfPlatformDC

```pascal
TPdfPlatformFontHandle = type pointer;  // opaque font handle
TPdfPlatformDC         = type pointer;  // opaque device context
```

### TPdfTextMetrics

```pascal
TPdfTextMetrics = record
  tmHeight, tmAscent, tmDescent: integer;
  tmInternalLeading, tmExternalLeading: integer;
  tmAveCharWidth, tmMaxCharWidth: integer;
  tmWeight: integer;
  tmOverhang: integer;
  tmFirstChar, tmLastChar, tmDefaultChar, tmBreakChar: integer;
  tmItalic, tmUnderlined, tmStruckOut: byte;
  tmPitchAndFamily, tmCharSet: byte;
end;
```

### TPdfOutlineMetrics

```pascal
TPdfOutlineMetrics = record
  otmSize:         cardinal;
  otmAscent:       integer;
  otmDescent:      integer;
  otmLineGap:      cardinal;
  otmItalicAngle:  integer;
  otmEMSquare:     cardinal;
  otmrcFontBox:    TRect;        // tight bounding box of all glyphs
  otmMacAscent, otmMacDescent, otmMacLineGap: integer;
  otmCapEmHeight, otmXHeight: cardinal;
  otmStrikeoutPosition, otmStrikeoutSize: integer;
  otmUnderscorePosition, otmUnderscoreSize: integer;
end;
```

### TPdfCharABC

```pascal
TPdfCharABC = record
  abcA: integer;   // pre-character spacing (can be negative)
  abcB: cardinal;  // glyph width (always positive)
  abcC: integer;   // post-character spacing (can be negative)
end;
TPdfCharABCArray = array of TPdfCharABC;
```

Total character advance = `abcA + abcB + abcC`, and that sum is what reaches
`/Widths` in the PDF.

**The sum must equal the scaled advance exactly.** A backend scaling design
units to the 1000-per-em grid rounds each of the three members, and three
roundings accumulate to ±1.5 — enough to break ISO 14289-1 7.21.5, which allows
a deviation of 1 against the embedded font program. Scale the advance once and
give `abcB` the remainder after the two bearings; the bearings stay correct
individually, which is what the other callers of the triple need. See U-1.

---

## Windows Backend (mormot.pdf.gdi.pas)

GDI API mapping:

| Interface method | Windows API |
|---|---|
| `CreateFont` | `CreateFontIndirectW` |
| `DeleteFont` | `DeleteObject` |
| `SelectFont` | `SelectObject` |
| `GetTextMetrics` | `GetTextMetricsW` |
| `GetOutlineMetrics` | `GetOutlineTextMetricsW` |
| `GetCharABCWidths` | `GetCharABCWidthsA` (ANSI — maps the byte through the DC codepage, so bytes 128..159 resolve to their WinAnsi characters; code points above 255 are not reachable through this call) |
| `GetFontData` | `GetFontData` |
| `FontDataError` | returns `GDI_ERROR` ($FFFFFFFF) |
| `EnumTrueTypeFonts` | `EnumFontFamiliesExW` with TRUETYPE_FONTTYPE |
| `CreateDC` | `CreateCompatibleDC(0)` |
| `DeleteDC` | `DeleteDC` |
| `GetScreenLogPixels` | `GetDeviceCaps(DC, LOGPIXELSY)` |

No additional runtime dependency — GDI is part of Windows.

---

## Unix/macOS Backend (mormot.pdf.freetype.pas)

FreeType2 API mapping:

| Interface method | FreeType2 API |
|---|---|
| `CreateFont` | `FT_New_Face` + `FT_Set_Char_Size` |
| `DeleteFont` | `FT_Done_Face` |
| `SelectFont` | internal context switch |
| `GetTextMetrics` | `FT_FaceRec.ascender/descender/height` |
| `GetOutlineMetrics` | `FT_FaceRec.bbox` + scaled values |
| `GetCharABCWidths` | `WinAnsiConvert.AnsiToWide[]`, then `FT_Load_Char` + `horiAdvance` |
| `GetFontData` | `FT_Load_Sfnt_Table` |
| `FontDataError` | returns $FFFFFFFF |
| `EnumTrueTypeFonts` | filesystem scan + `FT_New_Face` |
| `CreateDC` | dummy non-nil pointer (no real DC needed) |
| `DeleteDC` | no-op |
| `GetScreenLogPixels` | constant 96 |

**Font search paths:**

Linux:
- `/usr/share/fonts/**`
- `/usr/local/share/fonts/**`
- `~/.fonts/**`

macOS:
- `/Library/Fonts/**`
- `/System/Library/Fonts/**`
- `~/Library/Fonts/**`

If a font is not found: fallback to DejaVu Sans (Linux) or Helvetica (macOS).

**Runtime library:** `libfreetype.so.6` (Linux) / `libfreetype.6.dylib` (macOS) — loaded dynamically via `dlopen`. If not present: exception on first font access.

---

## Optional: IPdfFontSubsetter (mormot.pdf.hbsubset, Linux/macOS) — R-12

```pascal
TPdfFontSubsetRequest = record
  Unicodes: TIntegerDynArray;  // code points whose cmap entries must survive
  Glyphs: TIntegerDynArray;    // glyph IDs that must survive
end;

IPdfFontSubsetter = interface
  // false: face cannot be subset (CFF, invalid, library error) -> caller
  // embeds AFace unchanged; glyph IDs of ASubset equal those of AFace
  function Subset(const AFace: RawByteString;
    const ARequest: TPdfFontSubsetRequest; out ASubset: RawByteString): boolean;
end;

var PdfFontSubsetter: IPdfFontSubsetter;  // nil = no subsetter
```

- `mormot.ui.pdf` uses `mormot.pdf.hbsubset` on POSIX itself, like the FreeType
  backend: no project-side `uses` needed. Its `initialization` calls
  `LoadHarfBuzzSubset` and registers only when every symbol resolved, so
  `PdfFontSubsetter <> nil` means "usable"
- Two libraries: `hb_subset_*` from `libharfbuzz-subset.so.0` /
  `libharfbuzz-subset.0.dylib`, `hb_blob_*`/`hb_face_*`/`hb_set_*` from
  `libharfbuzz.so.0` / `libharfbuzz.0.dylib` (Homebrew paths tried on macOS)
- Needs HarfBuzz 2.9+ (`hb_subset_or_fail`, `hb_subset_input_set_flags`); older
  libraries leave it unregistered → whole-face embedding
- **HarfBuzz < 10.0 does not fail on a face without glyphs**: `hb_subset_or_fail`
  returns a 12-byte sfnt with no tables instead of nil. Fixed upstream in
  10.0.0 ("Subsetting will now fail if source font has no glyphs"). `Subset`
  therefore treats `numTables = 0` as failure itself — never trust a non-nil
  result alone. `TestSubsetAcceptsCff` (`'OTTO'` + 60 zero bytes) guards it;
  it only bites on such a HarfBuzz (issue #4, Ubuntu 24.04)
- HarfBuzz has no long-term releases. What the distributions ship (Repology,
  2026-10-02):

  | Distribution | HarfBuzz | Subsetting |
  |---|---|---|
  | RHEL / AlmaLinux / Rocky 8 | 1.7.5 | off (< 2.9) |
  | Debian 11, Ubuntu 22.04 LTS, RHEL / AlmaLinux / Rocky 9 | 2.7.4 | off (< 2.9) |
  | Debian 12 | 6.0.0 | on, empty result caught (< 10.0) |
  | Ubuntu 24.04 LTS, openSUSE Leap 15.6 | 8.3.0 | on, empty result caught (< 10.0) |
  | RHEL 10 (CentOS Stream 10) | 8.4.0 | on, empty result caught (< 10.0) |
  | Debian 13 (the Linux dev machine), Ubuntu 25.04 / 25.10 | 10.2.0 | on |
  | Ubuntu 26.04 LTS | 12.3.2 | on |
  | Fedora 43 / 44 | 11.5.1 / 14.1.0 | on |
  | macOS (Homebrew) | 14.5.1 | on |
- Tuning globals: `HbSubsetFlags` (default `RETAIN_GIDS or NOTDEF_OUTLINE or
  NO_HINTING`; `RETAIN_GIDS` is always forced), `HbSubsetDropLayoutTables`
  (default true: drop `GSUB/GPOS/GDEF`). Measured on the untagged
  `markdown_demo` / CJK / Arabic outputs: defaults 44.7 / 10.8 / 15.1 KB,
  keeping the layout tables 46.8 / 11.4 / 17.0 KB, keeping the hinting
  83.8 / 14.7 / 29.1 KB — all three variants render pixel-identically, so the
  smallest is the default. A PDF viewer never shapes text, and the glyph set
  of the request already holds every shaped glyph that was drawn
- Windows registers none and keeps `CreateFontPackage`
- How the engine builds the request and shares the result: `fonts.md` §3

---

## Document-Independent Measurement — TPdfFontMeasurer

`mormot.ui.pdf.pas` exposes the metrics of a face **without a `TPdfDocument`**, so `TGDIPages` can lay out its pages with the widths the PDF will really use (ROADMAP B-5):

```pascal
var M: TPdfFontMeasurer;
M := TPdfFontMeasurer.Create;
try
  if M.SetFont('Helvetica', {bold=}false, {italic=}false, {standardFonts=}true) then
    W := M.TextWidth('Hello', 11);   // PDF points
finally
  M.Free;
end;
```

- `SetFont` repeats `TPdfCanvas.SetFont`'s resolution order: the base-14 AFM tables (`STANDARDFONTS`) when `aStandardFonts` is set and the name is Helvetica/Times/Courier or an alias, otherwise `PdfPlatformFont.CreateFont` on a `Height = -1000` logfont plus `GetCharABCWidths(32, 255)` — i.e. 1000-per-em units, like every other width in the engine.
- Returns `false` when nothing resolves (no backend registered); the caller then falls back to its own measurement.
- Faces are cached per (name, bold, italic, standard-flag) on the measurer instance; `TPdfFaceMetrics` owns the platform font handle and its DC until the measurer is freed.
- Code points above WinAnsi use `DefaultWidth` — the GDI backend's `GetCharABCWidths` is the ANSI call, so per-code-point Unicode widths are not available through this path.

---

## Compiler Switches and `{$ifdef FPC}` (R-21)

Every unit starts with `{$I mormot.defines.inc}` after `interface` (by name, no relative path).

- **Enum size does not reach the C libraries.** `mormot.defines.inc` sets `{$MINENUMSIZE 1}` and `{$PACKSET 1}`, but the bindings in `mormot.pdf.freetype`, `mormot.pdf.harfbuzz` and `mormot.pdf.hbsubset` declare every C enum as `integer` and hold no set. Keep it that way in new bindings.
- **The `{$ifdef FPC}` branches that remain are real differences.** The seven in `mormot.ui.pdf` all come from the original (`reference/`): LCL against VCL units, the compatibility types, and four Windows API calls FPC declares differently — `EnumPrinters` (pointers), `GdiComment` (`var`), `EnumEnhMetaFile` (`RECT`), `CreateFontIndirectW` on a `const` parameter (FPC's `var` overload cannot take it). No mORMot2 function wraps them. `mormot.pdf.gdi` needs no branch: a local `var` fits both. The branches in `mormot.ui.core` and `mormot.ui.gdiplus` come with the mORMot2 originals. The one around all of `mormot.ui.report` is gone since R-20.
- **LCL against VCL units** (R-20): `mormot.ui.pdfcanvas` and `mormot.ui.report` take `LCLIntf`/`LCLType` under FPC and `Windows` under Delphi — `Windows` *before* `Graphics`, or its record `TBitmap` hides the class (dozens of errors on every `TBitmap.Create`).
- **`PDF_CANVASVIRTUAL`** (`mormot.ui.pdfcanvas`, defined under FPC): the LCL's `TCanvas` drawing methods are virtual, Delphi 7's are static. The bridge declares `TextOut`, `TextExtent`, `TextWidth`, `TextHeight`, `Rectangle`, `Ellipse`, `RoundRect`, `Draw` with `override` or `reintroduce` by this switch, and has `DoMoveTo`/`DoLineTo` (LCL) or reintroduced `MoveTo`/`LineTo` (Delphi). `DoLineTo` checks `psClear` itself: `TFPCustomCanvas.LineTo` skips it then, our Delphi `LineTo` does not.
- **Delphi on Linux/Android** (R-27): the POSIX backends load their libraries with `LibraryOpen`/`LibraryResolve`/`LibraryClose` from `mormot.core.os` — FPC's `dynlibs` does not exist there, and `TLibHandle` comes from `System` under FPC, from `mormot.core.os` under Delphi. `mormot.ui.pdf` turns `USE_GRAPHICS_UNIT` off for Delphi on `OSPOSIX` (no VCL): the `TBitmap`/`TGraphic` image API is left out, `GetSysColor` and `MM_TEXT` get local fallbacks. Android: `/system/fonts` is scanned, Roboto is the last fallback face; the app has to ship an NDK-built `libfreetype.so` (a glibc build does not load), and a program without a configured `TSynLog` family crashed in `TSynLog.FillInfo` on the first raised exception — configure it as `TSynTests.RunAsConsole` does.
- **Delphi 7 syntax** met in R-20: every declaration of an overloaded method needs `overload` (FPC accepts it on one); no `Default(T)` — `mormot.ui.report` has `NewCommand` (`Finalize` + `FillChar`); no typed constants with dynamic-array fields — build a `TTableLayout` in a function, zeroed first like a constant's omitted fields.

---

## Adding a New Platform

1. Create new unit `mormot.pdf.<platform>.pas`
2. Implement three classes:
   - `TPdf<Platform>FontProvider(TInterfacedObject, IPdfPlatformFont)`
   - `TPdf<Platform>SystemFonts(TInterfacedObject, IPdfSystemFonts)`
   - `TPdf<Platform>DCProvider(TInterfacedObject, IPdfPlatformDC)`
3. Register in `initialization` via `RegisterPdfPlatform(...)`
4. Add conditional `uses` in the application project

No changes to `mormot.ui.pdf.pas` required.
