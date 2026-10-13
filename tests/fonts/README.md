# Test Fonts

Fonts the tests register with `RegisterFontData` (`mormot.lib.core`), so that
a font test does not depend on the fonts a machine has installed. Each one is
a renamed subset of an SIL Open Font License 1.1 font: a Modified Version,
renamed so that it is never taken for the original, and under the same
licence (`OFL.txt`). The licence covers these files only, not the code of
this repository.

| File | Family | Source | Source sha256 |
|---|---|---|---|
| `mORMotTestSans-Regular.ttf` | mORMot Test Sans | `NotoSans-Regular.ttf` 2.004, Debian/Ubuntu package `fonts-noto-core` 20201225-2 | `89c3c497f618fdaa0b2d1e98fef93582f28c71debd2c4a8cdf41f190ced2909d` |

`mORMotTestSans-Regular.ttf` (34,804 bytes, sha256
`170271c706114acaf044c25b650efcb59043dcc57cd50916081bd40bd1f84f36`): Basic
Latin, Latin-1 and the punctuation of a report (dashes, quotes, bullet,
ellipsis, euro); the layout tables (GDEF, GPOS, GSUB) kept, the hinting
dropped; name IDs 1, 3, 4 and 6 renamed (the source has no 16).

Rebuilt with fontTools (4.65 here):

```bash
python tests/fonts/make_test_fonts.py \
  /usr/share/fonts/truetype/noto/NotoSans-Regular.ttf \
  tests/fonts/mORMotTestSans-Regular.ttf
```

The tests find this folder from the executable upwards
(`TestFontFile`, `tests/test_pdf_crossplatform.pas`).
