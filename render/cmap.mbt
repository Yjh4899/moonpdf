///|
/// A parsed Type0 encoding CMap. The renderer only needs the code width and the
/// code-to-CID ranges; generation-specific details are ignored.
pub struct ParsedCMap {
  code_bytes : Int32
  map : Array[(Int32, Int32)]
}

///|
fn cmap_white(value : Int32) -> Bool {
  value == 0 ||
  value == 9 ||
  value == 10 ||
  value == 12 ||
  value == 13 ||
  value == 32
}

///|
fn cmap_skip(data : Bytes, start : Int32) -> Int32 {
  let mut pos = start
  while pos < data.length() {
    if cmap_white(data.at(pos).to_int()) {
      pos = pos + 1
    } else if data.at(pos).to_int() == 37 {
      while pos < data.length() && data.at(pos).to_int() != 10 {
        pos = pos + 1
      }
    } else {
      break
    }
  }
  pos
}

///|
fn cmap_word(data : Bytes, start : Int32) -> (String, Int32) {
  let mut pos = cmap_skip(data, start)
  let begin = pos
  while pos < data.length() && !cmap_white(data.at(pos).to_int()) {
    pos = pos + 1
  }
  (@utf8.decode_lossy(data.exact_view(start=begin, end=pos)), pos)
}

///|
fn cmap_hex(
  data : Bytes,
  start : Int32,
) -> (Int32, Int32, Int32) raise RenderError {
  let mut pos = cmap_skip(data, start)
  if pos >= data.length() || data.at(pos).to_int() != 60 {
    raise RenderError("expected a CMap hex string")
  }
  pos = pos + 1
  let mut value = 0
  let mut digits = 0
  while pos < data.length() && data.at(pos).to_int() != 62 {
    let c = data.at(pos).to_int()
    let nibble = if c >= 48 && c <= 57 {
      c - 48
    } else if c >= 65 && c <= 70 {
      c - 55
    } else if c >= 97 && c <= 102 {
      c - 87
    } else {
      raise RenderError("invalid CMap hex digit")
    }
    value = (value << 4) | nibble
    digits = digits + 1
    pos = pos + 1
  }
  if pos >= data.length() {
    raise RenderError("unterminated CMap hex string")
  }
  (value, digits / 2, pos + 1)
}

///|
fn cmap_int(data : Bytes, start : Int32) -> (Int32, Int32) raise RenderError {
  let mut pos = cmap_skip(data, start)
  let begin = pos
  let mut value = 0
  while pos < data.length() {
    let c = data.at(pos).to_int()
    if c < 48 || c > 57 {
      break
    }
    value = value * 10 + (c - 48)
    pos = pos + 1
  }
  if pos == begin {
    raise RenderError("expected a CMap integer")
  }
  (value, pos)
}

///|
pub fn parse_cmap_data(data : Bytes) -> ParsedCMap raise RenderError {
  let map : Array[(Int32, Int32)] = []
  let mut code_bytes = 0
  let mut pos = 0
  while pos < data.length() {
    let (word, after) = cmap_word(data, pos)
    pos = after
    if word == "begincodespacerange" {
      let (_, bytes, next) = cmap_hex(data, pos)
      if bytes > code_bytes {
        code_bytes = bytes
      }
      pos = next
    } else if word == "begincidrange" {
      let mut done = false
      while !done {
        let (token, after_token) = cmap_word(data, pos)
        if token == "endcidrange" {
          pos = after_token
          done = true
        } else if token.length() == 0 {
          done = true
        } else {
          // The first token of a range line is a hex string, which the word
          // scanner reads as "<...>"; rewind and parse it properly.
          let (low, _, after_low) = cmap_hex(data, pos)
          let (high, _, after_high) = cmap_hex(data, after_low)
          let (cid, after_cid) = cmap_int(data, after_high)
          let mut code = low
          let mut count = 0
          while code <= high && count < 65536 {
            map.push((code, cid + (code - low)))
            code = code + 1
            count = count + 1
          }
          pos = after_cid
        }
      }
    } else if word == "begincidchar" {
      let mut done = false
      while !done {
        let (token, after_token) = cmap_word(data, pos)
        if token == "endcidchar" {
          pos = after_token
          done = true
        } else if token.length() == 0 {
          done = true
        } else {
          let (code, _, after_code) = cmap_hex(data, pos)
          let (cid, after_cid) = cmap_int(data, after_code)
          map.push((code, cid))
          pos = after_cid
        }
      }
    }
  }
  if code_bytes == 0 {
    code_bytes = 2
  }
  { code_bytes, map, }
}
