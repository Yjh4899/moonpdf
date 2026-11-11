///|
/// Byte cursor and object parser for the PDF syntax layer.
///
/// The parser is intentionally strict: malformed input raises `PdfError`
/// rather than being silently repaired. Repair policies belong in a separate,
/// explicit recovery layer.
priv struct Parser {
  data : Bytes
  mut pos : Int32
}

///|
fn Parser::new(data : Bytes) -> Parser {
  { data, pos: 0, }
}

///|
fn Parser::at_end(self : Parser) -> Bool {
  self.pos >= self.data.length()
}

///|
fn Parser::peek(self : Parser) -> Int32? {
  match self.data.get(self.pos) {
    Some(b) => Some(b.to_int())
    None => None
  }
}

///|
fn Parser::peek_at(self : Parser, offset : Int32) -> Int32? {
  match self.data.get(self.pos + offset) {
    Some(b) => Some(b.to_int())
    None => None
  }
}

///|
fn is_white(b : Int32) -> Bool {
  b == 0 || b == 9 || b == 10 || b == 12 || b == 13 || b == 32
}

///|
fn is_delimiter(b : Int32) -> Bool {
  is_white(b) ||
  b == 40 ||
  b == 41 ||
  b == 60 ||
  b == 62 ||
  b == 91 ||
  b == 93 ||
  b == 123 ||
  b == 125 ||
  b == 47 ||
  b == 37
}

///|
fn u8(value : Int32) -> Byte {
  value.to_byte()
}

///|
fn Parser::skip_ws(self : Parser) -> Unit {
  while !self.at_end() {
    let b = self.data.at(self.pos).to_int()
    if is_white(b) {
      self.pos = self.pos + 1
    } else if b == 37 {
      while !self.at_end() {
        let c = self.data.at(self.pos).to_int()
        if c == 10 || c == 13 {
          break
        }
        self.pos = self.pos + 1
      }
    } else {
      break
    }
  }
}

///|
fn Parser::starts_with(self : Parser, text : String) -> Bool {
  let needle = @utf8.encode(text)
  if self.pos + needle.length() > self.data.length() {
    return false
  }
  let mut i = 0
  while i < needle.length() {
    if self.data.at(self.pos + i) != needle.at(i) {
      return false
    }
    i = i + 1
  }
  true
}

///|
fn Parser::consume(self : Parser, text : String) -> Bool {
  if self.starts_with(text) {
    self.pos = self.pos + @utf8.encode(text).length()
    true
  } else {
    false
  }
}

///|
fn hex_value(b : Int32) -> Int32? {
  if b >= 48 && b <= 57 {
    Some(b - 48)
  } else if b >= 65 && b <= 70 {
    Some(b - 55)
  } else if b >= 97 && b <= 102 {
    Some(b - 87)
  } else {
    None
  }
}

///|
fn Parser::parse_name(self : Parser) -> String raise PdfError {
  if !self.consume("/") {
    raise PdfError("expected name")
  }
  let buf = @buffer.Buffer::Buffer()
  while !self.at_end() {
    let b = self.data.at(self.pos).to_int()
    if is_delimiter(b) {
      break
    } else if b == 35 {
      let hi = match self.peek_at(1) {
        Some(v) => hex_value(v)
        None => None
      }
      let lo = match self.peek_at(2) {
        Some(v) => hex_value(v)
        None => None
      }
      match (hi, lo) {
        (Some(h), Some(l)) => {
          buf.write_byte((h * 16 + l).to_byte())
          self.pos = self.pos + 3
        }
        _ => raise PdfError("invalid # escape in name")
      }
    } else {
      buf.write_byte(b.to_byte())
      self.pos = self.pos + 1
    }
  }
  @utf8.decode_lossy(buf.to_bytes())
}

