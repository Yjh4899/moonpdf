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
matrix. Type1 and CID/CJK remain fallback cases.

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

## ADR-013: standard-14 AFM widths with scaled bitmap glyphs

**Decision.** Embed the Adobe Core 14 AFM advance widths for Helvetica, Times
and Courier at codes 32..126. For a non-embedded standard font, use those widths
and horizontally scale the bitmap fallback glyph to the measured advance.

**Alternatives.** Keep a fixed advance; require an embedded font; ship a
built-in Helvetica clone.

**Why.** Many PDFs use the standard 14 fonts without embedding anything. Their
advances determine line layout, so a fixed 0.8 em advance makes text lines drift.
The AFM width tables are compact, freely redistributable, and give correct
positions without adding an external font.

**Consequence.** Standard-14 text lines now have correct advances. Glyphs remain
the 3×5 fallback and are squeezed for narrow characters; Symbol and ZapfDingbats
are not covered.

## ADR-014: Type0/CIDFontType2 before CID-keyed CFF

**Decision.** Implement Type0 fonts with `/Identity-H`, a CIDFontType2
descendant, two-byte codes, `/W`/`/DW` advances and `/CIDToGIDMap`. Resolve the
CID to a TrueType glyph id and draw it through the existing `glyf` path.

**Alternatives.** Start with CID-keyed CFF; map CJK Unicode through `cmap`;
convert CID fonts to simple fonts in the fixture generator.

**Why.** CIDFontType2 is the common CJK TrueType subset layout and needs no CFF
charset/FDSelect machinery. Handling two-byte codes and CID-to-GID mapping
first also prepares the text engine for CID-keyed CFF, which differs only in how
the glyph outline is obtained.

**Consequence.** Type0/CIDFontType2 documents render without a Unicode `cmap`;
the fixture uses Latin glyphs to exercise the CID path. CID-keyed CFF and CJK
encoding CMaps remain next.

## ADR-015: Type1 PFB/PFA before CID-keyed CFF

**Decision.** Parse `/FontFile` Type 1 programs, decrypt eexec and charstrings,
interpret Type 1 drawing operators, and map simple-font codes to Type 1 glyph
names.

**Alternatives.** Skip Type 1 as legacy; convert Type 1 to CFF at build time;
rely on external tools.

**Why.** Older PDFs still embed Type 1 fonts, and the Type 1 charstring language
is close enough to Type 2 that one more small interpreter completes the simple
font matrix. PFB/PFA parsing is self-contained and does not add a dependency.
`seac` draws the base glyph and places the accent at `(adx - asb, ady)`.

**Consequence.** Type 1 PFB/PFA fonts render with their own outlines. Charstring
encodings other than StandardEncoding (via `/Encoding` Differences) remain open,
along with CID-keyed CFF/CJK.

## ADR-016: CID-keyed CFF reuses the Type 2 interpreter

**Decision.** Extend the CFF reader with CID-keyed structures: Top DICT ROS,
`charset` (CID to GID), `FDArray`/`FDSelect`, and per-FD local Subrs. Keep the
same Type 2 interpreter and select the FD's subrs before running a glyph.

**Alternatives.** Convert CID CFF to a non-CID CFF at build time; use a separate
CJK font library; start with named CJK encoding CMaps.

**Why.** The charstring bytecode is identical between name-keyed and CID-keyed
CFF. The only differences are lookup tables (CID to GID) and which local subrs
apply. Reusing the interpreter keeps CJK CFF rendering on the same path pipeline
and avoids importing a second font stack.

**Consequence.** CID-keyed CFF renders through Identity-H CIDs. Named CJK
encoding CMaps (`UniGB-UCS2-H`, etc.) remain open.

## ADR-017: embedded Type0 CMaps before predefined ones

**Decision.** When `/Encoding` is a stream, parse its codespace and
`begincidrange`/`begincidchar` entries into a code-to-CID table and use the
codespace width to split text bytes.

**Alternatives.** Hardcode `UniGB-UCS2-H`/`UniJIS-UCS2-H` tables first; require
Identity-H; convert embedded CMaps to Identity-H in the fixture.

**Why.** The stream form exercises the same code-width and CID-mapping machinery
that named CMaps need, without importing large Adobe CMap resources. It also
covers documents that embed a custom subset CMap, which is common in generated
PDFs.

