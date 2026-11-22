"""Regenerate render/fallback_font_data.mbt from the OpenSans subset asset."""

import base64
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
data = (ROOT / "fixtures" / "fonts" / "OpenSans-Fallback.ttf").read_bytes()
encoded = base64.b64encode(zlib.compress(data, 9)).decode("ascii")
chunks = [encoded[i : i + 1000] for i in range(0, len(encoded), 1000)]
lines = [
    "///|",
    "/// Compressed OpenSans fallback (OFL), generated from fixtures/fonts/OpenSans-Fallback.ttf.",
    "let fallback_font_b64 : Array[String] = [",
]
lines.extend(f'  "{chunk}",' for chunk in chunks)
lines.append("]")
(ROOT / "render" / "fallback_font_data.mbt").write_text("\n".join(lines) + "\n", encoding="utf-8")
print(len(data), len(encoded), len(chunks))
