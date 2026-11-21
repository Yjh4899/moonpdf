///|
/// Export a path-only page as vector SVG. Returns `None` for unsupported
/// content; callers should fall back to the raster SVG container.
pub fn encode_svg_vector(
  page : @pdf.PdfPage,
  options : RenderOptions,
) -> Bytes? raise RenderError {
  if page.annots.length() > 0 {
    return None
  }
  let buf = @buffer.Buffer::Buffer()
  for part in page.contents {
    buf.write_bytes(part)
    buf.write_byte(u8(10))
  }
  let ops = @pdf.parse_content_stream(buf.to_bytes()) catch {
    @pdf.PdfError(msg) => raise RenderError("content stream: \{msg}")
  }
  let filtered = filter_optional_content(page, ops)
  let expanded = expand_forms(page, page.resources, filtered, 0)
  let mut out_w = (page.width * options.scale).to_int()
  let mut out_h = (page.height * options.scale).to_int()
  if out_w <= 0 {
    out_w = 1
  }
  if out_h <= 0 {
    out_h = 1
  }
  let device_scale = options.scale
  let x0 = page.crop_x0
  let y0 = page.crop_y0
  let x1 = page.crop_x1
  let y1 = page.crop_y1
  let base = match page.rotate {
    90 =>
      Matrix::new(
        0.0,
        device_scale,
        device_scale,
        0.0,
        -y0 * device_scale,
        -x0 * device_scale,
      )
    180 =>
      Matrix::new(
        -device_scale,
        0.0,
        0.0,
        device_scale,
        x1 * device_scale,
        -y0 * device_scale,
      )
    270 =>
      Matrix::new(
        0.0,
        -device_scale,
        -device_scale,
        0.0,
        y1 * device_scale,
        x1 * device_scale,
      )
    _ =>
      Matrix::new(
        device_scale,
        0.0,
        0.0,
        -device_scale,
        -x0 * device_scale,
        y1 * device_scale,
      )
  }
  let body = @buffer.Buffer::Buffer()
  let mut state : SvgState = {
    ctm: base,
    fill_r: 0,
    fill_g: 0,
    fill_b: 0,
    stroke_r: 0,
    stroke_g: 0,
    stroke_b: 0,
    line_width: 1.0,
  }
  let stack : Array[SvgState] = Array(capacity=8)
  let mut path = Path::new()
  for op in expanded {
    match op.op {
      "q" => stack.push(state)
      "Q" =>
        match stack.pop() {
          Some(previous) => state = previous
          None => ()
        }
      "cm" =>
        match
          (
            op_number(op, 0),
            op_number(op, 1),
            op_number(op, 2),
            op_number(op, 3),
            op_number(op, 4),
            op_number(op, 5),
          ) {
          (Some(a), Some(b), Some(c), Some(d), Some(e), Some(f)) =>
            state.ctm = Matrix::new(a, b, c, d, e, f).then(state.ctm)
          _ => ()
        }
      "w" =>
        match op_number(op, 0) {
          Some(width) => state.line_width = width
          None => ()
        }
      "g" =>
        match op_number(op, 0) {
          Some(v) => svg_apply_gray(state, v, false)
          None => ()
        }
      "G" =>
        match op_number(op, 0) {
          Some(v) => svg_apply_gray(state, v, true)
          None => ()
        }
      "rg" =>
        match (op_number(op, 0), op_number(op, 1), op_number(op, 2)) {
          (Some(r), Some(g), Some(b)) => svg_apply_rgb(state, r, g, b, false)
          _ => ()
        }
      "RG" =>
        match (op_number(op, 0), op_number(op, 1), op_number(op, 2)) {
          (Some(r), Some(g), Some(b)) => svg_apply_rgb(state, r, g, b, true)
          _ => ()
        }
      "k" =>
        match
          (
            op_number(op, 0),
            op_number(op, 1),
            op_number(op, 2),
            op_number(op, 3),
          ) {
          (Some(c), Some(m), Some(y), Some(k)) =>
            svg_apply_cmyk(state, c, m, y, k, false)
          _ => ()
        }
      "K" =>
        match
          (
            op_number(op, 0),
            op_number(op, 1),
            op_number(op, 2),
            op_number(op, 3),
          ) {
          (Some(c), Some(m), Some(y), Some(k)) =>
            svg_apply_cmyk(state, c, m, y, k, true)
          _ => ()
        }
      "m" =>
        match (op_number(op, 0), op_number(op, 1)) {
          (Some(x), Some(y)) => path.move_to(state.ctm.apply(x, y))
          _ => ()
        }
      "l" =>
        match (op_number(op, 0), op_number(op, 1)) {
          (Some(x), Some(y)) => path.line_to(state.ctm.apply(x, y))
          _ => ()
        }
      "c" =>
        match
          (
            op_number(op, 0),
            op_number(op, 1),
            op_number(op, 2),
            op_number(op, 3),
            op_number(op, 4),
            op_number(op, 5),
          ) {
          (Some(x1), Some(y1), Some(x2), Some(y2), Some(x3), Some(y3)) =>
            path.curve_to(
              state.ctm.apply(x1, y1),
              state.ctm.apply(x2, y2),
              state.ctm.apply(x3, y3),
            )
          _ => ()
        }
      "v" =>
        match
          (
            op_number(op, 0),
            op_number(op, 1),
            op_number(op, 2),
            op_number(op, 3),
          ) {
          (Some(x2), Some(y2), Some(x3), Some(y3)) => {
            let start = match path.current.last() {
              Some(p) => p
              None => { x: 0.0, y: 0.0, }
            }
            path.curve_to(
              start,
              state.ctm.apply(x2, y2),
              state.ctm.apply(x3, y3),
            )
          }
          _ => ()
        }
      "y" =>
        match
          (
            op_number(op, 0),
            op_number(op, 1),
            op_number(op, 2),
            op_number(op, 3),
          ) {
          (Some(x1), Some(y1), Some(x3), Some(y3)) => {
            let end = state.ctm.apply(x3, y3)
            path.curve_to(state.ctm.apply(x1, y1), end, end)
          }
          _ => ()
        }
      "re" =>
        match
          (
            op_number(op, 0),
            op_number(op, 1),
            op_number(op, 2),
            op_number(op, 3),
          ) {
          (Some(x), Some(y), Some(w), Some(h)) => {
            let p0 = state.ctm.apply(x, y)
            let p1 = state.ctm.apply(x + w, y)
            let p2 = state.ctm.apply(x + w, y + h)
            let p3 = state.ctm.apply(x, y + h)
            path.move_to(p0)
            path.line_to(p1)
            path.line_to(p2)
            path.line_to(p3)
            path.close()
          }
          _ => ()
        }
      "h" => path.close()
      "f" | "F" => {
        svg_paint(body, state, path, true, false, false)
        path = Path::new()
      }
      "f*" => {
        svg_paint(body, state, path, true, false, true)
        path = Path::new()
      }
      "S" | "s" => {
        svg_paint(body, state, path, false, true, false)
        path = Path::new()
      }
      "B" | "b" => {
        svg_paint(body, state, path, true, true, false)
        path = Path::new()
      }
      "B*" | "b*" => {
        svg_paint(body, state, path, true, true, true)
        path = Path::new()
      }
      "n" => path = Path::new()
      "J" | "j" | "d" | "i" | "ri" => ()
      "W"
      | "W*"
      | "BT"
      | "Tf"
      | "Td"
      | "TJ"
      | "Tj"
      | "Do"
      | "sh"
      | "BI"
      | "gs" => return None
      _ => return None
    }
  }
  let svg = @buffer.Buffer::Buffer()
  svg_write(
    svg,
    "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"\{out_w}\" height=\"\{out_h}\" viewBox=\"0 0 \{out_w} \{out_h}\">\n",
  )
  svg_write(
    svg,
    "<rect width=\"\{out_w}\" height=\"\{out_h}\" fill=\"rgb(\{options.bg_r},\{options.bg_g},\{options.bg_b})\"/>\n",
  )
  svg.write_bytes(body.to_bytes())
  svg_write(svg, "</svg>\n")
  Some(svg.to_bytes())
}
