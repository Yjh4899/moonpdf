# MoonPDF 0.43.0

Released 2026-11-22. Pure-MoonBit PDF 1.7 page renderer.

## Highlights

- Preserve font and text state across `BT`/`ET` (only matrices reset).
- Type-3 stitching functions in axial shadings.
- Full-pixel rounding for fractional page sizes.
- HSL blend modes: Hue, Saturation, Color, Luminosity.
- Gamma-aware supersample downsampling.
- Pixel-center scanline fill for thin text stems.
- Embedded OpenSans fallback for standard-14 text.
- Sub-pixel Type1 contour stroke for stem weight.
- Bilinear image sampling for scaled image XObjects.
- New regression fixtures: `text-bt.pdf`, `shading-type3.pdf`,
  `page-fraction.pdf`.

## Verification

- 61 unit/integration tests pass; `moon check --deny-warn` clean.
- 39 committed fixtures: 39 render, 34 within tolerance, 0 fail.
- 13 public real PDFs: 13 render, 5 within tolerance, 0 crash/timeout.
- 120 malformed PDFs: 0 crashes, 0 timeouts.
- CI: wasm-gc + native tests, fixture renders and pixel probes.
- Clean-clone check and CLI smoke test pass.

Real corpus highlights: attention 90.2%, alphatrans 98.2%, annotation 99.9%,
vertical 98.6%, dummy 99.8%. Known gaps: IRS 1040/W-9 about 82%, clip about 85%,
BERT/ResNet/tracemonkey about 86%, blendmode about 87%, GPT-4 about 88%. See
`docs/acceptance.md` and `docs/corpus-report-real.md`.

## Install

```bash
moon add Yjh4899/moonpdf@0.43.0
```

## CLI

```bash
moon run cmd/moonpdf -- input.pdf output.png --scale 2
moon run cmd/moonpdf -- input.pdf --all --out-dir out --svg
```

## License

Apache-2.0. The bundled OpenSans subset is SIL OFL 1.1; see
`fixtures/fonts/OFL.txt`.
