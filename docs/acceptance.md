# Acceptance audit — MoonPDF 0.43.1

This is the release checklist for the 0.43.1 acceptance pass. It records what was
verified, on which environment, and what remains a known gap.

## Release identity

- GitHub repository: `Yjh4899/moonpdf`
- mooncakes package: `Yjh4899/moonpdf`
- Version: `0.43.1`
- License: Apache-2.0; bundled OpenSans subset is SIL OFL 1.1.
- Readme: `README.md` (English), `README.zh.md` (Chinese), `README.mbt.md`
  (package-facing summary).

## Environment

- MoonBit: `moon 0.1.20261117`
- Default target: `wasm-gc`; CI additionally runs `moon test --target native`
- Local release check: Windows 11, PowerShell, Python tooling in `tools/`
- Reference renderer for differential checks: PyMuPDF

## Verification matrix

| Check | Command | Result |
| --- | --- | --- |
| Interface freshness | `moon info` | no stale `.mbti` |
| Formatting | `moon fmt` | clean |
| Warnings as errors | `moon check --deny-warn` | pass |
| Unit/integration tests | `moon test` | **61 passed, 0 failed** |
| Committed fixture corpus | `python tools/corpus_check.py --pdf-dir fixtures ...` | **39 render, 34 within tolerance, 0 fail** |
| Real public corpus | `python tools/corpus_check.py --pdf-dir corpus ...` | **13 render, 5 within tolerance, 0 fail, 0 timeout** |
| Malformed PDFs | `python tools/fuzz_pdf.py` | **120 cases, 0 crashes, 0 timeouts** |
| CLI smoke | `moon run cmd/moonpdf -- fixtures/text.pdf out/text.png` | PNG produced |
| Multi-page CLI | `--all` / `--pages` | covered by CI |
| SVG output | `--svg` | raster container fallback verified |

## Real-document corpus

13 public PDFs: arXiv papers (attention, BERT, GPT-4, ResNet, tracemonkey),
IRS 1040/W-9, and PDF.js transparency/blend/vertical samples.

- All 13 render without crash or timeout.
- Five pass the 0.90 pixel-closeness tolerance: alphatrans, annotation link,
  attention, dummy, vertical.
- Eight are tracked fidelity gaps, dominated by reference-renderer font
  hinting and CFF subset details. The largest known offsets are IRS 1040/W-9
  (about 82%), clip (about 85%), BERT (about 86%), ResNet (about 86%),
  tracemonkey (about 86%), blendmode (about 87%), and GPT-4 (about 88%).
- Full per-file MAE and timing: [`corpus-report-real.md`](corpus-report-real.md).

## Fixture corpus

39 committed PDFs cover xref/object streams, incremental updates, filters,
fonts, images, clipping, shadings, patterns, transparency, annotations,
optional content and text state.

- 39 render, 34 within tolerance, 0 fail.
- The five differences are documented reference edge cases plus the deliberate
  standard-14 OpenSans fallback tradeoff (ADR-054).
- Full table: [`corpus-report.md`](corpus-report.md).

## Robustness

- 120 malformed variants: 19 rendered, 101 controlled errors, 0 crashes,
  0 timeouts.
- Dedicated semantic cases include page-tree cycles, huge page dimensions,
  zero-offset xref entries, truncated streams and recursive forms.
- Details: [`fuzz-report.md`](fuzz-report.md).

## Performance

Latest recorded baseline (Windows, wall clock including `moon run` startup):
mean real-corpus render about **1.14 s/page** at scale 1.0; committed fixtures
about **0.27 s/page**. These numbers include CLI startup and are deliberately
conservative; the library path is faster.

## Public API and CLI

- Library facade: `MoonPdfDocument::open`, `page_count`, `render_png`,
  `render_svg`, `render_pages_png`, `render_pages_svg`.
- Low-level API: `parse_document`, `render_page`, `encode_png`,
  `encode_svg_vector`.
- CLI: single page, `--all`, `--pages 1,3-5`, `--out-dir`, `--scale`,
  `--svg`.
- PNG is the portable raster output; SVG is vector for path/embedded-font pages
  and a raster container otherwise.

## Known gaps

1. Exact reference font hinting is not reproduced; text-heavy real PDFs plateau
   around 85–90% pixel closeness.
2. IRS form CFF subsets still show font-face differences at title size.
3. Some reference blend/image color details remain below the 0.90 threshold.
4. Encrypted PDFs, linearization and full ICC color management are out of
   scope for this release.
5. wasm browser demo is not part of 0.43.1; the core is wasm-gc compatible.

## Release checklist

- [x] Version and readmes updated
- [x] Changelog/decisions updated
- [x] `moon info` / `moon fmt`
- [x] `moon check --deny-warn`
- [x] `moon test` (61)
- [x] Real corpus re-run after final changes
- [x] Fixture corpus re-run after final changes
- [x] CI green on pushed commit
- [x] mooncakes package page returns HTTP 200
