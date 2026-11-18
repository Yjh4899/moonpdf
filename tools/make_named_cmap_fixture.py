"""Patch a Noto CID CFF subset to Adobe-GB1 CIDs and build a named-CMap PDF."""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FIXTURES = ROOT / "fixtures"
CFF_IN = FIXTURES / "fonts" / "NotoSansCJKsc-Subset.cff"
CFF_OUT = FIXTURES / "fonts" / "NotoSansCJKsc-GB1.cff"

# GID 1..4 in the subset are 世, 你, 好, 界; these are their Adobe-GB1 CIDs.
ADOBE_CIDS = [3415, 2886, 1914, 2232]
CHARSET_OFFSET = 323

cff = bytearray(CFF_IN.read_bytes())
assert cff[CHARSET_OFFSET] == 0, "expected a format 0 CFF charset"
for i, cid in enumerate(ADOBE_CIDS):
    cff[CHARSET_OFFSET + 1 + i * 2:CHARSET_OFFSET + 3 + i * 2] = cid.to_bytes(2, "big")
CFF_OUT.write_bytes(bytes(cff))


def stream_object(dict_body: bytes, data: bytes) -> bytes:
    return (
        b"<< " + dict_body + b" /Length " + str(len(data)).encode() + b" >>\nstream\n"
        + data
        + b"\nendstream"
    )


# 你 好 世 界 in UTF-16BE.
content = b"0 0 0 rg\nBT\n/F1 36 Tf\n20 70 Td\n<4F60597D4E16754C> Tj\nET\n"
objects = [
    (1, b"<< /Type /Catalog /Pages 2 0 R >>"),
    (2, b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>"),
    (3, b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 150] /Resources 5 0 R /Contents 4 0 R >>"),
    (4, stream_object(b"", content)),
    (5, b"<< /Font << /F1 6 0 R >> >>"),
    (
        6,
        b"<< /Type /Font /Subtype /Type0 /BaseFont /NotoSansCJKsc /Encoding /UniGB-UCS2-H "
        b"/DescendantFonts [9 0 R] >>",
    ),
    (
        7,
        b"<< /Type /FontDescriptor /FontName /NotoSansCJKsc /Flags 4 "
        b"/FontBBox [-1000 -500 2000 1500] /ItalicAngle 0 /Ascent 1000 "
        b"/Descent -300 /CapHeight 700 /StemV 80 /FontFile3 8 0 R >>",
    ),
    (
        8,
        stream_object(
            b"/Subtype /CIDFontType0C /Length1 " + str(len(cff)).encode(),
            bytes(cff),
        ),
    ),
    (
        9,
        b"<< /Type /Font /Subtype /CIDFontType0 /BaseFont /NotoSansCJKsc "
        b"/CIDSystemInfo << /Registry (Adobe) /Ordering (GB1) /Supplement 6 >> "
        b"/FontDescriptor 7 0 R /DW 1000 /W ["
        + b" ".join(f"{cid} [1000]".encode() for cid in ADOBE_CIDS)
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
(FIXTURES / "font-named-cmap.pdf").write_bytes(bytes(out))
print("wrote", FIXTURES / "font-named-cmap.pdf", len(out), "bytes")
