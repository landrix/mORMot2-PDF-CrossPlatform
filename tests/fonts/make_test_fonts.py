"""Build tests/fonts/mORMotTestSans-Regular.ttf from Noto Sans Regular.

A renamed subset (SIL OFL 1.1, Modified Version): Basic Latin, Latin-1 and
the punctuation of a report; layout tables kept, hinting dropped.
"""
import hashlib, sys
from fontTools import subset
from fontTools.ttLib import TTFont

src, dst = sys.argv[1], sys.argv[2]
print("source sha256", hashlib.sha256(open(src, "rb").read()).hexdigest())

unicodes = list(range(0x20, 0x7F)) + list(range(0xA0, 0x100)) + [
    0x2013, 0x2014, 0x2018, 0x2019, 0x201A, 0x201C, 0x201D, 0x201E,
    0x2022, 0x2026, 0x20AC]
opts = subset.Options()
opts.layout_features = ["*"]
opts.hinting = False
opts.name_IDs = ["*"]
opts.name_languages = ["*"]
opts.notdef_outline = True
opts.glyph_names = False
font = TTFont(src)
sub = subset.Subsetter(opts)
sub.populate(unicodes=unicodes)
sub.subset(font)

FAMILY = "mORMot Test Sans"
names = {
    1: FAMILY,
    3: "mORMot Test Sans Regular; subset of Noto Sans Regular",
    4: FAMILY + " Regular",
    6: "mORMotTestSans-Regular",
    16: FAMILY,
}
table = font["name"]
for rec in list(table.names):
    if rec.nameID in names:
        rec.string = names[rec.nameID]
    elif rec.nameID in (17,):
        rec.string = "Regular"
# no record must still name the original family as its own
for rec in table.names:
    s = rec.toUnicode()
    if rec.nameID in (1, 3, 4, 6, 16) and "Noto" in s and "subset of" not in s:
        raise SystemExit("name %d still says %r" % (rec.nameID, s))
font.save(dst)
data = open(dst, "rb").read()
print("written", dst, len(data), "bytes, sha256", hashlib.sha256(data).hexdigest())
t = TTFont(dst)
print("family", t["name"].getDebugName(1), "| full", t["name"].getDebugName(4),
      "| glyphs", t["maxp"].numGlyphs, "| tables", sorted(t.keys()))
