# Standard coverage target

## Target statement

MoonPDF targets **page-rendering conformance with ISO 32000-1:2008 (PDF 1.7)**,
the last ISO-standardized PDF version with broad tooling support. "Rendering"
means the page appearance a conforming viewer produces from a document. It does
not include authoring/editing, JavaScript execution, 3D/portfolio features, or
DRM circumvention.

The target is the rendering-relevant portion of the standard as a whole, not a
private subset. Implementation milestones below are tracked as gaps; an
unfinished feature must fail with a specific diagnostic and stay on the
completion plan. It is not removed from scope to make the current build look
complete.

The public acceptance corpus is:

- the PDF.js test corpus (Apache-2.0), which contains a broad mix of real-world
  producers, filters, fonts and incremental updates;
- selected veraPDF and MuPDF test files where their licenses permit;
- a curated set of documents produced by common office suites and print tools.

## Clause map and target

| ISO 32000-1 clause | Area | Target |
| --- | --- | --- |
| 7.5 | File structure: header, xref table, xref stream, incremental updates, free list, trailer, object streams, stream filters | complete |
| 7.7 | Document structure: catalog, page tree, inherited attributes, resources | complete |
| 7.8 | Content streams and content model | complete |
| 8.2–8.5 | Graphics state, paths, painting, color spaces | complete |
| 8.6–8.9 | Images, Form XObjects, inline images, soft masks | complete |
| 8.10–8.11 | Shadings, patterns | complete |
| 9 | Text: fonts, encodings, text state, rendering modes, Type 1/TrueType/CFF, CID fonts | complete |
| 11 | Transparency and blend modes | complete |
| 12.5 | Annotation appearance streams | complete |
| 12.2 | Optional content groups (visibility) | complete |
| 14 | Metadata, tagged PDF, structure tree | not a rendering requirement |

## Acceptance criteria

1. **No crash, no hang.** Every page in the corpus either renders or raises a
   specific diagnostic within a fixed time budget.
2. **Visual agreement.** On the declared corpus, at least 98% of pages reach
   SSIM ≥ 0.95 against a MuPDF reference render at 144 dpi; the remaining pages
   are listed with the missing feature and a link to the corresponding clause.
3. **Incremental updates.** Every document with a `/Prev` chain renders the
   latest revision; reused objects from older revisions are resolved correctly.
4. **Resource reuse.** An incrementally saved page that reuses an older Form
   XObject, font or content stream produces the same page as a full rewrite of
   that revision.
5. **Diagnostics.** Unsupported filters/structures fail with a typed message;
   unknown content operators follow the PDF rule for unknown operators and are
   counted in the compatibility report.

## Current status (release 0.44.0)

| Area | Current | Gap to target |
| --- | --- | --- |
| classic xref, xref streams, object streams, hybrid `/XRefStm` | implemented | — |
| incremental updates (`/Prev`, free entries, revision overlay) | implemented | — |
| Flate, ASCIIHex, ASCII85, RunLength, LZW filters | implemented | image-specific codecs |
| page tree, inherited `MediaBox`/`Resources`, `/Rotate`, `/CropBox` | implemented | `BBox`/`CropBox` edge cases |
| paths, fill/stroke, RGB/gray/CMYK | implemented | dash/miter details |
| exact path clipping (`W`/`W*`) | implemented | clip stack depth is bounded by memory |
| Form XObjects | implemented (expansion, matrix, nested resources, `BBox` clip) | — |
| images: Flate/gray/RGB/CMYK, baseline DCT, inline images | implemented | progressive DCT, 1/2/4-bit samples |
| image soft masks (`/SMask`) | implemented | ExtGState `/TR` |
| ExtGState soft masks (`/SMask /Luminosity`/`/Alpha`) | implemented | transfer functions |
| embedded TrueType (`FontFile2`), cmap/hmtx/simple+composite glyf outlines | implemented | — |
| standard-14 metrics (Helvetica/Times/Courier AFM widths) | implemented | Symbol/ZapfDingbats |
| standard-14 ASCII kerning (AFM KernPairs) | implemented | — |
| embedded CFF (`FontFile3` Type1C, non-CID) Type 2 charstrings | implemented | — |
| CID-keyed CFF (`CIDFontType0`), charset/FDArray/FDSelect | implemented | — |
| Type0 / CIDFontType2, Identity-H, `/CIDToGIDMap` | implemented | — |
| embedded Type0 encoding CMaps (`begincidrange`/`begincidchar`) | implemented | vertical writing |
| named Adobe CJK CMaps (`UniGB/UCS2`, `UniJIS/UCS2`, `UniKS/UCS2`, `UniCNS/UCS2`) | implemented | vertical layout |
| embedded Type1 (`FontFile`) PFB/PFA charstrings, PFA hex eexec, `seac` | implemented | CID-keyed CFF |
| CID/CJK fonts | not yet | M2 |
| constant alpha via ExtGState `ca`/`CA` | implemented | group alpha |
| isolated transparency groups (Form `/Group`) | implemented | non-isolated/knockout groups |
| blend modes via ExtGState `/BM` | implemented | isolation groups |
| transparency, soft masks, shadings, patterns | partial | M3 |
| axial/radial shadings (`sh`, types 2/3, function type 2) | implemented | stitching/sampled functions |
| shading patterns (`PatternType 2`) | implemented | pattern color spaces |
| colored tiling patterns (`PatternType 1`, PaintType 1) | implemented | — |
| uncolored tiling patterns (`PaintType 2`) | implemented | pattern color spaces |
| annotation appearance streams, optional content | partial | interactive flags, nested form OC |
| SVG output (vector paths/images/clips/text, PNG fallback) | partial | standard-14 text, shadings, patterns |
| optional content groups (`/OC` BDC, `/OCProperties /D`) | implemented | form-level OC filtering |
| static annotation `/AP /N` form rendering | implemented | annotation flags and optional content |
| widget `/AS` appearance states (`/N` dictionary) | implemented | annotation flags |
| annotation Hidden/NoView/Invisible flags (`/F`) | implemented | — |

The gap column is the development plan, not a redefinition of the standard.
Each milestone is accepted against the same corpus and the same SSIM gate.

## Why PDF 1.7 rather than PDF 2.0

PDF 2.0 (ISO 32000-2) adds features that are still rare in the documents users
actually submit for preview or OCR, while dropping some legacy constructs that
remain common. PDF 1.7 is the widest practical rendering target and is the
baseline used by PDF.js, MuPDF and PDFium. PDF 2.0-only constructs will be
handled in a later profile; they do not narrow the PDF 1.7 target.
