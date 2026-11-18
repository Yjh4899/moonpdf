"""Generate page-geometry fixtures: /Rotate + /CropBox, and a rectangular clip."""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FIXTURES = ROOT / "fixtures"
FIXTURES.mkdir(exist_ok=True)


def stream_object(dict_body: bytes, data: bytes) -> bytes:
    return (
        b"<< " + dict_body + b" /Length " + str(len(data)).encode("ascii") + b" >>\nstream\n"
        + data
        + b"\nendstream"
    )


def build(objects, path: Path) -> None:
    out = bytearray(b"%PDF-1.7\n%\xe2\xe3\xcf\xd3\n")
    offsets = {}
    for num, body in objects:
        offsets[num] = len(out)
        out += f"{num} 0 obj\n".encode("ascii") + body + b"\nendobj\n"
    xref = len(out)
    size = max(offsets) + 1
    out += f"xref\n0 {size}\n".encode("ascii")
    out += b"0000000000 65535 f \n"
    for num in range(1, size):
        if num in offsets:
            out += f"{offsets[num]:010d} 00000 n \n".encode("ascii")
        else:
            out += b"0000000000 00000 f \n"
    out += (
        f"trailer\n<< /Size {size} /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n"
    ).encode("ascii")
    path.write_bytes(bytes(out))
    print("wrote", path)


def page_objects(page_dict: bytes, content: bytes, resources: bytes = b"<< >>"):
    return [
        (1, b"<< /Type /Catalog /Pages 2 0 R >>"),
        (2, b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>"),
        (3, page_dict),
        (4, stream_object(b"", content)),
        (5, resources),
    ]


# /Rotate 90 and CropBox smaller than MediaBox.
rotate_content = (
    b"1 0 0 rg\n"
    b"50 20 150 160 re f\n"
    b"0 0.35 0.9 rg\n"
    b"200 20 150 160 re f\n"
    b"0 0 0 rg\n"
    b"BT\n/F1 24 Tf\n70 90 Td\n(ROTATE 90) Tj\nET\n"
)
build(
    page_objects(
        b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 400 200] /CropBox [50 20 350 180] /Rotate 90 /Resources 5 0 R /Contents 4 0 R >>",
        rotate_content,
        b"<< /Font << /F1 6 0 R >> >>",
    )
    + [(6, b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>")],
    FIXTURES / "rotate-crop.pdf",
)

# Rectangular clip: a red page, then a blue rectangle clipped to a small box.
clip_content = (
    b"1 0 0 rg\n"
    b"0 0 200 200 re f\n"
    b"q\n"
    b"60 60 80 80 re W n\n"
    b"0 0 1 rg\n"
    b"0 0 200 200 re f\n"
    b"Q\n"
)
build(
    [
        (1, b"<< /Type /Catalog /Pages 2 0 R >>"),
        (2, b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>"),
        (3, b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Contents 4 0 R >>"),
        (4, stream_object(b"", clip_content)),
    ],
    FIXTURES / "clip.pdf",
)