**Consequence.** Embedded CMaps of 1/2/4-byte codes work. Named predefined CMaps
are covered by the range tables in ADR-019.

## ADR-018: standard-14 kerning from AFM KernPairs

**Decision.** Extract ASCII KernPairs from the Core 14 AFM files, store them as
code-pair adjustments, and apply the adjustment before drawing the next glyph.

**Alternatives.** Ignore kerning; use a hand-written pair list; parse TrueType
`kern` tables for every embedded font.

**Why.** Standard-14 text is common in generated PDFs and AFM already supplies
authoritative pair values. Restricting to codes 32..126 keeps the table small
while covering the pairs that dominate Latin text. The renderer interface stays
the same: kerning is one more text-space translation.

**Consequence.** Standard-14 Latin text gets correct pair spacing. Embedded
TrueType/CFF kerning and non-ASCII AFM pairs remain out of scope.

## ADR-019: named Adobe CJK CMaps as range tables

**Decision.** Embed the code-to-CID ranges of `UniGB-UCS2-H`,
`UniJIS-UCS2-H`, `UniKS-UCS2-H` and `UniCNS-UCS2-H` (plus their `-V` aliases)
as sorted `(lo, hi, startCid)` tables. Expand them into the same code-to-CID map
used by embedded CMaps.

**Alternatives.** Ship the original CMap files and parse them at runtime; use
`Identity-H` only; convert named CMaps to embedded ones in fixtures.

**Why.** The named CMaps are standard Adobe resources with stable mappings. Their
range form is compact, and the renderer already has the code-to-CID and
CID-to-GID layers. Shipping range tables avoids a runtime file dependency while
keeping the fixture's Adobe-GB1 CIDs honest.

**Consequence.** Named horizontal UCS2 CMaps work without external files.
Vertical writing (`-V`) currently uses horizontal layout; true vertical metrics
are a later item. UTF-8/UTF-16/UTF-32 named CMaps remain out of scope.

## ADR-020: constant alpha in the canvas compositor

**Decision.** Add a canvas alpha value and source-over blending in `Canvas::set`.
`gs` reads `/ca` and `/CA` from the ExtGState and sets fill/stroke alpha on the
graphics state; paint and text apply the corresponding alpha.

**Alternatives.** Render each object to a separate layer and composite; implement
full transparency groups and blend modes first; ignore alpha.

**Why.** Constant alpha is the most common transparency feature in ordinary
PDFs. Source-over blending at the pixel level is small, keeps the scanline
rasterizer unchanged, and gives correct overlap colors for fills, strokes and
text. Groups and blend modes can build on the same compositor later.

**Consequence.** `ca`/`CA` alpha works for vector and text painting. Transparency
groups, non-source-over blend modes and soft masks remain M3 work.

## ADR-021: blend modes over an opaque source-over canvas

**Decision.** Read `/BM` from ExtGState and apply the blend function to the
source color against the current backdrop before alpha compositing. Support the
common separable modes; treat unsupported modes as Normal.

**Alternatives.** Implement isolated transparency groups first; render to layers;
ignore blend modes.

**Why.** Most documents use blend modes on ordinary page content, where the
backdrop is already opaque. Computing `B(Cb, Cs)` per channel and then doing the
existing source-over alpha blend is small and composes with `ca`/`CA`. Group
isolation is a separate problem and can reuse the same functions later.

**Consequence.** Multiply/Screen/Overlay/Darken/Lighten/Dodge/Burn/HardLight/
SoftLight/Difference/Exclusion work on the main canvas. Non-separable modes and
isolated groups remain M3 work.

## ADR-022: exact clipping as a per-pixel mask

**Decision.** On `W`/`W*`, rasterize the current path into a byte mask at the
supersampled canvas resolution and intersect it with the existing clip mask.
`Canvas::set` rejects pixels outside the mask; `q`/`Q` save and restore the mask.

**Alternatives.** Intersect polygons analytically; keep the rectangular bbox
approximation; render clipping through a stencil buffer.

**Why.** A mask reuses the scanline fill logic, handles non-rectangular and
self-intersecting paths, and works for fills, strokes, text and images without
changing each painter. Supersampling gives antialiased clip edges after
downsampling.

**Consequence.** Exact `W`/`W*` clipping works and composes with alpha/blend.
Each clip allocation is `width * height` bytes at supersampled resolution;
deep clip stacks trade memory for simplicity.

## ADR-023: shading as per-pixel inverse mapping

