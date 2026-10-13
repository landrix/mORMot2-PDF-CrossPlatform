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
| `mORMotTestArabic-Regular.ttf` | mORMot Test Arabic | `NotoSansArabic-Regular.ttf` 2.005, `fonts-noto-core` 20201225-2 | `504d7407d86875acf7d04dfaa0fd7524d0b8797723bc4aa18022f29db25b0b6e` |
| `mORMotTestCJK-Regular.otf` | mORMot Test CJK | face 0 (JP) of `NotoSansCJK-Regular.ttc` 2.004, `fonts-noto-cjk` 1:20230817 | `b76b0433203017ca80401b2ee0dd69350349871c4b19d504c34dbdd80541690a` |

| File | Bytes | sha256 | What it holds |
|---|---|---|---|
| `mORMotTestSans-Regular.ttf` | 34,804 | `d13ea16e9b40d0b8894a6984536fccd408e4d2c209c0e8d29b3dbb52b5cbffa4` | `glyf`: Basic Latin, Latin-1 and the punctuation of a report (dashes, quotes, bullet, ellipsis, euro) |
| `mORMotTestArabic-Regular.ttf` | 56,360 | `6089fe1bf35d482d462b151809b6b44fe10d2009c3cd75569e27bfa17b465f4c` | `glyf`: the Arabic letters, marks and digits, **no presentation forms** in the cmap (U+FB50-FEFF): the contextual forms are reached only through GSUB, by a shaper |
| `mORMotTestCJK-Regular.otf` | 66,920 | `952173c26fbe5d702554386dcc1e0320727520478291da036618c01b9df78642` | CID-keyed CFF (Adobe-Identity-0): Basic Latin, a few ideographs and kana; after the subset most glyph indexes differ from their CIDs (U+5B57: glyph 257, CID 15364) |

All three keep their layout tables (GSUB and GPOS; GDEF in the two `glyf`
faces, BASE and VORG in the CJK face) and drop the hinting; name IDs 1-4 and 6 are renamed (16 and 17 likewise
and 18-25 dropped if a source has them - these three have none), and the
CFF names follow name ID 6. The copyright (0), trademark (7) and URL (11)
records of the sources are kept.

Rebuilt with fontTools (4.65 here), the same bytes every time (the `head`
dates are those of the source, the bounds those of the subset):

```bash
python tests/fonts/make_test_fonts.py <folder with the three sources> tests/fonts
```

On Debian/Ubuntu the sources are in `/usr/share/fonts/truetype/noto` and
`/usr/share/fonts/opentype/noto`. The tests find this folder from the
executable upwards (`TestFontFile`, `tests/test_pdf_crossplatform.pas`).
