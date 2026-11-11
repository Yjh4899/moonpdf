///|
pub suberror RenderError {
  RenderError(String)
}

///|
pub struct RenderOptions {
  scale : Double
  supersample : Int32
  bg_r : Int32
  bg_g : Int32
  bg_b : Int32
}

///|
pub fn RenderOptions::with_scale(scale : Double) -> RenderOptions {
  { scale, supersample: 2, bg_r: 255, bg_g: 255, bg_b: 255, }
}

///|
pub fn RenderOptions::default() -> RenderOptions {
  { scale: 1.0, supersample: 2, bg_r: 255, bg_g: 255, bg_b: 255, }
}

///|
pub struct RenderedPage {
  width : Int32
  height : Int32
  pixels : Bytes
}

///|
priv struct GState {
  mut ctm : Matrix
  mut fill_r : Int32
  mut fill_g : Int32
  mut fill_b : Int32
  mut stroke_r : Int32
  mut stroke_g : Int32
  mut stroke_b : Int32
  mut line_width : Double
  mut round_cap : Bool
}

///|
fn GState::initial(ctm : Matrix) -> GState {
  {
    ctm,
    fill_r: 0,
    fill_g: 0,
    fill_b: 0,
    stroke_r: 0,
    stroke_g: 0,
    stroke_b: 0,
    line_width: 1.0,
    round_cap: false,
  }
}

///|
priv struct TextState {
  mut matrix : Matrix
  mut line_matrix : Matrix
  mut font_size : Double
  mut char_spacing : Double
  mut word_spacing : Double
  mut h_scale : Double
  mut leading : Double
  mut rise : Double
}

///|
fn TextState::initial() -> TextState {
  {
    matrix: Matrix::identity(),
    line_matrix: Matrix::identity(),
    font_size: 12.0,
    char_spacing: 0.0,
    word_spacing: 0.0,
    h_scale: 1.0,
    leading: 0.0,
    rise: 0.0,
  }
}

///|
fn color_component(value : Double) -> Int32 {
  let v = value * 255.0
  if v <= 0.0 {
    0
  } else if v >= 255.0 {
    255
  } else {
    v.to_int()
  }
}

///|
fn op_number(op : @pdf.ContentOp, index : Int32) -> Double? {
  match op.operands.get(index) {
    Some(value) => value.as_number()
    None => None
  }
}

///|
fn op_string(op : @pdf.ContentOp, index : Int32) -> Bytes? {
  match op.operands.get(index) {
    Some(value) =>
      match value {
        @pdf.Str(bytes) => Some(bytes)
        _ => None
      }
    None => None
  }
}

///|
fn op_array(op : @pdf.ContentOp, index : Int32) -> Array[@pdf.PdfValue]? {
  match op.operands.get(index) {
    Some(value) =>
      match value {
        @pdf.Array(items) => Some(items)
        _ => None
      }
    None => None
  }
}

///|
fn set_fill(state : GState, r : Int32, g : Int32, b : Int32) -> Unit {
  state.fill_r = r
  state.fill_g = g
  state.fill_b = b
}

///|
fn set_stroke(state : GState, r : Int32, g : Int32, b : Int32) -> Unit {
  state.stroke_r = r
  state.stroke_g = g
  state.stroke_b = b
}

///|
fn apply_gray(state : GState, value : Double, stroke : Bool) -> Unit {
  let c = color_component(value)
  if stroke {
    set_stroke(state, c, c, c)
  } else {
    set_fill(state, c, c, c)
  }
}

///|
fn apply_rgb(
  state : GState,
  r : Double,
  g : Double,
  b : Double,
  stroke : Bool,
) -> Unit {
  let rr = color_component(r)
  let gg = color_component(g)
  let bb = color_component(b)
  if stroke {
    set_stroke(state, rr, gg, bb)
  } else {
    set_fill(state, rr, gg, bb)
  }
}

