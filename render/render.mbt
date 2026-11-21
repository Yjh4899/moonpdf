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
  mut fill_alpha : Double
  mut stroke_alpha : Double
  mut blend_mode : Int32
  mut fill_pattern : Pattern?
  mut pattern_r : Double
  mut pattern_g : Double
  mut pattern_b : Double
  mut clip_mask : Array[Byte]?
  mut soft_mask : Array[Byte]?
  clip : (Int32, Int32, Int32, Int32)
}

///|
fn GState::initial(
  ctm : Matrix,
  clip : (Int32, Int32, Int32, Int32),
  clip_mask : Array[Byte]?,
) -> GState {
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
    fill_alpha: 1.0,
    stroke_alpha: 1.0,
    blend_mode: 0,
    fill_pattern: None,
    pattern_r: 0.0,
    pattern_g: 0.0,
    pattern_b: 0.0,
    clip_mask,
    soft_mask: None,
    clip,
  }
}

///|
fn GState::copy(self : GState) -> GState {
  {
    ctm: self.ctm,
    fill_r: self.fill_r,
    fill_g: self.fill_g,
    fill_b: self.fill_b,
    stroke_r: self.stroke_r,
    stroke_g: self.stroke_g,
    stroke_b: self.stroke_b,
    line_width: self.line_width,
    round_cap: self.round_cap,
    fill_alpha: self.fill_alpha,
    stroke_alpha: self.stroke_alpha,
    blend_mode: self.blend_mode,
    fill_pattern: self.fill_pattern,
    pattern_r: self.pattern_r,
    pattern_g: self.pattern_g,
    pattern_b: self.pattern_b,
    clip_mask: self.clip_mask,
    soft_mask: self.soft_mask,
    clip: self.clip,
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
  mut font : PdfFont?
}

///|
fn TextState::copy(self : TextState) -> TextState {
  {
    matrix: self.matrix,
    line_matrix: self.line_matrix,
    font_size: self.font_size,
    char_spacing: self.char_spacing,
    word_spacing: self.word_spacing,
    h_scale: self.h_scale,
    leading: self.leading,
    rise: self.rise,
    font: self.font,
  }
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
    font: None,
  }
}

///|
fn blend_mode_from_name(name : String) -> Int32 {
  match name {
    "Multiply" => 1
    "Screen" => 2
    "Overlay" => 3
    "Darken" => 4
    "Lighten" => 5
    "ColorDodge" => 6
    "ColorBurn" => 7
    "HardLight" => 8
    "SoftLight" => 9
    "Difference" => 10
    "Exclusion" => 11
    _ => 0
  }
}

