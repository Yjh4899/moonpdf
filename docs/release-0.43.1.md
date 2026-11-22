# MoonPDF 0.43.1

Released 2026-11-22. Packaging and documentation refresh for 0.43.0; no renderer
behavior changes.

## Changes

- `README.mbt.md` now documents the `MoonPdfDocument` facade, CLI, current
  features and verification numbers.
- Added [`examples/README.md`](../examples/README.md) with runnable commands and
  a generated-image gallery.
- Refreshed [`docs/performance.md`](../docs/performance.md) with the 0.43.0
  measurements.
- Added [`docs/acceptance.md`](../docs/acceptance.md), the release audit and
  known-gap register.
- Added `v0.43.0` git tag and release notes.

## Verification

Same renderer as 0.43.0: 61 tests, 39 fixtures (34 within tolerance), 13 real
PDFs (5 within tolerance, 0 crash/timeout), 120 fuzz cases (0 crashes/timeouts).
