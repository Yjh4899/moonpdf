"""Build a PDF 1.7 fixture using an xref stream, an object stream and a
Flate-compressed page content stream.

Object 3 (page) and object 5 (font) live inside object stream 6. The xref is
itself a stream (object 7) with ``/W [1 4 2]``. This exercises the modern file
layout used by most current PDF writers.
"""

import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FIXTURES = ROOT / "fixtures"
FIXTURES.mkdir(exist_ok=True)


def be(value: int, width: int) -> bytes:
    return value.to_bytes(width, "big")


def stream_object(dict_body: bytes, data: bytes) -> bytes:
    return (
        b"<< " + dict_body + b" /Length " + str(len(data)).encode("ascii") + b" >>\nstream\n"
        + data
        + b"\nendstream"
    )


page_dict = (
    b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 320 200] "
    b"/Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>"
)
font_dict = b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>"

header = b"3 0 5 " + str(len(page_dict) + 1).encode("ascii") + b" "
first = len(header)
objstm_data = header + page_dict + b"\n" + font_dict
objstm = stream_object(
    b"/Type /ObjStm /N 2 /First " + str(first).encode("ascii"), objstm_data
)

content_raw = (
    b"0.12 0.45 0.85 rg\n20 120 120 50 re f\n"
    b"0.92 0.30 0.18 rg\n180 120 m 210 180 260 60 290 120 c f\n"
    b"0 0 0 rg\nBT\n/F1 16 Tf\n20 40 Td\n(XREF STREAM PDF) Tj\nET\n"
)
content = stream_object(b"/Filter /FlateDecode", zlib.compress(content_raw))

out = bytearray(b"%PDF-1.7\n%\xe2\xe3\xcf\xd3\n")
offsets = {}
for num, body in [
    (1, b"<< /Type /Catalog /Pages 2 0 R >>"),
    (2, b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>"),
    (4, content),
    (6, objstm),
]:
    offsets[num] = len(out)
    out += f"{num} 0 obj\n".encode("ascii") + body + b"\nendobj\n"

offsets[7] = len(out)
entries = [
    (0, 0, 0),
    (1, offsets[1], 0),
    (1, offsets[2], 0),
    (2, 6, 0),
    (1, offsets[4], 0),
    (2, 6, 1),
    (1, offsets[6], 0),
    (1, offsets[7], 0),
]
xref_data = bytearray()
for kind, field2, field3 in entries:
    xref_data += be(kind, 1) + be(field2, 4) + be(field3, 2)
compressed_xref = zlib.compress(bytes(xref_data))
xref_stream = stream_object(
    b"/Type /XRef /Size 8 /Root 1 0 R /W [1 4 2] /Filter /FlateDecode",
    compressed_xref,
)
out += b"7 0 obj\n" + xref_stream + b"\nendobj\n"
out += (
    b"startxref\n" + str(offsets[7]).encode("ascii") + b"\n%%EOF\n"
)

(FIXTURES / "xref-stream.pdf").write_bytes(bytes(out))
print("wrote", FIXTURES / "xref-stream.pdf")
