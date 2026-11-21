///|
/// A PDF font resource reduced to the data needed for text rendering: optional
/// embedded TrueType outlines and per-code advances in 1/1000 em units.
pub struct PdfFont {
  base_name : String
  tt : TrueTypeFont?
  cff : CffFont?
  type1 : Type1Font?
  widths : Array[Int32]
  cid_widths : Array[(Int32, Int32)]
  cid_to_gid : Array[Int32]?
  code_to_cid : Array[(Int32, Int32)]
  code_bytes : Int32
  two_byte : Bool
  first_char : Int32
  missing_width : Int32
  ascent : Double
  descent : Double
  standard : Bool
  kern : Array[(Int32, Int32, Int32)]
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
fn parse_cid_widths(
  page : @pdf.PdfPage,
  dict : Array[(String, @pdf.PdfValue)],
  default_width : Int32,
) -> Array[(Int32, Int32)] {
  let out : Array[(Int32, Int32)] = []
  match @pdf.dict_get(dict, "W") {
    Some(value) =>
      match page.resolve(value).as_array() {
        Some(items) => {
          let mut i = 0
          while i < items.length() {
            let first = match items[i].as_int() {
              Some(n) => n
              None => -1
            }
            if first >= 0 && i + 1 < items.length() {
              match page.resolve(items[i + 1]) {
                @pdf.Array(values) => {
                  let mut j = 0
                  while j < values.length() {
                    let width = match page.resolve(values[j]).as_number() {
                      Some(n) => n.to_int()
                      None => default_width
                    }
                    out.push((first + j, width))
                    j = j + 1
                  }
                  i = i + 2
                }
                _ =>
                  if i + 2 < items.length() {
                    let last = match items[i + 1].as_int() {
                      Some(n) => n
                      None => first
                    }
                    let width = match page.resolve(items[i + 2]).as_number() {
                      Some(n) => n.to_int()
                      None => default_width
                    }
                    let mut cid = first
                    while cid <= last {
                      out.push((cid, width))
                      cid = cid + 1
                    }
                    i = i + 3
                  } else {
                    i = i + 1
                  }
              }
            } else {
              i = i + 1
            }
          }
        }
        None => ()
      }
    None => ()
  }
  out
}

///|
fn parse_cid_to_gid(
  page : @pdf.PdfPage,
  dict : Array[(String, @pdf.PdfValue)],
) -> Array[Int32]? {
  match @pdf.dict_get(dict, "CIDToGIDMap") {
    Some(@pdf.Name("Identity")) => None
    Some(value) =>
      match page.resolve(value) {
        @pdf.Stream(stream) => {
          let data = @pdf.decode_stream(stream) catch { _ => return None }
          let count = data.length() / 2
          let map : Array[Int32] = Array::make(count, 0)
          let mut i = 0
          while i < count {
            map[i] = u16(data, i * 2) catch { _ => 0 }
            i = i + 1
          }
          Some(map)
        }
        _ => None
      }
    None => None
  }
}

///|
fn parse_type0_encoding(
  page : @pdf.PdfPage,
  dict : Array[(String, @pdf.PdfValue)],
) -> (Int32, Array[(Int32, Int32)]) {
  match @pdf.dict_get(dict, "Encoding") {
    Some(@pdf.Name("Identity-H")) => (2, [])
    Some(@pdf.Name(name)) =>
      match named_cmap(name) {
        Some(cmap) => (cmap.code_bytes, cmap.expand())
        None => (2, [])
      }
    Some(value) =>
      match page.resolve(value) {
        @pdf.Stream(stream) => {
          let data = @pdf.decode_stream(stream) catch { _ => return (2, []) }
          let cmap = parse_cmap_data(data) catch { _ => return (2, []) }
          (cmap.code_bytes, cmap.map)
        }
        _ => (2, [])
      }
    None => (2, [])
  }
}

///|
fn load_type0_font(
  page : @pdf.PdfPage,
  dict : Array[(String, @pdf.PdfValue)],
) -> PdfFont? {
  let descendant = match @pdf.dict_get(dict, "DescendantFonts") {
    Some(value) =>
      match page.resolve(value).as_array() {
        Some(items) =>
          if items.length() > 0 {
            page.resolve_dict(items[0])
          } else {
            []
          }
        None => []
      }
    None => []
  }
  if descendant.length() == 0 {
    return None
  }
  let descriptor = match @pdf.dict_get(descendant, "FontDescriptor") {
    Some(value) => page.resolve_dict(value)
    None => []
  }
  let tt = load_truetype(page, descriptor, "FontFile2")
  let cff = match tt {
    Some(_) => None
    None => load_cff(page, descriptor, "FontFile3")
  }
  match (tt, cff) {
    (None, None) => return None
    _ => ()
  }
  let base_name = match @pdf.dict_get(dict, "BaseFont") {
    Some(value) =>
      match value.as_name() {
        Some(name) => name
        None => ""
      }
    None => ""
  }
  let default_width = match font_dict_int(page, descendant, "DW") {
    Some(n) => n
    None => 1000
  }
  let cid_widths = parse_cid_widths(page, descendant, default_width)
  let cid_to_gid = parse_cid_to_gid(page, descendant)
  let (code_bytes, code_to_cid) = parse_type0_encoding(page, dict)
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
    type1: None,
    widths: [],
    cid_widths,
    cid_to_gid,
    code_to_cid,
    code_bytes,
    two_byte: true,
    first_char: 0,
    missing_width: default_width,
    ascent,
    descent,
    standard: false,
    kern: [],
  })
}

