"""Regenerate render/standard_widths.mbt from the parsed Core 14 AFM widths.

The widths in tools/standard_widths.json were extracted from the Adobe Core 14
AFM files (the AFM files permit use, copying and distribution for any purpose):

    https://github.com/laudebugs/laminapdf/tree/master/tools/std14-gen/data/afm

This script is kept for reproducibility; it is not part of the build.
"""

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
data = json.loads((ROOT / "tools" / "standard_widths.json").read_text(encoding="utf-8"))
FNS = {
    "Helvetica": "helvetica",
    "Helvetica-Bold": "helvetica_bold",
    "Helvetica-Oblique": "helvetica_oblique",
    "Helvetica-BoldOblique": "helvetica_bold_oblique",
    "Times-Roman": "times_roman",
    "Times-Bold": "times_bold",
    "Times-Italic": "times_italic",
    "Times-BoldItalic": "times_bold_italic",
    "Courier": "courier",
    "Courier-Bold": "courier_bold",
    "Courier-Oblique": "courier_oblique",
    "Courier-BoldOblique": "courier_bold_oblique",
}
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

lines = [
    "///|",
    "/// Advance widths for the PDF standard-14 fonts at codes 32..126, in",
    "/// 1/1000 em. Transcribed from the Adobe Core 14 AFM files; the AFM files",
    "/// permit use and redistribution for any purpose.",
]
for name, fn in FNS.items():
    vals = data[name]
    lines.append("///|")
    lines.append(f"fn {fn}() -> Array[Int32] {{")
    lines.append("  [")
    for i in range(0, len(vals), 16):
        lines.append("    " + ", ".join(str(v) for v in vals[i:i + 16]) + ",")
    lines.append("  ]")
    lines.append("}")
lines.append("///|")
lines.append("pub fn standard14_widths(base_name : String) -> Array[Int32]? {")
lines.append("  match base_name {")
for fn, names in ALIASES.items():
    pattern = " | ".join('"' + n + '"' for n in names)
    lines.append(f"    {pattern} => Some({fn}())")
lines.append("    _ => None")
lines.append("  }")
lines.append("}")

(ROOT / "render" / "standard_widths.mbt").write_text(
    "\n".join(lines) + "\n",
    encoding="utf-8",
)
print("wrote render/standard_widths.mbt")
