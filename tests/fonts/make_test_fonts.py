"""Build the test fonts of tests/fonts from their Noto sources.

Each one is a renamed subset (SIL OFL 1.1, Modified Version; the one of
Droid Sans Fallback under the Apache License 2.0): the layout tables kept,
the hinting dropped. Usage:

  python make_test_fonts.py <source folder> <tests/fonts>

The source folder holds NotoSans-Regular.ttf, NotoSansArabic-Regular.ttf,
NotoSansCJK-Regular.ttc and DroidSansFallbackFull.ttf (README.md: versions
and sha256).
"""
import hashlib, os, sys
from fontTools import subset
from fontTools.otlLib.builder import (buildAnchor, buildCursivePosSubtable,
                                      buildLookup)
from fontTools.ttLib import TTCollection, TTFont, newTable
from fontTools.ttLib.tables import otTables as ot
from fontTools.ttLib.tables._c_m_a_p import cmap_format_4, cmap_format_12
from fontTools.ttLib.tables._g_l_y_f import Glyph

# report punctuation: dashes, quotes, bullet, ellipsis, euro
PUNCT = [0x2013, 0x2014, 0x2018, 0x2019, 0x201A, 0x201C, 0x201D, 0x201E,
         0x2022, 0x2026, 0x20AC]
ASCII = list(range(0x20, 0x7F))
# Greek capitals and small letters: characters out of WinAnsi, which a
# document draws through its Type0 font
GREEK = [c for c in range(0x0391, 0x03AA) if c != 0x03A2] \
    + list(range(0x03B1, 0x03CA))


def text(s):
    return [ord(c) for c in s]


def add_cursive(font):
    """A made-up cursive attachment for 'marhaba' (GPOS type 3, 'curs').

    The entry anchor at the advance, the exit anchor 40 units in: a shaper
    shifts each exiting glyph by 40 and shortens its advance by as much -
    the case of a font whose shaped advances differ from hmtx (U-2). Appended
    after the subset, so the glyph IDs stay those of the subset."""
    order = font.getGlyphOrder()
    hmtx = font["hmtx"].metrics
    # init meem to fina reh, medi beh to fina alef: entry, exit - not init
    # hah, whose advance a kern pair changes as well
    joins = {316: (False, True), 404: (True, False), 48: (False, True),
             23: (True, False)}
    attach = {}
    for gid, (entry, exit_) in joins.items():
        name = order[gid]
        attach[name] = (buildAnchor(hmtx[name][0], 0) if entry else None,
                        buildAnchor(40, 0) if exit_ else None)
    lookup = buildLookup([buildCursivePosSubtable(attach,
                                                  font.getReverseGlyphMap())],
                         flags=1 | 8)  # RightToLeft, IgnoreMarks
    gpos = font["GPOS"].table
    gpos.LookupList.Lookup.append(lookup)
    gpos.LookupList.LookupCount = len(gpos.LookupList.Lookup)
    feature = ot.Feature()
    feature.FeatureParams = None
    feature.LookupListIndex = [gpos.LookupList.LookupCount - 1]
    feature.LookupCount = 1
    record = ot.FeatureRecord()
    record.FeatureTag = "curs"
    record.Feature = feature
    # the feature list sorted by tag, as the OpenType spec recommends: the
    # indexes of the language systems follow
    records = gpos.FeatureList.FeatureRecord + [record]
    by_tag = sorted(range(len(records)), key=lambda i: records[i].FeatureTag)
    moved = {old: new for new, old in enumerate(by_tag)}
    gpos.FeatureList.FeatureRecord = [records[i] for i in by_tag]
    gpos.FeatureList.FeatureCount = len(records)
    for script in gpos.ScriptList.ScriptRecord:
        systems = [script.Script.DefaultLangSys] + \
            [r.LangSys for r in script.Script.LangSysRecord]
        for ls in systems:
            if ls is not None:
                ls.FeatureIndex = sorted(moved[i] for i in
                                         ls.FeatureIndex + [len(records) - 1])
                ls.FeatureCount = len(ls.FeatureIndex)


