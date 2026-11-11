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
| `pdf/` | PDF syntax, object model, classic xref, page tree, content operators | `types.mbt`, `parse.mbt`, `document.mbt`, `content.mbt` |
| `render/` | graphics state, path flattening, scanline raster, fallback text, PNG | `geometry.mbt`, `path.mbt`, `canvas.mbt`, `font.mbt`, `render.mbt`, `png.mbt` |
| root | small facade: `page_count`, `render_page_png` | `moonpdf.mbt` |
| `cmd/moonpdf/` | argument parsing and file I/O | `main.mbt` |

The parser and renderer are separate packages on purpose. A future document
indexer, text extractor or accessibility checker should be able to depend on
`pdf/` without linking the rasterizer.

## Data flow

```text
Bytes
  └─ parse_document
       ├─ header / startxref
       ├─ classic xref table
       ├─ indirect objects (numbers, names, strings, arrays, dicts, streams)
       ├─ page tree walk (inherits MediaBox and Resources)
       └─ PdfDocument { pages: [PdfPage { width, height, contents, resources }] }

PdfPage
  └─ parse_content_stream
       └─ [ContentOp { operands, operator }]

ContentOp[]
  └─ interpreter
       ├─ GState stack (CTM, colors, line width, cap)
       ├─ TextState (text matrix, line matrix, font size, spacing)
       ├─ Path builder (m l c v y re h, curves flattened on insert)
       └─ paint (fill / stroke / fill+stroke)

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

The first slice ships a hand-written 3×5 bitmap fallback font. It is not a
substitute for embedded font outlines, but it makes text-bearing fixtures
readable and keeps layout debugging possible without a font engine. The text
path already implements:

- `Tf`, `Tc`, `Tw`, `Tz`, `TL`, `Ts`
- `Td`, `TD`, `Tm`, `T*`
- `Tj`, `TJ`, `'`, `"`
- per-glyph advance in text space, composed with the CTM

The next milestone replaces the fallback with TrueType `glyf` outline extraction
and a glyph cache; the interpreter interface stays the same.

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