///|
fn alpha_component(value : Double) -> Int32 {
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
  state.fill_pattern = None
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
  canvas.set_blend(state.blend_mode)
  if fill {
    match state.fill_pattern {
      Some(pattern) => paint_pattern(canvas, state, subpaths, even_odd, pattern)
      None => {
        canvas.set_alpha(alpha_component(state.fill_alpha))
        canvas.fill_polygons(
          subpaths,
          even_odd,
          state.fill_r,
          state.fill_g,
          state.fill_b,
        )
      }
    }
  }
  if stroke {
    canvas.set_alpha(alpha_component(state.stroke_alpha))
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
fn show_text_font(
  canvas : Canvas,
  state : GState,
  text : TextState,
  bytes : Bytes,
  font : PdfFont,
) -> Unit {
  canvas.set_alpha(alpha_component(state.fill_alpha))
  canvas.set_blend(state.blend_mode)
  let codes : Array[Int32] = []
  let raw = bytes.to_array()
  if font.two_byte {
    let step = if font.code_bytes > 0 { font.code_bytes } else { 2 }
    let mut i = 0
    while i + step <= raw.length() {
      let mut code = 0
      let mut j = 0
      while j < step {
        code = (code << 8) | raw[i + j].to_int()
        j = j + 1
      }
      codes.push(code)
      i = i + step
    }
  } else {
    for b in raw {
      codes.push(b.to_int())
    }
  }
  let mut previous = -1
  for code in codes {
    if previous >= 0 {
      let adjustment = font.kern_for(previous, code)
      if adjustment != 0 {
        text.matrix = text.matrix.then(
          Matrix::translate(
            adjustment.to_double() / 1000.0 * text.font_size * text.h_scale,
            0.0,
          ),
        )
      }
    }
    let full = text.matrix.then(state.ctm)
    let glyph = font.glyph_for_code(code)
    let drawn = if glyph > 0 {
      match font.tt {
        Some(tt) => {
          draw_glyph(
            canvas,
            tt,
            glyph,
            full,
            text.font_size,
            state.fill_r,
            state.fill_g,
            state.fill_b,
          )
          true
        }
        None =>
          match font.cff {
            Some(cff) => {
              draw_cff_glyph(
                canvas,
                cff,
                glyph,
                full,
                text.font_size,
                state.fill_r,
                state.fill_g,
                state.fill_b,
              )
              true
            }
            None => false
          }
      }
    } else {
      match font.type1 {
        Some(t1) => {
          let (name, ok) = t1_glyph_name(code)
          if ok {
            draw_type1_glyph(
              canvas,
              t1,
              name,
              full,
              text.font_size,
              state.fill_r,
              state.fill_g,
              state.fill_b,
            )
            true
          } else {
            false
          }
        }
        None => false
      }
    }
    if !drawn {
      let bitmap_advance = text.font_size * 0.8
      let target = font.width_for(code).to_double() / 1000.0 * text.font_size
      let mut sx = 1.0
      if font.standard && bitmap_advance > 0.0 {
        sx = target / bitmap_advance
        if sx < 0.35 {
          sx = 0.35
        } else if sx > 1.8 {
          sx = 1.8
        }
      }
      let glyph_matrix = if sx != 1.0 {
        Matrix::scale(sx, 1.0).then(full)
      } else {
        full
      }
      ignore(
        draw_text(
          canvas,
          Bytes::make(1, u8(code & 0xFF)),
          glyph_matrix,
          text.font_size,
          state.fill_r,
          state.fill_g,
          state.fill_b,
        ),
      )
    }
    let mut advance = font.width_for(font.cid_for_code(code)).to_double() /
      1000.0 *
      text.font_size +
      text.char_spacing
    if code == 32 {
      advance = advance + text.word_spacing
    }
    text.matrix = text.matrix.then(
      Matrix::translate(advance * text.h_scale, text.rise),
    )
    previous = code
  }
}

///|
fn show_text(
  canvas : Canvas,
  state : GState,
  text : TextState,
  bytes : Bytes,
) -> Unit {
  match text.font {
    Some(font) => show_text_font(canvas, state, text, bytes, font)
    None => {
      canvas.set_alpha(alpha_component(state.fill_alpha))
      canvas.set_blend(state.blend_mode)
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
      let total = advance +
        bytes.length().to_double() * text.char_spacing +
        extra
      let tx = total * text.h_scale
      text.matrix = text.matrix.then(Matrix::translate(tx, text.rise))
    }
  }
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
fn lookup_resource(
  page : @pdf.PdfPage,
  resources : Array[(String, @pdf.PdfValue)],
  category : String,
  name : String,
) -> @pdf.PdfValue? {
  let dict = match @pdf.dict_get(resources, category) {
    Some(value) => page.resolve_dict(value)
    None => return None
  }
  match @pdf.dict_get(dict, name) {
    Some(value) => Some(page.resolve(value))
    None => None
  }
}

///|
fn form_matrix(
  page : @pdf.PdfPage,
  dict : Array[(String, @pdf.PdfValue)],
) -> Matrix {
  match @pdf.dict_get(dict, "Matrix") {
    Some(value) =>
      match page.resolve(value).as_array() {
        Some(items) =>
          if items.length() >= 6 {
            match
              (
                items[0].as_number(),
                items[1].as_number(),
                items[2].as_number(),
                items[3].as_number(),
                items[4].as_number(),
                items[5].as_number(),
              ) {
              (Some(a), Some(b), Some(c), Some(d), Some(e), Some(f)) =>
                Matrix::new(a, b, c, d, e, f)
              _ => Matrix::identity()
            }
          } else {
            Matrix::identity()
          }
        None => Matrix::identity()
      }
    None => Matrix::identity()
  }
}

///|
/// Expand Form XObjects into the page operation stream. This keeps the
/// graphics-state interpreter flat while still reusing the form's content and
/// matrix. Nested forms are expanded recursively with their own resources.
fn expand_forms(
  page : @pdf.PdfPage,
  resources : Array[(String, @pdf.PdfValue)],
  ops : Array[@pdf.ContentOp],
  depth : Int32,
) -> Array[@pdf.ContentOp] raise RenderError {
  if depth > 8 {
    raise RenderError("Form XObject nesting is too deep")
  }
  let out : Array[@pdf.ContentOp] = Array(capacity=ops.length())
  for op in ops {
    if op.op == "Do" {
      let name = match op.operands.get(0) {
        Some(@pdf.Name(name)) => name
        _ => ""
      }
      if name == "" {
        continue
      }
      let value = match lookup_resource(page, resources, "XObject", name) {
        Some(value) => value
        None => continue
      }
      match value {
        @pdf.Stream(stream) => {
          let subtype = match @pdf.dict_get(stream.dict, "Subtype") {
            Some(value) => value.as_name()
            None => None
          }
          if subtype == Some("Form") {
            if group_is_transparency(page, stream.dict) {
              out.push(op)
              continue
            }
            let data = @pdf.decode_stream(stream) catch {
              _ => raise RenderError("failed to decode Form XObject \{name}")
            }
            let sub_ops = @pdf.parse_content_stream(data) catch {
              _ => raise RenderError("failed to parse Form XObject \{name}")
            }
            let form_resources = match @pdf.dict_get(stream.dict, "Resources") {
              Some(value) => page.resolve_dict(value)
              None => resources
            }
            let expanded = expand_forms(
              page,
              form_resources,
              sub_ops,
              depth + 1,
            )
            let matrix = form_matrix(page, stream.dict)
            out.push(@pdf.content_op([], "q"))
            out.push(
              @pdf.content_op(
                [
                  @pdf.pdf_real(matrix.a),
                  @pdf.pdf_real(matrix.b),
                  @pdf.pdf_real(matrix.c),
                  @pdf.pdf_real(matrix.d),
                  @pdf.pdf_real(matrix.e),
                  @pdf.pdf_real(matrix.f),
                ],
                "cm",
              ),
            )
            match @pdf.dict_get(stream.dict, "BBox") {
              Some(value) =>
                match page.resolve(value).as_array() {
                  Some(items) =>
                    if items.length() >= 4 {
                      match
                        (
                          items[0].as_number(),
                          items[1].as_number(),
                          items[2].as_number(),
                          items[3].as_number(),
                        ) {
                        (Some(bx0), Some(by0), Some(bx1), Some(by1)) =>
                          if bx1 > bx0 && by1 > by0 {
                            out.push(
                              @pdf.content_op(
                                [
                                  @pdf.pdf_real(bx0),
                                  @pdf.pdf_real(by0),
                                  @pdf.pdf_real(bx1 - bx0),
                                  @pdf.pdf_real(by1 - by0),
                                ],
                                "re",
                              ),
                            )
                            out.push(@pdf.content_op([], "W"))
                            out.push(@pdf.content_op([], "n"))
                          }
                        _ => ()
                      }
                    }
                  None => ()
                }
              None => ()
            }
            for sub in expanded {
              out.push(sub)
            }
            out.push(@pdf.content_op([], "Q"))
          } else {
            out.push(op)
          }
        }
        _ => out.push(op)
      }
    } else {
      out.push(op)
    }
  }
  out
}

///|
/// Render one PDF page to an RGB raster.
pub fn render_page(
  page : @pdf.PdfPage,
  options : RenderOptions,
) -> RenderedPage raise RenderError {
  render_page_inner(page, options, 0)
}

///|
fn render_page_inner(
  page : @pdf.PdfPage,
  options : RenderOptions,
  depth : Int32,
) -> RenderedPage raise RenderError {
  let buf = @buffer.Buffer::Buffer()
  for part in page.contents {
    buf.write_bytes(part)
    buf.write_byte(u8(10))
  }
  let ops = @pdf.parse_content_stream(buf.to_bytes()) catch {
    @pdf.PdfError(msg) => raise RenderError("content stream: \{msg}")
  }
  let mut out_w = (page.width * options.scale).to_int()
  let mut out_h = (page.height * options.scale).to_int()
  if out_w <= 0 {
    out_w = 1
  }
  if out_h <= 0 {
    out_h = 1
  }
  if out_w > 16384 || out_h > 16384 || out_w * out_h > 64000000 {
    raise RenderError("page dimensions are too large")
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
  let filtered = filter_optional_content(page, ops)
  let expanded = expand_forms(page, page.resources, filtered, 0)
  let mut state = GState::initial(base, canvas.clip_rect(), canvas.clip_mask())
  let stack : Array[GState] = Array(capacity=8)
  let text_stack : Array[TextState] = Array(capacity=8)
  let mut text = TextState::initial()
  let mut path = Path::new()
  for op in expanded {
    match op.op {
      "q" => {
        stack.push(state.copy())
        text_stack.push(text.copy())
      }
      "Q" => {
        match stack.pop() {
          Some(previous) => {
            state = previous
            let (cx0, cy0, cx1, cy1) = previous.clip
            canvas.reset_clip(cx0, cy0, cx1, cy1)
            canvas.set_clip_mask(previous.clip_mask)
            canvas.set_soft_mask(previous.soft_mask)
          }
          None => ()
        }
        match text_stack.pop() {
          Some(previous) => text = previous
          None => ()
        }
      }
      "gs" => {
        let name = match op.operands.get(0) {
          Some(@pdf.Name(name)) => name
          _ => ""
        }
        if name != "" {
          match lookup_resource(page, page.resources, "ExtGState", name) {
            Some(value) => {
              let dict = page.resolve_dict(value)
              match @pdf.dict_get(dict, "ca") {
                Some(number) =>
                  match page.resolve(number).as_number() {
                    Some(alpha) => state.fill_alpha = alpha
                    None => ()
                  }
                None => ()
              }
              match @pdf.dict_get(dict, "CA") {
                Some(number) =>
                  match page.resolve(number).as_number() {
                    Some(alpha) => state.stroke_alpha = alpha
                    None => ()
                  }
                None => ()
              }
              match @pdf.dict_get(dict, "BM") {
                Some(@pdf.Name(name)) =>
                  state.blend_mode = blend_mode_from_name(name)
                Some(@pdf.Array(items)) =>
                  if items.length() > 0 {
                    match items[0].as_name() {
                      Some(name) =>
                        state.blend_mode = blend_mode_from_name(name)
                      None => ()
                    }
                  }
                _ => ()
              }
              match @pdf.dict_get(dict, "SMask") {
                Some(value) =>
                  match page.resolve(value) {
                    @pdf.Dict(mask_dict) => {
                      let mask = render_soft_mask(
                        page, mask_dict, canvas, state, depth,
                      )
                      state.soft_mask = mask
                      canvas.set_soft_mask(mask)
                    }
                    @pdf.Name("None") => {
                      state.soft_mask = None
                      canvas.set_soft_mask(None)
                    }
                    _ => ()
                  }
                None => ()
              }
            }
            None => ()
          }
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
          Some(w) => state.line_width = w
          None => ()
        }
      "J" =>
        match op_number(op, 0) {
          Some(cap) => state.round_cap = cap.to_int() == 1
          None => ()
        }
      "cs" | "CS" => state.fill_pattern = None
      "scn" => {
        let count = op.operands.length()
        let name = if count > 0 {
          match op.operands[count - 1].as_name() {
            Some(name) => name
            None => ""
          }
        } else {
          ""
        }
        if name == "" {
          state.fill_pattern = None
        } else {
          match lookup_resource(page, page.resources, "Pattern", name) {
            Some(value) => {
              let pattern = load_pattern(page, value)
              match pattern {
                Some(pattern) =>
                  if pattern.uncolored {
                    if count == 2 {
                      match op_number(op, 0) {
                        Some(gray) => {
                          state.pattern_r = gray
                          state.pattern_g = gray
                          state.pattern_b = gray
                        }
                        None => ()
                      }
                    } else if count >= 4 {
                      match
                        (op_number(op, 0), op_number(op, 1), op_number(op, 2)) {
                        (Some(r), Some(g), Some(b)) => {
                          state.pattern_r = r
                          state.pattern_g = g
                          state.pattern_b = b
                        }
                        _ => ()
                      }
                    }
                  }
                None => ()
              }
              state.fill_pattern = pattern
            }
            None => state.fill_pattern = None
          }
        }
      }
      "SCN" => state.fill_pattern = None
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
      "W" | "W*" => {
        let (subpaths, _) = path.finish()
        canvas.clip_polygons(subpaths, op.op == "W*")
        state.clip_mask = canvas.clip_mask()
      }
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
      "BI" =>
        match (op.operands.get(0), op.operands.get(1)) {
          (Some(@pdf.Dict(dict)), Some(@pdf.Str(data))) => {
            let stream = @pdf.inline_image_stream(dict, data)
            let image = decode_image(page, stream)
            draw_image(canvas, state, image)
          }
          _ => ()
        }
      "sh" => {
        let name = match op.operands.get(0) {
          Some(@pdf.Name(name)) => name
          _ => ""
        }
        if name != "" {
          match lookup_resource(page, page.resources, "Shading", name) {
            Some(value) =>
              match load_shading(page, value) {
                Some(shading) => paint_shading(canvas, state, shading)
                None => ()
              }
            None => ()
          }
        }
      }
      "Do" => {
        let name = match op.operands.get(0) {
          Some(@pdf.Name(name)) => name
          _ => ""
        }
        if name != "" {
          match lookup_resource(page, page.resources, "XObject", name) {
            Some(value) =>
              match value {
                @pdf.Stream(stream) => {
                  let subtype = match @pdf.dict_get(stream.dict, "Subtype") {
                    Some(value) => value.as_name()
                    None => None
                  }
                  if subtype == Some("Form") {
                    if group_is_transparency(page, stream.dict) {
                      render_transparency_group(
                        page, stream, canvas, state, depth,
                      )
                    }
                  } else if subtype == Some("Image") {
                    let image = decode_image(page, stream)
                    canvas.set_alpha(255)
                    canvas.set_blend(state.blend_mode)
                    draw_image(canvas, state, image)
                  }
                }
                _ => ()
              }
            None => ()
          }
        }
      }
      _ => ()
    }
  }
  draw_annotations(page, canvas, base, depth)
  let final_canvas = canvas.downsample(ss)
  {
    width: final_canvas.width,
    height: final_canvas.height,
    pixels: final_canvas.to_rgb_bytes(),
  }
}
