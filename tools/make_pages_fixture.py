"""Generate a two-page fixture for the multi-page CLI."""

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
    (2, b"<< /Type /Pages /Kids [3 0 R 4 0 R] /Count 2 >>"),
    (3, b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 100 100] /Resources << >> /Contents 5 0 R >>"),
    (4, b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 100 100] /Resources << >> /Contents 6 0 R >>"),
    (5, stream_object(b"", b"1 0 0 rg\n0 0 100 100 re f\n")),
    (6, stream_object(b"", b"0 0 1 rg\n0 0 100 100 re f\n")),
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
(FIXTURES / "pages.pdf").write_bytes(bytes(out))
print("wrote", FIXTURES / "pages.pdf", len(out), "bytes")
