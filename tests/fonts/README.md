# Test Fonts

Fonts the tests register with `RegisterFontData` (`mormot.lib.core`), so that
a font test does not depend on the fonts a machine has installed. Each one is
a renamed subset of an SIL Open Font License 1.1 font: a Modified Version,
renamed so that it is never taken for the original, and under the same
licence (`OFL.txt`). `mORMotTestCJKGlyf-Regular.ttf` is a renamed and
modified subset of Droid Sans Fallback (Copyright 2006-2010 Google Corp.),
under the Apache License 2.0 (`LICENSE-Apache-2.0.txt`); what was changed
is listed below. The licences cover these files only, not the code of this
repository.

| File | Family | Source | Source sha256 |
|---|---|---|---|
| `mORMotTestSans-Regular.ttf` | mORMot Test Sans | `NotoSans-Regular.ttf` 2.004, Debian/Ubuntu package `fonts-noto-core` 20201225-2 | `89c3c497f618fdaa0b2d1e98fef93582f28c71debd2c4a8cdf41f190ced2909d` |
| `mORMotTestArabic-Regular.ttf` | mORMot Test Arabic | `NotoSansArabic-Regular.ttf` 2.005, `fonts-noto-core` 20201225-2 | `504d7407d86875acf7d04dfaa0fd7524d0b8797723bc4aa18022f29db25b0b6e` |
| `mORMotTestCJK-Regular.otf` | mORMot Test CJK | face 0 (JP) of `NotoSansCJK-Regular.ttc` 2.004, `fonts-noto-cjk` 1:20230817 | `b76b0433203017ca80401b2ee0dd69350349871c4b19d504c34dbdd80541690a` |
| `mORMotTestSymbol-Regular.ttf` | mORMot Test Symbol | `NotoSans-Regular.ttf`, as above | `89c3c497f618fdaa0b2d1e98fef93582f28c71debd2c4a8cdf41f190ced2909d` |
| `mORMotTestSymbolLow-Regular.ttf` | mORMot Test Symbol Low | `NotoSans-Regular.ttf`, as above | `89c3c497f618fdaa0b2d1e98fef93582f28c71debd2c4a8cdf41f190ced2909d` |
| `mORMotTestSymbolF2-Regular.ttf` | mORMot Test Symbol F2 | `NotoSans-Regular.ttf`, as above | `89c3c497f618fdaa0b2d1e98fef93582f28c71debd2c4a8cdf41f190ced2909d` |
| `mORMotTestUnicodeOnly-Regular.ttf` | mORMot Test Unicode Only | `NotoSans-Regular.ttf`, as above | `89c3c497f618fdaa0b2d1e98fef93582f28c71debd2c4a8cdf41f190ced2909d` |
| `mORMotTestFormat12-Regular.ttf` | mORMot Test Format12 | `NotoSans-Regular.ttf`, as above | `89c3c497f618fdaa0b2d1e98fef93582f28c71debd2c4a8cdf41f190ced2909d` |
| `mORMotTestCJKGlyf-Regular.ttf` | mORMot Test CJK Glyf | `DroidSansFallbackFull.ttf`, Debian/Ubuntu package `fonts-droid-fallback` 1:6.0.1r16-1.1build1 | `acb6440a713d880a13a21b468ba7cd43f5a2b2934972e51be791c880730777b8` |
| `mORMotTestCollection.ttc` | mORMot Test TTC A, mORMot Test TTC B | `NotoSans-Regular.ttf`, as above | `89c3c497f618fdaa0b2d1e98fef93582f28c71debd2c4a8cdf41f190ced2909d` |

