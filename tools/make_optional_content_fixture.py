"""Generate an optional-content (hidden OCG) fixture."""

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
    b"1 0 0 rg\n0 0 200 200 re f\n"
    b"/OC /OC1 BDC\n0 1 0 rg\n50 50 100 100 re f\nEMC\n"
)
objects = [
    (
        1,
        b"<< /Type /Catalog /Pages 2 0 R "
        b"/OCProperties << /OCGs [7 0 R] /D << /BaseState /ON /OFF [7 0 R] >> >> >>",
    ),
    (2, b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>"),
    (
        3,
        b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Resources 4 0 R /Contents 5 0 R >>",
    ),
    (4, b"<< /Properties << /OC1 7 0 R >> >>"),
    (5, stream_object(b"", content)),
    (7, b"<< /Type /OCG /Name (Hidden layer) >>"),
]
out = bytearray(b"%PDF-1.7\n%\xe2\xe3\xcf\xd3\n")
offsets = {}
for num, body in objects:
    offsets[num] = len(out)
    out += f"{num} 0 obj\n".encode() + body + b"\nendobj\n"
xref = len(out)
out += b"xref\n0 8\n0000000000 65535 f \n"
for num in range(1, 8):
    if num in offsets:
        out += f"{offsets[num]:010d} 00000 n \n".encode()
    else:
        out += b"0000000000 00000 f \n"
out += f"trailer\n<< /Size 8 /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n".encode()
(FIXTURES / "optional-content.pdf").write_bytes(bytes(out))
print("wrote", FIXTURES / "optional-content.pdf", len(out), "bytes")
