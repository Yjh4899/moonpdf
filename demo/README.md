# MoonPDF demo

Static gallery; no build step and no server-side code.

Open `demo/index.html` directly, or serve the repository root:

```powershell
python -m http.server 8000
# http://localhost:8000/demo/
```

The gallery contains:

- real-document comparisons for attention, IRS 1040 and the PDF.js blend sample;
- selected fixture renders (fonts, images, patterns, shadings, masks);
- runnable CLI / library snippets and the verification summary.

All images are generated from the current renderer and committed under
`demo/images/`. The real PDFs are public documents; their reference images are
included only for differential comparison.

If a number changes, regenerate the corpus reports first:

```powershell
python tools/corpus_check.py --pdf-dir corpus --download --out docs/corpus-report-real.md
python tools/corpus_check.py --pdf-dir fixtures --out docs/corpus-report.md
```

Then update the score labels in `demo/index.html`.
