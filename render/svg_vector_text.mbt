///|
fn svg_glyph_path(
  font : PdfFont,
  code : Int32,
  matrix : Matrix,
  size : Double,
) -> Path? {
  let glyph = font.glyph_for_code(code)
  if glyph > 0 {
    match font.tt {
      Some(tt) => tt_glyph_path(tt, glyph, matrix, size)
      None =>
        match font.cff {
          Some(cff) => cff.glyph_path(glyph, matrix, size) catch { _ => None }
          None => None
        }
    }
  } else {
    match font.type1 {
      Some(t1) => {
        let (name, ok) = t1_glyph_name(code)
        if ok {
          t1.glyph_path(name, matrix, size) catch {
            _ => None
          }
        } else {
          None
        }
      }
      None => None
    }
  }
}

///|
fn svg_show_text(
  body : @buffer.Buffer,
  state : SvgState,
  text : TextState,
  bytes : Bytes,
) -> Bool {
  let font = match text.font {
    Some(font) => font
    None => return false
  }
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
  let mut drawn = false
  for code in codes {
    if previous >= 0 {
      let adjustment = font.kern_for(previous, code)
      if adjustment != 0 {
        text.matrix = Matrix::translate(
          adjustment.to_double() / 1000.0 * text.font_size * text.h_scale,
          0.0,
        ).then(text.matrix)
      }
    }
    let full = text.matrix.then(state.ctm)
    match svg_glyph_path(font, code, full, text.font_size) {
      Some(path) => {
        svg_paint(body, state, path, true, false, false)
        drawn = true
      }
      None => ()
    }
    let mut advance = font.width_for(font.cid_for_code(code)).to_double() /
      1000.0 *
      text.font_size +
      text.char_spacing
    if code == 32 {
      advance = advance + text.word_spacing
    }
    text.matrix = Matrix::translate(advance * text.h_scale, text.rise).then(
      text.matrix,
    )
    previous = code
  }
  if !drawn {
    for code in codes {
      if code != 32 {
        return false
      }
    }
  }
  true
}

///|
fn svg_show_text_array(
  body : @buffer.Buffer,
  state : SvgState,
  text : TextState,
  items : Array[@pdf.PdfValue],
) -> Bool {
  for item in items {
    match item {
      @pdf.Str(bytes) =>
        if !svg_show_text(body, state, text, bytes) {
          return false
        }
      @pdf.Int(n) => {
        let tx = -n.to_double() / 1000.0 * text.font_size * text.h_scale
        text.matrix = Matrix::translate(tx, 0.0).then(text.matrix)
      }
      @pdf.Real(n) => {
        let tx = -n / 1000.0 * text.font_size * text.h_scale
        text.matrix = Matrix::translate(tx, 0.0).then(text.matrix)
      }
      _ => ()
    }
  }
  true
}
