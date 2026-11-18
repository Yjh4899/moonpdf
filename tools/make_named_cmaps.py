"""Generate render/named_cmaps.mbt from the Adobe Unicode UCS2 CMaps."""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "_cmap"
OUT = ROOT / "render" / "named_cmaps.mbt"

FILES = {
    "UniGB-UCS2-H": "UniGB-UCS2-H",
    "UniJIS-UCS2-H": "UniJIS-UCS2-H",
    "UniKS-UCS2-H": "UniKS-UCS2-H",
    "UniCNS-UCS2-H": "UniCNS-UCS2-H",
}


def parse(path):
    text = path.read_text(encoding="latin1")
    ranges = []
    for m in re.finditer(r"^<([0-9A-Fa-f]{4})>\s+<([0-9A-Fa-f]{4})>\s+(\d+)", text, re.M):
        lo, hi, cid = int(m.group(1), 16), int(m.group(2), 16), int(m.group(3))
        if hi >= lo:
            ranges.append((lo, hi, cid))
    # Single code mappings appear as "<code> cid" inside begincidchar.
    for m in re.finditer(r"^<([0-9A-Fa-f]{4})>\s+(\d+)\s*$", text, re.M):
        code, cid = int(m.group(1), 16), int(m.group(2))
        ranges.append((code, code, cid))
    # Sort and merge adjacent ranges with a constant CID delta.
    ranges.sort()
    merged = []
    for lo, hi, cid in ranges:
        if merged:
            plo, phi, pcid = merged[-1]
            if lo == phi + 1 and cid == pcid + (lo - plo):
                merged[-1] = (plo, hi, pcid)
                continue
        merged.append((lo, hi, cid))
    return merged


data = {name: parse(SRC / fname) for name, fname in FILES.items()}
lines = [
    "///|",
    "/// Named Adobe Unicode UCS2 CMaps. Each range maps a code interval to a",
    "/// starting Adobe CID; only horizontal CMaps are used for rendering.",
    "pub struct NamedCMap {",
    "  name : String",
    "  code_bytes : Int32",
    "  ranges : Array[(Int32, Int32, Int32)]",
    "}",
    "///|",
    "pub fn NamedCMap::cid_for(self : NamedCMap, code : Int32) -> Int32 {",
    "  for range in self.ranges {",
    "    if code >= range.0 && code <= range.1 {",
    "      return range.2 + (code - range.0)",
    "    }",
    "  }",
    "  0",
    "}",
    "///|",
    "pub fn NamedCMap::expand(self : NamedCMap) -> Array[(Int32, Int32)] {",
    "  let out : Array[(Int32, Int32)] = []",
    "  for range in self.ranges {",
    "    let mut code = range.0",
    "    while code <= range.1 {",
    "      out.push((code, range.2 + (code - range.0)))",
    "      code = code + 1",
    "    }",
    "  }",
    "  out",
    "}",
]
for name, ranges in data.items():
    fn = name.lower().replace("-", "_")
    chunks = [ranges[i:i + 3000] for i in range(0, len(ranges), 3000)]
    for index, chunk in enumerate(chunks):
        lines.append("///|")
        lines.append(f"fn {fn}_{index}() -> Array[(Int32, Int32, Int32)] {{")
        lines.append("  [")
        for lo, hi, cid in chunk:
            lines.append(f"    ({lo}, {hi}, {cid}),")
        lines.append("  ]")
        lines.append("}")
    lines.append("///|")
    lines.append(f"fn {fn}() -> Array[(Int32, Int32, Int32)] {{")
    lines.append("  let out : Array[(Int32, Int32, Int32)] = []")
    for index in range(len(chunks)):
        lines.append(f"  for item in {fn}_{index}() {{")
        lines.append("    out.push(item)")
        lines.append("  }")
    lines.append("  out")
    lines.append("}")
lines.append("///|")
lines.append("pub fn named_cmap(name : String) -> NamedCMap? {")
lines.append("  match name {")
for name in data:
    lines.append(
        f'    "{name}" | "{name[:-1]}V" => Some({{ name: "{name}", code_bytes: 2, ranges: {name.lower().replace("-", "_")}() }})'
    )
lines.append("    _ => None")
lines.append("  }")
lines.append("}")
OUT.write_text("\n".join(lines) + "\n", encoding="utf-8")
print({k: len(v) for k, v in data.items()})
