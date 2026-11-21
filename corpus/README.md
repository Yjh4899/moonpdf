# Corpus

This directory holds optional real-world PDFs for differential testing. PDFs are
not committed; only the manifest and the checker are.

```sh
python tools/corpus_check.py --pdf-dir corpus --download --out docs/corpus-report.md
```

The checker renders page 1 at scale 1.0, writes a Markdown/JSON report, and when
PyMuPDF is available compares MoonPDF with its rasterizer:

- MAE: mean absolute RGB difference (0 = identical).
- Pixels ≤ 8: fraction of pixels whose largest channel error is at most 8.
- A row is `DIFF` when fewer than 90% of pixels are within that tolerance.

The manifest URLs are public test resources. Check each upstream license before
redistributing a downloaded file.
