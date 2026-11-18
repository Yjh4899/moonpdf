# Decision log

Short architecture decision records. Each entry states the decision, the
alternatives and the consequence.

## ADR-001: own parser instead of depending on `pdflite`

**Decision.** Implement the PDF syntax layer in `pdf/`.

**Alternatives.** Depend on `moonbitlang/pdflite`; bind to a C parser.

**Why.** The renderer needs a page-oriented view (inherited boxes, content
streams, resource dictionaries) that is different from a document-editing API.
Owning the parser keeps the renderer self-contained, makes error messages
actionable and avoids coupling the project to another package's release cadence.
`pdflite` remains a complementary library; an adapter is possible later.

**Consequence.** More code to maintain, but no hidden dependency and a cleaner
review surface.

## ADR-002: supersampling instead of analytic coverage

**Decision.** Render at 2脳 and box-filter down.

**Alternatives.** Analytic area coverage per pixel; A-buffer.

**Why.** Supersampling gives predictable quality for fills, strokes and glyph
cells with a small amount of code. It also makes the scanline fill independent
of antialiasing, which keeps the first slice testable.

**Consequence.** 4脳 the pixel work at 2脳 supersampling. The parameter is already
in `RenderOptions`; a tiled renderer can change the policy later.

## ADR-003: bitmap fallback font first

**Decision.** Ship a hand-written 3脳5 bitmap font for the first slice.

**Alternatives.** Wait for a TrueType engine; embed a C font library.

**Why.** Text-bearing fixtures need readable output now. The interpreter already
implements the full text-state surface; swapping the glyph provider later does
not change the operator handling. A bitmap font also keeps the first slice free
of font-file parsing risk.

**Consequence.** Glyph shapes are not faithful. The limitation is stated in the
README and the compatibility matrix; outline fonts are M2.

## ADR-004: strict errors, no repair

**Decision.** Malformed structures raise; unsupported operators are skipped.

**Why.** A renderer that silently repairs damaged files is hard to audit. The
project prefers a specific error (`invalid xref entry offset`,
`missing endstream`) over a plausible but wrong image. Unknown content
operators are skipped because the PDF specification defines that behavior for
unknown operators.

**Consequence.** Some real-world damaged files are rejected until an explicit
recovery mode is added.

## ADR-005: PNG through core zlib

**Decision.** Encode PNG in MoonBit and use
`moonbitlang/core/compress/zlib` for the IDAT stream.

**Alternatives.** Write an uncompressed PNG; add an external image library.

**Why.** The core zlib package is already part of the toolchain, so the encoder
stays dependency-free and the output is a standard PNG that any viewer can open.
The chunk writer and CRC32 are small and testable.

**Consequence.** The zlib package is marked experimental; the `moon.pkg` records
the opt-in explicitly.

## ADR-006: no FFI in the rendering path

**Decision.** The library uses only MoonBit code and core packages. The CLI uses
`moonbitlang/x/fs` for file I/O.

**Why.** Portability across native and wasm is a core value of the project, and
FFI would make the rendering path target-specific. It also keeps review and
reproduction simple.

**Consequence.** A future JPEG decoder or font engine must be pure MoonBit or
carefully isolated behind an optional package.

## ADR-007: overlay revisions instead of rewriting a single object table

**Decision.** Parse every xref section in the `/Prev` chain and merge entries
oldest → newest, preserving free-entry deletions.

**Alternatives.** Concatenate all xref tables into one map while parsing; follow
only the newest table.

**Why.** Incremental saves are a normal, legal PDF layout. The newest table may
contain only the changed objects, so following only it loses the page tree and
resources from older revisions. Merging in revision order also makes overwrite
and delete semantics explicit and testable.

**Consequence.** The loader must keep revision order and resolve objects after
the merge; object streams add a second pass for type-2 entries.

## ADR-008: expand Form XObjects at the operation level

**Decision.** Inline Form XObject content into the page operation list with a
`q` / `/Matrix` `cm` / content / `Q` wrapper before interpretation.

**Alternatives.** Recursively call the interpreter with a separate graphics
state; implement a full form execution context.

**Why.** The graphics-state interpreter is already the largest stateful loop.
Expanding forms keeps it flat, makes nested resources explicit, and lets the
existing path/text/paint operators handle form content unchanged.

**Consequence.** `BBox` is synthesized as a rectangular `W` clip; form-level
transparency groups are not applied yet and remain in the compatibility matrix.

## ADR-009: in-tree baseline JPEG instead of a codec dependency

**Decision.** Implement baseline sequential JPEG (`SOF0`/`SOF1`) in
`render/jpeg.mbt`: marker parsing, DQT/DHT/SOF0/SOS, canonical Huffman decode,
dequantize, 8x8 IDCT, 4:2:0/4:2:2 upsampling and YCbCr to RGB.

**Alternatives.** Depend on a third-party JPEG decoder; bind to a C library.

**Why.** Image XObjects are common in real documents, and a JPEG decoder is the
one codec that cannot be avoided for camera/scanner PDFs. A small baseline
decoder keeps the rendering path pure MoonBit and avoids an FFI dependency in
the most performance-sensitive part. Progressive JPEG is rejected with a
diagnostic and stays on the roadmap.

**Consequence.** Baseline JPEG works; progressive JPEG, arithmetic coding and
CMYK/YCCK JPEG remain unsupported and are listed in the compatibility matrix.

## ADR-010: image sampling through the inverse CTM

**Decision.** Map each destination pixel center through the inverse CTM into the
image unit square, then sample the nearest source pixel.

**Alternatives.** Restrict images to axis-aligned rectangles; implement bilinear
sampling first.

**Why.** PDF images are painted into the unit square and can be rotated,
sheared or flipped by the CTM. Inverse mapping handles all of those cases with
one loop and no special-case geometry. Nearest sampling is sufficient for the
first image milestone and is easy to assert in tests.

**Consequence.** Minified images show aliasing; bilinear or area sampling is a
later quality improvement.

## ADR-011: TrueType outlines rendered through the vector rasterizer

**Decision.** Parse embedded `FontFile2` tables, extract `glyf` contours with
`cmap`/`hmtx`, and fill them through the existing path rasterizer.

**Alternatives.** Rasterize glyph bitmaps separately; bind to FreeType.

**Why.** The path rasterizer already handles transformed, antialiased fills, so
glyphs need no second rendering pipeline. Reusing it keeps text and vector art
visually consistent and avoids an FFI dependency. `cmap` 4/12 covers the common
Latin and BMP cases; Type1/CFF can feed the same `Path` interface later.

**Consequence.** Text is resolution-independent and transformed with the text
matrix. Composite TrueType glyphs, Type1 and CID/CJK remain fallback cases.

## ADR-012: CFF Type 2 charstrings feed the same path pipeline

**Decision.** Parse `/FontFile3` Type1C with the CFF INDEX/DICT reader and
interpret Type 2 charstrings into `Path` cubic segments. Non-CID CFF fonts are
resolved through the OpenType `cmap`, as with TrueType.

**Alternatives.** Convert CFF to outlines with an external font tool; add a
FreeType binding; rasterize CFF glyphs separately.

**Why.** CFF is the other common embedded outline format, especially for
OpenType/OTF fonts. Type 2 charstrings are a compact stack language, and their
lines/curves map directly onto the existing path API, so the renderer keeps one
rasterization path for TrueType, CFF and vector art.

**Consequence.** Non-CID CFF fonts render without conversion. CID-keyed CFF,
Type1 (`FontFile`) and standard-14 metrics still fall back to the bitmap font.