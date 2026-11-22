# MoonPDF 0.44.0

Released 2026-11-22. Demo, acceptance material and boundary-test release; the
renderer behavior is unchanged from 0.43.1.

## Added

- Static visual gallery: [`demo/index.html`](../demo/index.html)
  - real-document comparisons for attention, IRS 1040 and PDF.js blend modes;
  - fixture gallery for fonts, images, patterns, shadings and masks;
  - CLI/library snippets and verification summary.
- [`docs/proposal-material.md`](../docs/proposal-material.md): six-criterion
  evidence table and the CFF / transparency / font-fallback / differential
  tradeoffs for the proposal.
- 16 boundary tests (61 → 77), covering singular matrices, pixel-center spans,
  gamma downsampling, clipping, blend-mode extremes, image clamping, bilinear
  sampling and comment-only content streams.

## Verification

- 77 unit/integration tests pass; `moon check --deny-warn` clean.
- 39 fixtures: 39 render, 34 within tolerance, 0 fail.
- 13 real PDFs: 13 render, 5 within tolerance, 0 crash/timeout.
- 120 fuzz cases: 0 crashes, 0 timeouts.
- Clean-clone build and CLI smoke test pass.
- CI: wasm-gc + native tests, fixture renders and pixel probes.

## Notes

No renderer behavior changes; the pixel-closeness numbers are unchanged from
0.43.0/0.43.1. The new material is for acceptance and for explaining the
remaining known gaps.
