# MoonPDF

[![CI](https://github.com/Yjh4899/moonpdf/actions/workflows/ci.yml/badge.svg)](https://github.com/Yjh4899/moonpdf/actions/workflows/ci.yml)
[![mooncakes](https://img.shields.io/badge/mooncakes-Yjh4899%2Fmoonpdf-blue)](https://mooncakes.io/docs/Yjh4899/moonpdf)

[简体中文](README.zh.md)

**A pure-MoonBit PDF page rendering engine.** Parse a PDF, interpret its content
stream, rasterize the page, and write a PNG without a JavaScript VM, a C
library, or a browser.

Published as [`Yjh4899/moonpdf@0.6.0`](https://mooncakes.io/docs/Yjh4899/moonpdf)
on mooncakes.io.

## Why this exists

MoonBit already has PDF document tooling: `moonbitlang/pdflite` reads, writes and
manipulates PDF objects, `moonbitlang/pagelayout` generates pages, and the
official office viewer renders PDF previews by shipping PDF.js into the browser.

What the ecosystem does not have is the last mile: a native page rasterizer. Any
MoonBit application that needs a thumbnail, a page image for OCR or a visual
regression check currently has to embed a JavaScript engine or call out to an
external binary. MoonPDF closes that gap with a small, inspectable, multi-target
rendering core.

## Status

This repository is at the **images and page-geometry milestone**. It renders
real pages end to end, including incrementally saved files:

| Area | Current support |
| --- | --- |
| File structure | classic xref, xref streams, object streams, hybrid `/XRefStm`, incremental updates (`/Prev`) |
| Filters | Flate, ASCIIHex, ASCII85, RunLength, LZW; TIFF/PNG predictors |
| Page tree | inherited `MediaBox` / `Resources`, `/Rotate`, `/CropBox`, multiple pages |
| Content | `q/Q/cm`, paths (`m l c v y re h`), fill/stroke, RGB/gray/CMYK, line width/cap |
| Clip | rectangular `W` / `W*`, Form `BBox` |
| Forms | Form XObjects with `/Matrix`, nested resources and `BBox` clip |
| Images | 8-bit gray/RGB/CMYK, Flate and baseline JPEG, inline images |
| Text | text state, `Td/TD/Tm/T*`, `Tj/TJ/'/"`, embedded TrueType (simple/composite) and CFF outlines, bitmap fallback |
| Output | RGB PNG with zlib compression |

The target is ISO 32000-1:2008 page rendering. See
[`docs/standard-coverage.md`](docs/standard-coverage.md) for the clause-level
target and corpus gate, and [`docs/incremental-updates.md`](docs/incremental-updates.md)
for the `/Prev` algorithm and the reused-resource fixture.

Still missing, and tracked as milestones: Type1 fonts, standard-14 metrics,
CID/CJK, progressive JPEG and soft masks, transparency, shadings and annotation
appearance streams. See [`docs/compatibility.md`](docs/compatibility.md).

![MoonPDF rendering a fixture](docs/images/demo.png)

An incremental revision reusing the old Form XObject header and the old
font/resources, with a newly appended body stream:

![Incremental update: reused header, new body](docs/images/incremental.png)

A baseline JPEG image XObject with 4:2:0 chroma subsampling, decoded by the
in-tree JPEG decoder:

![JPEG image XObject](docs/images/image-jpeg.png)

Embedded OpenSans (OFL) rendered from `FontFile2` `glyf` outlines and `hmtx`
advances:

![Embedded TrueType font](docs/images/font-embedded.png)

Embedded Source Sans 3 (OFL) rendered from CFF Type 2 charstrings:

![Embedded CFF font](docs/images/font-cff.png)

## Quick start

Requirements: the MoonBit toolchain (`moon 0.1.20261102` or newer). Node.js is
not required.

```sh
moon check
moon test
moon run cmd/moonpdf -- fixtures/shapes.pdf out.png --scale 2
```

The default target is `wasm-gc`, so the CLI runs on any machine with the MoonBit
toolchain. Add `--target native` for maximum throughput; on Windows the native
backend requires MSVC Build Tools.

The CLI:

```text
moonpdf <input.pdf> [output.png] [--page N] [--scale S]
```

`--scale 1.0` means 72 dpi; `--scale 2` produces a 144 dpi image.

## Architecture

```text
bytes
  |
  +-- pdf/        lexer, object parser, xref chain, filters, page tree
  |
  +-- render/     content interpreter, graphics state, forms, text, images
  |    +-- path    Bezier flattening
  |    +-- canvas  supersampled scanline fill / stroke
  |    +-- font    3x5 fallback glyphs
  |    +-- image   image XObject sampling, baseline JPEG
  |    +-- png     zlib + PNG chunks + CRC32
  |
  +-- cmd/moonpdf CLI
```

The parser and renderer are separate packages so that document inspection tools
can use the object model without pulling in the rasterizer. The public facade is
`Yjh4899/moonpdf`; `page_count` and `render_page_png` are the stable entry points.

Design rules:

1. **Fail loudly.** Malformed input raises a typed error instead of being
   silently repaired. Recovery policies, when added, will be explicit APIs.
2. **No hidden runtime.** No FFI, no JS VM, no external process.
3. **Small, testable layers.** Every layer has unit tests and a narrow public
   surface.
4. **Measure the unsupported surface.** The compatibility matrix is part of the
   product, not an afterthought.

## Testing

```sh
moon test                 # 28 unit and integration tests
moon run cmd/moonpdf -- fixtures/text.pdf out/text.png --scale 2
```

CI runs `moon fmt --check`, `moon check --deny-warn`, `moon test`, renders all
fixtures and checks PNG dimensions and sampled pixels.

The fixtures are generated by scripts under [`tools/`](tools) and committed so
that CI can reproduce every render.

## Roadmap

| Milestone | Goal |
| --- | --- |
| M0 (delivered) | file structure, filters, incremental updates, vector graphics |
| M1 (delivered) | images, inline images, Rotate/CropBox, rectangular clipping |
| M2 (current) | embedded TrueType/CFF delivered; Type1, CID/CJK, text metrics |
| M3 | transparency, shadings, annotation appearance, SVG |
| M4 | corpus SSIM vs MuPDF, performance pass, wasm demo |

The full plan, scope boundaries and acceptance criteria are in
[`docs/scope.md`](docs/scope.md) and [`docs/roadmap.md`](docs/roadmap.md).

## References and license

- PDF 32000-1:2008, *Document management: Portable Document Format*.
- Behavioral reference implementations: MuPDF, PDFium and Poppler. No source
  code from those projects is copied; MoonPDF is implemented from the
  specification and from black-box output comparisons.
- `moonbitlang/pdflite` and `moonbitlang/office` are complementary MoonBit
  projects; MoonPDF does not vendor or re-export their code.

MoonPDF is licensed under the Apache License 2.0. See [LICENSE](LICENSE).

## AI-assisted development

AI tools are used for scaffolding, test generation and review. Architecture,
scope decisions and correctness checks remain explicit and reviewable. The
development log and the reasoning behind key trade-offs are recorded in
[`docs/decisions.md`](docs/decisions.md).