///|
fn parse_type1_opt(data : Bytes) -> Type1Font? {
  Some(parse_type1(data)) catch {
    _ => None
  }
}

///|
pub fn load_pdf_font(page : @pdf.PdfPage, value : @pdf.PdfValue) -> PdfFont? {
  let dict = page.resolve_dict(value)
  if dict.length() == 0 {
    return None
  }
  let subtype = match @pdf.dict_get(dict, "Subtype") {
    Some(value) => value.as_name()
    None => None
  }
  if subtype == Some("Type0") {
    return load_type0_font(page, dict)
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
  let type1 : Type1Font? = match (tt, cff) {
    (None, None) =>
      match @pdf.dict_get(descriptor, "FontFile") {
        Some(value) =>
          match page.resolve(value) {
            @pdf.Stream(stream) => {
              let data = @pdf.decode_stream(stream) catch { _ => return None }
              parse_type1_opt(data)
            }
            _ => None
          }
        None => None
      }
    _ => None
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
  match (tt, cff, type1) {
    (None, None, None) => standard = true
    _ => ()
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
  let kern = if standard {
    match standard14_kerning(base_name) {
      Some(pairs) => pairs
      None => []
    }
  } else {
    []
  }
  Some({
    base_name,
    tt,
    cff,
    type1,
    widths,
    cid_widths: [],
    cid_to_gid: None,
    code_to_cid: [],
    code_bytes: 1,
    two_byte: false,
    first_char,
    missing_width,
    ascent,
    descent,
    standard,
    kern,
  })
}

///|
pub fn PdfFont::width_for(self : PdfFont, code : Int32) -> Int32 {
  if self.two_byte {
    for entry in self.cid_widths {
      if entry.0 == code {
        return entry.1
      }
    }
    return self.missing_width
  }
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
pub fn PdfFont::kern_for(self : PdfFont, left : Int32, right : Int32) -> Int32 {
  for entry in self.kern {
    if entry.0 == left && entry.1 == right {
      return entry.2
    }
  }
  0
}

///|
pub fn PdfFont::cid_for_code(self : PdfFont, code : Int32) -> Int32 {
  if self.two_byte {
    for entry in self.code_to_cid {
      if entry.0 == code {
        return entry.1
      }
    }
  }
  code
}

///|
pub fn PdfFont::glyph_for_code(self : PdfFont, code : Int32) -> Int32 {
  if self.two_byte {
    let cid = self.cid_for_code(code)
    match self.cid_to_gid {
      Some(map) => if cid >= 0 && cid < map.length() { map[cid] } else { 0 }
      None =>
        match self.cff {
          Some(cff) => cff.glyph_for_cid(cid)
          None => cid
        }
    }
  } else {
    match self.tt {
      Some(tt) => tt.glyph_id(code)
      None =>
        match self.cff {
          Some(cff) => {
            let glyph = if cff.is_cid {
              cff.glyph_for_cid(code)
            } else {
              cff.glyph_id(code)
            }
            glyph
          }
          None => 0
        }
    }
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
pub fn tt_glyph_path(
  font : TrueTypeFont,
  glyph : Int32,
  matrix : Matrix,
  size : Double,
) -> Path? {
  let contours = font.glyph_contours(glyph) catch { _ => return None }
  if contours.length() == 0 {
    return None
  }
  let units = font.units_per_em()
  if units <= 0 {
    return None
  }
  let scale = size / units.to_double()
  let path = Path::new()
  for contour in contours {
    append_contour(path, contour, matrix, scale)
  }
  Some(path)
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

///|
pub fn draw_type1_glyph(
  canvas : Canvas,
  font : Type1Font,
  name : String,
  matrix : Matrix,
  size : Double,
  r : Int32,
  g : Int32,
  b : Int32,
) -> Unit {
  let path = font.glyph_path(name, matrix, size) catch { _ => return }
  match path {
    Some(path) => {
      let (subpaths, _) = path.finish()
      canvas.fill_polygons(subpaths, false, r, g, b)
    }
    None => ()
  }
}
