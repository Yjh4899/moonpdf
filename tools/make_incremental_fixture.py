"""Build an incrementally saved PDF fixture that reuses an old Form XObject.

Base revision:
  * object 4 is the page content: it only invokes the logo form ``/Logo Do``;
  * object 8 is a Form XObject that draws the blue header and its text;
  * object 6 is the shared page resource dictionary (font + logo).

Incremental revision:
  * rewrites only object 3, pointing ``/Contents`` at ``[4 0 R 7 0 R]``;
  * appends object 7, a new body stream (green panel + "REVISION TWO").

Object 4 (old content) and object 8 (old form resource) are reused untouched.
The expected page therefore contains the old blue "MOONPDF BASE" header and the
new green "REVISION TWO" body.
"""

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


base_items = [
    (1, b"<< /Type /Catalog /Pages 2 0 R >>"),
    (2, b"<< /Type /Pages /Kids [3 0 R] /Count 1 /Resources 6 0 R >>"),
    (3, b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 200] /Contents 4 0 R >>"),
    (4, stream_object(b"", b"/Logo Do\n")),
    (5, b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>"),
    (6, b"<< /Font << /F1 5 0 R >> /XObject << /Logo 8 0 R >> >>"),
    (
        8,
        stream_object(
            b"/Type /XObject /Subtype /Form /BBox [0 0 300 200] "
            b"/Resources << /Font << /F1 5 0 R >> >>",
            b"0.10 0.30 0.80 rg\n"
            b"20 140 260 40 re f\n"
            b"1 1 1 rg\n"
            b"BT\n/F1 20 Tf\n30 152 Td\n(MOONPDF BASE) Tj\nET\n",
        ),
    ),
]

out = bytearray(b"%PDF-1.7\n%\xe2\xe3\xcf\xd3\n")
offsets = {}
for num, body in base_items:
    offsets[num] = len(out)
    out += f"{num} 0 obj\n".encode("ascii") + body + b"\nendobj\n"

base_xref = len(out)
size = 9
out += f"xref\n0 {size}\n".encode("ascii")
out += b"0000000000 65535 f \n"
for num in range(1, size):
    if num in offsets:
        out += f"{offsets[num]:010d} 00000 n \n".encode("ascii")
    else:
        out += b"0000000000 00000 f \n"
out += (
    f"trailer\n<< /Size {size} /Root 1 0 R >>\n"
    f"startxref\n{base_xref}\n%%EOF\n"
).encode("ascii")

(FIXTURES / "incremental-base.pdf").write_bytes(bytes(out))

new_page = (
    b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 200] "
    b"/Contents [4 0 R 7 0 R] >>"
)
new_content = stream_object(
    b"",
    b"0.10 0.70 0.30 rg\n"
    b"20 40 260 70 re f\n"
    b"0 0 0 rg\n"
    b"BT\n/F1 18 Tf\n30 70 Td\n(REVISION TWO) Tj\nET\n",
)

incremental = bytearray(out)
new_offsets = {}
new_offsets[3] = len(incremental)
incremental += b"3 0 obj\n" + new_page + b"\nendobj\n"
new_offsets[7] = len(incremental)
incremental += b"7 0 obj\n" + new_content + b"\nendobj\n"

new_xref = len(incremental)
incremental += b"xref\n3 1\n" + f"{new_offsets[3]:010d} 00000 n \n".encode("ascii")
incremental += b"7 1\n" + f"{new_offsets[7]:010d} 00000 n \n".encode("ascii")
incremental += (
    f"trailer\n<< /Size {size} /Root 1 0 R /Prev {base_xref} >>\n"
    f"startxref\n{new_xref}\n%%EOF\n"
).encode("ascii")

(FIXTURES / "incremental.pdf").write_bytes(bytes(incremental))

# A full rewrite of the same logical revision: everything in one xref section.
# Rendering this file must be pixel-identical to the incremental file.
full_objects = {num: body for num, body in base_items}
full_objects[3] = new_page
full_objects[7] = new_content
full = bytearray(b"%PDF-1.7\n%\xe2\xe3\xcf\xd3\n")
full_offsets = {}
for num in range(1, size):
    if num in full_objects:
        full_offsets[num] = len(full)
        full += f"{num} 0 obj\n".encode("ascii") + full_objects[num] + b"\nendobj\n"
full_xref = len(full)
full += f"xref\n0 {size}\n".encode("ascii")
full += b"0000000000 65535 f \n"
for num in range(1, size):
    if num in full_offsets:
        full += f"{full_offsets[num]:010d} 00000 n \n".encode("ascii")
    else:
        full += b"0000000000 00000 f \n"
full += (
    f"trailer\n<< /Size {size} /Root 1 0 R >>\n"
    f"startxref\n{full_xref}\n%%EOF\n"
).encode("ascii")
(FIXTURES / "incremental-full.pdf").write_bytes(bytes(full))

print("wrote", FIXTURES / "incremental-base.pdf")
print("wrote", FIXTURES / "incremental.pdf")
print("wrote", FIXTURES / "incremental-full.pdf")