///|
fn apply_cmyk(
  state : GState,
  c : Double,
  m : Double,
  y : Double,
  k : Double,
  stroke : Bool,
) -> Unit {
  let r = (1.0 - c) * (1.0 - k)
  let g = (1.0 - m) * (1.0 - k)
  let b = (1.0 - y) * (1.0 - k)
  apply_rgb(state, r, g, b, stroke)
}

///|
fn paint(
  canvas : Canvas,
  state : GState,
  path : Path,
  fill : Bool,
  stroke : Bool,
  even_odd : Bool,
  close : Bool,
) -> Unit {
  if close {
    path.close()
  }
  let (subpaths, closed) = path.finish()
  if fill {
    canvas.fill_polygons(
      subpaths,
      even_odd,
      state.fill_r,
      state.fill_g,
      state.fill_b,
    )
  }
  if stroke {
    let mut i = 0
    while i < subpaths.length() {
      canvas.stroke_polyline(
        subpaths[i],
        closed[i],
        state.line_width * state.ctm.scale_factor(),
        state.round_cap,
        state.stroke_r,
        state.stroke_g,
        state.stroke_b,
      )
      i = i + 1
    }
  }
}

///|
fn next_line(text : TextState) -> Unit {
  text.line_matrix = text.line_matrix.then(
    Matrix::translate(0.0, -text.leading),
  )
  text.matrix = text.line_matrix
}

///|
fn show_text(
  canvas : Canvas,
  state : GState,
  text : TextState,
  bytes : Bytes,
) -> Unit {
  let full = text.matrix.then(state.ctm)
  let advance = draw_text(
    canvas,
    bytes,
    full,
    text.font_size,
    state.fill_r,
    state.fill_g,
    state.fill_b,
  )
  let mut extra = 0.0
  for b in bytes.to_array() {
    if b.to_int() == 32 {
      extra = extra + text.word_spacing
    }
  }
  let total = advance + bytes.length().to_double() * text.char_spacing + extra
  let tx = total * text.h_scale
  text.matrix = text.matrix.then(Matrix::translate(tx, text.rise))
}

///|
fn show_text_array(
  canvas : Canvas,
  state : GState,
  text : TextState,
  items : Array[@pdf.PdfValue],
) -> Unit {
  for item in items {
    match item {
      @pdf.Str(bytes) => show_text(canvas, state, text, bytes)
      @pdf.Int(n) => {
        let tx = -n.to_double() / 1000.0 * text.font_size * text.h_scale
        text.matrix = text.matrix.then(Matrix::translate(tx, 0.0))
      }
      @pdf.Real(n) => {
        let tx = -n / 1000.0 * text.font_size * text.h_scale
        text.matrix = text.matrix.then(Matrix::translate(tx, 0.0))
      }
      _ => ()
    }
  }
}

