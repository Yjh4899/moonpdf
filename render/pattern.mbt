///|
/// A PDF pattern resource. Shading patterns (type 2) and colored tiling
/// patterns (type 1) are supported; uncolored tiling patterns fall back to the
/// solid fill color.
pub struct Pattern {
  shading : Shading?
  tile : RenderedPage?
  matrix : Matrix
  bbox_x0 : Double
  bbox_y0 : Double
  bbox_x1 : Double
  bbox_y1 : Double
  x_step : Double
  y_step : Double
}

///|
fn pattern_numbers(
  page : @pdf.PdfPage,
  dict : Array[(String, @pdf.PdfValue)],
  key : String,
) -> Array[Double] {
  let out : Array[Double] = []
  match @pdf.dict_get(dict, key) {
    Some(value) =>
      match page.resolve(value).as_array() {
        Some(items) =>
          for item in items {
            match page.resolve(item).as_number() {
              Some(n) => out.push(n)
              None => out.push(0.0)
            }
          }
        None => ()
      }
    None => ()
  }
  out
}

///|
fn pattern_matrix(
  page : @pdf.PdfPage,
  dict : Array[(String, @pdf.PdfValue)],
) -> Matrix {
  let values = pattern_numbers(page, dict, "Matrix")
  if values.length() >= 6 {
    Matrix::new(
      values[0],
      values[1],
      values[2],
      values[3],
      values[4],
      values[5],
    )
  } else {
    Matrix::identity()
  }
}

///|
fn pattern_int(
  _page : @pdf.PdfPage,
  dict : Array[(String, @pdf.PdfValue)],
  key : String,
  fallback : Int32,
) -> Int32 {
  match @pdf.dict_get(dict, key) {
    Some(value) =>
      match value.as_int() {
        Some(n) => n
        None => fallback
      }
    None => fallback
  }
}

///|
pub fn load_pattern(page : @pdf.PdfPage, value : @pdf.PdfValue) -> Pattern? {
  let mut dict : Array[(String, @pdf.PdfValue)] = []
  let mut data : Bytes? = None
  match page.resolve(value) {
    @pdf.Stream(stream) => {
      dict = stream.dict
      data = Some(stream.data)
    }
    @pdf.Dict(items) => dict = items
    _ => ()
  }
  if dict.length() == 0 {
    return None
  }
  let kind = pattern_int(page, dict, "PatternType", 1)
  if kind == 2 {
    match @pdf.dict_get(dict, "Shading") {
      Some(shading_value) => {
        let shading = load_shading(page, shading_value)
        Some({
          shading,
          tile: None,
          matrix: pattern_matrix(page, dict),
          bbox_x0: 0.0,
          bbox_y0: 0.0,
          bbox_x1: 0.0,
          bbox_y1: 0.0,
          x_step: 0.0,
          y_step: 0.0,
        })
      }
      None => None
    }
  } else {
    let paint_type = pattern_int(page, dict, "PaintType", 1)
    if paint_type == 2 {
      return Some({
        shading: None,
        tile: None,
        matrix: pattern_matrix(page, dict),
        bbox_x0: 0.0,
        bbox_y0: 0.0,
        bbox_x1: 0.0,
        bbox_y1: 0.0,
        x_step: 0.0,
        y_step: 0.0,
      })
    }
    let bbox = pattern_numbers(page, dict, "BBox")
    if bbox.length() < 4 {
      return None
    }
    let bx0 = bbox[0]
    let by0 = bbox[1]
    let bx1 = bbox[2]
    let by1 = bbox[3]
    let cell_w = bx1 - bx0
    let cell_h = by1 - by0
    if cell_w <= 0.0 || cell_h <= 0.0 {
      return None
    }
    let x_step = match @pdf.dict_get(dict, "XStep") {
      Some(value) =>
        match value.as_number() {
          Some(n) => n
          None => cell_w
        }
      None => cell_w
    }
    let y_step = match @pdf.dict_get(dict, "YStep") {
      Some(value) =>
        match value.as_number() {
          Some(n) => n
          None => cell_h
        }
      None => cell_h
    }
    let resources = match @pdf.dict_get(dict, "Resources") {
      Some(value) => page.resolve_dict(value)
      None => page.resources
    }
    let raw = match data {
      Some(raw) => raw
      None => return None
    }
    let decoded = @pdf.decode_stream(@pdf.inline_image_stream(dict, raw)) catch {
      _ => return None
    }
    if decoded.length() == 0 {
      return None
    }
    let prefix = @utf8.encode("q\n1 0 0 1 \{(-bx0)} \{(-by0)} cm\n")
    let suffix = @utf8.encode("\nQ\n")
    let buf = @buffer.Buffer::Buffer()
    buf.write_bytes(prefix)
    buf.write_bytes(decoded)
    buf.write_bytes(suffix)
    let cell_page = @pdf.make_page(
      cell_w,
      cell_h,
      0.0,
      0.0,
      cell_w,
      cell_h,
      0,
      [buf.to_bytes()],
      resources,
      [],
      [],
      page.objects,
    )
    let tile = render_page(cell_page, RenderOptions::with_scale(1.0)) catch {
      _ => return None
    }
    Some({
      shading: None,
      tile: Some(tile),
      matrix: pattern_matrix(page, dict),
      bbox_x0: bx0,
      bbox_y0: by0,
      bbox_x1: bx1,
      bbox_y1: by1,
      x_step,
      y_step,
    })
  }
}

