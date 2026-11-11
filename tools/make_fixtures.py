"""Generate small, uncompressed PDF fixtures for MoonPDF tests.

The fixtures deliberately avoid xref streams, object streams, Flate and
embedded fonts so they exercise the first vertical slice of the parser.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FIXTURES = ROOT / "fixtures"
FIXTURES.mkdir(exist_ok=True)


def build_pdf(content: bytes, width: int, height: int, path: Path) -> None:
    objects = []
    objects.append(b"<< /Type /Catalog /Pages 2 0 R >>")
    objects.append(b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>")
    objects.append(
        (
            f"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 {width} {height}] "
            f"/Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>"
        ).encode("ascii")
    )
    objects.append(
        b"<< /Length " + str(len(content)).encode("ascii") + b" >>\nstream\n"
        + content
        + b"\nendstream"
    )
    objects.append(b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>")

    out = bytearray(b"%PDF-1.4\n%\xe2\xe3\xcf\xd3\n")
    offsets = [0]
    for i, obj in enumerate(objects, start=1):
        offsets.append(len(out))
        out += f"{i} 0 obj\n".encode("ascii") + obj + b"\nendobj\n"
    xref_at = len(out)
    out += f"xref\n0 {len(objects) + 1}\n".encode("ascii")
    out += b"0000000000 65535 f \n"
    for off in offsets[1:]:
        out += f"{off:010d} 00000 n \n".encode("ascii")
    out += (
        f"trailer\n<< /Size {len(objects) + 1} /Root 1 0 R >>\n"
        f"startxref\n{xref_at}\n%%EOF\n"
    ).encode("ascii")
    path.write_bytes(bytes(out))


content = b"""1 1 1 rg
0 0 300 200 re f
1 0 0 rg
20 20 110 55 re f
0.1 0.35 0.85 rg
20 120 m
60 190 110 60 170 120 c
f
0 0.6 0.2 RG
5 w
20 30 m
280 30 l
S
0 0 0 rg
BT
/F1 18 Tf
20 160 Td
(MoonPDF 2026) Tj
ET
"""

build_pdf(content, 300, 200, FIXTURES / "shapes.pdf")

content2 = b"""1 1 1 rg
0 0 400 300 re f
0 0 0 rg
BT
/F1 24 Tf
30 250 Td
(PAGE ONE) Tj
ET
BT
/F1 12 Tf
30 220 Td
(A pure MoonBit PDF renderer) Tj
ET
0.9 0.2 0.1 rg
30 60 340 100 re f
ET
"""

build_pdf(content2, 400, 300, FIXTURES / "text.pdf")

print("wrote", FIXTURES / "shapes.pdf")
print("wrote", FIXTURES / "text.pdf")

content3 = b"""0.07 0.08 0.11 rg
0 272 600 88 re f
1 1 1 rg
BT
/F1 34 Tf
32 300 Td
(MOONPDF) Tj
ET
0.16 0.55 0.95 rg
40 110 130 110 re f
0.92 0.24 0.20 rg
210 110 m
260 230 330 40 390 150 c
f
0.08 0.75 0.45 RG
6 w
40 250 m
560 250 l
S
0 0 0 rg
BT
/F1 14 Tf
40 80 Td
(A PURE MOONBIT PDF RENDERER) Tj
ET
BT
/F1 8 Tf
40 24 Td
(NATIVE DETERMINISTIC NO JS VM) Tj
ET
"""

build_pdf(content3, 600, 360, FIXTURES / "demo.pdf")
print("wrote", FIXTURES / "demo.pdf")
