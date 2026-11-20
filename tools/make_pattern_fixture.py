"""Generate a shading-pattern fixture (PatternType 2)."""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FIXTURES = ROOT / "fixtures"


def stream_object(dict_body: bytes, data: bytes) -> bytes:
    return (
        b"<< " + dict_body + b" /Length " + str(len(data)).encode() + b" >>\nstream\n"
        + data
        + b"\nendstream"
    )


content = b"/Pattern cs\n/P1 scn\n50 50 100 100 re f\n"
objects = [
    (1, b"<< /Type /Catalog /Pages 2 0 R >>"),
    (2, b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>"),
    (3, b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Resources 4 0 R /Contents 5 0 R >>"),
    (4, b"<< /Pattern << /P1 6 0 R >> >>"),
    (5, stream_object(b"", content)),
    (6, b"<< /PatternType 2 /Shading 7 0 R >>"),
    (
        7,
        b"<< /ShadingType 2 /ColorSpace /DeviceRGB /Coords [0 0 200 0] "
        b"/Function << /FunctionType 2 /Domain [0 1] /C0 [1 0 0] /C1 [0 0 1] /N 1 >> "
        b"/Extend [true true] >>",
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
    out += f"{offsets[num]:010d} 00000 n \n".encode()
out += f"trailer\n<< /Size {size} /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n".encode()
(FIXTURES / "pattern.pdf").write_bytes(bytes(out))
print("wrote", FIXTURES / "pattern.pdf", len(out), "bytes")