///|
fn paint_tile(
  canvas : Canvas,
  state : GState,
  pattern : Pattern,
  tile : RenderedPage,
  subpaths : Array[Array[Point]],
  even_odd : Bool,
) -> Unit {
  let pattern_inverse = match pattern.matrix.invert() {
    Some(matrix) => matrix
    None => return
  }
  let inverse = match state.ctm.invert() {
    Some(matrix) => matrix
    None => return
  }
  let previous = canvas.clip_mask()
  canvas.clip_polygons(subpaths, even_odd)
  canvas.set_alpha(alpha_component(state.fill_alpha))
  canvas.set_blend(state.blend_mode)
  let (x0, y0, x1, y1) = canvas.clip_rect()
  let mut y = y0
  while y < y1 {
    let mut x = x0
    while x < x1 {
      let user = inverse.apply(x.to_double() + 0.5, y.to_double() + 0.5)
      let point = pattern_inverse.apply(user.x, user.y)
      let cell_x = @math.floor(point.x / pattern.x_step)
      let cell_y = @math.floor(point.y / pattern.y_step)
      let local_x = point.x - cell_x * pattern.x_step
      let local_y = point.y - cell_y * pattern.y_step
      if local_x >= pattern.bbox_x0 &&
        local_x <= pattern.bbox_x1 &&
        local_y >= pattern.bbox_y0 &&
        local_y <= pattern.bbox_y1 {
        let u = (local_x - pattern.bbox_x0) /
          (pattern.bbox_x1 - pattern.bbox_x0)
        let v = (local_y - pattern.bbox_y0) /
          (pattern.bbox_y1 - pattern.bbox_y0)
        let mut tx = (u * tile.width.to_double()).to_int()
        let mut ty = ((1.0 - v) * tile.height.to_double()).to_int()
        if tx < 0 {
          tx = 0
        }
        if ty < 0 {
          ty = 0
        }
        if tx >= tile.width {
          tx = tile.width - 1
        }
        if ty >= tile.height {
          ty = tile.height - 1
        }
        let idx = (ty * tile.width + tx) * 3
        canvas.set(
          x,
          y,
          tile.pixels.at(idx).to_int(),
          tile.pixels.at(idx + 1).to_int(),
          tile.pixels.at(idx + 2).to_int(),
        )
      }
      x = x + 1
    }
    y = y + 1
  }
  canvas.set_clip_mask(previous)
}

///|
fn paint_pattern(
  canvas : Canvas,
  state : GState,
  subpaths : Array[Array[Point]],
  even_odd : Bool,
  pattern : Pattern,
) -> Unit {
  match pattern.shading {
    Some(shading) => {
      let previous = canvas.clip_mask()
      canvas.clip_polygons(subpaths, even_odd)
      paint_shading(canvas, state, shading)
      canvas.set_clip_mask(previous)
    }
    None =>
      match pattern.tile {
        Some(tile) =>
          paint_tile(canvas, state, pattern, tile, subpaths, even_odd)
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
}
