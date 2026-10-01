# mORMot Refactoring — Plan

The integration of this project into the mORMot2 trunk as `src/pdf` (ROADMAP
R-28). The architecture is Arnaud's proposal; this file plans the work in
steps and records what each step was checked with.

- **Architecture:** https://gist.github.com/synopse/9e31d8808ed2575ad5ad23da6fe41e4f
  — the phase numbers below are the gist's (§21); Phases 0 and 1b are ours
- **Discussion:** the gist's comments (architecture), the mORMot forum (process)
- **Feature freeze** while the refactoring runs: bug fixes only

---

## Rules for Every Step

The gist's §22 (as of 2026-10-01) merged with ROADMAP's Working Method, so
that no step needs the gist at hand. When the gist changes, update this
section.

**Behaviour**

1. **Behaviour first.** Unless a step says otherwise, the demo PDFs come out
   identical to the baseline after normalization (Phase 0); existing tests
   stay valid. A difference is a defect until it is explained and accepted
   in this file. For the refactoring this replaces ROADMAP's pixel check.
2. **One step, one PR, one kind of change.** Never two of: move units,
   rename public API, change font metrics, change PDF serialization, change
   report layout. Each must be reviewable on its own.

**Architecture**

3. **No new dependency without justification.** Every new `uses` follows the
   gist's dependency graph (§14). Forbidden: `mormot.lib.font` →
   `mormot.pdf.*`, `mormot.pdf.core` → GUI, `mormot.pdf` → GUI.
4. **No generic abstraction without need.** An interface only when there are
   two implementations or a clear testing or injection need.
5. **Low-level units stay small.** `mormot.lib.font` and `mormot.pdf.core`
   depend on little.
6. **Capabilities, not platform emulation.** No Unix equivalent of a Windows
   handle to keep the old internal model when a direct abstraction is possible.
7. **Public convenience.** `uses mormot.pdf` or `uses mormot.pdf.report` is
   enough; a user never picks the font backend.

**Ours**

8. **Documentation moves with the code.** A step that renames or moves
   something updates `CLAUDE.md` and the affected skills in the same PR.
9. **Shaping changes** are checked with a font without Arabic presentation
   forms (`.claude/skills/fonts.md` §10).
10. **PAC and veraPDF** are run by Martin (PAC on Windows, veraPDF on macOS).
11. **Access to `src/` stays restricted** (`CLAUDE.md`), also for refactoring
    steps: each file is asked for with its reason. Martin follows every step
    and must not lose track; no standing permission.

**Checked after every step:**

| Check | Where |
|---|---|
| `test_runner` green, same assertion count | Windows: FPC Win64, Delphi 7, Delphi 2010 |
| All eight demos build and run (GUI demos with `--export`) | the same |
| Demo PDFs identical to the baseline after normalization | the same |
| `test_runner`, demos, PDFs against the baseline | Linux and macOS — every step that touches POSIX code, otherwise at the end of the phase |
| PAC 2024, veraPDF | only when a PDF differs, and at the end of each phase |
| Delphi 13 (Win64, Linux64, Android64) | the community; asked for at the end of each phase |

---

## Phases

### Phase 0 — Baseline

Before anything moves. In this order — Sven's merge can change output (the
trunk's `mormot.lib.uniscribe`, ported trunk commits), so it is checked
against today's `main`:

