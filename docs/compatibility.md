# Compatibility matrix

The matrix is part of the contract. "Partial" means the feature is implemented
for the declared subset; "not yet" means the renderer will either ignore the
operator or fail, and the behavior is documented here.

## Document level

| Feature | Status | Notes |
| --- | --- | --- |
| `%PDF-1.x` header | yes | version is read but not enforced |
| classic xref table | yes | `startxref` + `xref` + `trailer` |
| xref streams | not yet | raises `xref streams are not supported yet` |
| object streams | not yet | indirect objects must be at their xref offsets |
| incremental updates (`/Prev`) | not yet | only the latest table is read |
| encrypted documents | not yet | no password handling |
| damaged-file repair | no | strict errors by design |

## Page tree

| Feature | Status | Notes |
| --- | --- | --- |
| `/Pages` → `/Kids` recursion | yes | arbitrary depth |
| inherited `/MediaBox` | yes | default Letter if absent |
| inherited `/Resources` | yes | page-local overrides parent |
| `/Rotate` | not yet | page rotation is ignored |
| `/CropBox` | not yet | `MediaBox` is used |
| multiple content streams | yes | concatenated with a newline |

## Graphics

| Operator | Status | Notes |
| --- | --- | --- |
| `q`, `Q`, `cm` | yes | full 3×2 matrix |
| `w`, `J`, `j`, `M`, `d` | partial | width and cap; join/miter/dash stored but not applied |
| `m`, `l`, `c`, `v`, `y`, `re`, `h` | yes | curves flattened at 16 segments |
| `S`, `s`, `f`, `F`, `f*`, `B`, `B*`, `b`, `b*`, `n` | yes | nonzero and even-odd |
| `W`, `W*` (clip) | not yet | ignored |
| `g`, `G`, `rg`, `RG`, `k`, `K` | yes | gray, RGB, CMYK → RGB |
| `cs`, `CS`, `sc`, `scn`, `SC`, `SCN` | partial | 1/3/4 numeric components; named spaces ignored |
| `Do` (XObject) | not yet | images and forms are skipped |
| `sh` (shading) | not yet | skipped |
| `BI ... ID ... EI` | not yet | inline images are not parsed |
| transparency / blend groups | not yet | always opaque |

## Text

| Operator | Status | Notes |
| --- | --- | --- |
| `BT`, `ET` | yes | resets text state |
| `Tf` | partial | size is used; font resource is not loaded |
| `Tc`, `Tw`, `Tz`, `TL`, `Ts` | yes | text state |
| `Td`, `TD`, `Tm`, `T*` | yes | text and line matrices |
| `Tj`, `TJ`, `'`, `"` | yes | fallback bitmap glyphs |
| embedded TrueType / CFF | not yet | planned next |
| standard 14 font metrics | not yet | fixed advance currently |
| vertical writing mode | not yet | ignored |

## Output

| Feature | Status |
| --- | --- |
| 8-bit RGB PNG | yes |
| arbitrary scale / DPI | yes |
| 2× supersampling | yes, fixed |
| grayscale / alpha PNG | not yet |
| SVG | not yet |

## Failure behavior

- Structural errors raise `PdfError` / `MoonPdfError` with the byte offset or a
  specific missing token.
- Unsupported operators are ignored, matching the PDF convention that unknown
  operators are skipped. Unsupported *document structures* (xref streams,
  encryption) raise instead of guessing.
- The CLI prints the error and does not write a partial PNG.
