# mORMot PDF Cross-Platform — Implementation Roadmap

Open work only. Finished work is in the git history, and the technical knowledge
it produced in `.claude/skills/` — this file repeats neither.

**State on 2026-09-27.** The engine is cross-platform, writes PDF 1.7, and its
tagged output passes PAC 2024 with accepted warnings only (W-1, a hint on
every Figure; W-2, e-mail addresses without links in `zugferd_demo`) and veraPDF
`ua1`. PDF/A-3U with PDF/UA-1 is verified (R-17). Fonts are embedded and subset
on all three platforms; tables carry `THead`/`TBody`/`TFoot` row groups. All
three platforms build with FPC; `test_runner` is green with 243 assertions on
Windows, 282 on Linux and 302 on macOS (after the fourth R-20 step).
**Layer 1 builds on Delphi 7** (R-19, done), and since R-20 step 4 the
TCanvas bridge and the `TGDIPages` core too: 243 assertions on Win32, and the
tagged Unicode test file passes PAC 2024 and veraPDF `ua1` from Delphi 7/Win32
and FPC/Win64 alike. The macOS run found a heap-dependent `.ttc` defect in the
FreeType backend, fixed (`fonts.md` §3). The Linux re-run is done up to
veraPDF on its files (V), and its post-R-21 files pass veraPDF. R-21 is done
on all three platforms. R-23 is
done: `layer1_demo` builds with FPC on all three platforms and with Delphi 7,
and passes PAC 2024 and veraPDF `ua1` everywhere. The six console demos
build with Delphi 7 (R-20 step 5), and the batch export of the two GUI demos
(step 6); their Delphi 7 files pass PAC 2024 and veraPDF `ua1`, and Linux and
macOS were re-checked after step 6 (2026-09-28). **Next:** R-20, the preview
on the VCL.

---

## To Announce — the Next Forum Post

Changes a user of the library notices: API, behaviour, fixed output. Collected
here until the post is written, then the list is emptied. Candidates from
before this list was started (2026-09-27) are marked "check": whether an
earlier post covered them.

- **Delphi 7** (check): layer 1 — `TPdfDocument`/`TPdfCanvas`, GDI backend,
  Uniscribe — builds on Delphi 7, Win32 (R-19). `layer1_demo` is the first
  demo for it, tagged and PDF/UA-conformant from both compilers (R-23)
- **Fixed** (check): under FPC a `TPdfReal` of exactly 0 was written as
  nothing — every outline destination (`/XYZ 0 802 ]`, one operand short),
  alpha 0, a rectangle or `/BBox` edge at 0. Files with bookmarks from FPC
  builds before the fix are affected
- **`TPdfVclCanvas`**: new `TextOutUtf8` and `TextWidthUtf8` taking
  `RawUtf8`, the same on every compiler. The `string` methods read `string`
  as the compiler holds it (unchanged under FPC)
- **Removed** (check): `pdf_demo_windows`, the Delphi 7 golden master on the
  original library, with its `peekpdf` tools
- **`TGDIPages` takes `RawUtf8`** for all text — parameters, `TReportFormat`,
  `TTableLayout`, `Title`/`Author`/`Subject`, `ExportPdf*` — and `TFileName`
  for file names. FPC callers compile unchanged, except that
  **`GetReportFonts` and `GetExportFonts` now return `RawUtf8`**: an `out`
  parameter needs the exact type, so their `string` variables become
  `RawUtf8`. Code that draws through `TPdfDocumentVcl` without `TGDIPages`
  takes `GetPdfFonts` from `mormot.pdf.types` instead, which returns
  `string` — the demos do so now
