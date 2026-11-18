///|
/// A PDF font resource reduced to the data needed for text rendering: optional
/// embedded TrueType outlines and per-code advances in 1/1000 em units.
pub struct PdfFont {
  base_name : String
  tt : TrueTypeFont?
  cff : CffFont?
  widths : Array[Int32]
  first_char : Int32
  missing_width : Int32
  ascent : Double
  descent : Double
  standard : Bool
}

///|
fn font_dict_int(
  page : @pdf.PdfPage,
  dict : Array[(String, @pdf.PdfValue)],
  key : String,
) -> Int32? {
  match @pdf.dict_get(dict, key) {
    Some(value) =>
      match page.resolve(value).as_int() {
        Some(n) => Some(n)
        None => None
      }
    None => None
  }
}

///|
fn load_truetype(
  page : @pdf.PdfPage,
  descriptor : Array[(String, @pdf.PdfValue)],
  key : String,
) -> TrueTypeFont? {
  match @pdf.dict_get(descriptor, key) {
    Some(value) =>
      match page.resolve(value) {
        @pdf.Stream(stream) => {
          let data = @pdf.decode_stream(stream) catch { _ => return None }
          let font = parse_truetype(data) catch { _ => return None }
          Some(font)
        }
        _ => None
      }
    None => None
  }
}

///|
fn load_cff(
  page : @pdf.PdfPage,
  descriptor : Array[(String, @pdf.PdfValue)],
  key : String,
) -> CffFont? {
  match @pdf.dict_get(descriptor, key) {
    Some(value) =>
      match page.resolve(value) {
        @pdf.Stream(stream) => {
          let data = @pdf.decode_stream(stream) catch { _ => return None }
          let font = parse_cff(data) catch { _ => return None }
          Some(font)
        }
        _ => None
      }
    None => None
  }
}

///|
fn derived_widths(tt : TrueTypeFont) -> Array[Int32] {
  let widths : Array[Int32] = Array::make(95, 500)
  let units = if tt.units_per_em() > 0 { tt.units_per_em() } else { 1000 }
  let mut code = 32
  while code <= 126 {
    let glyph = tt.glyph_id(code)
    let advance = if glyph > 0 { tt.advance_width(glyph) } else { 0 }
    widths[code - 32] = if advance > 0 { advance * 1000 / units } else { 500 }
    code = code + 1
  }
  widths
}

///|
pub fn load_pdf_font(page : @pdf.PdfPage, value : @pdf.PdfValue) -> PdfFont? {
  let dict = page.resolve_dict(value)
  if dict.length() == 0 {
    return None
  }
  let base_name = match @pdf.dict_get(dict, "BaseFont") {
    Some(value) =>
      match value.as_name() {
        Some(name) => name
        None => ""
      }
    None => ""
  }
  let descriptor = match @pdf.dict_get(dict, "FontDescriptor") {
    Some(value) => page.resolve_dict(value)
    None => []
  }
  let tt = load_truetype(page, descriptor, "FontFile2")
  let cff = match tt {
    Some(_) => None
    None => load_cff(page, descriptor, "FontFile3")
  }
  let mut first_char = match font_dict_int(page, dict, "FirstChar") {
    Some(n) => n
    None => 0
  }
  let mut standard = false
  let mut widths : Array[Int32] = []
  match @pdf.dict_get(dict, "Widths") {
    Some(value) =>
      match page.resolve(value).as_array() {
        Some(items) =>
          for item in items {
            let width = match page.resolve(item).as_number() {
              Some(n) => n.to_int()
              None => 0
            }
            widths.push(width)
          }
        None => ()
      }
    None => ()
  }
  if widths.length() == 0 {
    match tt {
      Some(font) => widths = derived_widths(font)
      None =>
        match cff {
          Some(_) => ()
          None =>
            match standard14_widths(base_name) {
              Some(table) => {
                widths = table
                first_char = 32
                standard = true
              }
              None => ()
            }
        }
    }
  }
  match tt {
    None =>
      match cff {
        None => standard = true
        Some(_) => ()
      }
    Some(_) => ()
  }
  let missing_width = match font_dict_int(page, dict, "MissingWidth") {
    Some(n) => n
    None => 500
  }
  if widths.length() == 0 {
    return None
  }
  let (ascent, descent) = match tt {
    Some(font) =>
      (
        font.ascent().to_double() / font.units_per_em().to_double() * 1000.0,
        font.descent().to_double() / font.units_per_em().to_double() * 1000.0,
      )
    None => (800.0, -200.0)
  }
  Some({
    base_name,
    tt,
    cff,
    widths,
    first_char,
    missing_width,
    ascent,
    descent,
    standard,
  })
}

