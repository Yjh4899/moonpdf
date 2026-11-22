"""Generate shading-type3 and fractional-page regression fixtures."""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FIXTURES = ROOT / "fixtures"


def stream_object(dict_body: bytes, data: bytes) -> bytes:
    return (
        b"<< " + dict_body + b" /Length " + str(len(data)).encode() + b" >>\nstream\n"
        + data
        + b"\nendstream"
    )


def write_pdf(name: str, objects: list[tuple[int, bytes]], size: int) -> None:
    out = bytearray(b"%PDF-1.7\n%\xe2\xe3\xcf\xd3\n")
    offsets = {}
    for num, body in objects:
        offsets[num] = len(out)
        out += f"{num} 0 obj\n".encode() + body + b"\nendobj\n"
    xref = len(out)
    out += f"xref\n0 {size}\n0000000000 65535 f \n".encode()
    for num in range(1, size):
        out += f"{offsets[num]:010d} 00000 n \n".encode()
    out += f"trailer\n<< /Size {size} /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n".encode()
    (FIXTURES / name).write_bytes(bytes(out))
    print("wrote", FIXTURES / name, len(out))


# A type-3 stitching function wrapping a single type-2 function.
shading_objects = [
    (1, b"<< /Type /Catalog /Pages 2 0 R >>"),
    (2, b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>"),
    (
        3,
        b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 100] /Resources 4 0 R /Contents 5 0 R >>",
    ),
    (4, b"<< /Shading << /Sh1 6 0 R >> >>"),
    (5, stream_object(b"", b"q 0 0 200 100 re W n /Sh1 sh Q\n")),
    (
        6,
        b"<< /ShadingType 2 /ColorSpace /DeviceRGB /Coords [0 0 200 0] "
        b"/Domain [0 1] /Function 7 0 R /Extend [true true] >>",
    ),
    (7, b"<< /FunctionType 3 /Domain [0 1] /Functions [8 0 R] /Bounds [] /Encode [0 1] >>"),
    (8, b"<< /FunctionType 2 /Domain [0 1] /C0 [1 0 0] /C1 [0 0 1] /N 1 >>"),
]
write_pdf("shading-type3.pdf", shading_objects, 9)

# Fractional MediaBox: raster dimensions must round up to the full page.
fraction_objects = [
    (1, b"<< /Type /Catalog /Pages 2 0 R >>"),
    (2, b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>"),
    (
        3,
        b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200.5 100.5] /Resources 4 0 R /Contents 5 0 R >>",
    ),
    (4, b"<< >>"),
    (5, stream_object(b"", b"1 0 0 rg 0 0 200.5 100.5 re f\n")),
]
write_pdf("page-fraction.pdf", fraction_objects, 6)
