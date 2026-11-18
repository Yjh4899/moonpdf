# Scope and acceptance

## Problem

MoonBit can parse and generate PDFs, but it cannot turn a PDF page into pixels.
The official office viewer proves the gap: its PDF preview delegates to PDF.js
in the browser. Any native MoonBit tool that needs a thumbnail, a page image for
OCR, or a visual regression check must embed a JavaScript VM or shell out to an
external renderer.

## Final standard coverage

The completion target is **ISO 32000-1:2008 (PDF 1.7) page rendering**. The
target is the rendering-relevant portion of the standard as a whole, not a
private subset; current gaps are tracked as milestone work, not as scope
exclusions. See [`standard-coverage.md`](standard-coverage.md) for the clause
map, the public corpus and the SSIM/no-crash acceptance gate.

Incremental updates (`/Prev` chains, xref streams, object streams, hybrid
`/XRefStm`) are explicitly **in scope** and are implemented in this release.
The concrete reuse fixture is documented in
[`incremental-updates.md`](incremental-updates.md).

## Three concrete scenarios

1. **Document service.** A MoonBit backend receives an uploaded PDF and returns
   a first-page PNG for an approval queue. Today the service needs Node/PDF.js
   or a system `pdftoppm`; MoonPDF makes the conversion a library call.
2. **AI / agent document pipeline.** A multimodal model or OCR step needs page
   images, not raw PDF bytes. MoonPDF exposes page rasterization as a
   deterministic native function that can run in a service, a CLI or a wasm
   module without a browser.
3. **Desktop / IDE preview and CI.** A MoonBit-native document tool wants an
   embedded page preview; a document generator renders its own output and
   compares page hashes in CI, catching layout regressions without a JavaScript
   toolchain.

## Delivered in release 0.7.0

- classic xref tables, xref streams, object streams and hybrid `/XRefStm`;
- incremental updates: `/Prev` chain, revision overlay, free entries;
- FlateDecode, ASCIIHexDecode, ASCII85Decode, RunLengthDecode, LZWDecode;
- page tree with inherited `MediaBox` and `Resources`;
- content operators for graphics state, paths, fill/stroke, color and text;
- Form XObjects (matrix, nested resources, recursive expansion, BBox clip);
- image XObjects: 8-bit gray/RGB/CMYK, Flate and baseline JPEG; inline images;
- embedded TrueType (`FontFile2`): cmap 4/12, hmtx advances, simple/composite `glyf` outlines;
- embedded CFF (`FontFile3` Type1C, non-CID): CFF INDEX/DICT, Type 2 charstrings;
- standard-14 Helvetica/Times/Courier metrics from the Adobe Core 14 AFMs;
- `/Rotate` 0/90/180/270, `/CropBox`, rectangular `W`/`W*` clip;
- fill rules, line width and round caps;
- 3×5 fallback text with `Tj` / `TJ` and text positioning;
- RGB PNG output;
- CLI with page selection and scale;
- unit and integration tests, fixtures and CI;
- explicit compatibility matrix, standard-coverage target and error messages.

## Acceptance criteria for the current milestone

1. `moon check --deny-warn` and `moon test` pass on a clean checkout.
2. `moon run cmd/moonpdf -- fixtures/demo.pdf out.png --scale 2` writes a valid
   PNG with the expected dimensions.
3. Vector fixtures render with the expected colors and geometry.
4. The incremental fixture follows `/Prev`, reuses the old Form XObject and
   renders both the blue header and the new green body.
5. The xref-stream fixture renders through an object stream and a
   Flate-compressed content stream.
6. Unsupported PDF structures fail with a specific error, never with a silently
   wrong image.
7. CI runs formatting, checking, tests, all fixture renders and pixel checks.

## Out of scope

- PDF authoring, editing, form filling, signing and encryption removal.
- JavaScript execution, 3D annotations, portfolios and embedded files.
- OCR, layout analysis and semantic document understanding.
- Bit-exact pixel parity with a specific renderer; the target is the
  clause-level coverage plus the corpus SSIM gate.

## Success metrics

| Metric | Current | Target |
| --- | --- | --- |
| Fixture pages rendered end to end | 14/14 | public corpus |
| Unit + integration tests | 29 | 100+ |
| Unsupported-feature errors with a typed message | 100% | 100% |
| Incremental-update fixtures | 1 | every `/Prev` document in corpus |
| Visual diff vs reference renderer | pixel probes on fixtures | SSIM ≥ 0.95 on 98% of corpus |
