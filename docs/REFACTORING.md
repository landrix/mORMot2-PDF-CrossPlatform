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

**One step, one PR, one kind of change** (gist §22): move units, rename,
change metrics, change serialization — never two of them at once.

**Behaviour first.** Unless a step says otherwise, the demo PDFs must come out
identical to the baseline after normalization (Phase 0). A difference is a
defect until it is explained and accepted in this file.

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

1. A versioned normalizer in Pascal (no Python on the Windows machine, no
   `pdftoppm`): inflate the streams, mask dates, `/ID` and subset prefixes —
   the method used by hand so far (ROADMAP R-26, R-25)
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
