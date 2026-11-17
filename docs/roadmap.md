# Roadmap

The milestones are ordered by user value per unit of risk. Each milestone ends
with an observable acceptance check, so progress is visible without reading the
source. The final target is ISO 32000-1:2008 page rendering; see
[`standard-coverage.md`](standard-coverage.md).

## M0 — File structure and vector slice (current)

**Delivered**

- classic xref, xref streams, object streams, hybrid `/XRefStm`;
- incremental updates: `/Prev` chain, revision overlay, free entries;
- Flate/ASCIIHex/ASCII85/RunLength/LZW filters and predictors;
- page tree with inherited `MediaBox` / `Resources`;
- content stream interpreter for paths, fill/stroke, color and text;
- Form XObjects with `/Matrix` and nested resources;
- supersampled scanline rasterizer and fallback bitmap glyphs;
- PNG encoder and CLI;
- unit/integration tests, fixtures, CI and compatibility matrix;
- incremental fixture reusing an old Form XObject and old resources.

**Acceptance**

```sh
moon check --deny-warn
moon test
moon run cmd/moonpdf -- fixtures/incremental.pdf out/incremental.png --scale 2
```

The incremental page must show the reused blue header and the new green body.

## M1 — Images and page geometry

**Deliverables**

- image XObjects and inline images: DCTDecode (JPEG), Flate/PNG predictors;
- `/Rotate`, `/CropBox`, `BBox` clipping and rectangular `W`/`W*`;
- more real-world fixtures, including camera/scanner output.

**Acceptance**

- A declared image corpus renders with correct dimensions and visible content.
- Rotation and crop boxes match the reference layout.
- Unsupported image codecs fail with a specific diagnostic.

## M2 — Fonts and text fidelity

**Deliverables**

- TrueType `glyf` outline extraction and a glyph cache;
- CFF/Type1 subset;
- standard-14 metrics fallback;
- correct text advance and simple kerning;
- CID/CJK fonts and encodings.

**Acceptance**

- Text-only pages match reference layout within 1% of page width.
- Unsupported characters produce an explicit diagnostic, not silent boxes.

## M3 — Compositing and interactive appearance

**Deliverables**

- clipping paths;
- transparency groups and blend modes;
- shadings and patterns;
- annotation appearance streams;
- optional content visibility;
- SVG output and a wasm demo.

**Acceptance**

- A visual diff suite with SSIM thresholds per feature class.
- The wasm demo produces the same raster as native for the fixture corpus.

## M4 — Corpus quality and performance

**Deliverables**

- differential harness against MuPDF on the public corpus;
- tile-based rendering, glyph cache, adaptive curve flattening;
- benchmark report (pages/second, memory) on a fixed machine class.

**Acceptance**

- 100% no-crash/no-hang; 98% of pages SSIM ≥ 0.95.
- Documented performance numbers and a reproducible benchmark command.

## Explicit non-goals

- A PDF editor or authoring tool.
- A JavaScript engine for AcroForm scripts.
- OCR or semantic layout analysis.
- Bit-exact parity with any specific renderer.