def make_symbol(font, base=0xF000):
    """Make the face a symbol font: one (3,0) cmap at U+F020-F07E, as
    Wingdings has, the OS/2 code page of the symbol character set, the name
    records of the symbol encoding. With base 0 the cmap holds the bytes as
    they are, as some older symbol fonts do."""
    best = font.getBestCmap()
    sub = cmap_format_4(4)
    sub.platformID, sub.platEncID, sub.language = 3, 0, 0
    sub.cmap = {base + c: best[c] for c in ASCII if c in best}
    table = newTable("cmap")
    table.tableVersion = 0
    table.tables = [sub]
    font["cmap"] = table
    os2 = font["OS/2"]
    os2.ulCodePageRange1, os2.ulCodePageRange2 = 1 << 31, 0
    os2.ulUnicodeRange1 = os2.ulUnicodeRange2 = 0
    os2.ulUnicodeRange3 = os2.ulUnicodeRange4 = 0
    os2.usFirstCharIndex, os2.usLastCharIndex = min(sub.cmap), max(sub.cmap)
    for rec in font["name"].names:
        if rec.platformID == 3:
            rec.platEncID = 0


def make_unicode_only(font):
    """Keep one cmap, (0,3) Unicode BMP: no (3,1), (3,0) or (1,0), as the
    first faces of macOS GeezaPro.ttc have - a simple TrueType font cannot
    reach its glyphs (ISO 32000-1 9.6.6.4)."""
    best = font.getBestCmap()
    sub = cmap_format_4(4)
    sub.platformID, sub.platEncID, sub.language = 0, 3, 0
    sub.cmap = dict(best)
    table = newTable("cmap")
    table.tableVersion = 0
    table.tables = [sub]
    font["cmap"] = table


def make_format12_only(font):
    """Keep one cmap, (3,10) format 12: no format 4 at all, as macOS Hiragino
    Kaku Gothic, STHeiti and Geneva have. U+1F600 maps to the glyph of 'A',
    a character beyond the BMP for the reader to leave out."""
    best = font.getBestCmap()
    sub = cmap_format_12(12)
    sub.platformID, sub.platEncID, sub.language = 3, 10, 0
    sub.cmap = dict(best)
    sub.cmap[0x1F600] = best[0x41]
    table = newTable("cmap")
    table.tableVersion = 0
    table.tables = [sub]
    font["cmap"] = table


def pad_glyphs(font, count=4200):
    """Put count empty glyphs out of the cmap after .notdef: the glyphs drawn
    get IDs above 4096 - two glyphs 4096 apart with no character, and a keep
    list of high IDs - in a face of a few KB. The tables address glyphs by
    name, so cmap and glyf follow; the layout and vertical tables go."""
    for tag in ("GSUB", "GPOS", "GDEF", "vhea", "vmtx"):
        if tag in font:
            del font[tag]
    order = font.getGlyphOrder()
    # expanded first: a composite still in raw bytes keeps the old component
    # IDs, which would then address the pads
    for name in order:
        font["glyf"][name]
    pads = ["pad%04d" % i for i in range(count)]
    for name in pads:
        glyph = Glyph()
        glyph.numberOfContours = 0
        font["glyf"].glyphs[name] = glyph
        font["hmtx"].metrics[name] = (0, 0)
    order = order[:1] + pads + order[1:]
    font.setGlyphOrder(order)
    font["glyf"].glyphOrder = order
    font["maxp"].numGlyphs = len(order)


