"""Generate a Type0 CID CFF fixture using an embedded encoding CMap."""

from pathlib import Path

from fontTools.ttLib import TTFont

ROOT = Path(__file__).resolve().parent.parent
FIXTURES = ROOT / "fixtures"
SUBSET = FIXTURES / "fonts" / "NotoSansCJKsc-Subset.otf"
CFF = FIXTURES / "fonts" / "NotoSansCJKsc-Subset.cff"


def stream_object(dict_body: bytes, data: bytes) -> bytes:
    return (
        b"<< " + dict_body + b" /Length " + str(len(data)).encode() + b" >>\nstream\n"
        + data
        + b"\nendstream"
    )


cff_data = CFF.read_bytes()
font = TTFont(SUBSET)
cmap = font.getBestCmap()
chars = ["你", "好", "世", "界"]
cids = [
    int(font.getGlyphOrder()[font.getGlyphID(cmap[ord(ch)])][3:])
    for ch in chars
]
pairs = [(ord(ch), cid) for ch, cid in zip(chars, cids)]
ranges = b"".join(
    f"<{code:04X}> <{code:04X}> {cid}\n".encode() for code, cid in pairs
)
cmap_data = (
    b"%!PS-Adobe-3.0 Resource-CMap\n"
    b"begincmap\n"
    b"/CIDSystemInfo << /Registry (Adobe) /Ordering (UCS) /Supplement 0 >> def\n"
    b"/CMapName /Custom-UCS2 def\n/CMapType 2 def\n"
    b"1 begincodespacerange\n<0000> <FFFF>\nendcodespacerange\n"
    + str(len(pairs)).encode()
    + b" begincidrange\n"
    + ranges
    + b"endcidrange\n"
    b"endcmap\n"
    b"CMapName currentdict /CMap defineresource pop\n"
    b"end\n"
)
content = (
    b"0 0 0 rg\nBT\n/F1 36 Tf\n20 70 Td\n<"
    + b"".join(f"{code:04X}".encode() for code, _ in pairs)
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
        b"<< /Type /Font /Subtype /Type0 /BaseFont /NotoSansCJKsc /Encoding 10 0 R "
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
        + b" ".join(f"{cid} [1000]".encode() for _, cid in pairs)
        + b"] >>",
    ),
    (10, stream_object(b"", cmap_data)),
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
(FIXTURES / "font-cid-cmap.pdf").write_bytes(bytes(out))
print("wrote", FIXTURES / "font-cid-cmap.pdf", len(out), "bytes", pairs)
