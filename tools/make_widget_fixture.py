"""Generate a widget appearance-state fixture (/AS On/Off)."""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FIXTURES = ROOT / "fixtures"


def stream_object(dict_body: bytes, data: bytes) -> bytes:
    return (
        b"<< " + dict_body + b" /Length " + str(len(data)).encode() + b" >>\nstream\n"
        + data
        + b"\nendstream"
    )


objects = [
    (1, b"<< /Type /Catalog /Pages 2 0 R >>"),
    (2, b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>"),
    (
        3,
        b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] "
        b"/Annots [7 0 R 8 0 R] /Resources << >> /Contents 4 0 R >>",
    ),
    (4, stream_object(b"", b"")),
    (
        7,
        b"<< /Type /Annot /Subtype /Widget /Rect [50 50 100 100] /AS /On "
        b"/AP << /N << /On 9 0 R /Off 10 0 R >> >> >>",
    ),
    (
        8,
        b"<< /Type /Annot /Subtype /Widget /Rect [120 50 170 100] /AS /Off "
        b"/AP << /N << /On 9 0 R /Off 10 0 R >> >> >>",
    ),
    (
        9,
        stream_object(
            b"/Type /XObject /Subtype /Form /BBox [0 0 50 50] /Resources << >>",
            b"0 1 0 rg\n0 0 50 50 re f\n",
        ),
    ),
    (
        10,
        stream_object(
            b"/Type /XObject /Subtype /Form /BBox [0 0 50 50] /Resources << >>",
            b"1 0 0 rg\n0 0 50 50 re f\n",
        ),
    ),
]
out = bytearray(b"%PDF-1.7\n%\xe2\xe3\xcf\xd3\n")
offsets = {}
for num, body in objects:
    offsets[num] = len(out)
    out += f"{num} 0 obj\n".encode() + body + b"\nendobj\n"
xref = len(out)
out += b"xref\n0 11\n0000000000 65535 f \n"
for num in range(1, 11):
    if num in offsets:
        out += f"{offsets[num]:010d} 00000 n \n".encode()
    else:
        out += b"0000000000 00000 f \n"
out += f"trailer\n<< /Size 11 /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n".encode()
(FIXTURES / "widget-states.pdf").write_bytes(bytes(out))
print("wrote", FIXTURES / "widget-states.pdf", len(out), "bytes")
