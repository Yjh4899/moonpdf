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
      ops.push({ operands: operands.copy(), op, })
      operands.clear()
    }
  }
  ops
}
