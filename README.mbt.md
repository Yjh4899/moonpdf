# MoonPDF

A pure-MoonBit PDF page rendering engine: parse a PDF, interpret its content
stream, rasterize the page and write a PNG without a JavaScript VM or a C
library.

The public facade exposes `page_count(data)` and `render_page_png(data, page,
scale)`. The parser lives in `pdf/`, the renderer in `render/`, and the CLI in
`cmd/moonpdf/`.

See [README.md](README.md) for the full project description, compatibility
matrix and roadmap.