///|
fn Parser::parse_literal_string(self : Parser) -> Bytes raise PdfError {
  if !self.consume("(") {
    raise PdfError("expected literal string")
  }
  let buf = @buffer.Buffer::Buffer()
  let mut depth = 1
  while !self.at_end() {
    let b = self.data.at(self.pos).to_int()
    self.pos = self.pos + 1
    if b == 92 {
      if self.at_end() {
        break
      }
      let e = self.data.at(self.pos).to_int()
      self.pos = self.pos + 1
      match e {
        110 => buf.write_byte(u8(10))
        114 => buf.write_byte(u8(13))
        116 => buf.write_byte(u8(9))
        98 => buf.write_byte(u8(8))
        102 => buf.write_byte(u8(12))
        40 => buf.write_byte(u8(40))
        41 => buf.write_byte(u8(41))
        92 => buf.write_byte(u8(92))
        10 => ()
        13 =>
          if !self.at_end() && self.data.at(self.pos).to_int() == 10 {
            self.pos = self.pos + 1
          }
        _ =>
          if e >= 48 && e <= 55 {
            let mut value = e - 48
            let mut count = 1
            while count < 3 && !self.at_end() {
              let d = self.data.at(self.pos).to_int()
              if d >= 48 && d <= 55 {
                value = value * 8 + (d - 48)
                self.pos = self.pos + 1
                count = count + 1
              } else {
                break
              }
            }
            buf.write_byte((value % 256).to_byte())
          } else {
            buf.write_byte(e.to_byte())
          }
      }
    } else if b == 40 {
      depth = depth + 1
      buf.write_byte(b.to_byte())
    } else if b == 41 {
      depth = depth - 1
      if depth == 0 {
        break
      }
      buf.write_byte(b.to_byte())
    } else {
      buf.write_byte(b.to_byte())
    }
  }
  if depth != 0 {
    raise PdfError("unterminated literal string")
  }
  buf.to_bytes()
}

///|
fn Parser::parse_hex_string(self : Parser) -> Bytes raise PdfError {
  if !self.consume("<") {
    raise PdfError("expected hex string")
  }
  let buf = @buffer.Buffer::Buffer()
  let mut high = -1
  while !self.at_end() {
    let b = self.data.at(self.pos).to_int()
    self.pos = self.pos + 1
    if b == 62 {
      break
    }
    if is_white(b) {
      continue
    }
    match hex_value(b) {
      Some(v) =>
        if high < 0 {
          high = v
        } else {
          buf.write_byte((high * 16 + v).to_byte())
          high = -1
        }
      None => raise PdfError("invalid hex digit")
    }
  }
  if high >= 0 {
    buf.write_byte((high * 16).to_byte())
  }
  buf.to_bytes()
}

///|
fn Parser::parse_number(self : Parser) -> (Double, Bool) raise PdfError {
  let buf = @buffer.Buffer::Buffer()
  let mut is_real = false
  while !self.at_end() {
    let b = self.data.at(self.pos).to_int()
    let is_digit = b >= 48 && b <= 57
    let is_sign = b == 43 || b == 45
    let is_dot = b == 46
    let is_exp = b == 69 || b == 101
    if is_digit || is_sign || is_dot || is_exp {
      if is_dot || is_exp {
        is_real = true
      }
      buf.write_byte(b.to_byte())
      self.pos = self.pos + 1
    } else {
      break
    }
  }
  let text = @utf8.decode_lossy(buf.to_bytes())
  if text.length() == 0 {
    raise PdfError("expected number")
  }
  let value = @string.parse_double(text) catch {
    _ => raise PdfError("invalid number: \{text}")
  }
  (value, !is_real)
}

///|
fn Parser::try_parse_int(self : Parser) -> Int32? {
  let save = self.pos
  self.skip_ws()
  let mut sign = 1
  match self.peek() {
    Some(45) => {
      sign = -1
      self.pos = self.pos + 1
    }
    Some(43) => self.pos = self.pos + 1
    _ => ()
  }
  let mut digits = 0
  let mut value = 0
  while !self.at_end() {
    let b = self.data.at(self.pos).to_int()
    if b >= 48 && b <= 57 {
      value = value * 10 + (b - 48)
      self.pos = self.pos + 1
      digits = digits + 1
    } else {
      break
    }
  }
  if digits == 0 {
    self.pos = save
    None
  } else {
    Some(sign * value)
  }
}

