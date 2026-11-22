"""Generate a fixture that sets Tf once and uses BT/ET twice."""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FIXTURES = ROOT / "fixtures"


def stream_object(dict_body: bytes, data: bytes) -> bytes:
    return (
        b"<< " + dict_body + b" /Length " + str(len(data)).encode() + b" >>\nstream\n"
        + data
        + b"\nendstream"
    )


content = (
    b"/F1 24 Tf\n"
    b"BT\n10 60 Td\n(Hello) Tj\nET\n"
    b"BT\n10 20 Td\n(World) Tj\nET\n"
)
widths = [500] * 95
objects = [
    (1, b"<< /Type /Catalog /Pages 2 0 R >>"),
    (2, b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>"),
    (3, b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 100] /Resources 4 0 R /Contents 5 0 R >>"),
    (4, b"<< /Font << /F1 6 0 R >> >>"),
    (5, stream_object(b"", content)),
    (
        6,
        b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /FirstChar 32 /LastChar 126 "
        b"/Widths [" + b" ".join(str(w).encode() for w in widths) + b"] /Encoding /WinAnsiEncoding >>",
    ),
]
out = bytearray(b"%PDF-1.7\n%\xe2\xe3\xcf\xd3\n")
offsets = {}
for num, body in objects:
    offsets[num] = len(out)
    out += f"{num} 0 obj\n".encode() + body + b"\nendobj\n"
xref = len(out)
out += b"xref\n0 7\n0000000000 65535 f \n"
for num in range(1, 7):
    out += f"{offsets[num]:010d} 00000 n \n".encode()
out += f"trailer\n<< /Size 7 /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n".encode()
(FIXTURES / "text-bt.pdf").write_bytes(bytes(out))
print("wrote", FIXTURES / "text-bt.pdf", len(out))
