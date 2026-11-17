# Compatibility matrix

The matrix is part of the contract. "Implemented" means the declared subset of
the feature works and is tested; "partial" means only the listed portion is
implemented; "next" means it is on the roadmap and currently fails with a
diagnostic or is ignored where the PDF specification permits skipping.

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
| `/Rotate` | next | page rotation is ignored |
| `/CropBox` | next | `MediaBox` is used |
| multiple content streams | yes | concatenated in order |
| content stream filters | yes | decoded before parsing |

## Graphics

| Operator | Status | Notes |
| --- | --- | --- |
| `q`, `Q`, `cm` | yes | full 3×2 matrix |
| `w`, `J`, `j`, `M`, `d` | partial | width and cap; join/miter/dash stored but not applied |
| `m`, `l`, `c`, `v`, `y`, `re`, `h` | yes | curves flattened at 16 segments |
| `S`, `s`, `f`, `F`, `f*`, `B`, `B*`, `b`, `b*`, `n` | yes | nonzero and even-odd |
| `W`, `W*` (clip) | next | ignored |
| `g`, `G`, `rg`, `RG`, `k`, `K` | yes | gray, RGB, CMYK → RGB |
| `cs`, `CS`, `sc`, `scn`, `SC`, `SCN` | partial | 1/3/4 numeric components; named spaces ignored |
| `Do` (Form XObject) | yes | content expanded with `/Matrix` and nested resources; `BBox` clipping next |
| `Do` (Image XObject) | next | images and inline images are skipped |
| `sh` (shading) | next | skipped |
| `BI ... ID ... EI` | next | inline images are not parsed |
| transparency / blend groups | next | always opaque |

## Text

| Operator | Status | Notes |
| --- | --- | --- |
| `BT`, `ET` | yes | resets text state |
| `Tf` | partial | size is used; font resource is not loaded |
| `Tc`, `Tw`, `Tz`, `TL`, `Ts` | yes | text state |
| `Td`, `TD`, `Tm`, `T*` | yes | text and line matrices |
| `Tj`, `TJ`, `'`, `"` | yes | fallback bitmap glyphs |
| embedded Type1 / TrueType / CFF | next | milestone M2 |
| standard 14 font metrics | next | fallback fixed advance currently |
| CID / CJK fonts | next | milestone M2 |
| vertical writing mode | next | ignored |

## Output

| Feature | Status |
| --- | --- |
| 8-bit RGB PNG | yes |
| arbitrary scale / DPI | yes |
| 2× supersampling | yes, fixed |
| grayscale / alpha PNG | next |
| SVG | next |

## Failure behavior

- Structural errors raise `PdfError` / `MoonPdfError` with the byte offset or a
  specific missing token.
- Unsupported document structures (encryption, unsupported filters) raise.
- Unknown content operators are skipped, matching the PDF convention. A
  diagnostic counter for skipped operators is planned with the corpus report.
- The CLI prints the error and does not write a partial PNG.
