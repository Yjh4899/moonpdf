"""Extract ASCII kerning pairs from the Adobe Core 14 AFM files.

The AFM files permit use, copying and distribution for any purpose. The parsed
pairs are stored in tools/standard_kerning.json and rendered into
render/standard_kerning.mbt by make_standard_kerning.py.
"""

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
AFM_DIR = ROOT / "_afm"
OUT_JSON = ROOT / "tools" / "standard_kerning.json"
OUT_MBT = ROOT / "render" / "standard_kerning.mbt"

FONTS = [
    "Helvetica",
    "Helvetica-Bold",
    "Helvetica-Oblique",
    "Helvetica-BoldOblique",
    "Times-Roman",
    "Times-Bold",
    "Times-Italic",
    "Times-BoldItalic",
    "Courier",
    "Courier-Bold",
    "Courier-Oblique",
    "Courier-BoldOblique",
]
ALIASES = {
    "helvetica": ["Helvetica", "Arial", "ArialMT"],
    "helvetica_bold": ["Helvetica-Bold", "Arial-Bold", "Arial-BoldMT"],
    "helvetica_oblique": ["Helvetica-Oblique", "Arial-Italic", "Arial-ItalicMT"],
    "helvetica_bold_oblique": ["Helvetica-BoldOblique", "Arial-BoldItalic", "Arial-BoldItalicMT"],
    "times_roman": ["Times-Roman", "TimesNewRoman", "TimesNewRomanPSMT"],
    "times_bold": ["Times-Bold", "TimesNewRomanPS-BoldMT"],
    "times_italic": ["Times-Italic", "TimesNewRomanPS-ItalicMT"],
    "times_bold_italic": ["Times-BoldItalic", "TimesNewRomanPS-BoldItalicMT"],
    "courier": ["Courier", "CourierNew", "CourierNewPSMT"],
    "courier_bold": ["Courier-Bold", "CourierNewPS-BoldMT"],
    "courier_oblique": ["Courier-Oblique", "CourierNewPS-ItalicMT"],
    "courier_bold_oblique": ["Courier-BoldOblique", "CourierNewPS-BoldItalicMT"],
}


def parse_font(path):
    text = path.read_text(encoding="latin1")
    name_to_code = {}
    for m in re.finditer(r"^C\s+(-?\d+)\s*;.*?N\s+([^\s;]+)", text, re.M):
        code = int(m.group(1))
        if 32 <= code <= 126:
            name_to_code[m.group(2)] = code
    pairs = {}
    for m in re.finditer(r"^KPX\s+(\S+)\s+(\S+)\s+(-?\d+)", text, re.M):
        left, right, value = m.group(1), m.group(2), int(m.group(3))
        if left in name_to_code and right in name_to_code:
            key = (name_to_code[left], name_to_code[right])
            pairs[key] = value
    return [[a, b, v] for (a, b), v in sorted(pairs.items())]


data = {}
for font in FONTS:
    data[font] = parse_font(AFM_DIR / f"{font}.afm")
OUT_JSON.write_text(json.dumps(data, indent=2), encoding="utf-8")

lines = [
    "///|",
    "/// ASCII kerning pairs for the PDF standard-14 fonts, in 1/1000 em.",
    "/// Transcribed from the Adobe Core 14 AFM files.",
]
for font, fn in [
    ("Helvetica", "helvetica"),
    ("Helvetica-Bold", "helvetica_bold"),
    ("Helvetica-Oblique", "helvetica_oblique"),
    ("Helvetica-BoldOblique", "helvetica_bold_oblique"),
    ("Times-Roman", "times_roman"),
    ("Times-Bold", "times_bold"),
    ("Times-Italic", "times_italic"),
    ("Times-BoldItalic", "times_bold_italic"),
    ("Courier", "courier"),
    ("Courier-Bold", "courier_bold"),
    ("Courier-Oblique", "courier_oblique"),
    ("Courier-BoldOblique", "courier_bold_oblique"),
]:
    pairs = data[font]
    lines.append("///|")
    lines.append(f"fn {fn}_kern() -> Array[(Int32, Int32, Int32)] {{")
    lines.append("  [")
    for a, b, v in pairs:
        lines.append(f"    ({a}, {b}, {v}),")
    lines.append("  ]")
    lines.append("}")
lines.append("///|")
lines.append("pub fn standard14_kerning(base_name : String) -> Array[(Int32, Int32, Int32)]? {")
lines.append("  match base_name {")
for fn, names in ALIASES.items():
    pattern = " | ".join('"' + n + '"' for n in names)
    lines.append(f"    {pattern} => Some({fn}_kern())")
lines.append("    _ => None")
lines.append("  }")
lines.append("}")
OUT_MBT.write_text("\n".join(lines) + "\n", encoding="utf-8")
print({k: len(v) for k, v in data.items()})
