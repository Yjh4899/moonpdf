# MoonPDF examples

Run from the repository root after `moon build` is available:

```powershell
# Single page at 72 dpi
moon run cmd/moonpdf -- fixtures/demo.pdf out/demo.png --scale 2

# Every page, vector SVG where supported
moon run cmd/moonpdf -- fixtures/pages.pdf --all --out-dir out/pages --svg

# Selected pages
moon run cmd/moonpdf -- fixtures/pages.pdf --pages 1,3-5 --out-dir out/selected
```

## Gallery

| Example | Command | Image |
| --- | --- | --- |
| Demo page | `fixtures/demo.pdf` | ![Demo](https://raw.githubusercontent.com/Yjh4899/moonpdf/main/docs/images/demo.png) |
| Incremental update | `fixtures/incremental.pdf` | ![Incremental](https://raw.githubusercontent.com/Yjh4899/moonpdf/main/docs/images/incremental.png) |
| Embedded TrueType | `fixtures/font-embedded.pdf` | ![TrueType](https://raw.githubusercontent.com/Yjh4899/moonpdf/main/docs/images/font-embedded.png) |
| Embedded CFF | `fixtures/font-cff.pdf` | ![CFF](https://raw.githubusercontent.com/Yjh4899/moonpdf/main/docs/images/font-cff.png) |
| CID font | `fixtures/font-cid.pdf` | ![CID](https://raw.githubusercontent.com/Yjh4899/moonpdf/main/docs/images/font-cid.png) |
| JPEG image XObject | `fixtures/image-jpeg.pdf` | ![JPEG](https://raw.githubusercontent.com/Yjh4899/moonpdf/main/docs/images/image-jpeg.png) |
| Pattern | `fixtures/pattern.pdf` | ![Pattern](https://raw.githubusercontent.com/Yjh4899/moonpdf/main/docs/images/pattern.png) |
| Shading | `fixtures/shading.pdf` | ![Shading](https://raw.githubusercontent.com/Yjh4899/moonpdf/main/docs/images/shading.png) |
| Soft mask | `fixtures/soft-mask-extgstate.pdf` | ![Soft mask](https://raw.githubusercontent.com/Yjh4899/moonpdf/main/docs/images/soft-mask-extgstate.png) |

All images are generated from committed fixtures by the current renderer.

For a self-contained visual showcase, open [`demo/index.html`](../demo/index.html)
or serve `demo/` with `python -m http.server`.

## Real-document checks

```powershell
python tools/corpus_check.py --pdf-dir corpus --download `
  --out docs/corpus-report-real.md
```

The public corpus contains arXiv papers, IRS forms and PDF.js transparency and
blend samples. See [`docs/corpus-report-real.md`](../docs/corpus-report-real.md)
for per-file MAE, timing and known gaps.

## Browser / wasm

MoonPDF targets `wasm-gc` and the renderer has no filesystem or platform
dependency. The CLI is the supported entry point in 0.43.0; a browser wrapper is
future work and is tracked in [`docs/roadmap.md`](../docs/roadmap.md).