| File | Bytes | sha256 | What it holds |
|---|---|---|---|
| `mORMotTestSans-Regular.ttf` | 42,168 | `db82eb84a7b34f91b0f94f130a2d161642e07207531ed6d2b848ba3ba2a17ef8` | `glyf`: Basic Latin, Latin-1, the punctuation of a report (dashes, quotes, bullet, ellipsis, euro) and the Greek letters - characters out of WinAnsi, drawn through the Type0 font |
| `mORMotTestArabic-Regular.ttf` | 56,436 | `218c71509626c81ee98c57b76e5ba0e1b1ab529cc349d162c761cea6b6765784` | `glyf`: the Arabic letters, marks and digits, **no presentation forms** in the cmap (U+FB50-FEFF): the contextual forms are reached only through GSUB, by a shaper; plus one **made-up** `curs` lookup (GPOS type 3) for 'marhaba': meem to reh and beh to alef, the exit anchor 40 units in, so a shaper gives these glyphs an x offset of -40 and an advance 40 below `hmtx` |
| `mORMotTestCJK-Regular.otf` | 66,920 | `952173c26fbe5d702554386dcc1e0320727520478291da036618c01b9df78642` | CID-keyed CFF (Adobe-Identity-0): Basic Latin, a few ideographs and kana; after the subset most glyph indexes differ from their CIDs (U+5B57: glyph 257, CID 15364) |
| `mORMotTestSymbol-Regular.ttf` | 23,976 | `d93ae69394dc88c7f30d1ae86160497b2e2975f5a6c3e9859f51377af2bac259` | `glyf`: a symbol font as Wingdings is one - ASCII at U+F020-F07E in a single (3,0) cmap, the symbol code page (OS/2 bit 31), the name records in the symbol encoding |
| `mORMotTestSymbolLow-Regular.ttf` | 24,008 | `64a8eeaaadec4ce731801bfecb5684773ff998c366b1fb38e20c5b9fbb673c3a` | the same symbol font with its cmap at U+0020-007E, the bytes as they are, as some older symbol fonts have it |
| `mORMotTestSymbolF2-Regular.ttf` | 24,000 | `36d0bfca007ffadd5913994bb26bce6b007dc52e55db6943b77f0ecb1043b2cc` | the same symbol font with its cmap at U+F220-F27E, the last of the ranges ISO 32000-1 9.6.6.4 names for the bytes |
| `mORMotTestUnicodeOnly-Regular.ttf` | 34,860 | `90db20f37fea8cf7a3b70df5ff66df57b5a1cc851ee87fa0a9b6c0f4a7e6bafa` | `glyf`: the Latin of Test Sans (Basic Latin, Latin-1, the punctuation) in a single **(0,3)** cmap - no (3,1), (3,0) or (1,0), as the first faces of macOS `GeezaPro.ttc` have: a simple TrueType font cannot reach its glyphs (ISO 32000-1 9.6.6.4), its text goes through the Type0 font |
| `mORMotTestFormat12-Regular.ttf` | 42,240 | `60d3b7e26492b38b243d38ebf33d9ec26df6e0c8a891f3b4e7041b8d9a15e159` | `glyf`: the characters of Test Sans in a single **(3,10) format 12** cmap - no format 4 at all, as macOS Hiragino Kaku Gothic, STHeiti and Geneva have; plus U+1F600, beyond the BMP, on the glyph of 'A' |
| `mORMotTestCJKGlyf-Regular.ttf` | 31,088 | `aea021acb4dddb507b843c6f55b9d60db179b41b24930ef27723f3958ed0bc42` | `glyf` (TrueType outlines, which FontSub subsets, unlike the CFF of Test CJK): the ideographs and kana of the tests and the golden files, the space and the CJK punctuation, **no Latin**; **4200 empty glyphs** out of the cmap after `.notdef`, so the glyphs drawn are 4201-4254 (4233-4254 the components of its composites) - two glyphs 4096 apart with no character (`TestShapedGlyphKeys`) and a keep list of high IDs in a face of 31 KB. No layout or vertical tables |
| `mORMotTestCollection.ttc` | 46,776 | `875acb78bbf2b9d91f4a0f686a0bf98924a399a0cfffc8f484d2e2c7b37d3ccd` | a collection of two `glyf` faces: face 0 Basic Latin, face 1 the same without 'A'-'G', so its 'H' is glyph 34, face 0's glyph 41 |

All but Test CJK Glyf keep their layout tables (GSUB and GPOS; GDEF in the
`glyf` faces, BASE and VORG in the CJK face), and all drop the hinting; name IDs 1-4 and 6 are
renamed (16 and 17 likewise and 18-25 dropped if a source has them - the
three sources have none), and the
CFF names follow name ID 6. The copyright (0), trademark (7) and URL (11)
records of the sources are kept.

Rebuilt with fontTools (4.65 here), the same bytes every time (the `head`
dates are those of the source, the bounds those of the subset; GSUB and
GPOS packed by fontTools' own packer even where `uharfbuzz` is installed,
whose repacker lays the same tables out in other bytes):

```bash
python tests/fonts/make_test_fonts.py <folder with the four sources> tests/fonts
```

On Debian/Ubuntu the sources are in `/usr/share/fonts/truetype/noto`,
`/usr/share/fonts/opentype/noto` and `/usr/share/fonts/truetype/droid`. The tests find this folder from the
executable upwards (`TestFontFile`, `tests/test_pdf_crossplatform.pas`).
