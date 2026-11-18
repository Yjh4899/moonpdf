"""Generate image XObject fixtures: a Flate RGB image and a baseline JPEG."""

import io
import zlib
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
FIXTURES = ROOT / "fixtures"
FIXTURES.mkdir(exist_ok=True)


def stream_object(dict_body: bytes, data: bytes) -> bytes:
    return (
        b"<< " + dict_body + b" /Length " + str(len(data)).encode("ascii") + b" >>\nstream\n"
        + data
        + b"\nendstream"
    )


def build(image_dict: bytes, image_data: bytes, path: Path) -> None:
    content = stream_object(b"", b"q\n100 0 0 100 50 50 cm\n/Im1 Do\nQ\n")
    objects = [
        (1, b"<< /Type /Catalog /Pages 2 0 R >>"),
        (2, b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>"),
        (3, b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Resources 5 0 R /Contents 4 0 R >>"),
        (4, content),
        (5, b"<< /XObject << /Im1 6 0 R >> >>"),
        (6, stream_object(image_dict, image_data)),
    ]
    out = bytearray(b"%PDF-1.7\n%\xe2\xe3\xcf\xd3\n")
    offsets = {}
    for num, body in objects:
        offsets[num] = len(out)
        out += f"{num} 0 obj\n".encode("ascii") + body + b"\nendobj\n"
    xref = len(out)
    out += b"xref\n0 7\n"
    out += b"0000000000 65535 f \n"
    for num in range(1, 7):
        out += f"{offsets[num]:010d} 00000 n \n".encode("ascii")
    out += (
        b"trailer\n<< /Size 7 /Root 1 0 R >>\nstartxref\n"
        + str(xref).encode("ascii")
        + b"\n%%EOF\n"
    )
    path.write_bytes(bytes(out))
    print("wrote", path)


# 32x32 RGB: left red, right blue, with a green square in the middle.
flate_img = Image.new("RGB", (32, 32))
pix = flate_img.load()
for y in range(32):
    for x in range(32):
        if 12 <= x < 20 and 12 <= y < 20:
            pix[x, y] = (0, 220, 0)
        elif x < 16:
            pix[x, y] = (230, 30, 30)
        else:
            pix[x, y] = (30, 60, 230)
flate_data = zlib.compress(flate_img.tobytes())
build(
    b"/Type /XObject /Subtype /Image /Width 32 /Height 32 "
    b"/ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /FlateDecode",
    flate_data,
    FIXTURES / "image-flate.pdf",
)

# 64x64 baseline JPEG: four colored quadrants plus a gradient.
jpeg_img = Image.new("RGB", (64, 64))
pix = jpeg_img.load()
for y in range(64):
    for x in range(64):
        if x < 32 and y < 32:
            pix[x, y] = (240, 40, 40)
        elif x >= 32 and y < 32:
            pix[x, y] = (40, 80, 230)
        elif x < 32 and y >= 32:
            pix[x, y] = (40, 200, 80)
        else:
            pix[x, y] = (240, 220, 60)
buf = io.BytesIO()
jpeg_img.save(buf, format="JPEG", quality=90)
build(
    b"/Type /XObject /Subtype /Image /Width 64 /Height 64 "
    b"/ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode",
    buf.getvalue(),
    FIXTURES / "image-jpeg.pdf",
)

# Inline image: 4x4 red samples written directly in the content stream.
inline_samples = bytes([255, 0, 0]) * 16
inline_content = (
    b"q\n100 0 0 100 50 50 cm\nBI\n/W 4\n/H 4\n/CS /RGB\n/BPC 8\nID\n"
    + inline_samples
    + b"\nEI\nQ\n"
)
inline_objects = [
    (1, b"<< /Type /Catalog /Pages 2 0 R >>"),
    (2, b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>"),
    (3, b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Contents 4 0 R >>"),
    (4, stream_object(b"", inline_content)),
]
out = bytearray(b"%PDF-1.7\n%\xe2\xe3\xcf\xd3\n")
offsets = {}
for num, body in inline_objects:
    offsets[num] = len(out)
    out += f"{num} 0 obj\n".encode("ascii") + body + b"\nendobj\n"
xref = len(out)
out += b"xref\n0 5\n0000000000 65535 f \n"
for num in range(1, 5):
    out += f"{offsets[num]:010d} 00000 n \n".encode("ascii")
out += (
    b"trailer\n<< /Size 5 /Root 1 0 R >>\nstartxref\n"
    + str(xref).encode("ascii")
    + b"\n%%EOF\n"
)
(FIXTURES / "inline-image.pdf").write_bytes(bytes(out))
print("wrote", FIXTURES / "inline-image.pdf")