- **Fixed:** a paragraph lost its quotation marks — `"quoted text"` came out
  as `quoted text` — and the quoted part could not wrap, because the words
  were split with `TStringList.DelimitedText`, which treats `"` as a quote
  character (`markdown_demo`'s Alan Kay quote)
- **Preview and printing moved out of `TGDIPages`:** it is a non-visual
  `TComponent` now, usable without forms. `Report.ShowPreviewForm` becomes
  `ShowReportPreview(Report)`, `Report.PrintPages(From, To_)` becomes
  `PrintReport(Report, From, To_)`, both in the new unit
  `mormot.ui.reportpreview`. `ShowPrintDialog` (printed without a dialog)
  and `OpenPdfFile` (did nothing) are removed. `Orientation` is of the new
  type `TReportOrientation` with the same values `poPortrait`/`poLandscape`
  — a unit that also uses `Printers` after `mormot.ui.report` gets
  `Printers.poPortrait` and a type error; qualify it or drop `Printers`.
  New `ExportPdfCreator` for `/Creator`, which came from
  `Application.Title`: a GUI application sets it to its title, otherwise
  the executable name is written
- **Delphi 7 builds the TCanvas bridge and the `TGDIPages` core**:
  `test_runner` 243/243 as with FPC, and `markdown_demo` writes the same PDF
  as its FPC build. The rule for Delphi: draw through a `TPdfVclCanvas`
  reference — Delphi 7's `TCanvas` methods are static, a call through
  `TCanvas` writes nothing into the PDF. **`TPdfDocumentVcl.VclCanvas` now
  has the type `TPdfVclCanvas`** (was `TCanvas`); code that assigns it to a
  `TCanvas` variable still compiles
- **All six console demos build with Delphi 7** (`pdf_demo`, `chinese_demo`,
  `rtl_demo`, `zugferd_demo` besides `layer1_demo` and `markdown_demo`) and
  write the same PDF as with FPC. **Every demo now names its PDF
  `<demo>_<os>_<cpu>_<compiler>.pdf`**, as `layer1_demo` did (was
  `<demo>_<os>.pdf`), so the files of all compilers share one folder
- **The GUI demos' `--export` builds with Delphi 7** as well: `report_demo`
  and `mormot_demo` (ORM and static SQLite included) build their report in
  a `uReport.pas` without a form — the pattern for a report that has to run
  without a GUI
- **Coming with R-20** (announce when done): the preview and the GUI demos
  on Delphi

---

## Working Method

**One fix at a time.** Implement, verify, accept, then start the next. Changes
to `BeginStructContent` and the structure tree are unattributable when bundled —
a PAC error like "unbalanced marked content" then names no culprit.

| Role | System |
|---|---|
| Development, build, fast iteration | **Linux** |
| PAC 2024 + tag-tree inspection | **Windows** (only platform; mandatory) |
| Third-platform verification per change | macOS |
| Delphi 7 build and Win32 run (R-19) | **Windows** VM with Delphi 7 (`dcc32`) |
| `veraPDF` (`ua1`, `3b`, `3u`, `3a`) | installed on macOS since 2026-09-22; the Windows and Linux files are copied there |

**PAC caveat.** The traffic-light status is not enough: a flat tree of
individually valid `Table`/`TR`/`TD` elements passes while the nesting is
broken. Always open the *Logical Structure* view as well.

**Toolchain.** The paths of the individual development machines are not part of
this repository; record them in `CLAUDE.local.md` (not versioned,
`CLAUDE.local.md.example` shows the format). A Lazarus installed outside the
distribution packages usually leaves `lazbuild` off `PATH` — use the full path
then. What holds regardless of the machine:

**Linux.** Linking the demos needs the GTK2 development symlinks, which
distributions do not always install: symlink `libgtk-x11-2.0.so`,
`libgdk-x11-2.0.so` and `libatk-1.0.so` to their `.so.0` files in a scratch
directory and build with `lazbuild --opt=-Fl<dir>`.

**Windows.** Target **x86_64-win64**; an aarch64-win64 FPC is not usable —
mORMot2 ships no static libraries for it. Build every project with `-B`: stale
`.ppu` files in `examples/*/lib/` outlive a unit-path change and will hide it.
Where the only `pdftotext` available is xpdf's rather than poppler's, there is
no `-bbox` — use `-layout` for column and line alignment. Without `pdffonts`,
`/BaseFont` survives as plain text in an uncompressed file, so
`grep -a -oE "/BaseFont[ ]*/[A-Za-z0-9+,#_-]+"` tells a subset (six-letter
prefix) from a whole face well enough.

**macOS.** Target **aarch64-darwin**. Linking prints a wall of `ld: warning:
object file ... built for newer macOS version (11.0) than being linked
(10.15)` — noise from the prebuilt mORMot2 units, not an error. HarfBuzz from
Homebrew (`/opt/homebrew/lib`) is on one of the paths `mormot.pdf.hbsubset`
probes, so no linker flag is needed; `hb-info` ships with it and is the
quickest way to tell a CFF face from a `glyf` one. Where the poppler tools are
missing, output is checked by file size and by reading the font dictionaries
with `python3` — inflating the object streams first, since the tagged demos
deflate `/BaseFont` out of reach of the grep.

**`--export` needs no display on macOS.** The Cocoa widgetset runs both GUI
demos headless; the `xvfb-run` advice is Linux/GTK2 only.

**Checking a change.** Build all six demos and `test_runner`, then compare the
PDFs with the previous run: file size, `pdffonts`, `pdftotext` output, and the
pages rendered with `pdftoppm -r 110 -png` compared pixel by pixel. A change
that is meant to be invisible has to come out pixel-identical. A pixel
comparison is valid **within** one platform only — see V below.

---

## Open

### R-20 — Delphi: the TCanvas Bridge and `TGDIPages` — priority 2

**The obstacle, checked against the source 2026-09-25.** `TPdfVclCanvas =
class(TCanvas)` overrides `TextOut`, `TextExtent`, `TextWidth`, `TextHeight`,
`Rectangle`, `Ellipse`, `RoundRect`, `Draw`, `DoMoveTo` and `DoLineTo` — all
virtual in the LCL. In Delphi 7's `Graphics.pas` only `Changed`, `Changing` and
`CreateHandle` are virtual; `DoMoveTo`/`DoLineTo` do not exist; and the unit
uses `LCLIntf`/`LCLType` unconditionally.

With `reintroduce` it would compile, but a call through a `TCanvas` reference —
`C := Doc.VclCanvas; C.TextOut(…)` in every demo, and
`TGDIPages.RenderPageToCanvas(ACanvas: TCanvas)` — binds statically to the VCL
method. That draws through GDI onto the measuring DC, and the PDF stays empty.
**FPC shows the same effect today** for the four methods the bridge already
reintroduces (`FillRect`, `Polyline`, `Polygon`, `StretchDraw`): this is why
`RenderPageToCanvas` uses `Rectangle` instead of `FillRect`.

**Approach — option B.** Under Delphi the caller holds the concrete type:
`VclCanvas` returns `TPdfVclCanvas`, the methods are reintroduced, and
`TGDIPages` gets a render path taking a `TPdfVclCanvas`. The preview keeps
drawing on a real VCL canvas. The limit has to be documented: code that draws
through a plain `TCanvas` reference writes nothing into the PDF.

**`TGDIPages` does not exist under Delphi today.** `mormot.ui.report` is
wrapped in `{$IFDEF FPC}`; under Delphi it is an empty stub pointing to the
original in `mORMot2/src/ui`, which must never be on the search path. So R-20
ports it: besides `LCLType`/`LazFileUtils`, `TFPGMap<string, …>` needs a
replacement (Delphi 7 has no generics).

**Strings — decided 2026-09-27: `RawUtf8` inside, conversion at the GUI only.**
1. **`TGDIPages` takes `RawUtf8`** wherever it takes text today as `string`:
   the `Draw*` methods, `SetHeader`/`SetFooter`, the table rows (`array of
   RawUtf8`), `Title`/`Author`/`Subject`, the `ExportPdf*` texts, font and
   format names. `TDrawCommand` stores `RawUtf8`. FPC/LCL callers do not
   change (their `string` holds UTF-8 already); a Delphi 7 caller converts
   with `StringToUtf8`, otherwise non-ASCII arrives garbled without an error —
   to be documented. No `string` overloads: under FPC the call would be
   ambiguous. The original's `DrawText`/`DrawTextU`/`DrawTextW` triple is not
   followed; our signatures differ from it anyway.
2. **The bridge keeps `string`** where `TCanvas` dictates it (`TextOut`,
   `TextWidth`, …) and reads it per compiler: FPC as UTF-8, Delphi 7 from the
   ANSI code page, Unicode Delphi as UTF-16. mORMot2's `StringToUtf8` and
   `StringToSynUnicode` do exactly that, so `TextOut` switches from
   `UTF8Decode` (UTF-8 on every compiler) to `StringToSynUnicode`, as
   `TextWidth` already uses `StringToUtf8`. Beside them the bridge gets
   `RawUtf8` methods (`TextOutUtf8`, `TextWidthUtf8`, …, separately named),
   which `TGDIPages` uses.
   **Checked 2026-09-27, no defect:** `TextOut` (`UTF8Decode`) and
   `TextWidth` (`StringToUtf8`) read the same UTF-8 under FPC, whatever the
   unit order and with Windows on cp1252: `mormot.core.os` calls
   `SetMultiByteConversionCodePage(CP_UTF8)` on FPC before
   `mormot.core.unicode` sets `CurrentAnsiConvert`. Measured with two probe
   programs (LCL first, mORMot2 first): both 65001, the same 46.008 pt for
   "ÄÖÜ" in Arial 12.
3. **`TGDIPages` is split:** a core without GUI (recording, layout, PDF
   export; `RawUtf8` throughout) and the preview and printing in their own
   unit, converting only when they draw on the screen. The core builds under
   Delphi first, the `--export` path of the GUI demos with it; the preview
   and the `.dfm` of the GUI demos follow.
4. **File names are `TFileName`** (`ExportPDF`): a boundary to the operating
   system, the mORMot2 convention.

Optional, for consistency down to layer 1: a `TPdfCanvas.TextOutUtf8`, so
callers need not go through `Utf8ToSynUnicode` + `TextOutW` as `layer1_demo`
does.

**Step 1, point 2 — done on Windows, 2026-09-27:** `TextOutFrac` decodes with
`StringToSynUnicode`, `TextOutUtf8` and `TextWidthUtf8` are new,
`TextWidthFrac` delegates to `TextWidthUtf8`. `TestVclCanvasUtf8Text` (4
assertions) fails 1/4 with the UTF-8 decoding of either method broken;
`test_runner` 241/241. The eight demo PDFs are the same apart from date and
`/ID`. Linux 280/280 and macOS 300/300 on 2026-09-27, the tagged demos of all
three platforms pass veraPDF `ua1`.

**Step 2, point 1 — done on Windows, 2026-09-27:** `TGDIPages` on `RawUtf8`,
still FPC-only. Every text parameter, record field, property and the format
registry key are `RawUtf8`, file names `TFileName`; conversion only towards
the LCL (`Utf8ToString`) and layer 1's `string` API. `RenderPageToCanvas`
draws on the bridge with `TextOutUtf8`. `GetReportFonts`/`GetExportFonts`
return `RawUtf8`, so the three report demos changed their variables, and the
four TCanvas demos call `GetPdfFonts` and no longer use `mormot.ui.report`.
Word splitting moved from `TStringList.DelimitedText` to
`CsvToRawUtf8DynArray`, which fixed lost quotation marks (see "To
Announce"); `TestParagraphKeepsQuotes` fails 1/2 on the old unit.
`test_runner` 243/243. Seven demo PDFs are the same apart from date and
`/ID`; `markdown_demo` differs only in the quote, now with its quotation
marks. Linux 282/282 and macOS 302/302 on 2026-09-27, as expected.

**Step 3, point 3 — done on Windows, 2026-09-27:** `TGDIPages` is a
non-visual `TComponent` — it was a `TScrollBox` nobody placed on a form. The
new unit `mormot.ui.reportpreview` holds `ShowReportPreview(Report)` and
`PrintReport(Report, From, To_)`, both on the public API only. The core lost
`Controls`, `Forms`, `ExtCtrls`, `StdCtrls`, `ComCtrls`, `Dialogs`,
`Printers`, `LazFileUtils` and `fgl`: `Orientation` has its own
`TReportOrientation` (same value names), the format registry is two arrays
with `FindRawUtf8`, the measuring DPI comes from the bitmap's
`Font.PixelsPerInch` instead of `Screen`, and `/Creator` from the new
`ExportPdfCreator`, else `Executable.ProgramName` — what `Application.Title`
gave; `report_demo` passes its title. `ShowPreviewForm`, `PrintPages`,
`ShowPrintDialog` (it printed without a dialog) and `OpenPdfFile` (empty)
are gone. `test_runner` 243/243; the eight demo PDFs as after step 2,
`/Creator` unchanged. The preview (zoom, page keys, Ctrl+wheel) checked by
hand on Windows. Linux and macOS: see step 4.

**Step 4, points 1 and 3 — done on Windows, 2026-09-27:** the bridge and the
`TGDIPages` core build on Delphi 7. The bridge reintroduces the static VCL
methods (`PDF_CANVASVIRTUAL`, see `platform-backends.md`), `VclCanvas` has
the type `TPdfVclCanvas`, `RenderPageToCanvas` draws through a local
`Bridge` reference. `mormot.ui.report` lost its `{$IFDEF FPC}` wrapper and
the Delphi stub. Delphi 7 syntax: `overload` on every overloaded
declaration, `NewCommand` for `Default(TDrawCommand)`, `markdown_demo`
builds its `TTableLayout` in a function. `PDF_HASVCLCANVAS` is on for every
compiler: Delphi 7 `test_runner` 243/243 (127 before); the one failure on
the way, `TestLineToWritesCompletePath`, found that `DoLineTo` has to skip
`psClear` itself. `markdown_demo` from Delphi 7 and from FPC/Win64: same
size, no difference after masking dates, `/ID` and subset prefixes, same
roles. FPC: `test_runner` 243/243, the eight demo PDFs as after step 2.
**Linux and macOS for steps 2 to 4 — done, 2026-09-27:** `test_runner`
282/282 on Debian and 302/302 on macOS, all eight demos build and run; the
tagged demos of all three platforms and the Delphi 7 `markdown_demo` pass
veraPDF `ua1`, `zugferd_demo` also `3u` and Mustang. The Delphi 7
`markdown_demo` file passes PAC 2024 too.

**Remaining, in this order** (surveyed 2026-09-27, sources only):
5. **The four TCanvas demos on Delphi 7** — `pdf_demo`, `chinese_demo`,
   `rtl_demo`, `zugferd_demo`. All four hold the canvas in a `C: TCanvas`,
   which compiles on Delphi 7 and leaves the PDF empty: it becomes
   `TPdfVclCanvas`. Text beyond ASCII goes through `TextOutUtf8` — the UTF-8
   byte constants of `chinese_demo` and `rtl_demo`, and the literals in the
   source (`pdf_demo`'s "Special chars" line, the dash in `chinese_demo`'s
   title), which Delphi 7 would read as ANSI. Each demo: FPC PDF unchanged,
   the Delphi 7 PDF compared with it; they check CJK subsetting, Uniscribe
   shaping and PDF/A-3U from Delphi 7.
   **Done on Windows, 2026-09-27:** the four demos build with Delphi 7 as
   well; `pdf_demo` drops its `TPdfDocumentGDI` branch (not ported, it would
   not have compiled) and its `VC` cast. The FPC PDFs are the same as before
   apart from date and `/ID`, and the Delphi 7 PDFs the same as the FPC ones
   after inflating the streams and masking dates, `/ID`, subset prefixes and
   offsets; `pdftotext` gives the umlauts, `€`, `…` from both. One byte-level
   difference, in `chinese_demo` only: the `cmap` format 12 (3/10) subtable of
   both Microsoft YaHei subsets carries `language` = `0x0008CA34` from Win32
   and 0 from Win64, the same on every run (the other demos' subsets have no
   format 12 and are byte-identical). The spec wants 0 there. It comes from
   the 32-bit `CreateFontPackage` itself: the source face (`msyh.ttc`) has
   0, we pass language 0, `ReduceTTF` copies the tables unchanged, and a
   test run with `lpfnAllocate` filling its blocks with `$AA` left the value
   as it was — so the DLL writes it, not our heap. No FPC for Win32 here to
   confirm from a second compiler. Checkers on the Delphi 7 files, done
   2026-09-28: `pdf_demo` and `zugferd_demo` pass PAC 2024 and veraPDF `ua1`
   106/106, `zugferd_demo` also `3u` 148/148 and Mustang; `chinese_demo` and
   `rtl_demo` are untagged, so `ua1` does not apply (100/106 on every
   platform, as before).
   Also since this step: every demo names its PDF
   `<demo>_<os>_<cpu>_<compiler>.pdf`, as `layer1_demo` did.
6. **`report_demo --export` and `mormot_demo --export`** on Delphi 7: the
   export path without the form; `mormot_demo` brings the ORM and the static
   SQLite for Win32.
   **Done on Windows, 2026-09-27:** each GUI demo got a `uReport.pas` that
   builds and exports the report from a `TReportOptions` record, without a
   form; `uMainForm` only fills the record from its controls (and
   `mormot_demo`'s form no longer holds a client: `server.pas` has
   `ReadInvoiceData` and `DemoDatabaseFile`, which falls back to `data/`
   below the current folder). The `.lpr` builds the form under FPC only
   (`REPORTDEMO_FORM`, `MORMOTDEMO_FORM`), so on Delphi 7 the program is the
   batch export. Delphi 7 syntax on the way: `mormot_demo`'s `TTableLayout`
   typed constant became a function, its `'—'` a UTF-8 constant, and
   `mormot.uses.inc` is FPC-only — on Delphi 7 it only adds FastMM4. The ORM
   and `static\delphi\sqlite3.obj` link as they are. Both demos: the FPC
   `--export` PDF as before, the Delphi 7 one the same as FPC after masking
   (fonts byte-identical, same `pdftotext`, the locale-dependent dates and
   amounts included); `mormot_demo` with the sample database, 37 orders.
   Checkers on the Delphi 7 files, done 2026-09-28: both pass PAC 2024 and
   veraPDF `ua1` 106/106. Not checked here: the FPC GUI itself (preview,
   print, export dialog) after the split.
   **Linux and macOS for steps 5 and 6 — done, 2026-09-28:** `test_runner`
   302/302 on macOS; all eight demos build and run there, `report_demo` and
   `mormot_demo` with `--export` headless, their PDFs the same size as
   before the two steps apart from the date. The Debian and the macOS files
   pass veraPDF `ua1` 106/106 for every tagged demo, `zugferd_demo` also
   `3u` 148/148 and Mustang. Page counts and structure trees (roles and
   their counts) match across macOS, Debian, FPC/Win64 and Delphi 7 for all
   nine files.
7. **`mormot.ui.reportpreview` on the VCL.**
8. **The GUI demos with their forms on Delphi** — built in code or a `.dfm`
   beside the `.lfm`, to be decided.

**Not part of R-20:** Delphi 2010 and later have `TCustomCanvas` with virtual
drawing methods (not verified here), where overriding might work without typed
references. Checking that needs a current Delphi, e.g. a Community Edition.

**Rejected — option C**, the EMF route of the original `TPdfDocumentGdi`: EMF
carries no structure, so there is no tagged output, and the original in
`mORMot2/src/ui` already does this on Delphi 7.

**The reference is `layer1_demo`** (R-23). A page drawn through the bridge
under Delphi has to give the same text and structure as the same page through
layer 1.

### R-22 — Source Comments Back to the Why — priority 3

**The rule** (`CLAUDE.md`, Coding Conventions, since 2026-09-26): a source
comment says in a line or two why the code is as it is. Findings may sit in the
source while a fix is in progress; once it is accepted they move to the skill
(what future work needs) or the commit message (how it was found), and the
comment shrinks to the rule it protects.

**The state.** The older code carries the investigations themselves —
measurements, validator runs, spec clauses argued out, roadmap IDs — above all
`mormot.ui.pdf.pas` (`PrepareForSaving`, `PrepareFontSubsets`, the text
rendering chains), also `mormot.ui.report.pas`, the backends and the test
units. Part of it repeats the skills, part of it is found nowhere else.

**Work.** Unit by unit, one commit each; `mormot.ui.pdf.pas` by section. For
every long comment: is the knowledge in a skill? If not, move it there first,
then cut the comment. Comments only — `test_runner` gives the same assertion
count, and the demo PDFs are byte-identical apart from date and `/ID`.
The `///` API documentation inherited from the original mORMot2 units stays.

### Windows Font Subsets Are Larger — priority 4

Harmless — the subsets are valid and pass veraPDF — but the Windows demo PDFs
are 2–5 times the size of the POSIX ones (`markdown_demo` 230 KB against
46/51 KB, `report_demo` 79 KB against 14 KB), and the embedded fonts are
nearly all of it. Measured on `report_demo` (Calibri, 2026-09-26), sfnt tables
of one subset, uncompressed:

| Table | Windows (`CreateFontPackage`) | Linux (`hb-subset`) |
|---|---|---|
| `glyf` | 61,902 | 4,044 |
| `hmtx` / `loca` | 27,240 / 14,098 — every glyph ID | 384 / 194 |
| `fpgm` + `prep` + `cvt ` | 14,304 | — |
| total | 120,016 | 5,628 |

Both keep the glyph IDs; `hb-subset` still cuts `hmtx`/`loca` after the
highest kept ID and drops the hinting. Where to start: why `glyf` stays 15
times larger (the keep list, or composite glyphs pulled in), then whether
dropping the hinting tables is allowed after `CreateFontPackage`.

### R-24 — Tests on GitHub Actions — priority 4

**Why.** `test_runner` runs by hand on three machines today; a push should
build and test by itself on at least Linux and Windows.

**Rule: no unmaintained actions.** `gcarreno/setup-lazarus` was checked on
2026-09-26 and rejected — its maintainer has stepped back. Install the
toolchain from maintained sources instead: `apt` on Ubuntu (FPC 3.2.2 and
Lazarus in 24.04), Chocolatey or the official installer on Windows,
Homebrew on macOS.

**Work, in this order:**
1. Linux job: FPC, Lazarus, `libfreetype6`, `libharfbuzz-subset0`, the GTK2
   development packages (the LCL `Interfaces` link), fonts (Liberation, Noto
   CJK and Arabic, so tests run instead of skipping); maybe `xvfb-run`
2. Windows job (x86_64-win64), `test_runner --noenter`
3. macOS: the GitHub runners are arm64 (`aarch64-darwin`); only if Homebrew
   installs FPC and Lazarus for it cleanly
4. build the eight demos too, and upload their PDFs as artifacts for PAC and
   veraPDF

**To check first:**
- does mORMot2's `RunAsConsole` set a non-zero exit code on a failed
  assertion — CI needs it
- mORMot2 in CI: a checkout of `synopse/mORMot2` at a fixed revision,
  registered with `lazbuild --add-package-link`, plus the static libraries
  (`mormot2static`) — which of them `test_runner` links
- which faces the Windows runners have (Calibri, Microsoft YaHei, an Arabic
  face); missing ones turn tests into skips, not failures

**Out of reach:** Delphi 7 (no licence on a runner) and PAC 2024 (a Windows
GUI) stay manual. veraPDF runs on Java and could follow as a later step.

### V — Verification Outstanding

All three platforms build and pass `test_runner` (243 assertions on Windows,
282 on Linux, 302 on macOS — after the fourth R-20 step, macOS again after the
sixth). The tagged demos pass veraPDF `ua1` 106/106 on all three and from
Delphi 7 — the seven tagged files from Linux, macOS, FPC/Win64 and Delphi 7,
measured again on 2026-09-28 after R-20 step 6 — and PAC 2024 for the files
of all three platforms and of Delphi 7; `zugferd_demo` also `3u` 148/148 and
Mustang. The structure trees (roles and their counts) and page counts match
across the platforms and both compilers for every tagged demo. That was the
stated gate for a first version tag, and
the project still has none.

| Open | Why it matters |
|---|---|
| HarfBuzz older than 2.9 | loads, but lacks `hb_subset_or_fail`. The **missing** library is covered by `tests/no_hbsubset.sh`; an old one needs an old distribution, e.g. Debian 11 |
| The U-2 width fix on Linux | exercised on macOS only: no Linux Arabic face reaches the shaper width path (`fonts.md` §10), and `TestShapedGlyphWidthFromHmtx` skips itself there |
| veraPDF in the routine runs | installed on macOS with `ua1`, `3a`, `3b`, `3u` (path in `CLAUDE.local.md`); run by hand on each platform's files, not scripted |
| The `.ttc` fix on Linux | `TestTtcFaceExtraction` skips itself: the Linux machine has no `.ttc` installed (e.g. `fonts-noto-cjk` would bring one) |
| Delphi beyond layer 1 | the TCanvas bridge and `TGDIPages` — R-20; only Delphi 7 has been built |

**Comparing the platforms — but not pixel by pixel.** The demos resolve
different families (Calibri/Cambria/Consolas, Liberation, Trebuchet MS/Georgia/
Andale Mono), so different advance widths, line breaks and page counts are
correct behaviour, not a defect. B-5 made the measurement platform-independent
*for one face*, not the faces themselves. What must match: `pdftotext` output,
the structure tree (roles and their counts), `pdffonts` (embedded, subset,
`uni`), page count and the PAC result. A true cross-platform render diff would
need a demo that forces one face on all three systems — worth building only if
this comparison is to be automated.

**The two checkers do not overlap.** veraPDF found U-1, which PAC had passed,
and PAC checks the tag tree, which veraPDF cannot judge. A PDF/UA claim needs
both.

### PDF/A — What R-17 Left Open — unprioritised

R-17 reached its goal on 2026-09-24: PDF/A-3U with PDF/UA-1, and A-3A and
A-3B with it, verified on all three platforms with veraPDF, Mustang and PAC.
What is left:

- **A-1B**, the commonest level overall, was to be pulled along and is not
  verified; nor are A-1A, A-2A and A-2B. Object streams, xref streams and
  transparency (R-2, R-3, R-7) are forbidden under A-1 — the first thing to
  check there.
- **The CJK peer with a `glyf` face** on Linux or Windows — see the peer entry
  below.
- **`CreateFileAttachment` accepts any file at any level**, although A-1
  forbids embedded files and A-2 allows only PDF/A ones. The caller has to
  know.
- **The engine does not enforce `Tagged` for the A levels**; untagged `pdfa3A`
  fails `3a` on 6.7.2.2 and 6.7.3.3. The documentation says so.

**Do not remove the unverified levels.** `PdfA` is public API and the
constructor takes `APdfA`; dropping enum members breaks callers of a library
whose point is to make the Windows unit available elsewhere. A-1 is not
obsolete — an archive demanding A-1 rejects A-3 precisely because A-3 permits
arbitrary attachments. Say in the documentation which levels are verified
instead.

### W-1 — "Possibly Inappropriate Use of Figure" — accepted

PAC 2024 passes, but keeps the hint "Possibly inappropriate use of figure
structure element" on every `Figure` this engine writes — `pdf_demo` and
`layer1_demo` alike. Not caused by text in the figure (`pdf_demo` keeps it
without), nor by drawing it as vector paths.

**Measured 2026-09-26 (PAC 2024, Windows),** one tagged page each, same `/Alt`:

| Variant | Hint | Error |
|---|---|---|
| no Figure | — | — |
| one filled rectangle as a path, with `/BBox` | yes | — |
| the same rectangle as an image XObject, with `/BBox` | yes | — |
| the path under a CTM, so no `/BBox` | yes | "no bounding box" (B-13) |

So the hint comes with any Figure, path or image, with or without `/BBox`.
Accepted; not investigated further.

### W-2 — E-Mail Addresses Without a Link Element (`zugferd_demo`) — accepted

PAC 2024 passes the demo but keeps one quality hint: "Link in text does not
have a Link element". It points at `seller@email.de` and `buyer@info.de`,
which the invoice data carries and the page draws as plain text. Not a
PDF/UA failure — veraPDF `ua1` passes 106/106 and PAC is green. A real link
would need a tagged link annotation, which the engine cannot write (R-18),
so the hint is accepted, like W-1.

### R-18 — Tagged Link Annotations — only on explicit request

`CreateHyperLink` writes a link annotation, but the engine has no `Link`
structure role: `TPdfStructRole` has no `psrLink`, and nothing writes the
object reference (`OBJR`) to the annotation, its `/StructParent` or the
parent-tree entry behind it.

**Measured 2026-09-24 (macOS):** a tagged document with one
`CreateHyperLink(…, 'mailto:…')` fails veraPDF `ua1` on four rules, 102/106 —
7.18.1-2 (annotation without `/Contents`), 7.18.3-1 (page without
`/Tabs /S`), 7.18.5-1 (link not tagged as a `Link` element), 7.18.5-2 (link
without an alternate description). **So `CreateHyperLink` does not belong in
tagged output today.**

**`TGDIPages.DrawLink` is safe but not a link.** Measured with a URL
(`DrawLink('example.com', 'https://example.com')`, tagged export): the text is
drawn link-styled and tagged as a `Span` inside the line's `P`, the URL is
dropped — no annotation, no `/URI` — and `ua1` passes 106/106. Conformant,
not clickable. `markdown_demo` calls it without a URL at all.

Work: the role, `OBJR` and `/StructParent` for annotations, the parent-tree
entries, `/Contents` and `/Tabs /S`; then `mailto:` links for addresses, and
`DrawLink` writing a real annotation for its URL. Done, it would also clear
W-2. Not planned: build it only when someone asks for it.

### The Unused WinAnsi Peer Beside a CJK or Arabic Font — unprioritised

The engine creates a WinAnsi peer beside every Identity-H font and emits a `Tf`
for it, but for a face that draws only CJK or Arabic that instance shows
nothing — `SetFont` selects the WinAnsi instance and writes `Tf` at once, and
the text output switches to the CID font right after (`/F1 18 Tf /F2 18 Tf`).
poppler reports `Unknown font tag` for it. Pre-existing and unrelated to CFF
(it appears on files from before R-15c).

**Measured with a `glyf` face on Windows, 2026-09-26 — not cosmetic.** The
peer was a `/TrueType` font without `/FirstChar`, `/LastChar` and `/Widths`,
which ISO 32000-1 table 111 requires for a simple TrueType font, because they
were written only when a character was used. PAC 2024 stopped on it ("'FirstChar'
not defined in TrueType font"), on the R-19 test file (Microsoft YaHei and
Tahoma) from both compilers. `chinese_demo` and `rtl_demo` carry the same
peer, but are untagged, so PAC had never run on them. On macOS the Hiragino
peer is a `/Type1` (a CFF face), and veraPDF passed PDF/A-3U and PDF/UA-1 with
it on 2026-09-24.

**Stopgap, done 2026-09-26:** a peer with no used character gets
`/FirstChar 32 /LastChar 32` and the width of the space, so the dictionary is
valid; `TestTaggedUnicode` asserts that no simple TrueType font lacks
`/FirstChar` (fails 1/5 without the change).

**The fix still open:** stop emitting the peer — write `Tf` only when text is
shown, and leave an unused peer out of the page resources and the file. That
touches the font lifecycle on every platform — see `fonts.md` §4 on the
dual-instance model. Whether the `/Type1` peer of a CFF face needs the same
stopgap (it too lacks `/Widths`) is to be checked with it.

### R-15b — Symbolic Fonts Are Not Subset on POSIX — unprioritised

**Effort:** 0.5 day | **Files:** `src/core/mormot.ui.pdf.pas`,
`src/platform/unix/mormot.pdf.freetype.pas`

The one remaining difference between the platforms that is **not** a property of
the platform. `PrepareFontSubsets` skips a symbolic font when
`PdfFontSubsetter <> nil`: such a font reaches its glyphs through the `(3,0)`
cmap under the `F0xx` convention, and `AddToSubsetRequest` knows neither those
code points nor the glyph IDs behind them, so hb-subset would drop every glyph
the WinAnsi instance draws. Keeping the whole face is the safe answer there.

Windows does not need the exclusion since R-15a: `AddWinAnsiGlyphs` resolves the
characters to glyph indices through the face itself, which works whatever cmap
the lookup goes through. Aligning the two therefore means **improving POSIX**,
not restricting Windows — give `IPdfPlatformFont` a character-to-glyph lookup
(FreeType has `FT_Get_Char_Index`) and let `AddToSubsetRequest` fill the glyph
list on both platforms, then drop the exclusion.

Neither side is verified: no demo and no test uses a symbolic face, so the
Windows claim above is an argument from the code, not a measurement. Whoever
takes this should add a demo or test with Wingdings/Symbol first.

Related and equally untested: what `CreateFontPackage` does with a **CFF** face
on Windows. POSIX subsets CFF since R-15c; every face in the demos is
`glyf`-based, so the Windows CFF path has never run. Whether PDF/A or tagged
output impose extra `/FontFile3` conditions is likewise unchecked —
`chinese_demo`, the only CFF case, is neither.

### R-10 — Table Row Pagination — unprioritised

**Effort:** 2–3 days | **File:** `src/core/mormot.ui.report.pas`

A table row taller than the remaining page space forces a page break before the
row. Let the row split: partial cell content on the current page, the rest on
the next. The split row's cells have to stay inside **one** `TR` element
referencing both pages — `TPdfDocumentVcl.ResumeStructContent` does this for
text blocks (B-2) and is the model to follow.

### R-11 — TTC Face Index — unprioritised

**Effort:** 1 day | **Files:** `src/platform/unix/mormot.pdf.freetype.pas`,
`src/core/mormot.pdf.types.pas`

Only face index 0 of a `.ttc` is reachable, because `TPdfFontMap` carries no
face index. Add one so the remaining faces can be selected by name. The
FreeType backend already extracts a single face as a standalone sfnt
(`ExtractSfntFromTtc`), so the embedding side needs no change.

### R-13 — Shaped Arabic on the Windows Path — unprioritised

**Effort:** 0.5 day | **File:** `tests/`

The advance half is done (`TestShapedGlyphWidthFromHmtx`, see `fonts.md` §10).
Left is the end-to-end half: `TestUseUniscribeIsPortable` (from R-16) is a
compile-time guard, not an output check. Nothing yet asserts that shaped Arabic
reaches the PDF on the Windows path — by checking the `/ToUnicode` entries for
`U+FExx` after drawing with `UseUniscribe` set. A Windows-side test; under
R-19 it would run on Win32 as well.

### Charts — out of scope; an example only on explicit request

The project has no chart engine and will not get one, as it generates no
invoice XML. A chart is an image from a chart library, drawn into a `Figure`
with an alternate text; a chart that carries data gets its values as a real
table besides (README, "Tagged PDF"). For the engine that image is an image
like any other, so a demo would show nothing new, and it would bring a
third-party dependency (licence, per-platform build). A layer 2 example with a
chart library's bitmap is to be built only when someone asks for it.

### EMF/MetaFile and GDI+ Gradients — no work planned

Windows-only (`TPdfDocumentGdi`), not portable.
