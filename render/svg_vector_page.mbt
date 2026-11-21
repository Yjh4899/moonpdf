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
    clip_id: None,
  }
  let stack : Array[SvgState] = Array(capacity=8)
  let mut text = TextState::initial()
  let text_stack : Array[TextState] = Array(capacity=8)
  let defs = @buffer.Buffer::Buffer()
  let mut clip_seq = 0
  let mut path = Path::new()
  for op in expanded {
    match op.op {
      "q" => {
        stack.push(state)
        text_stack.push(text)
      }
      "Q" => {
        match stack.pop() {
          Some(previous) => state = previous
          None => ()
        }
        match text_stack.pop() {
          Some(previous) => text = previous
          None => ()
        }
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
      "Do" => {
        let name = match op.operands.get(0) {
          Some(value) =>
            match value.as_name() {
              Some(name) => name
              None => ""
            }
          None => ""
        }
        let stream = match
          lookup_resource(page, page.resources, "XObject", name) {
          Some(@pdf.Stream(stream)) => stream
          _ => return None
        }
        let is_image = match @pdf.dict_get(stream.dict, "Subtype") {
          Some(value) =>
            match value.as_name() {
              Some(name) => name == "Image"
              None => false
            }
          None => false
        }
        if !is_image {
          return None
        }
        let image = decode_image(page, stream) catch { _ => return None }
        if image.alpha is Some(_) {
          return None
        }
        let encoded = base64_encode(svg_image_png(image))
        let m = state.ctm
        svg_write(
          body,
          "<image x=\"0\" y=\"0\" width=\"1\" height=\"1\" preserveAspectRatio=\"none\" transform=\"matrix(\{m.a},\{m.b},\{-m.c},\{-m.d},\{m.c + m.e},\{m.d + m.f})\" href=\"data:image/png;base64,",
        )
        svg_write(body, encoded)
        svg_write(body, "\"/>\n")
      }
      "BT" => text = TextState::initial()
      "ET" => ()
      "Tf" => {
        match op_number(op, 1) {
          Some(size) => text.font_size = size
          None => ()
        }
        let name = match op.operands.get(0) {
          Some(@pdf.Name(name)) => name
          _ => ""
        }
        if name == "" {
          text.font = None
        } else {
          match lookup_resource(page, page.resources, "Font", name) {
            Some(value) => text.font = load_pdf_font(page, value)
            None => text.font = None
          }
        }
      }
      "Tc" =>
        match op_number(op, 0) {
          Some(v) => text.char_spacing = v
          None => ()
        }
      "Tw" =>
        match op_number(op, 0) {
          Some(v) => text.word_spacing = v
          None => ()
        }
      "Tz" =>
        match op_number(op, 0) {
          Some(v) => text.h_scale = v / 100.0
          None => ()
        }
      "TL" =>
        match op_number(op, 0) {
          Some(v) => text.leading = v
          None => ()
        }
      "Ts" =>
        match op_number(op, 0) {
          Some(v) => text.rise = v
          None => ()
        }
      "Td" =>
        match (op_number(op, 0), op_number(op, 1)) {
          (Some(tx), Some(ty)) => {
            text.line_matrix = Matrix::translate(tx, ty).then(text.line_matrix)
            text.matrix = text.line_matrix
          }
          _ => ()
        }
      "TD" =>
        match (op_number(op, 0), op_number(op, 1)) {
          (Some(tx), Some(ty)) => {
            text.leading = -ty
            text.line_matrix = Matrix::translate(tx, ty).then(text.line_matrix)
            text.matrix = text.line_matrix
          }
          _ => ()
        }
      "Tm" =>
        match
          (
            op_number(op, 0),
            op_number(op, 1),
            op_number(op, 2),
            op_number(op, 3),
            op_number(op, 4),
            op_number(op, 5),
          ) {
          (Some(a), Some(b), Some(c), Some(d), Some(e), Some(f)) => {
            let matrix = Matrix::new(a, b, c, d, e, f)
            text.line_matrix = matrix
            text.matrix = matrix
          }
          _ => ()
        }
      "T*" => next_line(text)
      "Tj" =>
        match op_string(op, 0) {
          Some(bytes) =>
            if !svg_show_text(body, state, text, bytes) {
              return None
            }
          None => ()
        }
      "TJ" =>
        match op_array(op, 0) {
          Some(items) =>
            if !svg_show_text_array(body, state, text, items) {
              return None
            }
          None => ()
        }
      "'" => {
        next_line(text)
        match op_string(op, 0) {
          Some(bytes) =>
            if !svg_show_text(body, state, text, bytes) {
              return None
            }
          None => ()
        }
      }
      "\"" => {
        match op_number(op, 0) {
          Some(v) => text.word_spacing = v
          None => ()
        }
        match op_number(op, 1) {
          Some(v) => text.char_spacing = v
          None => ()
        }
        next_line(text)
        match op_string(op, 2) {
          Some(bytes) =>
            if !svg_show_text(body, state, text, bytes) {
              return None
            }
          None => ()
        }
      }
      "Tr" =>
        match op_number(op, 0) {
          Some(mode) => if mode != 0.0 { return None }
          None => ()
        }
      "W" | "W*" => {
        match state.clip_id {
          Some(_) => return None
          None => ()
        }
        let (subpaths, closed) = path.finish()
        let data = svg_path_data(subpaths, closed)
        if data.length() > 0 {
          let id = "clip\{clip_seq}"
          clip_seq = clip_seq + 1
          svg_write(defs, "<clipPath id=\"")
          svg_write(defs, id)
          svg_write(defs, "\"><path d=\"")
          svg_write(defs, data)
          svg_write(defs, "\"")
          if op.op == "W*" {
            svg_write(defs, " clip-rule=\"evenodd\"")
          }
          svg_write(defs, "/></clipPath>\n")
          state.clip_id = Some(id)
        }
      }
      "sh" | "BI" | "gs" => return None
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
  if defs.to_bytes().length() > 0 {
    svg_write(svg, "<defs>\n")
    svg.write_bytes(defs.to_bytes())
    svg_write(svg, "</defs>\n")
  }
  svg.write_bytes(body.to_bytes())
  svg_write(svg, "</svg>\n")
  Some(svg.to_bytes())
}