**Decision.** Parse shading types 2 (axial) and 3 (radial) with a type 2
exponential function, then for each device pixel in the clip bbox inverse-map
through the CTM, compute `t`, evaluate C0/C1, and write the pixel.

**Alternatives.** Build a gradient texture and fill the path; rasterize the
shading into a separate canvas and composite; only support axial shadings.

**Why.** The inverse map handles arbitrary CTMs and works for both axial and
radial geometry with one loop. It reuses the existing clip mask and alpha/blend
state, so `sh` respects the same compositing rules as fills. A texture pipeline
can replace it later if profiling demands.

**Consequence.** Axial/radial gradients render. Stitching/sampled functions,
patterns and shading types 4–7 remain M3 work.

## ADR-024: shading patterns reuse the shading painter

**Decision.** Model a `PatternType 2` resource as a shading. On `scn`, set the
fill pattern on the graphics state; on fill, intersect the canvas clip with the
path mask, paint the shading, then restore the previous mask.

**Alternatives.** Build a pattern tile texture; implement tiling patterns first;
convert shading patterns to shading operators in the fixture.

**Why.** A shading pattern is already a shading plus a fill mask. Reusing
`paint_shading` and the exact clip mask avoids a second rendering path and keeps
pattern fills consistent with `sh`. Tiling patterns need cell rendering and
repeat logic, which is a larger separate piece.

**Consequence.** Shading-pattern fills work. Tiling patterns (`PatternType 1`)
fall back to the solid fill color and remain M3 work.

## ADR-025: tiling pattern cells rendered through a synthetic page

**Decision.** Render a `PatternType 1` cell by constructing a synthetic
`PdfPage` from its `/BBox`, content stream and resources, then sampling that
tile in pattern space. Colored patterns (`PaintType 1`) are supported; uncolored
patterns fall back to the solid fill color.

**Alternatives.** Write a separate mini-interpreter for pattern content; raster
the cell into a texture with a bespoke parser; support only shading patterns.

**Why.** Pattern cell content is ordinary PDF content with its own resources.
Reusing `render_page` avoids duplicating the operator interpreter and gives
pattern cells forms, text, images and nested clipping for free. The tile is
small, so the recursive render cost is bounded by the cell BBox.

**Consequence.** Colored tiling patterns repeat correctly under CTM and pattern
matrices. Uncolored patterns and very large cells remain M3 work.

## ADR-026: annotation appearances through a synthetic page

**Decision.** For each annotation with `/AP /N` stream, create a synthetic page
sized to the annotation `/Rect`, prefix the form content with a BBox-to-rect
`cm`, render it, and composite the result after page content.

**Alternatives.** Expand annotations into the page content stream; render
annotation layers directly with the interpreter; ignore annotations.

**Why.** Annotation appearance streams are ordinary form XObjects with their own
resources. The synthetic page reuses the full form/text/image pipeline and keeps
annotation placement (BBox to Rect) explicit. Rendering after content matches the
PDF display order.

**Consequence.** Static widget/stamp appearances render in the right rectangle.
Interactive state dictionaries (`/AP /N` as a state map), annotation flags and
optional content remain M3 work. Nested annotation appearances are capped at
depth 4 to keep recursive appearance rendering bounded.

## ADR-027: widget appearance states via `/AS`

**Decision.** When `/AP /N` is a state dictionary, resolve the stream named by
the annotation `/AS`; if `/AS` is absent, use the first stream in the dictionary.

**Alternatives.** Always use `/On`; render every state stacked; ignore widget
states.

**Why.** `/AS` is the document's declaration of which appearance is active. It
is a small lookup after the static form path and makes checkbox/radio widgets
render in the state the PDF says they are in.

**Consequence.** `/On`/`/Off` and custom state names work. Annotation flags and
appearance-stream `/AP /R`/`/D` variants remain M3 work.

## ADR-028: optional content filtered before interpretation

**Decision.** Resolve the page's hidden OCG object numbers from catalog
`/OCProperties /D` (`/BaseState`, `/ON`, `/OFF`) and remove operations inside
hidden `/OC` BDC/EMC sections before form expansion and interpretation.

**Alternatives.** Skip painters at execution time with a visibility stack;
support only `/BaseState`; ignore optional content.