///|
fn Parser::parse_value(self : Parser) -> PdfValue raise PdfError {
  self.skip_ws()
  match self.peek() {
    None => raise PdfError("unexpected end of input")
    Some(47) => Name(self.parse_name())
    Some(40) => Str(self.parse_literal_string())
    Some(91) => {
      self.pos = self.pos + 1
      let items : Array[PdfValue] = Array(capacity=8)
      while true {
        self.skip_ws()
        if self.consume("]") {
          break
        }
        if self.at_end() {
          raise PdfError("unterminated array")
        }
        items.push(self.parse_value())
      }
      Array(items)
    }
    Some(60) =>
      if self.peek_at(1) == Some(60) {
        self.pos = self.pos + 2
        let items : Array[(String, PdfValue)] = Array(capacity=8)
        while true {
          self.skip_ws()
          if self.consume(">>") {
            break
          }
          if self.at_end() {
            raise PdfError("unterminated dictionary")
          }
          self.skip_ws()
          let key = self.parse_name()
          let value = self.parse_value()
          items.push((key, value))
        }
        Dict(items)
      } else {
        Str(self.parse_hex_string())
      }
    Some(116) =>
      if self.consume("true") {
        Bool(true)
      } else {
        raise PdfError("unexpected token")
      }
    Some(102) =>
      if self.consume("false") {
        Bool(false)
      } else {
        raise PdfError("unexpected token")
      }
    Some(110) =>
      if self.consume("null") {
        Null
      } else {
        raise PdfError("unexpected token")
      }
    Some(_) => {
      let (value, is_int) = self.parse_number()
      if is_int {
        let n = value.to_int()
        let save = self.pos
        self.skip_ws()
        match self.try_parse_int() {
          Some(gen) => {
            self.skip_ws()
            if self.consume("R") {
              return Ref(n, gen)
            }
          }
          None => ()
        }
        self.pos = save
        Int(n)
      } else {
        Real(value)
      }
    }
  }
}

///|
/// Parse a top-level `N G obj ... endobj` object starting at `offset`.
pub fn parse_indirect_object(
  data : Bytes,
  offset : Int32,
) -> (Int32, Int32, PdfValue) raise PdfError {
  let p = Parser::new(data)
  p.pos = offset
  let num = match p.try_parse_int() {
    Some(n) => n
    None => raise PdfError("expected object number at offset \{offset}")
  }
  let gen = match p.try_parse_int() {
    Some(g) => g
    None => raise PdfError("expected generation number")
  }
  p.skip_ws()
  if !p.consume("obj") {
    raise PdfError("expected 'obj'")
  }
  let value = p.parse_value()
  p.skip_ws()
  if p.consume("stream") {
    let dict = match value {
      Dict(d) => d
      _ => raise PdfError("stream without dictionary")
    }
    if p.peek() == Some(13) {
      p.pos = p.pos + 1
    }
    if p.peek() == Some(10) {
      p.pos = p.pos + 1
    }
    let start = p.pos
    let needle = @utf8.encode("endstream")
    let mut found = -1
    let mut i = start
    while i + 9 <= data.length() {
      let mut same = true
      let mut j = 0
      while j < 9 {
        if data.at(i + j) != needle.at(j) {
          same = false
          break
        }
        j = j + 1
      }
      if same {
        found = i
        break
      }
      i = i + 1
    }
    if found < 0 {
      raise PdfError("missing endstream")
    }
    let mut stop = found
    if stop > start && data.at(stop - 1).to_int() == 10 {
      stop = stop - 1
    }
    if stop > start && data.at(stop - 1).to_int() == 13 {
      stop = stop - 1
    }
    let bytes = Bytes::from_array(data.exact_view(start~, end=stop).to_array())
    (num, gen, Stream({ dict, data: bytes, }))
  } else {
    (num, gen, value)
  }
}

///|
pub fn parse_value_from_bytes(data : Bytes) -> PdfValue raise PdfError {
  let p = Parser::new(data)
  p.parse_value()
}
