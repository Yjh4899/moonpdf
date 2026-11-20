"""Generate an annotation appearance-stream fixture."""

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
        b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Annots [7 0 R] "
        b"/Resources << >> /Contents 4 0 R >>",
    ),
    (4, stream_object(b"", b"")),
    (
        7,
        b"<< /Type /Annot /Subtype /Widget /Rect [50 50 150 100] "
        b"/AP << /N 8 0 R >> >>",
    ),
    (
        8,
        stream_object(
            b"/Type /XObject /Subtype /Form /BBox [0 0 100 50] /Resources << >>",
            b"0 1 0 rg\n0 0 100 50 re f\n",
        ),
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
    if num in offsets:
        out += f"{offsets[num]:010d} 00000 n \n".encode()
    else:
        out += b"0000000000 00000 f \n"
out += f"trailer\n<< /Size {size} /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n".encode()
(FIXTURES / "annotation.pdf").write_bytes(bytes(out))
print("wrote", FIXTURES / "annotation.pdf", len(out), "bytes")
