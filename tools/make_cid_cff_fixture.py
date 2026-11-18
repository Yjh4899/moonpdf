"""Generate a CID-keyed CFF fixture from a subset of Noto Sans CJK SC."""

import struct
from pathlib import Path

from fontTools.ttLib import TTFont

ROOT = Path(__file__).resolve().parent.parent
FIXTURES = ROOT / "fixtures"
SUBSET = FIXTURES / "fonts" / "NotoSansCJKsc-Subset.otf"
CFF_OUT = FIXTURES / "fonts" / "NotoSansCJKsc-Subset.cff"


def stream_object(dict_body: bytes, data: bytes) -> bytes:
    return (
        b"<< " + dict_body + b" /Length " + str(len(data)).encode() + b" >>\nstream\n"
        + data
        + b"\nendstream"
    )


font = TTFont(SUBSET)
cff_data = font.reader["CFF "]
CFF_OUT.write_bytes(cff_data)

units = font["head"].unitsPerEm
hmtx = font["hmtx"]
glyph_order = font.getGlyphOrder()
chars = ["你", "好", "世", "界"]
cmap = font.getBestCmap()
gids = [font.getGlyphID(glyph_order[font.getGlyphID(cmap[ord(ch)])]) for ch in chars]
# The subset's glyph order is [.notdef, cid09514, ...]; derive the CIDs from
# the glyph names so the PDF codes match the CFF charset.
cids = [int(glyph_order[gid][3:]) for gid in gids]
widths = [round(hmtx[glyph_order[gid]][0] * 1000 / units) for gid in gids]

content = (
    b"0 0 0 rg\nBT\n/F1 36 Tf\n20 70 Td\n<"
    + b"".join(f"{cid:04X}".encode() for cid in cids)
    + b"> Tj\nET\n"
)
objects = [
    (1, b"<< /Type /Catalog /Pages 2 0 R >>"),
    (2, b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>"),
    (3, b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 150] /Resources 5 0 R /Contents 4 0 R >>"),
    (4, stream_object(b"", content)),
    (5, b"<< /Font << /F1 6 0 R >> >>"),
    (
        6,
        b"<< /Type /Font /Subtype /Type0 /BaseFont /NotoSansCJKsc /Encoding /Identity-H "
        b"/DescendantFonts [9 0 R] >>",
    ),
    (
        7,
        b"<< /Type /FontDescriptor /FontName /NotoSansCJKsc /Flags 4 "
        b"/FontBBox [-1000 -500 2000 1500] /ItalicAngle 0 /Ascent 1000 "
        b"/Descent -300 /CapHeight 700 /StemV 80 /FontFile3 8 0 R >>",
    ),
    (8, stream_object(b"/Subtype /CIDFontType0C /Length1 " + str(len(cff_data)).encode(), cff_data)),
    (
        9,
        b"<< /Type /Font /Subtype /CIDFontType0 /BaseFont /NotoSansCJKsc "
        b"/CIDSystemInfo << /Registry (Adobe) /Ordering (Identity) /Supplement 0 >> "
        b"/FontDescriptor 7 0 R /DW 1000 /W ["
        + b" ".join(f"{cid} [{width}]".encode() for cid, width in zip(cids, widths))
        + b"] >>",
    ),
]
out = bytearray(b"%PDF-1.7\n%\xe2\xe3\xcf\xd3\n")
offsets = {}
for num, body in objects:
    offsets[num] = len(out)
    out += f"{num} 0 obj\n".encode() + body + b"\nendobj\n"
xref = len(out)
size = max(offsets) + 1
out += f"xref\n0 {size}\n0000000000 65535 f \n".encode()
for num in range(1, size):
    out += f"{offsets[num]:010d} 00000 n \n".encode()
out += f"trailer\n<< /Size {size} /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n".encode()
(FIXTURES / "font-cid-cff.pdf").write_bytes(bytes(out))
print("wrote", FIXTURES / "font-cid-cff.pdf", len(out), "bytes", "cids", cids, "widths", widths)