1. ~~The check tool~~ done: `tests/pdfcheck`, in Pascal (no Python,
   `pdffonts` or `pdftoppm` on the Windows machine), on all three platforms:
   - `run <fpc|d7|d2010> <dir>`: run the eight demos of one compiler and
     collect their PDFs — in the tool rather than a `.bat` and a `.sh`, so it
     is written once. On Linux without a display: `xvfb-run pdfcheck run ...`
   - `compare <dirA> <dirB>`: both sides normalized — streams inflated;
     dates, `/ID`, XMP uuids, subset prefixes, stream lengths and the
     cross-reference offsets masked (the method used by hand so far, ROADMAP
     R-26, R-25) — then compared; the first differing line is shown
   - `fonts <file>`: the fonts as `pdffonts` lists them — type, font file
     key, subset, `/ToUnicode`
   - `struct <file>`: the roles of the structure tree and their counts
   - `normalize <file> <out>`: one file normalized, to look at a difference

   The reading code is `tests/pdf_inspect.pas`, shared with the tests. A test
   tool, not the draft of the PDF reader (gist §1, after the migration).
   Within one platform `compare` decides; across platforms, where the fonts
   differ, `pdftotext`, `fonts`, `struct` and the page count must match
   (ROADMAP V).

   **Checked:** two runs per compiler compare equal — Windows (FPC, Delphi 7,
   Delphi 2010), Linux, macOS; a changed file is reported with its line, a
   missing one as such. `fonts` gives the font dictionaries a text search
   counts in all eight demos; a hand-written file covers a non-embedded
   Type1 and a CFF `FontFile3` (Windows; on Linux and macOS still to run).
   `struct` gives `zugferd_demo`'s roles as
   ROADMAP R-26 records them. `test_runner` unchanged, 259/259 on all three
   Windows compilers
2. Baseline of today's `main`: `test_runner` (assertion count) and the PDFs
   of all eight demos on Windows (FPC Win64, Delphi 7, Delphi 2010), Linux
   and macOS
3. Sven's branch `mormot2-merge` merged: the trunk commits to `mormot.ui.pdf`,
   the trunk's `mormot.ui.core`, `mormot.ui.gdiplus` and `mormot.lib.uniscribe`
   instead of the copies. Checked against step 2 on all three platforms —
   the ported commits are not Windows-only; every difference explained (the
   EMF fixes touch no demo)
4. Baseline again after the merge, on all three platforms: the reference for
   Phase 1

### Phase 1 — Generic Font Layer

Gist §4–§6, §16. Behaviour unchanged.

- `mormot.lib.font`, `mormot.lib.font.gdi`, `mormot.lib.font.freetype`,
  `mormot.lib.font.harfbuzz` from `mormot.pdf.types` and the four backend units
- `Pdf` dropped from names that are not PDF-specific
- **Windows shaping and subsetting behind the interfaces:** Uniscribe and
  `CreateFontPackage` are called from `mormot.ui.pdf` today; they become the
  shaper and subsetter of `mormot.lib.font.gdi` (not in the gist)
- `libharfbuzz` and `libharfbuzz-subset` stay separately loaded
- The device-context interface moves unchanged, marked transitional

### Phase 1b — Remove the Device Context

Gist §19. Its own phase: the step most likely to change metrics.

- `IPdfPlatformDC`, `SelectFont`, `CreateDC`, the screen `LOGPIXELSY`
  replaced by a face object that owns its state
- Output identical; every difference explained

### Phase 2 — Raw PDF Without VCL/LCL

Gist §7–§10. `uses mormot.pdf` builds in a console program without a GUI
framework, on every compiler.

- `mormot.pdf.core` and `mormot.pdf.image` only where the boundary is real
  (gist §23)
- `mormot.pdf.font` for the PDF side of fonts
- The `TBitmap`/`TGraphic` image API moves to an adapter — user code changes

### Phase 3 — Canvas Adapter

Gist §11. `mormot.pdf.canvas`: `TPdfDocumentVcl`, `TPdfVclCanvas`, bitmap
adapters, EMF.

### Phase 4 — Reporting

Gist §12, §13. `mormot.pdf.report` and `mormot.pdf.report.preview`.
Needs the decision on the trunk's existing `TGdiPages` first.

### Phase 5 — Cleanup

Gist §20. Transitional names and aliases removed, unit splits reviewed.

---

## Outside the Phases

Process, agreed in the forum:

- Tests into `mormot2tests` as `test.pdf.*.pas`
- Demos: place in the trunk (`ex/`?)
- `zugferd_demo`: the KoSIT invoice XML (Apache-2.0) replaced by a sample
  under the mORMot licence (Sven)
- Licence headers, `OSWINDOWS`/`OSDARWIN`, the defines include, formatting,
  ASCII-only sources, roadmap references out of the comments (Sven)

## Open Decisions

- The trunk's existing `TGdiPages` (`TScrollBox`, preview built in) — before
  Phase 4
- Golden files in the trunk, or the normalizer comparison only
