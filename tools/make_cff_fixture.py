"""Embed Source Sans 3 (OFL, CFF/OTF) as a PDF FontFile3 and render text."""

import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FIXTURES = ROOT / "fixtures"
FONT = FIXTURES / "fonts" / "SourceSans3-Regular.otf"


def u16(data, off):
    return struct.unpack(">H", data[off:off + 2])[0]


def i16(data, off):
    return struct.unpack(">h", data[off:off + 2])[0]


def u32(data, off):
    return struct.unpack(">I", data[off:off + 4])[0]


def tables(data):
    count = u16(data, 4)
    out = {}
    for i in range(count):
        rec = 12 + i * 16
        out[data[rec:rec + 4].decode("latin1")] = (u32(data, rec + 8), u32(data, rec + 12))
    return out


def cmap_lookup(data, cmap_off, code):
    count = u16(data, cmap_off + 2)
    sub = None
    for i in range(count):
        rec = cmap_off + 4 + i * 8
        platform, encoding = u16(data, rec), u16(data, rec + 2)
        candidate = cmap_off + u32(data, rec + 4)
        if ((platform, encoding) == (3, 1) or platform == 0) and u16(data, candidate) == 4:
            sub = candidate
    if sub is None:
        raise SystemExit("no format 4 cmap")
    seg = u16(data, sub + 6) // 2
    end_off = sub + 14
    start_off = end_off + 2 * seg + 2
    delta_off = start_off + 2 * seg
    range_off = delta_off + 2 * seg
    for i in range(seg):
        end = u16(data, end_off + 2 * i)
        start = u16(data, start_off + 2 * i)
        if start <= code <= end:
            delta = i16(data, delta_off + 2 * i)
            ro = u16(data, range_off + 2 * i)
            if ro == 0:
                return (code + delta) & 0xFFFF
            glyph = u16(data, range_off + 2 * i + ro + 2 * (code - start))
            return (glyph + delta) & 0xFFFF if glyph else 0
    return 0


def stream_object(dict_body: bytes, data: bytes) -> bytes:
    return (
        b"<< " + dict_body + b" /Length " + str(len(data)).encode() + b" >>\nstream\n"
        + data
        + b"\nendstream"
    )


font_data = FONT.read_bytes()
t = tables(font_data)
head, hhea, hmtx, cmap = t["head"][0], t["hhea"][0], t["hmtx"][0], t["cmap"][0]
units = u16(font_data, head + 18)
num_h = u16(font_data, hhea + 34)
widths = []
for code in range(32, 127):
    glyph = cmap_lookup(font_data, cmap, code)
    idx = glyph if glyph < num_h else num_h - 1
    advance = u16(font_data, hmtx + idx * 4)
    widths.append(max(0, round(advance * 1000 / units)))

content = (
    b"0 0 0 rg\n"
    b"BT\n/F1 28 Tf\n20 90 Td\n(CFF outlines) Tj\nET\n"
    b"BT\n/F1 14 Tf\n20 55 Td\n(Source Sans 3 / Type1C) Tj\nET\n"
)
objects = [
    (1, b"<< /Type /Catalog /Pages 2 0 R >>"),
    (2, b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>"),
    (3, b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 340 150] /Resources 5 0 R /Contents 4 0 R >>"),
    (4, stream_object(b"", content)),
    (5, b"<< /Font << /F1 6 0 R >> >>"),
    (
        6,
        (
            b"<< /Type /Font /Subtype /Type1 /BaseFont /SourceSans3 "
            b"/FirstChar 32 /LastChar 126 /Widths ["
            + b" ".join(str(w).encode() for w in widths)
            + b"] /FontDescriptor 7 0 R /Encoding /WinAnsiEncoding >>"
        ),
    ),
    (
        7,
        b"<< /Type /FontDescriptor /FontName /SourceSans3 /Flags 32 "
        b"/FontBBox [-500 -300 1200 1000] /ItalicAngle 0 /Ascent 1000 "
        b"/Descent -300 /CapHeight 700 /StemV 80 /FontFile3 8 0 R >>",
    ),
    (8, stream_object(b"/Subtype /Type1C /Length1 " + str(len(font_data)).encode(), font_data)),
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
(FIXTURES / "font-cff.pdf").write_bytes(bytes(out))
print("wrote", FIXTURES / "font-cff.pdf", len(out), "bytes")
