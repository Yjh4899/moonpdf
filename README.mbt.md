# MoonPDF

A pure-MoonBit PDF 1.7 page renderer: parse a PDF, interpret its content stream,
rasterize the page and write PNG or SVG — no JavaScript VM, no C library, no
browser.

## Public API

The high-level facade keeps one parsed document and renders pages from it:

```moonbit nocheck
///|
let document = @moonpdf.MoonPdfDocument::open(data) catch { ... }

///|
let pages = document.page_count()

///|
let png = document.render_png(0, 1.0) catch { ... }

///|
let svg = document.render_svg(0, 1.0) catch { ... }
```

Single-page helpers such as `page_count(data)` and `render_page_png(data, page,
scale)` remain available. Low-level entry points are `parse_document`,
`render_page`, `encode_png` and `encode_svg_vector`.

## CLI

```text
moonpdf <input.pdf> [output.png|output.svg] [options]
  --page N      1-based page (default 1)
  --all         render every page
  --pages LIST  e.g. 1,3-5
  --out-dir D   output directory
  --scale S     1.0 = 72 dpi
  --svg         SVG output
```

## What is implemented

PDF 1.7 rendering-relevant coverage includes classic xref, xref/object streams,
hybrid xref, incremental updates, Flate/ASCII/LZW/RunLength filters, page trees,
Form XObjects, images (gray/RGB/CMYK, Flate, JPEG, inline, soft masks),
TrueType/CFF/Type1/Type0/CID fonts, transparency groups, constant alpha, blend
modes, clipping, axial/radial shadings, tiling/shading patterns, annotations,
optional content and vector SVG for supported pages.

Version 0.43.0 adds `BT`/`ET` font-state preservation, type-3 stitching
shadings, full-pixel page rounding, HSL blend modes, gamma-aware downsampling,
pixel-center fill, an embedded OpenSans fallback, Type1 stem weight and bilinear
image sampling.

## Verification

- 61 unit/integration tests, `moon check --deny-warn` clean.
- 39 committed fixtures: 39 render, 34 within pixel tolerance, 0 fail.
- 13 public real PDFs: 13 render, 5 within tolerance, 0 crash/timeout.
- 120 malformed PDFs: 0 crashes, 0 timeouts.
- CI runs wasm-gc tests plus native tests, fixture renders and pixel probes.

See [README.md](README.md) for the full description and
[`docs/acceptance.md`](docs/acceptance.md) for the 0.43.0 release audit.
