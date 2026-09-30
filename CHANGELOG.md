# Changelog

## Unreleased

Written at the next release from the list "To Announce" in
[docs/ROADMAP.md](docs/ROADMAP.md), which collects every change a user notices
until then.

## v0.10.0 — 2026-09-30

PDF/A-3 and hybrid e-invoices (ZUGFeRD / Factur-X), Delphi support from
Delphi 7 to Delphi 13, and a report engine that no longer needs a GUI. Some
changes break existing code — see *Breaking changes* first.

### Breaking changes

- **`TGDIPages` takes `RawUtf8`** for all text — parameters, `TReportFormat`,
  `TTableLayout`, `Title`/`Author`/`Subject`, `ExportPdf*` — and `TFileName`
  for file names. FPC callers compile unchanged, except that
  **`GetReportFonts` and `GetExportFonts` return `RawUtf8`**: an `out`
  parameter needs the exact type, so their `string` variables become
  `RawUtf8`. Code that draws through `TPdfDocumentVcl` without `TGDIPages`
  takes `GetPdfFonts` from `mormot.pdf.types`, which returns `string`.
- **Preview and printing moved out of `TGDIPages`**, which is a non-visual
  `TComponent` now, usable without forms. `Report.ShowPreviewForm` becomes
  `ShowReportPreview(Report)`, `Report.PrintPages(From, To_)` becomes
  `PrintReport(Report, From, To_)`, both in the new unit
  `mormot.ui.reportpreview`. `ShowPrintDialog` (printed without a dialog) and
  `OpenPdfFile` (did nothing) are removed. `Orientation` has the new type
  `TReportOrientation` with the same values `poPortrait`/`poLandscape` — a
  unit that also uses `Printers` after `mormot.ui.report` gets
  `Printers.poPortrait` and a type error; qualify it or drop `Printers`.
  `/Creator` came from `Application.Title`; it is `ExportPdfCreator` now, and
  without it the executable name is written.
- **Shaping is one switch on every platform: `UseUniscribe`** — Uniscribe on
  Windows, HarfBuzz on Linux/macOS. On Linux/macOS `RightToLeftText` alone no
  longer shapes: set `UseUniscribe := True` as well, as Windows always needed.
  `RightToLeftText` only sets the direction; without it HarfBuzz takes the
  direction from the script. Latin text stays in the simple font.
- **`TPdfDocumentVcl.VclCanvas` has the type `TPdfVclCanvas`** (was
  `TCanvas`). Code that assigns it to a `TCanvas` variable still compiles —
  but on Delphi draw through the `TPdfVclCanvas` reference, see *Delphi*.
- **Demo PDFs are named `<demo>_<os>_<cpu>_<compiler>.pdf`** (was
  `<demo>_<os>.pdf`), so the files of all compilers share one folder.

### PDF/A-3 and e-invoices

- **PDF/A-3U with PDF/UA-1** in one file, verified on all three platforms
  with veraPDF (`3u`, `ua1`), Mustang and PAC 2024; `pdfa3A` passes `3a`, and
  PDF/A-3B is verified with and without tagging. New `pdfa3U` (appended to
  `TPdfALevel`), `PdfMetadataFacturX` for the `fx:` XMP properties, and an
  `/AFRelationship` on the file overload of `CreateFileAttachment`. With
  PDF/A and tagging the engine writes the `pdfuaid` extension schema itself.
- **`TGDIPages` exports PDF/A-3 attachments and an XMP extension**:
  `AddExportPdfAttachment`, `ClearExportPdfAttachments`,
  `ExportPdfMetadataExtension`. `mormot.ui.report` re-exports what its
  `ExportPdf*` options take (PDF/A levels, `TPdfFileFormat`, `afr*`,
  `PdfMetadataFacturX`), so a report program needs no other unit of ours.
- **`zugferd_demo`** (new, demo 7) builds a ZUGFeRD / Factur-X invoice,
  profile EN 16931, with `TGDIPages`: the page is read from the embedded
  `factur-x.xml` (third-party KoSIT test data, Apache-2.0), so the two cannot
  differ. The engine provides the container and neither generates nor
  validates invoice XML.

### Delphi

- **Delphi 7 and Delphi 2010** (Win32; Delphi 2010 as the Unicode Delphi)
  build layer 1, the TCanvas bridge and the `TGDIPages` core. All six console
  demos and the `--export` of the two GUI demos build and write the same PDF
  as FPC; PAC 2024 and veraPDF pass them. Build scripts:
  `tests\build_delphi7.bat`, `tests\build_delphi2010.bat`. The preview and
  the demo windows still need FPC (roadmap R-20).
- **Draw through a `TPdfVclCanvas` reference on Delphi.** Delphi 7's
  `TCanvas` methods are static: a call through a plain `TCanvas` writes
  nothing into the PDF. Text beyond ASCII goes through the new `TextOutUtf8`
  and `TextWidthUtf8` of `TPdfVclCanvas`, which take `RawUtf8` on every
  compiler; the `string` methods read `string` as the compiler holds it.
