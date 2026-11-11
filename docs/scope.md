# Scope and acceptance

## Problem

MoonBit can parse and generate PDFs, but it cannot turn a PDF page into pixels.
The official office viewer proves the gap: its PDF preview delegates to PDF.js
in the browser. Any native MoonBit tool that needs a thumbnail, a page image for
OCR, or a visual regression check must embed a JavaScript VM or shell out to an
external renderer.

## Three concrete scenarios

1. **Document service.** A MoonBit backend receives an uploaded PDF and returns
   a first-page PNG for an approval queue. Today the service needs Node/PDF.js
   or a system `pdftoppm`; MoonPDF makes the conversion a library call.
2. **AI / agent document pipeline.** A multimodal model or OCR step needs page
   images, not raw PDF bytes. MoonPDF exposes page rasterization as a
   deterministic native function that can run in a service, a CLI or a wasm
   module without a browser.
3. **Desktop / IDE preview.** A MoonBit-native document tool wants an embedded
   page preview. MoonPDF provides the raster; the host only has to display a
   PNG. The same engine can later drive visual diffing between two revisions of
   a contract or a generated report.

A fourth, near-term scenario is CI: a document generator can render its own
output and compare page hashes, catching layout regressions without a
JavaScript toolchain.

## MVP (this repository)

The initial-review slice is intentionally narrow but complete end to end:

- classic xref tables and indirect objects;
- page tree with inherited `MediaBox` and `Resources`;
- content operators for graphics state, paths, fill/stroke, color and text;
- fill rules (nonzero and even-odd), line width and round caps;
- 3×5 fallback text with `Tj` / `TJ` and text positioning;
- RGB PNG output;
- CLI with page selection and scale;
- unit tests, fixtures and CI;
- explicit compatibility matrix and error messages.

## Acceptance criteria for the MVP

1. `moon check --deny-warn` and `moon test` pass on a clean checkout.
2. `moon run cmd/moonpdf -- fixtures/demo.pdf out.png --scale 2` writes a valid
   PNG with the expected dimensions.
3. The two vector fixtures render with the expected colors and geometry.
4. Unsupported PDF features fail with a specific error, never with a silently
   wrong image.
5. The README states what is and is not supported, with links to the
   compatibility matrix and roadmap.
6. CI runs formatting, checking, tests and the end-to-end render.

## Out of scope (for now)

- PDF authoring, editing, form filling, signing and encryption removal.
- JavaScript execution, 3D annotations, portfolios and embedded files.
- OCR, layout analysis and semantic document understanding.
- Full PDF 2.0, linearization and incremental-update semantics.
- Bit-exact pixel parity with MuPDF/PDFium; the target is structural and
  perceptual correctness on a declared corpus.

## Success metrics

| Metric | MVP target | Later target |
| --- | --- | --- |
| Fixture pages rendered end to end | 3/3 | 50+ page corpus |
| Unit tests | 13+ | 100+ |
| Source size | ~2k lines MoonBit | 10k+ |
| Unsupported-feature errors with a typed message | 100% | 100% |
| Visual diff vs reference renderer | not claimed | SSIM ≥ 0.98 on declared subset |
