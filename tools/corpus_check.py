"""Render a PDF corpus with MoonPDF and compare against PyMuPDF when available.

Usage:
    python tools/corpus_check.py --pdf-dir fixtures --out docs/corpus-report.md
    python tools/corpus_check.py --pdf-dir corpus --download

PyMuPDF is optional; without it the report still records render success, time and
produced PNG size. Install with `pip install pymupdf`.
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import time
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MANIFEST = ROOT / "corpus" / "manifest.json"
DEFAULT_OUT = ROOT / "docs" / "corpus-report.md"


def find_pdfs(directory: Path) -> list[Path]:
    return sorted(p for p in directory.glob("*.pdf") if p.is_file())


def download_corpus(directory: Path) -> int:
    if not MANIFEST.exists():
        print(f"no manifest at {MANIFEST}")
        return 0
    entries = json.loads(MANIFEST.read_text(encoding="utf-8"))
    directory.mkdir(parents=True, exist_ok=True)
    count = 0
    for entry in entries:
        target = directory / entry["name"]
        if target.exists():
            continue
        print(f"download {entry['name']} <- {entry['url']}")
        try:
            with urllib.request.urlopen(entry["url"], timeout=60) as response:
                target.write_bytes(response.read())
            count += 1
        except Exception as error:  # noqa: BLE001 - report and continue
            print(f"  failed: {error}")
    return count


def moon_command(pdf: Path, png: Path) -> list[str]:
    return [
        "moon",
        "run",
        "cmd/moonpdf",
        "--",
        str(pdf),
        str(png),
        "--scale",
        "1",
    ]


def render_with_moonpdf(pdf: Path, png: Path, timeout: int) -> dict:
    started = time.perf_counter()
    try:
        proc = subprocess.run(
            moon_command(pdf, png),
            cwd=ROOT,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=timeout,
        )
        elapsed = (time.perf_counter() - started) * 1000.0
        return {
            "ok": proc.returncode == 0 and png.exists(),
            "ms": round(elapsed, 1),
            "returncode": proc.returncode,
            "stderr": (proc.stderr or "").strip()[-500:],
            "stdout": (proc.stdout or "").strip()[-500:],
        }
    except subprocess.TimeoutExpired:
        return {
            "ok": False,
            "ms": round((time.perf_counter() - started) * 1000.0, 1),
            "returncode": -1,
            "stderr": f"timeout after {timeout}s",
            "stdout": "",
        }


def render_reference(pdf: Path, png: Path) -> dict:
    try:
        import pymupdf  # type: ignore
    except ImportError:
        try:
            import fitz as pymupdf  # type: ignore
        except ImportError:
            return {"ok": False, "error": "pymupdf not installed"}
    try:
        document = pymupdf.open(str(pdf))
        if document.page_count < 1:
            return {"ok": False, "error": "no pages"}
        page = document.load_page(0)
        pixmap = page.get_pixmap(matrix=pymupdf.Matrix(1, 1), alpha=False)
        pixmap.save(str(png))
        document.close()
        return {"ok": True}
    except Exception as error:  # noqa: BLE001 - record reference failures
        return {"ok": False, "error": str(error)[:300]}


def compare_images(moon_png: Path, reference_png: Path) -> dict:
    try:
        from PIL import Image, ImageChops
        import numpy as np
    except ImportError:
        return {"ok": False, "error": "Pillow/numpy not installed"}
    try:
        left = Image.open(moon_png).convert("RGB")
        right = Image.open(reference_png).convert("RGB")
        if left.size != right.size:
            right = right.resize(left.size)
        a = np.asarray(left, dtype=np.int16)
        b = np.asarray(right, dtype=np.int16)
        difference = np.abs(a - b)
        mae = float(difference.mean())
        close = float((difference.max(axis=2) <= 8).mean())
        return {"ok": True, "mae": round(mae, 2), "close": round(close, 4)}
    except Exception as error:  # noqa: BLE001
        return {"ok": False, "error": str(error)[:300]}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--pdf-dir", action="append", default=[])
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT)
    parser.add_argument("--json", type=Path, default=None)
    parser.add_argument("--timeout", type=int, default=120)
    parser.add_argument("--limit", type=int, default=0)
    parser.add_argument("--no-reference", action="store_true")
    parser.add_argument("--download", action="store_true")
    parser.add_argument("--pymupdf-path", type=Path, default=None)
    args = parser.parse_args()
    if args.pymupdf_path:
        sys.path.insert(0, str(args.pymupdf_path))

    directories = [ROOT / value for value in (args.pdf_dir or ["fixtures"])]
    if args.download:
        for directory in directories:
            download_corpus(directory)

    pdfs: list[Path] = []
    for directory in directories:
        pdfs.extend(find_pdfs(directory))
    if args.limit:
        pdfs = pdfs[: args.limit]
    if not pdfs:
        print("no PDFs found")
        return 1

    work = ROOT / "out" / "corpus"
    work.mkdir(parents=True, exist_ok=True)
    rows = []
    for index, pdf in enumerate(pdfs, 1):
        name = pdf.name
        moon_png = work / f"{pdf.stem}-moon.png"
        ref_png = work / f"{pdf.stem}-ref.png"
        if moon_png.exists():
            moon_png.unlink()
        if ref_png.exists():
            ref_png.unlink()
        print(f"[{index}/{len(pdfs)}] {name}")
        moon = render_with_moonpdf(pdf, moon_png, args.timeout)
        reference = {"ok": False}
        similarity = {"ok": False}
        if not args.no_reference:
            reference = render_reference(pdf, ref_png)
            if moon["ok"] and reference.get("ok"):
                similarity = compare_images(moon_png, ref_png)
        result = "PASS" if moon["ok"] else "FAIL"
        if similarity.get("ok") and similarity.get("close", 0) < 0.90:
            result = "DIFF"
        rows.append(
            {
                "pdf": name,
                "moon": moon,
                "reference": reference,
                "similarity": similarity,
                "result": result,
            }
        )

    passed = sum(1 for row in rows if row["result"] == "PASS")
    failed = sum(1 for row in rows if row["result"] == "FAIL")
    diff = sum(1 for row in rows if row["result"] == "DIFF")
    measured = [row["moon"]["ms"] for row in rows if row["moon"]["ok"]]
    summary = {
        "pdfs": len(rows),
        "pass": passed,
        "fail": failed,
        "diff": diff,
        "mean_ms": round(sum(measured) / len(measured), 1) if measured else 0,
    }

    if args.json:
        args.json.write_text(
            json.dumps({"summary": summary, "rows": rows}, indent=2),
            encoding="utf-8",
        )

    lines = [
        "# Corpus report",
        "",
        "Generated by `tools/corpus_check.py`. First page, scale 1.0.",
        "",
        f"- PDFs: **{summary['pdfs']}**",
        f"- Render pass: **{passed}**",
        f"- Render fail: **{failed}**",
        f"- Pixel diff (`close < 0.90`): **{diff}**",
        f"- Mean render time: **{summary['mean_ms']} ms/PDF**",
        "",
        "| PDF | MoonPDF | Time (ms) | Reference | MAE | Pixels <= 8 | Result |",
        "| --- | --- | --- | --- | --- | --- | --- |",
    ]
    for row in rows:
        moon = row["moon"]
        reference = row["reference"]
        similarity = row["similarity"]
        moon_text = "ok" if moon["ok"] else f"fail ({moon.get('returncode')})"
        ref_text = "ok" if reference.get("ok") else "n/a"
        mae = similarity.get("mae", "-")
        close = similarity.get("close", "-")
        if isinstance(close, float):
            close = f"{close * 100:.1f}%"
        lines.append(
            f"| `{row['pdf']}` | {moon_text} | {moon['ms']} | {ref_text} | {mae} | {close} | {row['result']} |"
        )
    args.out.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"wrote {args.out}")
    print(json.dumps(summary, indent=2))
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
