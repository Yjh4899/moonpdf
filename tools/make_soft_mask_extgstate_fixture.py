"""Generate an ExtGState soft-mask fixture (luminosity mask)."""

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
    b"0 0 1 rg\n0 0 200 200 re f\n/GS1 gs\n"
    b"1 0 0 rg\n0 0 200 200 re f\n"
)
mask = b"1 g\n0 0 100 200 re f\n0 g\n100 0 100 200 re f\n"
objects = [
    (1, b"<< /Type /Catalog /Pages 2 0 R >>"),
    (2, b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>"),
    (3, b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Resources 5 0 R /Contents 4 0 R >>"),
    (4, stream_object(b"", content)),
    (5, b"<< /ExtGState << /GS1 6 0 R >> >>"),
    (
        6,
        b"<< /Type /ExtGState /SMask << /S /Luminosity /G 7 0 R >> >>",
    ),
    (
        7,
        stream_object(
            b"/Type /XObject /Subtype /Form /BBox [0 0 200 200] "
            b"/Group << /S /Transparency >> /Resources << >>",
            mask,
        ),
    ),
]
out = bytearray(b"%PDF-1.7\n%\xe2\xe3\xcf\xd3\n")
offsets = {}
for num, body in objects:
    offsets[num] = len(out)
    out += f"{num} 0 obj\n".encode() + body + b"\nendobj\n"
xref = len(out)
out += b"xref\n0 8\n0000000000 65535 f \n"
for num in range(1, 8):
    out += f"{offsets[num]:010d} 00000 n \n".encode()
out += f"trailer\n<< /Size 8 /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n".encode()
(FIXTURES / "soft-mask-extgstate.pdf").write_bytes(bytes(out))
print("wrote", FIXTURES / "soft-mask-extgstate.pdf", len(out), "bytes")
