# Roadmap

The milestones are ordered by user value per unit of risk. Each milestone ends
with an observable acceptance check, so progress is visible without reading the
source.

## M0 — Vertical slice (current)

**Deliverables**

- classic xref, indirect objects, page tree;
- content stream interpreter for paths, fill/stroke, color and text;
- supersampled scanline rasterizer;
- fallback bitmap glyphs;
- PNG encoder and CLI;
- unit tests, fixtures, CI, compatibility matrix.

**Acceptance**

```sh
moon check --deny-warn
moon test
moon run cmd/moonpdf -- fixtures/demo.pdf out/demo.png --scale 2
```

The output is a valid PNG with the page's declared dimensions.

## M1 — Real-world documents

**Deliverables**

- FlateDecode via `moonbitlang/core/compress/zlib`;
- xref streams and object streams;
- inline images and image XObjects (JPEG/PNG);
- `/Rotate` and `/CropBox`;
- rectangular clipping for `W` / `W*`;
- page content from real-world fixtures.

**Acceptance**

- Render a declared corpus of at least 20 real PDFs.
- Every unsupported feature in the corpus is counted and reported.
- No crash on malformed input; errors are typed.

## M2 — Fonts and text fidelity

**Deliverables**

- TrueType `glyf` outline extraction and a glyph cache;
- CFF/Type1 subset;
- standard-14 metrics fallback;
- correct text advance and simple kerning;
- text extraction smoke test to cross-check positions.

**Acceptance**

- Text-only pages match reference layout within 1% of page width.
- Emoji/CJK unsupported characters produce an explicit diagnostic, not silent
  boxes.

## M3 — Compositing and vector output

**Deliverables**

- clipping paths;
- transparency groups and blend modes;
- shadings and patterns;
- SVG output for embedding;
- wasm demo that renders in the browser without PDF.js.

**Acceptance**

- A visual diff suite with SSIM thresholds per feature class.
- The wasm demo produces the same raster as native for the fixture corpus.

## M4 — Performance and differential quality

**Deliverables**

- tile-based rendering and a glyph cache;
- adaptive curve flattening;
- differential test harness against MuPDF;
- benchmark report (pages/second, memory) on a fixed machine class.

**Acceptance**

- No regression in the visual suite.
- Documented performance numbers and a reproducible benchmark command.

## Explicit non-goals

- A PDF editor or authoring tool.
- A JavaScript engine for AcroForm scripts.
- OCR or semantic layout analysis.
- Bit-exact parity with any specific renderer.
