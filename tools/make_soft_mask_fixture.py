"""Generate an image soft-mask (/SMask) fixture."""

import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FIXTURES = ROOT / "fixtures"


def stream_object(dict_body: bytes, data: bytes) -> bytes:
    return (
        b"<< " + dict_body + b" /Length " + str(len(data)).encode() + b" >>\nstream\n"
        + data
        + b"\nendstream"
    )


size = 32
image = bytearray()
for _y in range(size):
    for _x in range(size):
        image += bytes([255, 0, 0])
mask = bytearray()
for _y in range(size):
    for x in range(size):
        mask.append(255 - x * 255 // (size - 1))

content = b"0 0 1 rg\n0 0 200 200 re f\nq\n100 0 0 100 50 50 cm\n/Im1 Do\nQ\n"
objects = [
    (1, b"<< /Type /Catalog /Pages 2 0 R >>"),
    (2, b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>"),
    (3, b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Resources 5 0 R /Contents 4 0 R >>"),
    (4, stream_object(b"", content)),
    (5, b"<< /XObject << /Im1 6 0 R >> >>"),
    (
        6,
        stream_object(
            b"/Type /XObject /Subtype /Image /Width 32 /Height 32 "
            b"/ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /FlateDecode /SMask 7 0 R",
            zlib.compress(bytes(image)),
        ),
    ),
    (
        7,
        stream_object(
            b"/Type /XObject /Subtype /Image /Width 32 /Height 32 "
            b"/ColorSpace /DeviceGray /BitsPerComponent 8 /Filter /FlateDecode",
            zlib.compress(bytes(mask)),
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
(FIXTURES / "soft-mask.pdf").write_bytes(bytes(out))
print("wrote", FIXTURES / "soft-mask.pdf", len(out), "bytes")