**Why.** Optional content is a document presentation choice, not a different
drawing model. Filtering the operation list is simple, keeps the interpreter
unaware of OCG bookkeeping, and naturally supports nested marked-content
sections. The page model carries the hidden set so every content stream uses the
same decision.

**Consequence.** Hidden layers are omitted from rendered output. Optional content
inside Form XObjects, `/OCProperties` usage dictionaries and per-page
configuration overrides remain next.

## ADR-029: honor annotation visibility flags

**Decision.** Before rendering an annotation, read `/F` and skip when the
Invisible (1), Hidden (2) or NoView (32) bits are set.

**Alternatives.** Render every annotation; only honor Hidden; rely on `/AP`
presence.

**Why.** Visibility flags are explicit document instructions, and rendering a
Hidden annotation would be visibly wrong. The bit check is cheap, happens before
appearance rendering, and matches the flag semantics used by PDF viewers.

**Consequence.** Hidden/NoView annotations are omitted. Print-only semantics and
annotation appearances on the `/AP /R`/`/D` paths remain out of scope.

## ADR-030: uncolored patterns as tinted stencils

**Decision.** Render a `PaintType 2` tiling cell once with the default black
fill, keep it as a stencil, and at paint time tint non-white tile pixels with the
color components preceding the pattern name in `scn`.

**Alternatives.** Re-render the cell for every fill color; require pattern
content to declare its own color; skip uncolored patterns.

**Why.** Uncolored pattern content is a stencil by definition. The rendered black
tile is a usable coverage mask, and tinting needs no per-fill recursive render.
Opacity from antialiased tile edges is preserved as alpha.

**Consequence.** Uncolored tiling patterns work with RGB/solid fill colors.
Pattern color spaces and per-fill caching remain refinements.

## ADR-031: image soft masks as an alpha plane

**Decision.** Decode an image XObject's `/SMask` stream as 8-bit gray, resample
it to the image dimensions, and apply it per sample via the canvas alpha.

**Alternatives.** Ignore `/SMask`; pre-composite the mask into RGBA image data;
support only `/Mask` color-key transparency.

**Why.** `/SMask` carries the alpha plane separately from color. Storing it as
an alpha array keeps image decoding and color conversion unchanged, and applying
it at draw time composes with the existing `ca`/`CM` alpha and blend modes.

**Consequence.** Image soft masks render with correct fade/transparency. ExtGState
soft masks and `/Matte` color correction remain next.

## ADR-032: SVG container with embedded PNG first

**Decision.** `encode_svg` writes a self-contained SVG whose `<image>` element
references a base64 PNG of the rendered page. Add a `--svg` CLI switch.

**Alternatives.** Wait for a full vector exporter; emit SVG paths directly in the
rasterizer; omit SVG until M4.

**Why.** A self-contained SVG is useful immediately: it has exact page
dimensions, scales in SVG viewers, and preserves every feature the rasterizer
already supports. A vector exporter needs a second drawing backend and can be
added without changing the public CLI or facade.

**Consequence.** SVG output is currently a raster container, not vector paths.
This is documented as partial; vector export remains M3 work.

## ADR-033: vector SVG for path-only pages, raster fallback otherwise

**Decision.** Add a second SVG exporter that re-interprets page content into SVG
`<path>` elements for pages made of paths. Unsupported features (text, images,
shadings, patterns, clips) make it return `None`; the caller then uses the
embedded-PNG SVG container.

**Alternatives.** Replace the raster container immediately; emit SVG only for
the full feature set; keep raster-only SVG.

**Why.** Path-only pages are common for diagrams and get real vector output
without a full second drawing backend. The fallback keeps every other page
rendering correctly and makes the transition incremental.

**Consequence.** Path-only pages export crisp SVG paths. Text, images, clips and
transparency still fall back to PNG; vector text/images are next.

## ADR-034: vector SVG images as embedded PNG

**Decision.** When the vector exporter reaches an image XObject, decode the
image to RGB, encode it as PNG, embed it as a base64 `<image>`, and map the PDF
unit square through the current CTM with a y-flip.

**Alternatives.** Fall back to the page raster whenever an image appears; emit
raw image samples; support only JPEG.

**Why.** An image is already a self-contained raster inside a vector page, so
embedding it preserves vector paths around it without making the whole page a
raster. The y-flip maps PDF image rows (top row at `y = 1`) to SVG's top-down
image coordinates.

**Consequence.** Path+image pages export vector SVGs. Images with soft masks and
vector text still use the raster fallback.