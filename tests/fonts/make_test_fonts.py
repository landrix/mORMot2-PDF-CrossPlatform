"""Build the test fonts of tests/fonts from their Noto sources.

Each one is a renamed subset (SIL OFL 1.1, Modified Version): the layout
tables kept, the hinting dropped. Usage:

  python make_test_fonts.py <source folder> <tests/fonts>

The source folder holds NotoSans-Regular.ttf, NotoSansArabic-Regular.ttf and
NotoSansCJK-Regular.ttc (README.md: versions and sha256).
"""
import hashlib, os, sys
from fontTools import subset
from fontTools.ttLib import TTFont

# report punctuation: dashes, quotes, bullet, ellipsis, euro
PUNCT = [0x2013, 0x2014, 0x2018, 0x2019, 0x201A, 0x201C, 0x201D, 0x201E,
         0x2022, 0x2026, 0x20AC]


def text(s):
    return [ord(c) for c in s]


FONTS = [
    # Basic Latin, Latin-1, punctuation
    dict(src="NotoSans-Regular.ttf", index=0,
         dst="mORMotTestSans-Regular.ttf", family="mORMot Test Sans",
         ps="mORMotTestSans-Regular",
         unicodes=list(range(0x20, 0x7F)) + list(range(0xA0, 0x100)) + PUNCT),
    # the Arabic letters, marks and digits, NO presentation forms (U+FB50-FEFF):
    # the contextual forms are reached through GSUB only, by a shaper
    dict(src="NotoSansArabic-Regular.ttf", index=0,
         dst="mORMotTestArabic-Regular.ttf", family="mORMot Test Arabic",
         ps="mORMotTestArabic-Regular",
         unicodes=[0x20, 0x060C, 0x061B, 0x061F] + list(range(0x0621, 0x063B))
         + list(range(0x0640, 0x0653)) + list(range(0x0660, 0x066A))
         + [0x200C, 0x200D]),
    # face 0 (JP) of the collection: CID-keyed CFF; after the subset the
    # glyph index of a character is no longer its CID
    dict(src="NotoSansCJK-Regular.ttc", index=0,
         dst="mORMotTestCJK-Regular.otf", family="mORMot Test CJK",
         ps="mORMotTestCJK-Regular",
         unicodes=list(range(0x20, 0x7F)) + [0x3000, 0x3001, 0x3002]
         + text("字体嵌入测试"      # the smoke test
                "你好，世界！"      # the golden files
                "一二三中文日本語漢"
                "あいうかなカナ")),
]

src_dir, dst_dir = sys.argv[1], sys.argv[2]
for f in FONTS:
    src = os.path.join(src_dir, f["src"])
    dst = os.path.join(dst_dir, f["dst"])
    print(f["src"], "sha256", hashlib.sha256(open(src, "rb").read()).hexdigest())
    opts = subset.Options()
    opts.layout_features = ["*"]
    opts.hinting = False
    opts.name_IDs = ["*"]
    opts.name_languages = ["*"]
    opts.notdef_outline = True
    opts.glyph_names = False
    opts.desubroutinize = True
    opts.recalc_bounds = True  # head, hhea and maxp of the subset, not the source
    opts.font_number = f["index"]
    font = subset.load_font(src, opts)
    font.recalcTimestamp = False  # the same bytes on every rebuild
    sub = subset.Subsetter(opts)
    sub.populate(unicodes=f["unicodes"])
    sub.subset(font)
    # the names: family, unique, full, PostScript, typographic family/style;
    # the other names that would still identify the original go
    family = f["family"]
    names = {1: family, 2: "Regular",
             3: family + " Regular; subset of " + font["name"].getDebugName(4),
             4: family + " Regular", 6: f["ps"], 16: family, 17: "Regular"}
    table = font["name"]
    table.names = [r for r in table.names
                   if not (18 <= r.nameID <= 25) or r.nameID in names]
    for rec in table.names:
        if rec.nameID in names:
            rec.string = names[rec.nameID]
    if "CFF " in font:
        cff = font["CFF "].cff
        cff.fontNames = [f["ps"]]
        top = cff.topDictIndex[0]
        for fd in getattr(top, "FDArray", []):
            if hasattr(fd, "FontName"):
                fd.FontName = f["ps"] + fd.FontName[fd.FontName.rfind("-"):]
        for key in ("FullName", "FamilyName"):
            if hasattr(top, key):
                setattr(top, key, names[4] if key == "FullName" else family)
    for rec in table.names:
        s = rec.toUnicode()
        if rec.nameID in (1, 3, 4, 6, 16, 17) and "Noto" in s \
                and "subset of" not in s:
            raise SystemExit("name %d still says %r" % (rec.nameID, s))
    cmap = font.getBestCmap()
    if any(0xFB50 <= c <= 0xFEFF for c in cmap):
        raise SystemExit("presentation forms in the cmap of " + f["dst"])
    font.save(dst)
    data = open(dst, "rb").read()
    print("  written", f["dst"], len(data), "bytes, sha256",
          hashlib.sha256(data).hexdigest())
    t = TTFont(dst)
    print("  family", t["name"].getDebugName(1), "| glyphs",
          t["maxp"].numGlyphs, "| cmap", len(t.getBestCmap()),
          "| tables", " ".join(sorted(k.strip() for k in t.keys())))
