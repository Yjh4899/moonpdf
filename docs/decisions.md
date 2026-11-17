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

**Consequence.** `BBox` clipping and form-level transparency groups are not
applied yet; both are tracked in the compatibility matrix.