FONTS = [
    # Basic Latin, Latin-1, punctuation, Greek
    dict(src="NotoSans-Regular.ttf", index=0,
         dst="mORMotTestSans-Regular.ttf", family="mORMot Test Sans",
         ps="mORMotTestSans-Regular",
         unicodes=ASCII + list(range(0xA0, 0x100)) + PUNCT + GREEK),
    # the Arabic letters, marks and digits, NO presentation forms (U+FB50-FEFF):
    # the contextual forms are reached through GSUB only, by a shaper
    dict(src="NotoSansArabic-Regular.ttf", index=0,
         dst="mORMotTestArabic-Regular.ttf", family="mORMot Test Arabic",
         ps="mORMotTestArabic-Regular",
         unicodes=[0x20, 0x060C, 0x061B, 0x061F] + list(range(0x0621, 0x063B))
         + list(range(0x0640, 0x0653)) + list(range(0x0660, 0x066A))
         + [0x200C, 0x200D], post=add_cursive),
    # face 0 (JP) of the collection: CID-keyed CFF; after the subset the
    # glyph index of a character is no longer its CID
    dict(src="NotoSansCJK-Regular.ttc", index=0,
         dst="mORMotTestCJK-Regular.otf", family="mORMot Test CJK",
         ps="mORMotTestCJK-Regular",
         unicodes=ASCII + [0x3000, 0x3001, 0x3002]
         + text("字体嵌入测试"      # the smoke test
                "你好，世界！"      # the golden files
                "一二三中文日本語漢"
                "あいうかなカナ")),
    # a symbol font: ASCII at U+F020-F07E only
    dict(src="NotoSans-Regular.ttf", index=0,
         dst="mORMotTestSymbol-Regular.ttf", family="mORMot Test Symbol",
         ps="mORMotTestSymbol-Regular", unicodes=ASCII, post=make_symbol),
    # the same symbol font with its cmap at U+0020-007E
    dict(src="NotoSans-Regular.ttf", index=0,
         dst="mORMotTestSymbolLow-Regular.ttf", family="mORMot Test Symbol Low",
         ps="mORMotTestSymbolLow-Regular", unicodes=ASCII,
         post=lambda font: make_symbol(font, 0)),
    # the same symbol font with its cmap at U+F220-F27E: the last of the
    # ranges ISO 32000-1 9.6.6.4 names for the bytes of a symbol font
    dict(src="NotoSans-Regular.ttf", index=0,
         dst="mORMotTestSymbolF2-Regular.ttf", family="mORMot Test Symbol F2",
         ps="mORMotTestSymbolF2-Regular", unicodes=ASCII,
         post=lambda font: make_symbol(font, 0xF200)),
    # the Latin of Test Sans with a (0,3) cmap only
    dict(src="NotoSans-Regular.ttf", index=0,
         dst="mORMotTestUnicodeOnly-Regular.ttf",
         family="mORMot Test Unicode Only", ps="mORMotTestUnicodeOnly-Regular",
         unicodes=ASCII + list(range(0xA0, 0x100)) + PUNCT,
         post=make_unicode_only),
    # the Latin and Greek of Test Sans with a (3,10) format 12 cmap only
    dict(src="NotoSans-Regular.ttf", index=0,
         dst="mORMotTestFormat12-Regular.ttf",
         family="mORMot Test Format12", ps="mORMotTestFormat12-Regular",
         unicodes=ASCII + list(range(0xA0, 0x100)) + PUNCT + GREEK,
         post=make_format12_only),
    # a CJK face with TrueType outlines (FontSub subsets glyf only), its
    # glyphs drawn above glyph 4096
    dict(src="DroidSansFallbackFull.ttf", index=0,
         dst="mORMotTestCJKGlyf-Regular.ttf", family="mORMot Test CJK Glyf",
         ps="mORMotTestCJKGlyf-Regular", post=pad_glyphs,
         unicodes=[0x20, 0x3000, 0x3001, 0x3002]
         + text("字体嵌入测试"   # the smoke test
                "你好，世界！"   # the golden files
                "一二三中文日本語漢"
                "あいうかなカナ")),
    # a collection of two faces of their own names: face 1 lacks 'A'-'G', so
    # 'H' is another glyph there than in face 0
    dict(src="NotoSans-Regular.ttf", index=0,
         dst="mORMotTestCollection.ttc", faces=[
             dict(family="mORMot Test TTC A", ps="mORMotTestTTCA-Regular",
                  unicodes=ASCII),
             dict(family="mORMot Test TTC B", ps="mORMotTestTTCB-Regular",
                  unicodes=[c for c in ASCII if not 0x41 <= c <= 0x47])]),
]


