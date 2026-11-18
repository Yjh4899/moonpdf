# Architecture

## Goals

MoonPDF turns PDF bytes into an RGB raster. It is a rendering engine, not a PDF
editor: it reads documents, it does not write them.

The architecture optimizes for four properties:

1. **Auditable layers.** A byte-level parser, a content-stream interpreter, a
   rasterizer and an encoder can each be tested in isolation.
2. **No hidden runtime.** No FFI, no JavaScript VM, no subprocess. The only
   dependencies are MoonBit core packages and `moonbitlang/x/fs` in the CLI.
3. **Deterministic output.** The same bytes and scale produce the same PNG.
4. **Honest boundaries.** Unsupported features fail with a typed error and are
   listed in the compatibility matrix, instead of producing a plausible but
   wrong image.

## Package map

| Package | Responsibility | Key files |
| --- | --- | --- |
| `pdf/` | syntax, object model, xref chain, filters, page tree, content operators | `types.mbt`, `parse.mbt`, `document.mbt`, `content.mbt`, `filter.mbt` |
| `render/` | graphics state, paths, scanline raster, text/fonts, forms, images, PNG | `geometry.mbt`, `path.mbt`, `canvas.mbt`, `font.mbt`, `pdf_font.mbt`, `truetype.mbt`, `cff.mbt`, `image.mbt`, `jpeg.mbt`, `render.mbt`, `png.mbt` |
| root | small facade: `page_count`, `render_page_png` | `moonpdf.mbt` |
| `cmd/moonpdf/` | argument parsing and file I/O | `main.mbt` |
| `tests/integration/` | end-to-end fixtures: incremental update, xref stream, pixel probes | `lib.mbt`, `integration_test.mbt` |

The parser and renderer are separate packages on purpose. A future document
indexer, text extractor or accessibility checker should be able to depend on
`pdf/` without linking the rasterizer.

## Data flow

```text
Bytes
  └─ parse_document
       ├─ header / last startxref
       ├─ xref chain: classic table or xref stream, linked by /Prev
       ├─ hybrid /XRefStm supplement
       ├─ revision overlay (oldest -> newest; free entries delete objects)
       ├─ objects at byte offsets + objects inside /ObjStm streams
       ├─ stream filters: Flate, ASCIIHex, ASCII85, RunLength, LZW + predictors
       ├─ page tree walk (inherits MediaBox and Resources)
       └─ PdfDocument { pages: [PdfPage { width, height, contents, resources, objects }] }

PdfPage
  ├─ contents: decoded content streams
  └─ parse_content_stream
       └─ [ContentOp { operands, operator }]

ContentOp[]
  ├─ expand_forms: inline Form XObjects with /Matrix and nested resources
  └─ interpreter
       ├─ GState stack (CTM, colors, line width, cap)
       ├─ TextState (text matrix, line matrix, font size, spacing)
       ├─ Path builder (m l c v y re h, curves flattened on insert)
       ├─ paint (fill / stroke / fill+stroke)
       └─ Do: Form expansion, image XObject, inline image

Canvas
  ├─ supersampled scanline fill (nonzero or even-odd)
  ├─ stroke as quads + round joins
  └─ box-filter downsample

RenderedPage
  └─ encode_png
       ├─ IHDR / IDAT / IEND
       ├─ zlib stream from moonbitlang/core/compress/zlib
       └─ CRC32 over chunk type + data
```

## Cross-reference chain and revisions

The document loader follows the same structure as a conforming reader:

1. Read the last `startxref` offset.
2. Parse that section. It may be a classic `xref` table or an xref stream with
   `/W` and `/Index`.
3. Follow `/Prev` to older sections. A hybrid classic section may also carry
   `/XRefStm`, whose entries supplement the table; classic entries win.
4. Merge entries **oldest → newest**. A later entry for the same object number
   replaces the older one; a free entry removes the object.
5. Load type-1 objects at their offsets, then type-2 objects from `/ObjStm`
   containers. Object streams must not be nested.
6. Take `/Root` from the newest trailer that provides it.

The parser never concatenates revisions into a fake single table: it keeps the
revision order so overwrite and deletion semantics stay explicit. See
[`incremental-updates.md`](incremental-updates.md) for the fixture.

## Form XObjects

A `Do` operator can reference a Form XObject. The renderer expands the form's
content stream into the current operation list with `q`, the form `/Matrix`, the
expanded content, and `Q`. Nested forms use their own `/Resources` dictionary;
plain Form XObject resources inherit from the parent when absent. `BBox`
clipping is the remaining gap and is tracked in the compatibility matrix.


