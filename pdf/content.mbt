///|
/// One content-stream operation: its operands and the operator keyword.
pub struct ContentOp {
  operands : Array[PdfValue]
  op : String
}

///|
fn Parser::read_keyword(self : Parser) -> String {
  let buf = @buffer.Buffer::Buffer()
  while !self.at_end() {
    let b = self.data.at(self.pos).to_int()
    if is_white(b) || is_delimiter(b) {
      break
    }
    buf.write_byte(b.to_byte())
    self.pos = self.pos + 1
  }
  @utf8.decode_lossy(buf.to_bytes())
}

///|
fn normalize_inline_key(key : String) -> String {
  match key {
    "W" => "Width"
    "H" => "Height"
    "BPC" => "BitsPerComponent"
    "CS" => "ColorSpace"
    "F" => "Filter"
    "DP" => "DecodeParms"
    "IM" => "ImageMask"
    "D" => "Decode"
    _ => key
  }
}

///|
fn normalize_inline_value(key : String, value : PdfValue) -> PdfValue {
  if key == "ColorSpace" {
    match value {
      Name("RGB") => Name("DeviceRGB")
      Name("G") => Name("DeviceGray")
      Name("CMYK") => Name("DeviceCMYK")
      _ => value
    }
  } else if key == "Filter" {
    match value {
      Name("Fl") => Name("FlateDecode")
      Name("AHx") => Name("ASCIIHexDecode")
      Name("A85") => Name("ASCII85Decode")
      Name("RL") => Name("RunLengthDecode")
      Name("DCT") => Name("DCTDecode")
      _ => value
    }
  } else {
    value
  }
}

///|
fn Parser::parse_inline_image(
  self : Parser,
) -> (Array[(String, PdfValue)], Bytes) raise PdfError {
  let dict : Array[(String, PdfValue)] = []
  let mut data_start = -1
  while true {
    self.skip_ws()
    match self.peek() {
      Some(47) => {
        let key = self.parse_name()
        let value = self.parse_value()
        let normalized_key = normalize_inline_key(key)
        dict.push(
          (normalized_key, normalize_inline_value(normalized_key, value)),
        )
      }
      Some(_) => {
        let keyword = self.read_keyword()
        if keyword == "ID" {
          if self.peek() == Some(13) {
            self.pos = self.pos + 1
            if self.peek() == Some(10) {
              self.pos = self.pos + 1
            }
          } else if (match self.peek() {
              Some(b) => is_white(b)
              None => false
            }) {
            self.pos = self.pos + 1
          }
          data_start = self.pos
          break
        } else {
          raise PdfError("invalid inline image dictionary")
        }
      }
      None => raise PdfError("invalid inline image dictionary")
    }
  }
  if data_start < 0 {
    raise PdfError("inline image has no ID marker")
  }
  let declared = match dict_get(dict, "L") {
    Some(Int(n)) => n
    _ =>
      match dict_get(dict, "Length") {
        Some(Int(n)) => n
        _ => -1
      }
  }
  if declared >= 0 && data_start + declared <= self.data.length() {
    let data = Bytes::from_array(
      self.data
      .exact_view(start=data_start, end=data_start + declared)
      .to_array(),
    )
    self.pos = data_start + declared
    self.skip_ws()
    if !self.consume("EI") {
      raise PdfError("inline image has no EI marker")
    }
    return (dict, data)
  }
  let mut end = -1
  let mut i = data_start
  while i + 1 < self.data.length() {
    if self.data.at(i).to_int() == 69 && self.data.at(i + 1).to_int() == 73 {
      let before_ok = i == data_start || is_white(self.data.at(i - 1).to_int())
      let after_ok = i + 2 >= self.data.length() ||
        is_white(self.data.at(i + 2).to_int())
      if before_ok && after_ok {
        end = i
        break
      }
    }
    i = i + 1
  }
  if end < 0 {
    raise PdfError("inline image has no EI delimiter")
  }
  let mut stop = end
  if stop > data_start && self.data.at(stop - 1).to_int() == 10 {
    stop = stop - 1
  }
  if stop > data_start && self.data.at(stop - 1).to_int() == 13 {
    stop = stop - 1
  }
  let data = Bytes::from_array(
    self.data.exact_view(start=data_start, end=stop).to_array(),
  )
  self.pos = end + 2
  (dict, data)
}

///|
/// Parse a content stream into operations. Operands are parsed with the same
/// syntax layer as document objects; a failed operand parse is treated as an
/// operator keyword.
pub fn parse_content_stream(data : Bytes) -> Array[ContentOp] raise PdfError {
  let p = Parser::new(data)
  let ops : Array[ContentOp] = Array(capacity=32)
  let operands : Array[PdfValue] = Array(capacity=8)
  while true {
    p.skip_ws()
    if p.at_end() {
      break
    }
    let save = p.pos
    let mut parsed = false
    let mut value = Null
    try {
      value = p.parse_value()
      parsed = true
    } catch {
      _ => p.pos = save
    }
    if parsed {
      operands.push(value)
    } else {
      let op = p.read_keyword()
      if op.length() == 0 {
        raise PdfError("empty operator at offset \{p.pos}")
      }
      if op == "BI" {
        let (dict, image_data) = p.parse_inline_image()
        ops.push({ operands: [Dict(dict), Str(image_data)], op: "BI", })
      } else {
        ops.push({ operands: operands.copy(), op, })
      }
      operands.clear()
    }
  }
  ops
}

///|
/// Construct a content operation for a synthesized operator (used by form
/// expansion in the renderer).
pub fn content_op(operands : Array[PdfValue], op : String) -> ContentOp {
  { operands, op, }
}
