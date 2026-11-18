"""Generate a Type1 (/FontFile) fixture from Latin Modern Roman 10."""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FIXTURES = ROOT / "fixtures"
FONT = FIXTURES / "fonts" / "lmr10.pfb"
AFM = FIXTURES / "fonts" / "lmr10.afm"


def stream_object(dict_body: bytes, data: bytes) -> bytes:
    return (
        b"<< " + dict_body + b" /Length " + str(len(data)).encode() + b" >>\nstream\n"
        + data
        + b"\nendstream"
    )


afm = AFM.read_text(encoding="latin1")
widths_by_code = {}
for m in re.finditer(r"^C\s+(-?\d+)\s*;\s*WX\s+([\d.]+)", afm, re.M):
    code = int(m.group(1))
    if 32 <= code <= 126:
        widths_by_code[code] = round(float(m.group(2)))
widths = [widths_by_code.get(code, 500) for code in range(32, 127)]

font_data = FONT.read_bytes()
content = (
    b"0 0 0 rg\n"
    b"BT\n/F1 28 Tf\n20 70 Td\n(Type1 outlines) Tj\nET\n"
)
objects = [
    (1, b"<< /Type /Catalog /Pages 2 0 R >>"),
    (2, b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>"),
    (3, b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 340 150] /Resources 5 0 R /Contents 4 0 R >>"),
    (4, stream_object(b"", content)),
    (5, b"<< /Font << /F1 6 0 R >> >>"),
    (
        6,
        (
            b"<< /Type /Font /Subtype /Type1 /BaseFont /LMRoman10-Regular "
            b"/FirstChar 32 /LastChar 126 /Widths ["
            + b" ".join(str(w).encode() for w in widths)
            + b"] /FontDescriptor 7 0 R /Encoding /WinAnsiEncoding >>"
        ),
    ),
    (
        7,
        b"<< /Type /FontDescriptor /FontName /LMRoman10-Regular /Flags 32 "
        b"/FontBBox [-430 -290 1417 1127] /ItalicAngle 0 /Ascent 700 "
        b"/Descent -200 /CapHeight 683 /StemV 80 /FontFile 8 0 R >>",
    ),
    (8, stream_object(f"/Length1 {len(font_data)}".encode(), font_data)),
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
(FIXTURES / "font-type1.pdf").write_bytes(bytes(out))
print("wrote", FIXTURES / "font-type1.pdf", len(out), "bytes")