## Coordinates

PDF user space has its origin at the bottom-left and y pointing up. The screen
canvas has its origin at the top-left and y pointing down. The base matrix is:

```text
a = scale * supersample
d = -scale * supersample
f = page.height * scale * supersample
```

Every path point is transformed by the current transformation matrix (CTM) when
it is added to the path. This keeps the rasterizer in device space and makes
clipping and stroke width straightforward. Text is handled differently: the
text matrix and the CTM are composed per show-text operation, so glyph cells can
be transformed as small quadrilaterals.

## Rasterizer

The rasterizer is deliberately small and predictable:

- **Fill:** scanline intersections at `y + 0.5`, sorted by x; even-odd pairs or
  nonzero winding accumulation.
- **Curves:** cubic Béziers are flattened into 16 line segments at insert time.
  The tolerance is fixed for the first slice and will become adaptive.
- **Stroke:** one quad per segment plus round joins/caps. This is an
  approximation; miter and bevel joins are planned.
- **Antialiasing:** render at `supersample × scale` and box-filter down. The
  first slice uses 2× supersampling, which is a good quality/cost trade-off.
- **Color:** RGB, gray and CMYK are converted to 8-bit RGB at state-change time.

The canvas is a flat `Array[Byte]` with three bytes per pixel. No per-pixel
objects, no hidden allocation in the inner loop.

## Text

`Tf` resolves a `/Font` resource into a `PdfFont`. When the descriptor contains
a `/FontFile2`, the loader parses the TrueType tables (`cmap` formats 4/12,
`hmtx`, `loca`, simple and composite `glyf`) and the renderer fills the glyph
contours through the same path rasterizer used for vector art. A `/FontFile3`
Type1C stream goes through the CFF reader (INDEX/DICT and Type 2 charstrings)
and joins the same path pipeline. CID-keyed CFF additionally resolves the
charset (CID to GID), `FDArray`/`FDSelect`, and per-FD local Subrs. A `/FontFile`
Type 1 program goes through the PFB/PFA eexec and charstring decryptors, then the
Type 1 operator interpreter, including `seac` base/accent composition.
A Type0 font resolves its `DescendantFonts` CIDFontType2 dictionary, decodes
two-byte Identity-H codes, maps CIDs through `/CIDToGIDMap`, and reads advances
from `/W`/`/DW`. Per-code advances for simple fonts come from the PDF `/Widths`
array, with `hmtx` used as a fallback when `/Widths` is absent.

The text path implements:

- `Tf`, `Tc`, `Tw`, `Tz`, `TL`, `Ts`
- `Td`, `TD`, `Tm`, `T*`
- `Tj`, `TJ`, `'`, `"`
- per-glyph advance in text space, composed with the CTM

A hand-written 3×5 bitmap fallback remains for fonts without supported outlines
(Type1, CID without a cmap). Standard-14 Helvetica/Times/Courier fonts use the
Adobe Core 14 AFM widths, with bitmap glyphs scaled to the measured advance.
Type1 and CID/CJK are the remaining M2 work; the interpreter interface does not
change.

## Error model

Parsing raises `pdf.PdfError(String)`; rendering raises
`render.RenderError(String)`. The public facade converts both to
`MoonPdfError(String)` so callers have one error type. Errors carry a short,
specific message (`invalid xref entry offset`, `missing endstream`, ...). Silent
repair is not performed. A future recovery mode will be an explicit, opt-in API.

## Testing

| Layer | Tests |
| --- | --- |
| object parser | numbers, names, strings, arrays, dicts, refs, streams |
| content parser | operators, operands, text arrays |
| matrix / path | composition, rotation, flattening |
| canvas | fill, stroke, downsample |
| PNG | signature, IHDR |
| end-to-end | CLI renders `fixtures/*.pdf` and writes a valid PNG |

The integration step in CI renders every fixture and checks the PNG signature
and the expected pixel dimensions. Differential testing against MuPDF is the
next quality gate; it is listed in the roadmap, not claimed today.

## Why not reuse `pdflite`?

`moonbitlang/pdflite` is a strong PDF object toolkit, but it is oriented toward
reading, writing and manipulating documents. MoonPDF needs a renderer-specific
view of content streams, graphics state and page boxes. Keeping the parser in
this repository lets the renderer evolve without being constrained by a
document-editing API, and it makes the project self-contained for review. The
two projects are complementary; a future adapter could feed `pdflite` pages
into the same renderer.