///|
pub fn PdfFont::width_for(self : PdfFont, code : Int32) -> Int32 {
  let index = code - self.first_char
  if index >= 0 && index < self.widths.length() {
    let width = self.widths[index]
    if width > 0 {
      width
    } else {
      self.missing_width
    }
  } else {
    self.missing_width
  }
}

///|
pub fn PdfFont::ascent(self : PdfFont) -> Double {
  self.ascent
}

///|
pub fn PdfFont::descent(self : PdfFont) -> Double {
  self.descent
}

///|
fn midpoint(a : FontPoint, b : FontPoint) -> FontPoint {
  { x: (a.x + b.x) / 2.0, y: (a.y + b.y) / 2.0, on_curve: true, }
}

///|
fn append_contour(
  path : Path,
  contour : Array[FontPoint],
  matrix : Matrix,
  scale : Double,
) -> Unit {
  let n = contour.length()
  if n < 2 {
    return
  }
  let mut start_index = -1
  let mut i = 0
  while i < n {
    if contour[i].on_curve {
      start_index = i
      break
    }
    i = i + 1
  }
  let start = if start_index >= 0 {
    contour[start_index]
  } else {
    midpoint(contour[n - 1], contour[0])
  }
  path.move_to(matrix.apply(start.x * scale, start.y * scale))
  let mut control : FontPoint? = None
  let mut step = 1
  while step <= n {
    let index = if start_index >= 0 {
      (start_index + step) % n
    } else {
      step % n
    }
    let point = contour[index]
    if point.on_curve {
      match control {
        Some(c) =>
          path.quad_to(
            matrix.apply(c.x * scale, c.y * scale),
            matrix.apply(point.x * scale, point.y * scale),
          )
        None => path.line_to(matrix.apply(point.x * scale, point.y * scale))
      }
      control = None
    } else {
      match control {
        Some(c) => {
          let mid = midpoint(c, point)
          path.quad_to(
            matrix.apply(c.x * scale, c.y * scale),
            matrix.apply(mid.x * scale, mid.y * scale),
          )
        }
        None => ()
      }
      control = Some(point)
    }
    step = step + 1
  }
  match control {
    Some(c) =>
      path.quad_to(
        matrix.apply(c.x * scale, c.y * scale),
        matrix.apply(start.x * scale, start.y * scale),
      )
    None => ()
  }
  path.close()
}

///|
pub fn draw_glyph(
  canvas : Canvas,
  font : TrueTypeFont,
  glyph : Int32,
  matrix : Matrix,
  size : Double,
  r : Int32,
  g : Int32,
  b : Int32,
) -> Unit {
  let contours = font.glyph_contours(glyph) catch { _ => return }
  if contours.length() == 0 {
    return
  }
  let units = font.units_per_em()
  if units <= 0 {
    return
  }
  let scale = size / units.to_double()
  let path = Path::new()
  for contour in contours {
    append_contour(path, contour, matrix, scale)
  }
  let (subpaths, _) = path.finish()
  canvas.fill_polygons(subpaths, false, r, g, b)
}

///|
pub fn draw_cff_glyph(
  canvas : Canvas,
  font : CffFont,
  glyph : Int32,
  matrix : Matrix,
  size : Double,
  r : Int32,
  g : Int32,
  b : Int32,
) -> Unit {
  let path = font.glyph_path(glyph, matrix, size) catch { _ => return }
  match path {
    Some(path) => {
      let (subpaths, _) = path.finish()
      canvas.fill_polygons(subpaths, false, r, g, b)
    }
    None => ()
  }
}