- **Delphi 13 on Win32, Win64, Linux64 and Android64** — contributed by
  [@tobfel](https://github.com/tobfel) in
  [PR #1](https://github.com/martin-doyle/mORMot2-PDF-CrossPlatform/pull/1),
  many thanks. Layer 1 and the FreeType, HarfBuzz and hb-subset backends
  build for Linux64 and Android64; the backends load their libraries through
  `mormot.core.os` now, no longer FPC's `dynlibs`. On Windows the TCanvas
  bridge and the `TGDIPages` core build as well. Delphi has no VCL on Linux
  and Android: `CreateOrGetImage(TBitmap)` and `TPdfImage.Create(TGraphic)`
  are missing there (JPEG goes through `CreateJpegDirect`), and neither the
  bridge nor `TGDIPages` builds. On Android the fonts come from
  `/system/fonts`, and the app ships an NDK build of `libfreetype.so`
  (`tests/delphi13/android/BUILD-FREETYPE.md`). The IDE projects are in
  `tests/delphi13/`. The maintainers have no Delphi 13: these results are the
  contributor's, and further checks depend on the community.

### Other changes

- **No platform unit in your `uses` any more:** `mormot.ui.pdf` brings the
  HarfBuzz shaper itself, like the FreeType2 backend and the subsetter;
  remove `mormot.pdf.harfbuzz` from your `uses` clause or leave it.
- **`GetPdfFonts` and `PDF_FONT_TTF_*`** in `mormot.pdf.types`;
  `GetReportFonts`/`REPORT_FONT_*` stay as aliases.
- **`TTableLayout.GridColor`** colours the cell borders of header, data and
  footer rows; unset it is `clBlack`, as before.
- **`layer1_demo`** (new, demo 8): `TPdfDocument`/`TPdfCanvas` alone, tagged
  headings, text, a figure and a table with `THead`/`TBody`/`TFoot`.
- **Removed:** `pdf_demo_windows`, the Delphi 7 golden master on the original
  library, with its `peekpdf` tools.

### Fixed

- Under FPC a `TPdfReal` of exactly 0 was written as nothing — every outline
  destination (`/XYZ 0 802 ]`, one operand short), alpha 0, a rectangle or
  `/BBox` edge at 0. Files with bookmarks from earlier FPC builds are
  affected.
- The XMP packet header from Unicode Delphi was double-encoded (`C3 AF C2 BB
  C2 BF` instead of the byte order mark `EF BB BF`) in every PDF/A and tagged
  file.
- `/CIDToGIDMap` was written for PDF/A only; PDF/UA-1 7.21.3.2 wants it for
  every `CIDFontType2`.
- PAC 2024 stopped on tagged CJK or Arabic: the WinAnsi peer lacked
  `/FirstChar`, `/LastChar`, `/Widths`.
- Linux/macOS: a `.ttc` face could be embedded as the whole collection
  (23 MB for Hiragino Sans GB), at random, by heap layout.
- Tagged PDF/A freed its `StructTreeRoot` twice on `Free` and skipped `/Lang`
  and `DisplayDocTitle`; untagged PDF/A claimed `/MarkInfo` over an empty
  tree. `pdfuaid` had no extension schema, so every tagged PDF/A failed
  ISO 19005 6.6.2.3.1. An attachment read from a file had `/Params /Size 0`.
- `GetCharABCWidthsI` was imported without `stdcall` (wrong on Win32).
- `TPdfVclCanvas` passed `Font.Name` in the ANSI code page on Delphi 7; it is
  UTF-8 now.
- A paragraph lost its quotation marks — `"quoted text"` came out as
  `quoted text` — and the quoted part could not wrap.
- `mormot_demo --export` hung in a fresh clone on a modal error dialog,
  because `data/` was missing. The folder is versioned and created if
  missing; a failed `--export` of `mormot_demo` or `report_demo` ends with
  exit code 1 and the reason on stderr.

### Verification

`test_runner` is green with 259 assertions on Windows (FPC, Delphi 7 and
Delphi 2010), 298 on Linux and 317 on macOS; the differences are skips. The
tagged demos pass PAC 2024 and veraPDF `ua1` on all three platforms, from
every compiler; `zugferd_demo` also passes veraPDF `3u` and Mustang.
Delphi 13, from the contributor: 259/259 on Win32 and Win64, 171/171 on
Linux64 (LMDE 7), 129/129 on Android64.

### Known limitations

- **Delphi:** no preview window and no demo window yet (R-20); on Linux and
  Android no TCanvas bridge and no `TGDIPages`; the demos are untried with
  Delphi 13, and Delphi for macOS is untried.
- **Android:** HarfBuzz and hb-subset are not packaged — no shaping, whole
  faces embedded.
- **Links in tagged output:** `CreateHyperLink` in a tagged document fails
  PDF/UA; `TGDIPages.DrawLink` draws link-styled text without a URL (R-18).
- **PDF/A-1 and -2** are implemented, not verified; PDF/A-1 accepts
  attachments although it forbids them.
- From v0.9.0, still open: symbolic fonts are not subset on POSIX (R-15b),
  table rows do not split across pages (R-10), only face index 0 of a `.ttc`
  is reachable (R-11), EMF and GDI+ gradients are Windows-only.

## v0.9.0 — 2026-09-23

First tagged release. Cross-platform PDF and report generation for Windows,
Linux and macOS, with tagged (PDF/UA-style) output verified by two independent
checkers on all three platforms.

### Verification

The four tagged demos — `pdf_demo`, `markdown_demo`, `report_demo`,
`mormot_demo` — pass **veraPDF 1.30.2** (`ua1` profile, 106/106 rules) and
**PAC 2024** on Windows, Linux and macOS. `chinese_demo` and `rtl_demo` are
untagged by design, but satisfy the glyph-width rule everywhere as well.

`mormot_demo` renders a 206-row table from an SQLite database across 5 pages and
produces **one** `Table` element: 207 `TR` (1 header + 206 data rows), 1030 `TD`
(206 × 5 columns), 5 `TH`. The header repeated on continuation pages is marked
as an artifact and opens no second `THead`.

Test suite green on all three platforms: 239 assertions on macOS, 222 on Linux.
The difference is skips, not failures — tests stand down when the machine lacks
what they need (no `.ttc` collections on Linux, no Arabic face there that
applies a GPOS offset) and say so rather than reporting a green they did not
earn. Linux runs two assertions macOS cannot, having Droid Sans Fallback
installed, so the platforms complement each other rather than one covering a
subset of the other.

**The fallback without `libharfbuzz-subset` is measured, not simulated.**
`tests/no_hbsubset.sh` masks the library inside a mount namespace and runs the
suite again: it stays green at 197 assertions, with the two subset suites
standing down (19 → 7, 22 → 9) instead of failing. The nine that remain include
the tests for the whole-face path itself.

### Fixed in this release

- **U-1 — glyph widths disagreed with the embedded font program on POSIX**
  (ISO 14289-1 7.21.5). Two independent causes in the FreeType backend's
  `GetCharABCWidths`. First, an ANSI/Unicode mix-up: the engine passes WinAnsi
  *byte* values, matching the Windows `GetCharABCWidthsA` it mirrors, but the
  byte was handed to `FT_Load_Char`, which expects a Unicode code point. Bytes
  128–159 are printable punctuation in WinAnsi and unassigned C1 controls in
  Unicode, so the bullet (`#$95`) and em dash (`#$97`) missed the CMAP and were
  written with the `.notdef` advance. Second, the three ABC members were scaled
  separately although every consumer sums them, accumulating three roundings
  where the rule allows one unit. Failure counts on the tagged demos went
  5 → 0, 64 → 0, 63 → 0 and 99 → 0 on Linux, and 11 → 0 and 83 → 0 on macOS.

- **U-2 — a shaped Arabic glyph carried the shaper's advance in `/W`.**
  HarfBuzz returns the *positioned* advance, so a cursively attached glyph comes
  back shortened by exactly the amount it is offset. `/W` must state the
  unpositioned advance from `hmtx`. Both errors cancelled out on screen, which
  is why the defect was invisible in viewers and in PAC. The width now comes
  from the font's own `hmtx` table, and the emitted `TJ` array compensates any
  difference so the rendered text is unchanged — verified by recomputing the pen
  movement, not only by re-running the checker.

Both fixes are in POSIX code; Windows was already correct and served as the
reference for the expected values.

One test was fixed too, and it is worth naming because it was wrong in an
instructive way. `TestWinAnsiHighRangeWidths` asserted that the bullet's advance
differs from the `.notdef` advance, treating equality as proof of a failed
lookup. Nothing stops a font from giving `.notdef` the same advance as a real
glyph, and the face picked on Linux does exactly that — so a correct lookup
failed the check. It now compares two *unmapped* WinAnsi codes with each other
instead, which assumes nothing about the face's metrics.

### Known limitations

Documented in `docs/ROADMAP.md`, and none of them blocks normal use:

- The **U-2 fix is exercised on macOS only.** No Linux Arabic face reaches the
  code path it repairs — Noto Naskh Arabic resolves shaped glyphs through the
  CMAP — so the regression test skips itself there rather than reporting a
  false green.
- The **fallback without `libharfbuzz-subset`** is verified for a *missing*
  library (`tests/no_hbsubset.sh`, see Verification above), but not for a **HarfBuzz older
  than 2.9**, which loads and then turns out to lack `hb_subset_or_fail`. That
  needs an old distribution to test. Without a usable subsetter the whole face
  is embedded, which is correct but produces much larger files.
- **Symbolic fonts are not subset on POSIX** (R-15b), **table rows do not split
  across pages** (R-10), and **only face index 0 of a `.ttc` is reachable**
  (R-11).
- **EMF/metafile input and GDI+ gradients remain Windows-only** by nature.