def build(src, index, family, ps, unicodes):
    opts = subset.Options()
    opts.layout_features = ["*"]
    opts.hinting = False
    opts.name_IDs = ["*"]
    opts.name_languages = ["*"]
    opts.notdef_outline = True
    opts.glyph_names = False
    opts.desubroutinize = True
    opts.recalc_bounds = True  # head, hhea and maxp of the subset, not the source
    opts.font_number = index
    font = subset.load_font(src, opts)
    font.recalcTimestamp = False  # the same bytes on every rebuild
    # the pure Python packer of GSUB/GPOS: with uharfbuzz installed fontTools
    # packs them with HarfBuzz's repacker, the same tables in other bytes
    font.cfg["fontTools.ttLib.tables.otBase:USE_HARFBUZZ_REPACKER"] = False
    sub = subset.Subsetter(opts)
    sub.populate(unicodes=unicodes)
    sub.subset(font)
    # the names: family, unique, full, PostScript, typographic family/style;
    # the alternate and WWS names 18-25 go
    names = {1: family, 2: "Regular",
             3: family + " Regular; subset of " + font["name"].getDebugName(4),
             4: family + " Regular", 6: ps, 16: family, 17: "Regular"}
    table = font["name"]
    table.names = [r for r in table.names if not 18 <= r.nameID <= 25]
    for rec in table.names:
        if rec.nameID in names:
            rec.string = names[rec.nameID]
    if "CFF " in font:
        cff = font["CFF "].cff
        cff.fontNames = [ps]
        top = cff.topDictIndex[0]
        for fd in getattr(top, "FDArray", []):
            if hasattr(fd, "FontName"):
                fd.FontName = ps + fd.FontName[fd.FontName.rfind("-"):]
        for key in ("FullName", "FamilyName"):
            if hasattr(top, key):
                setattr(top, key, names[4] if key == "FullName" else family)
    for rec in table.names:
        s = rec.toUnicode()
        if rec.nameID in (1, 3, 4, 6, 16, 17) and ("Noto" in s or "Droid" in s) \
                and "subset of" not in s:
            raise SystemExit("name %d still says %r" % (rec.nameID, s))
    if any(0xFB50 <= c <= 0xFEFF for c in font.getBestCmap()):
        raise SystemExit("presentation forms in the cmap of " + family)
    return font


src_dir, dst_dir = sys.argv[1], sys.argv[2]
for f in FONTS:
    src = os.path.join(src_dir, f["src"])
    dst = os.path.join(dst_dir, f["dst"])
    print(f["src"], "sha256", hashlib.sha256(open(src, "rb").read()).hexdigest())
    if "faces" in f:
        collection = TTCollection()
        collection.fonts = [build(src, f["index"], face["family"], face["ps"],
                                  face["unicodes"]) for face in f["faces"]]
        collection.save(dst)
        fonts = TTCollection(dst).fonts
    else:
        font = build(src, f["index"], f["family"], f["ps"], f["unicodes"])
        if "post" in f:
            f["post"](font)
        font.save(dst)
        fonts = [TTFont(dst)]
    for t in fonts:
        # every component of a composite glyph has an outline of its own
        glyf = t["glyf"] if "glyf" in t else None
        for name in (t.getGlyphOrder() if glyf else []):
            g = glyf[name]
            if g.isComposite():
                for c in g.components:
                    if glyf[c.glyphName].numberOfContours == 0:
                        raise SystemExit("%s: %s uses the empty glyph %s"
                                         % (f["dst"], name, c.glyphName))
    data = open(dst, "rb").read()
    print("  written", f["dst"], len(data), "bytes, sha256",
          hashlib.sha256(data).hexdigest())
    for t in fonts:
        print("  family", t["name"].getDebugName(1), "| glyphs",
              t["maxp"].numGlyphs, "| cmap", len(t["cmap"].tables[0].cmap),
              "| tables", " ".join(sorted(k.strip() for k in t.keys())))
