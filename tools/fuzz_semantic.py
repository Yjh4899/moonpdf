"""Targeted semantic corruption cases for the MoonPDF fuzzer."""

from __future__ import annotations


def _stream(dict_body: bytes, data: bytes) -> bytes:
    return (
        b"<< " + dict_body + b" /Length " + str(len(data)).encode() + b" >>\nstream\n"
        + data
        + b"\nendstream"
    )


def _pdf(objects: list[tuple[int, bytes]]) -> bytes:
    out = bytearray(b"%PDF-1.7\n%\xe2\xe3\xcf\xd3\n")
    offsets = {}
    for num, body in objects:
        offsets[num] = len(out)
        out += f"{num} 0 obj\n".encode() + body + b"\nendobj\n"
    xref = len(out)
    size = max(offsets) + 1
    out += f"xref\n0 {size}\n0000000000 65535 f \n".encode()
    for num in range(1, size):
        if num in offsets:
            out += f"{offsets[num]:010d} 00000 n \n".encode()
        else:
            out += b"0000000000 00000 f \n"
    out += f"trailer\n<< /Size {size} /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n".encode()
    return bytes(out)


def semantic_cases() -> list[tuple[str, bytes]]:
    cases: list[tuple[str, bytes]] = []
    cases.append(
        (
            "huge-page",
            _pdf(
                [
                    (1, b"<< /Type /Catalog /Pages 2 0 R >>"),
                    (2, b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>"),
                    (
                        3,
                        b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 100000 100000] "
                        b"/Resources << >> /Contents 4 0 R >>",
                    ),
                    (4, _stream(b"", b"")),
                ]
            ),
        )
    )
    cases.append(
        (
            "huge-image",
            _pdf(
                [
                    (1, b"<< /Type /Catalog /Pages 2 0 R >>"),
                    (2, b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>"),
                    (
                        3,
                        b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] "
                        b"/Resources << /XObject << /Im1 5 0 R >> >> /Contents 4 0 R >>",
                    ),
                    (4, _stream(b"", b"q 100 0 0 100 50 50 cm /Im1 Do Q\n")),
                    (
                        5,
                        _stream(
                            b"/Type /XObject /Subtype /Image /Width 50000 /Height 50000 "
                            b"/ColorSpace /DeviceRGB /BitsPerComponent 8",
                            b"\x00",
                        ),
                    ),
                ]
            ),
        )
    )
    form_body = (
        b"/Type /XObject /Subtype /Form /BBox [0 0 10 10] "
        b"/Resources << /XObject << /Fm1 5 0 R >> >>"
    )
    cases.append(
        (
            "recursive-form",
            _pdf(
                [
                    (1, b"<< /Type /Catalog /Pages 2 0 R >>"),
                    (2, b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>"),
                    (
                        3,
                        b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] "
                        b"/Resources << /XObject << /Fm1 5 0 R >> >> /Contents 4 0 R >>",
                    ),
                    (4, _stream(b"", b"/Fm1 Do\n")),
                    (5, _stream(form_body, b"/Fm1 Do\n")),
                ]
            ),
        )
    )
    cases.append(
        (
            "page-tree-cycle",
            _pdf(
                [
                    (1, b"<< /Type /Catalog /Pages 2 0 R >>"),
                    (2, b"<< /Type /Pages /Kids [2 0 R] /Count 1 >>"),
                ]
            ),
        )
    )
    cases.append(
        (
            "bad-xref-offsets",
            b"%PDF-1.7\n1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n"
            b"2 0 obj\n<< /Type /Pages /Kids [] /Count 0 >>\nendobj\n"
            b"xref\n0 3\n0000000000 65535 f \n0000000000 00000 n \n0000000000 00000 n \n"
            b"trailer\n<< /Size 3 /Root 1 0 R >>\nstartxref\n0\n%%EOF\n",
        )
    )
    return cases
