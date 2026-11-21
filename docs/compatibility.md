# Compatibility matrix

The matrix records the implementation status of each feature. "Implemented"
means the feature works for the listed cases and is tested; "partial" means only
the listed portion is implemented; "next" means it is on the roadmap and
currently fails with a diagnostic or is ignored where the PDF specification
permits skipping.

The target is ISO 32000-1:2008 page rendering, not this table. See
[`standard-coverage.md`](standard-coverage.md) for the clause-level target and
the public-corpus acceptance gate.

## Document level

| Feature | Status | Notes |
| --- | --- | --- |
| `%PDF-1.x` header | yes | version is read but not enforced |
| classic xref table | yes | `startxref` + `xref` + `trailer` |
| xref streams (`/Type /XRef`) | yes | `/W`, `/Index`, Flate, predictors 10–15 |
| object streams (`/ObjStm`) | yes | type-2 xref entries, object number/offset pairs |
| hybrid files (`/XRefStm`) | yes | classic entries take precedence over the supplemental stream |
| incremental updates (`/Prev`) | yes | revision overlay; free entries remove objects |
| linearized files | not required | linearization hints are ignored, the xref chain is still read |
| encrypted documents | next | no password handling |
| damaged-file repair | no | strict errors by design |

## Stream filters

| Filter | Status |
| --- | --- |
| FlateDecode | yes |
| ASCIIHexDecode | yes |
| ASCII85Decode | yes |
| RunLengthDecode | yes |
| LZWDecode | yes |
| DCTDecode / JPXDecode (images) | next |
| CCITTFaxDecode / JBIG2Decode (images) | next |

`/DecodeParms` supports TIFF predictor 2 and PNG predictors 10–15 for 8-bit
samples. Image-specific color transforms are part of the image milestone.

## Page tree

| Feature | Status | Notes |
| --- | --- | --- |
| `/Pages` → `/Kids` recursion | yes | arbitrary depth |
| inherited `/MediaBox` | yes | default Letter if absent |
| inherited `/Resources` | yes | page-local overrides parent |
| `/Rotate` | yes | 0/90/180/270; output dimensions swap for 90/270 |
| `/CropBox` | yes | intersected with `MediaBox`; used as the render origin |
| multiple content streams | yes | concatenated in order |
| content stream filters | yes | decoded before parsing |

## Graphics

| Operator | Status | Notes |
| --- | --- | --- |
| `q`, `Q`, `cm` | yes | full 3×2 matrix |
| `w`, `J`, `j`, `M`, `d` | partial | width and cap; join/miter/dash stored but not applied |
| `m`, `l`, `c`, `v`, `y`, `re`, `h` | yes | curves flattened at 16 segments |
| `S`, `s`, `f`, `F`, `f*`, `B`, `B*`, `b`, `b*`, `n` | yes | nonzero and even-odd |
| `W`, `W*` (clip) | yes | per-pixel mask from the path; exact fill-rule clipping |
| `g`, `G`, `rg`, `RG`, `k`, `K` | yes | gray, RGB, CMYK → RGB |
| `cs`, `CS`, `sc`, `scn`, `SC`, `SCN` | partial | 1/3/4 numeric components; named spaces ignored |
| `Do` (Form XObject) | yes | content expanded with `/Matrix`, nested resources and `BBox` clip |
| `Do` (Image XObject) | yes | Flate/RGB/gray/CMYK 8-bit; baseline DCT (JPEG) |
| `sh` (shading) | yes | axial/radial types 2/3 with type 2 exponential functions |
| PatternType 2 (shading pattern) | yes | `scn` pattern fill clipped to the path |
| PatternType 1 (colored tiling pattern) | yes | cell rendered recursively and tiled in pattern space |
| PatternType 1 (uncolored tiling pattern) | yes | stencil tile tinted by the `scn` color |
| `BI ... ID ... EI` | yes | inline dictionary abbreviations, raw/Flate/DCT data |
| transparency: constant alpha (`ca`/`CA` via `gs`) | partial | fill/stroke alpha; groups partial |
| blend modes (`/BM` in ExtGState) | partial | Multiply/Screen/Overlay/Darken/Lighten/Dodge/Burn/HardLight/SoftLight/Difference/Exclusion |
| transparency groups | partial | isolated groups via white/black backdrop extraction; non-isolated/knockout next |
| progressive JPEG (`SOF2`) | next | baseline `SOF0`/`SOF1` only |
| soft mask (`/SMask`) | partial | image `/SMask` alpha; ExtGState soft masks next |
| annotation appearance streams (`/AP /N`) | partial | static forms, `/AS` states, Hidden/NoView flags |
| optional content (`/OC` BDC, `/OCProperties /D`) | partial | page content; form content filtering next |

## Text

| Operator | Status | Notes |
| --- | --- | --- |
| `BT`, `ET` | yes | resets text state |
| `Tf` | partial | size, embedded TrueType and non-CID CFF resources |
| `Tc`, `Tw`, `Tz`, `TL`, `Ts` | yes | text state |
| `Td`, `TD`, `Tm`, `T*` | yes | text and line matrices |
| `Tj`, `TJ`, `'`, `"` | yes | fallback bitmap glyphs |
| embedded TrueType (`FontFile2`) | yes | `glyf` simple and composite outlines, cmap 4/12, hmtx advances |
| embedded CFF (`FontFile3` Type1C, non-CID) | yes | CFF INDEX/DICT and Type 2 charstrings |
| embedded Type1 (`FontFile`) | yes | PFB/PFA eexec, charstring decrypt, Type 1 drawing ops, `seac` accents |
| standard 14 font metrics | yes | AFM widths for Helvetica/Times/Courier; bitmap glyphs |
| standard-14 kerning | yes | ASCII KernPairs from the Core 14 AFMs |
| Type0 / CIDFontType2 (`Identity-H`, `/CIDToGIDMap`) | yes | two-byte codes, `/W` and `/DW` widths |
| CID-keyed CFF (`CIDFontType0`) | yes | CFF charset, FDArray/FDSelect, per-FD subrs |
| embedded Type0 encoding CMap (`begincidrange`/`begincidchar`) | yes | 1/2/4-byte codes; named predefined CMaps are next |
| named predefined CJK CMaps (`UniGB/UCS2`, `UniJIS/UCS2`, `UniKS/UCS2`, `UniCNS/UCS2`) | yes | horizontal and `-V` aliases; vertical layout is next |
| vertical writing mode | next | ignored |

## Output

| Feature | Status |
| --- | --- |
| 8-bit RGB PNG | yes |
| arbitrary scale / DPI | yes |
| 2× supersampling | yes, fixed |
| grayscale / alpha PNG | next |
| SVG | partial | vector paths/images/clips/text outlines; PNG fallback for standard-14 text, shadings, patterns |

## Failure behavior

- Structural errors raise `PdfError` / `MoonPdfError` with the byte offset or a
  specific missing token.
- Unsupported document structures (encryption, unsupported filters) raise.
- Unknown content operators are skipped, matching the PDF convention. A
  diagnostic counter for skipped operators is planned with the corpus report.
- The CLI prints the error and does not write a partial PNG.