///|
/// Render one PDF page to an RGB raster.
pub fn render_page(
  page : @pdf.PdfPage,
  options : RenderOptions,
) -> RenderedPage raise RenderError {
  let buf = @buffer.Buffer::Buffer()
  for part in page.contents {
    buf.write_bytes(part)
    buf.write_byte(u8(10))
  }
  let ops = @pdf.parse_content_stream(buf.to_bytes()) catch {
    _ => raise RenderError("failed to parse page content stream")
  }
  let mut out_w = (page.width * options.scale).to_int()
  let mut out_h = (page.height * options.scale).to_int()
  if out_w <= 0 {
    out_w = 1
  }
  if out_h <= 0 {
    out_h = 1
  }
  let ss = if options.supersample < 1 { 1 } else { options.supersample }
  let render_w = out_w * ss
  let render_h = out_h * ss
  let canvas = Canvas::new(
    render_w,
    render_h,
    options.bg_r,
    options.bg_g,
    options.bg_b,
  )
  let device_scale = options.scale * ss.to_double()
  let base = Matrix::new(
    device_scale,
    0.0,
    0.0,
    -device_scale,
    0.0,
    page.height * device_scale,
  )
  let mut state = GState::initial(base)
  let stack : Array[GState] = Array(capacity=8)
  let mut text = TextState::initial()
  let mut path = Path::new()
  for op in ops {
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
          Some(w) => state.line_width = w
          None => ()
        }
      "J" =>
        match op_number(op, 0) {
          Some(cap) => state.round_cap = cap.to_int() == 1
          None => ()
        }
      "g" =>
        match op_number(op, 0) {
          Some(v) => apply_gray(state, v, false)
          None => ()
        }
      "G" =>
        match op_number(op, 0) {
          Some(v) => apply_gray(state, v, true)
          None => ()
        }
      "rg" =>
        match (op_number(op, 0), op_number(op, 1), op_number(op, 2)) {
          (Some(r), Some(g), Some(b)) => apply_rgb(state, r, g, b, false)
          _ => ()
        }
      "RG" =>
        match (op_number(op, 0), op_number(op, 1), op_number(op, 2)) {
          (Some(r), Some(g), Some(b)) => apply_rgb(state, r, g, b, true)
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
            apply_cmyk(state, c, m, y, k, false)
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
            apply_cmyk(state, c, m, y, k, true)
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
      "S" => {
        paint(canvas, state, path, false, true, false, false)
        path = Path::new()
      }
      "s" => {
        paint(canvas, state, path, false, true, false, true)
        path = Path::new()
      }
      "f" | "F" => {
        paint(canvas, state, path, true, false, false, false)
        path = Path::new()
      }
      "f*" => {
        paint(canvas, state, path, true, false, true, false)
        path = Path::new()
      }
      "B" => {
        paint(canvas, state, path, true, true, false, false)
        path = Path::new()
      }
      "B*" => {
        paint(canvas, state, path, true, true, true, false)
        path = Path::new()
      }
      "b" => {
        paint(canvas, state, path, true, true, false, true)
        path = Path::new()
      }
      "b*" => {
        paint(canvas, state, path, true, true, true, true)
        path = Path::new()
      }
      "n" => path = Path::new()
      "BT" => text = TextState::initial()
      "ET" => ()
      "Tf" =>
        match op_number(op, 1) {
          Some(size) => text.font_size = size
          None => ()
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
            text.line_matrix = text.line_matrix.then(Matrix::translate(tx, ty))
            text.matrix = text.line_matrix
          }
          _ => ()
        }
      "TD" =>
        match (op_number(op, 0), op_number(op, 1)) {
          (Some(tx), Some(ty)) => {
            text.leading = -ty
            text.line_matrix = text.line_matrix.then(Matrix::translate(tx, ty))
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
            text.matrix = Matrix::new(a, b, c, d, e, f)
            text.line_matrix = text.matrix
          }
          _ => ()
        }
      "T*" => next_line(text)
      "Tj" =>
        match op_string(op, 0) {
          Some(bytes) => show_text(canvas, state, text, bytes)
          None => ()
        }
      "TJ" =>
        match op_array(op, 0) {
          Some(items) => show_text_array(canvas, state, text, items)
          None => ()
        }
      "'" => {
        next_line(text)
        match op_string(op, 0) {
          Some(bytes) => show_text(canvas, state, text, bytes)
          None => ()
        }
      }
      "\"" => {
        match (op_number(op, 0), op_number(op, 1)) {
          (Some(word), Some(char)) => {
            text.word_spacing = word
            text.char_spacing = char
          }
          _ => ()
        }
        next_line(text)
        match op_string(op, 2) {
          Some(bytes) => show_text(canvas, state, text, bytes)
          None => ()
        }
      }
      _ => ()
    }
  }
  let final_canvas = canvas.downsample(ss)
  {
    width: final_canvas.width,
    height: final_canvas.height,
    pixels: final_canvas.to_rgb_bytes(),
  }
}
