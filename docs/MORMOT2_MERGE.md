# Merging into mORMot2 — Plan

Goal: bring the cross-platform PDF/report engine into synopse/mORMot2 in a form
the maintainer can merge. Working branch: `mormot2-merge`. State of the analysis:
2026-09-30, fork `d5851ec`, mORMot2 `cbc906b6b`.

This file is a working document for the fork. It does not go upstream.

**Maintainer direction** (forum thread 7604, post #11, 2026-09-24, ab): "We could
define a new "src/pdf" folder for the units, not any more in "src/ui". The
mormot.pdf.xxxx.pas unit names just show this pattern." — so the target is
`src/pdf/mormot.pdf.*`, not `src/ui`; the table in §2 is to be read with that.

**Step 1 done** (upstream catch-up, see §4): all upstream `mormot.ui.pdf` commits
since the base ported, `EMR_ALPHABLEND` re-enabled, `mormot.ui.core`/`gdiplus`
replaced by the upstream files (include path only differs), the fork's copy of
`mormot.lib.uniscribe` removed — `GetGlyphIndicesW` is imported in
`mormot.ui.pdf` itself (mORMot2's `mormot2.lpk` now ships `mormot.lib.uniscribe`,
so the fork's copy was shadowed; this also made aarch64-win64 fail).
Verified: aarch64-win64 FPC 3.3.1 259/259, Delphi 13 Win32 and Win64 259/259
(against mORMot2 `31cf2232a`: `cbc906b6b` itself does not compile on Delphi 13,
`PCCERT_CONTEXT` clash in `mormot.net.sock.windows.inc` — upstream issue),
aarch64-linux FPC 3.2.2 291/296 (5 = CJK/Arabic/CFF fonts missing on the machine,
same as before the change).

## 1. Where the fork stands against mORMot2

### Base drift

- `reference/mormot.ui.pdf.pas` matches upstream `63d06371a` (2026-03-08).
  `reference/mormot.ui.report.pas` matches upstream blob `01b411665d`.
  The effective base is `63d06371a` … `056420a96`.
- Upstream commits to `mormot.ui.pdf.pas` since then are all missing in `src/core`:

  | Commit | Change | Port |
  |---|---|---|
  | `d76f5d793` | PT_BEZIERTO in EMR_POLYDRAW(16) used points i+1..i+3 | **bug fix, must** |
  | `b2b130b58` | `EMR_ALPHABLEND`/`TEMRAlphaBlend` for FPC (in `mormot.ui.core`) | **must**, then re-enable the case in pdf.pas |
  | `aa24b524b` | pointer-to-ordinal casts (`PtrUInt`, `inc(PByte(..))`) | yes |
  | `3f78c7372` | local `SwapBuffer` → core `bswap16array` | yes, all call sites |
  | `7b86aadd1` | `UINT_999[].TextLo`, no ASMINTEL branch | yes |
  | `d10e522e9` | `StrIEqual` | yes |
  | `204f619ab` | `Seek(0, soCurrent)` → `Position` | yes |
  | `3ca9cffbf` | `TTemp512`/`TTemp16`/`TTemp4` | yes |
  | `286703156` | comment | yes |
  | `801445bff`, `cf21f26e9` | `{$ifndef HAS_UI_PDF}` empty-unit guard | redesign, see §3 |

- `mormot.ui.report.pas` is a rewrite (`TGDIPages = class(TComponent)`, upstream
  `TGdiPages = class(TScrollBox)`; 179 of 199 upstream members gone, no EMF, no
  encryption, preview in a separate LCL-only unit). Upstream report commits since
  the base (`7f330f690` ExportPdfStream(aRaiseException), `59f3eb7db` ExportPdf error
  propagation, `01cf8676d` owner password default) apply as ideas only.
  Upstream still has `PDFFileName := dlg.Name` (should be `dlg.FileName`) in
  `ExportPdf` — worth a separate small upstream fix.
- `src/core/mormot.ui.core.pas` and `mormot.ui.gdiplus.pas` are stale copies that only
  undo upstream work: drop them, use upstream.
- `src/lib/mormot.lib.uniscribe.pas`: the only real change is the additive
  `GetGlyphIndicesW` import + `GGI_MARK_NONEXISTING_GLYPHS` (glyph keep list for
  `CreateFontPackage`). Also needed because FPC's `windows` unit lacks them on
  aarch64-win64 (build fails there at `mormot.ui.pdf.pas:7408`).

### Upstream test `test/test.ui.pdf.pas` (`TTestUiPdf`, PR #571)

Registered in `mormot2tests.dpr` under `HAS_UI_PDF` (Windows + VCL/LCL). It checks
byte-exact `Hash32` of generated PDFs. The fork changed the embedding path
(glyph keep list) and writer internals, so the hashes are expected to change:
run it against the fork on Windows first, then decide per hash. Tests 2, 4, 5, 6
need metafile/`TPdfDocumentGdi` → need a Windows-only guard once the unit
compiles on POSIX.

### Rule violations (mORMot2 conventions, derived from the upstream tree)

Blocking:
1. Unit names/folders: `src/core/` holds `mormot.ui.*`/`mormot.pdf.*` (core must be
   RTL-only `mormot.core.*`), `src/platform/` and the `mormot.pdf.` prefix do not
   exist in mORMot2 (`src/README.md`, `src/FOLDER-DEPENDENCIES.md`).
2. Library loading: FreeType/HarfBuzz/hb-subset use hand-written
   `LibraryOpen`/path chains and load in `initialization`. mORMot2 pattern:
   `class(TSynLibrary)` + `TryLoadResolve` + lazy `XxxIsAvailable`, nothing in
   `initialization` (see `mormot.lib.curl.pas`).
3. API break of `TGdiPages` (see above).
4. `HAS_UI_PDF` gate removed → `NO_UI`/`NO_UI_PDF` ignored.
5. `examples/zugferd_demo/factur-x.xml` is Apache-2.0: not compatible with the
   GPL-2.0 option of mORMot's MPL/GPL/LGPL licence → replace with own sample data.

Conventions (mechanical, large):
- licence header missing in 9 of 13 units, all tests, examples; no `{ *** }`
  section blocks in the new units
- `{$I mormot.defines.inc}` → `{$I ..\mormot.defines.inc}` (tests `..\src\`)
- `MSWINDOWS`/`DARWIN`/`UNIX` → `OSWINDOWS`/`OSDARWIN`/`OSPOSIX`;
  `PDF_HASVCLCANVAS` → defines.inc; `PDF_CANVASVIRTUAL`; uppercase `{$IFDEF}`;
  `Graphics`/`Forms` without `NEEDVCLPREFIX`
- formatting in report/reportpreview/pdfcanvas/backends: `Result`/`Exit`/`True`,
  capitalised simple types, one-line `if`, aligned declarations, `// ----`
  separators, `{ }` comments, several units per uses line
- ~85 comment references to ROADMAP items (`R-nn`, `B-n`, PAC, MIGRATION_PLAN,
  "Phase n"), ~20 German comment lines, ~104 non-ASCII lines in `src/`
- `raise Exception.Create` (10×), `Format` (33×) in report; `FindFirst`/
  `GetEnvironmentVariable` in the FreeType backend
- `TGDIPages` → `TGdiPages`; placeholder GUIDs (`{A1B2C3D4-…}`) in
  `mormot.pdf.types`/`fpimage`; `mormot.pdf.fpimage` unused
- tests: own runner and names; mORMot2 wants `test/test.ui.*.pas` with
  `TTestUi…(TSynTestCase)` registered in `mormot2tests.dpr`, skipping cleanly
  when fonts/libraries are missing (on WSL without CJK/Arabic/CFF fonts 5 of 296
  assertions fail instead of skipping)
- examples: `.dpr` + `.lpi` pairs under `ex/<kebab-name>/`
- packages: `packages/lazarus/mormot2ui.lpk` / `mormot2.lpk`, `src/ui/README.md`,
  `src/lib/README.md`, `CONTRIBUTORS.md`
- not for upstream: `reference/`, `.claude/`, `CLAUDE*.md`, `docs/`, `README*`,
  `CHANGELOG.md`, test runner projects, `*.bat`, `no_hbsubset.sh`

## 2. Proposed target layout in mORMot2

Revised after ab's answer of 2026-10-01 (§3). Proposal, not agreed yet:

| Unit | Content | LCL/VCL |
|---|---|---|
| `src/lib/mormot.lib.freetype.pas` | thin FreeType2 binding, `TSynLibrary`, lazy | no |
| `src/lib/mormot.lib.harfbuzz.pas` | thin HarfBuzz + hb-subset binding, `TSynLibrary`, lazy | no |
| `src/pdf/mormot.pdf.core.pas` | PDF objects, writer, `TPdfDocument`, `TPdfCanvas`, the font backend interfaces (today `mormot.pdf.types`); candidate for a further split (fonts/TrueType, tagging/structure, PDF/A + XMP) | **no** |
| `src/pdf/mormot.pdf.gdi.pas` | Windows font backend on plain GDI | no |
| `src/pdf/mormot.pdf.freetype.pas` | POSIX font backend on `mormot.lib.freetype` | no |
| `src/pdf/mormot.pdf.harfbuzz.pas` | POSIX shaper and subsetter on `mormot.lib.harfbuzz` | no |
| `src/pdf/mormot.pdf.graphics.pas` | `TGraphic`/`TBitmap` images, `TMetaFile` + `TPdfDocumentGdi` (Windows) | yes |
| `src/pdf/mormot.pdf.canvas.pas` | TCanvas bridge (`TPdfDocumentVcl`) | yes |
| `src/pdf/mormot.pdf.report.pas` (+ `.preview`) | the report engine | yes |
| `src/pdf/mormot.pdf.reader.pas` | new: PDF reader (xref chains, incremental updates, object streams, filters, standard security handler, embedded files) | no |
| `src/ui/mormot.ui.pdf.pas`, `mormot.ui.report.pas` | open: kept for existing users, or a thin compatibility layer over `src/pdf` | yes |

Not going upstream: `src/core/mormot.ui.core.pas`, `mormot.ui.gdiplus.pas` (upstream
copies), `mormot.pdf.fpimage.pas` (unused).
Tests: `test/test.pdf.*.pas` registered in `mormot2tests`; examples: a few in `ex/`.

Reader starting point: `intf.XRechnungPdfExtract.pas` in XRechnung-for-Delphi
(Landrix, GPLv3 + commercial; Landrix owns it and contributes it under
mORMot's MPL/GPL/LGPL).
It resolves the object graph through the xref chain (incremental updates, so a
replaced invoice is not picked up), rebuilds a broken xref by scanning, decodes
Flate/LZW (+ predictor), ASCIIHex, ASCII85, RunLength, and reads RC4-encrypted
files with an empty user password. For mORMot its own MD5/RC4/zlib go to
`mormot.crypt.core`/`mormot.lib.z`, and the code to mORMot style.

## 3. Open questions

Answered by ab (forum 7604, 2026-10-01):
- **Q1 Backends:** libraries as `mormot.lib.*.pas` as far as possible; no
  `windows.inc`/`posix.inc` include files ("very badly supported by the Delphi IDE").
- **Folder/units:** instead of one huge `mormot.ui.pdf.pas`, several smaller units
  — that is the point of a folder of its own. Folder name open: `pdf/`, or
  `report/`/`export/` holding reporting as well — "worth discussing".
- **LCL/VCL-free raw PDF generator:** wanted. (The fork has it on Delphi
  Linux/Android already: `USE_GRAPHICS_UNIT` off.)
- **PDF reader:** "a well demanded improvement", to be prepared.

Still open:
- **Q2 Report:** replace `mormot.ui.report` (`TGdiPages`, a `TScrollBox` with a much
  bigger API) or a new unit next to it.
- **Q3 `HAS_UI_PDF`:** with an LCL/VCL-free core the PDF units need no UI flag; the
  Graphics-based units get one (Windows + VCL/LCL for the metafile part).
- **Q5 Folder name** and whether `mormot.ui.pdf`/`mormot.ui.report` stay.
- **Q4 PR sequence:** (a) upstream catch-up, (b) `mormot.lib.freetype`/`harfbuzz`,
  (c) the split into `src/pdf` with an LCL/VCL-free core, (d) canvas bridge and
  graphics, (e) report, (f) tests/examples, (g) reader.

## 4. Order of work in this fork

1. Catch up with upstream: port the commits of §1 into `src/core/mormot.ui.pdf.pas`,
   drop the stale `mormot.ui.core`/`gdiplus` copies.
2. Mechanical conventions that do not depend on Q1–Q3: headers, include style,
   OS conditionals, comment cleanup, ASCII, exceptions, `FormatUtf8`, GUIDs.
3. `TSynLibrary`-based bindings `mormot.lib.freetype`/`mormot.lib.harfbuzz`.
4. Layer 1 without LCL/VCL: move the `Graphics`-dependent parts out of the core.
5. After Q2/Q5: renames/moves into `src/pdf`, report strategy, `HAS_UI_PDF`.
6. Tests into `test.pdf.*` form, examples, packages, READMEs.
7. Reader, from the XRechnung extractor.

Each step: build `test_runner` (Windows aarch64-win64, WSL aarch64-linux with FPC
3.2.2/3.2.4/3.3.1, Delphi 13 Win32/Win64) and compare the demo PDFs
(ROADMAP "Checking a change").
