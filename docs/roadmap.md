# Roadmap

The milestones are ordered by user value per unit of risk. Each milestone ends
with an observable acceptance check, so progress is visible without reading the
source. The final target is ISO 32000-1:2008 page rendering; see
[`standard-coverage.md`](standard-coverage.md).

## M0 — File structure and vector slice (delivered)

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

## M1 — Images and page geometry (current)

**Delivered**

- image XObjects: 8-bit gray/RGB/CMYK, Flate and baseline DCTDecode;
- inline images (`BI ... ID ... EI`) with abbreviated dictionaries;
- `/Rotate` 0/90/180/270, `/CropBox`, rectangular `W`/`W*` and Form `BBox` clip;
- fixtures with pixel assertions for images, rotation/crop and clipping.

**Remaining**

- progressive JPEG, soft masks and 1/2/4-bit image samples;
- exact path clipping (currently rectangular bounds);
- a larger camera/scanner image corpus.

**Acceptance**

- The declared image fixtures render with correct dimensions and colors.
- Rotation and crop boxes match the expected layout.
- Unsupported codecs fail with a specific diagnostic.

## M2 — Fonts and text fidelity (delivered)

**Delivered**

- embedded TrueType (`FontFile2`): `cmap` form 4/12, `hmtx` advances, simple and composite `glyf` outlines;
- embedded CFF (`FontFile3` Type1C, non-CID): INDEX/DICT and Type 2 charstrings;
- standard-14 Helvetica/Times/Courier metrics from the Adobe Core 14 AFMs;
- Type0 / CIDFontType2 with Identity-H, `/W` widths and `/CIDToGIDMap`;
- Type1 (`FontFile`): PFB/PFA eexec, Type 1 charstrings and `seac` accents;
- CID-keyed CFF (`CIDFontType0`): charset, FDArray/FDSelect, per-FD subrs;
- embedded Type0 encoding CMaps (`begincidrange`/`begincidchar`);
- named Adobe CJK CMaps (`UniGB/UCS2`, `UniJIS/UCS2`, `UniKS/UCS2`, `UniCNS/UCS2`);
- standard-14 ASCII kerning from AFM KernPairs;
- per-code PDF `/Widths`, glyph placement through text and CTM matrices;
- embedded-font fixtures with pixel assertions.

**Remaining**

- vertical writing mode (`-V` CMaps currently use horizontal layout).

**Acceptance**

- Text-only pages match reference layout within 1% of page width.
- Unsupported characters produce an explicit diagnostic, not silent boxes.

## M3 — Compositing and interactive appearance (current)

**Delivered so far**

- constant fill/stroke/text alpha from `ExtGState /ca` and `/CA`;
- blend modes from `ExtGState /BM` (source-over canvas, no isolation yet);
- exact `W`/`W*` path clipping with a per-pixel mask;
- axial/radial shadings (`sh`, types 2/3);
- shading patterns (`PatternType 2`);
- colored tiling patterns (`PatternType 1`);
- static annotation `/AP /N` appearance rendering;
- widget `/AS` state dictionaries;
- hidden optional content groups (`/OC` BDC);
- annotation Hidden/NoView/Invisible flags;
- uncolored tiling patterns (`PaintType 2`).

**Remaining**

- transparency groups and isolation;
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
