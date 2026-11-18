///|
/// Type 1 font program reader and charstring interpreter for PDF `/FontFile`.
/// Supports PFB/PFA input, eexec and charstring decryption, local Subrs and the
/// core Type 1 drawing operators. `seac` composites fall back to the base glyph.
pub struct Type1Font {
  charstrings : Array[(String, Bytes)]
  subrs : Array[Bytes]
}

///|
fn t1_white(value : Int32) -> Bool {
  value == 0 ||
  value == 9 ||
  value == 10 ||
  value == 12 ||
  value == 13 ||
  value == 32
}

///|
fn t1_le32(data : Bytes, pos : Int32) -> Int32 {
  data.at(pos).to_int() |
  (data.at(pos + 1).to_int() << 8) |
  (data.at(pos + 2).to_int() << 16) |
  (data.at(pos + 3).to_int() << 24)
}

///|
fn t1_find(data : Bytes, needle : Bytes, start : Int32) -> Int32 {
  if needle.length() == 0 {
    return start
  }
  let mut i = start
  while i + needle.length() <= data.length() {
    let mut matched = true
    let mut j = 0
    while j < needle.length() {
      if data.at(i + j) != needle.at(j) {
        matched = false
        break
      }
      j = j + 1
    }
    if matched {
      return i
    }
    i = i + 1
  }
  -1
}

///|
fn t1_concat(parts : Array[Bytes]) -> Bytes {
  let buf = @buffer.Buffer::Buffer()
  for part in parts {
    buf.write_bytes(part)
  }
  buf.to_bytes()
}

///|
fn t1_decrypt(data : Bytes, seed : Int32, skip : Int32) -> Bytes {
  let out : Array[Byte] = Array(capacity=data.length())
  let mut r = seed
  for b in data.to_array() {
    let c = b.to_int()
    out.push((c ^ (r >> 8)).to_byte())
    r = ((c + r) * 52845 + 22719) & 0xFFFF
  }
  if skip >= out.length() {
    Bytes::make(0, u8(0))
  } else {
    let rest : Array[Byte] = []
    let mut i = skip
    while i < out.length() {
      rest.push(out[i])
      i = i + 1
    }
    Bytes::from_array(rest)
  }
}

///|
fn t1_extract(data : Bytes) -> (Bytes, Bytes) raise RenderError {
  if data.length() >= 2 && data.at(0).to_int() == 0x80 {
    let clear : Array[Bytes] = []
    let encrypted : Array[Bytes] = []
    let mut pos = 0
    while pos + 6 <= data.length() && data.at(pos).to_int() == 0x80 {
      let kind = data.at(pos + 1).to_int()
      let length = t1_le32(data, pos + 2)
      if length < 0 || pos + 6 + length > data.length() {
        raise RenderError("truncated Type 1 PFB segment")
      }
      let segment = Bytes::from_array(
        data.exact_view(start=pos + 6, end=pos + 6 + length).to_array(),
      )
      if kind == 1 {
        clear.push(segment)
      } else if kind == 2 {
        encrypted.push(segment)
      }
      pos = pos + 6 + length
    }
    if encrypted.length() == 0 {
      raise RenderError("Type 1 PFB has no encrypted segment")
    }
    (t1_concat(clear), t1_concat(encrypted))
  } else {
    let marker = t1_find(data, @utf8.encode("eexec"), 0)
    if marker < 0 {
      raise RenderError("Type 1 font has no eexec section")
    }
    let clear = Bytes::from_array(
      data.exact_view(start=0, end=marker).to_array(),
    )
    let encrypted = Bytes::from_array(
      data.exact_view(start=marker + 5, end=data.length()).to_array(),
    )
    (clear, encrypted)
  }
}

///|
fn t1_skip_ws(data : Bytes, start : Int32) -> Int32 {
  let mut pos = start
  while pos < data.length() && t1_white(data.at(pos).to_int()) {
    pos = pos + 1
  }
  pos
}

///|
fn t1_token(data : Bytes, start : Int32) -> (String, Int32) {
  let mut pos = t1_skip_ws(data, start)
  let begin = pos
  while pos < data.length() && !t1_white(data.at(pos).to_int()) {
    pos = pos + 1
  }
  (@utf8.decode_lossy(data.exact_view(start=begin, end=pos)), pos)
}

///|
fn t1_int(data : Bytes, start : Int32) -> (Int32, Int32) raise RenderError {
  let mut pos = t1_skip_ws(data, start)
  let mut sign = 1
  if pos < data.length() && data.at(pos).to_int() == 45 {
    sign = -1
    pos = pos + 1
  }
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
    raise RenderError("expected a Type 1 integer")
  }
  (value * sign, pos)
}

///|
fn t1_parse_subrs(
  data : Bytes,
  start : Int32,
  len_iv : Int32,
) -> Array[Bytes] raise RenderError {
  let (_, after_marker) = t1_token(data, start)
  let (count, after_count) = t1_int(data, after_marker)
  let mut pos = t1_skip_ws(data, after_count)
  let (array_token, after_array) = t1_token(data, pos)
  if array_token != "array" {
    raise RenderError("expected a Type 1 Subrs array")
  }
  pos = after_array
  let subrs : Array[Bytes] = Array(capacity=count)
  let mut i = 0
  while i < count {
    let (dup, after_dup) = t1_token(data, pos)
    if dup != "dup" {
      raise RenderError("expected a Type 1 Subrs entry")
    }
    let (_, after_index) = t1_int(data, after_dup)
    let (length, after_length) = t1_int(data, after_index)
    let (rd, after_rd) = t1_token(data, after_length)
    if rd != "RD" {
      raise RenderError("expected RD in Type 1 Subrs")
    }
    let mut data_start = after_rd
    if data_start < data.length() && t1_white(data.at(data_start).to_int()) {
      data_start = data_start + 1
    }
    if length < 0 || data_start + length > data.length() {
      raise RenderError("truncated Type 1 Subrs entry")
    }
    let raw = Bytes::from_array(
      data.exact_view(start=data_start, end=data_start + length).to_array(),
    )
    let (nd, after_nd) = t1_token(data, data_start + length)
    if nd != "NP" {
      raise RenderError("expected NP after Type 1 Subrs")
    }
    subrs.push(t1_decrypt(raw, 4330, len_iv))
    pos = after_nd
    i = i + 1
  }
  subrs
}

///|
fn t1_parse_charstrings(
  data : Bytes,
  start : Int32,
  len_iv : Int32,
) -> Array[(String, Bytes)] raise RenderError {
  let (_, after_marker) = t1_token(data, start)
  let (count, after_count) = t1_int(data, after_marker)
  let mut pos = t1_skip_ws(data, after_count)
  let (_, after_dict) = t1_token(data, pos)
  let (_, after_dup) = t1_token(data, after_dict)
  let (begin, after_begin) = t1_token(data, after_dup)
  if begin != "begin" {
    raise RenderError("expected Type 1 CharStrings begin")
  }
  pos = after_begin
  let out : Array[(String, Bytes)] = Array(capacity=count)
  let mut i = 0
  while i < count {
    pos = t1_skip_ws(data, pos)
    if pos >= data.length() || data.at(pos).to_int() != 47 {
      raise RenderError("expected a Type 1 glyph name")
    }
    let (name, after_name) = t1_token(data, pos + 1)
    let (length, after_length) = t1_int(data, after_name)
    let (rd, after_rd) = t1_token(data, after_length)
    if rd != "RD" {
      raise RenderError("expected RD in Type 1 CharStrings")
    }
    let mut data_start = after_rd
    if data_start < data.length() && t1_white(data.at(data_start).to_int()) {
      data_start = data_start + 1
    }
    if length < 0 || data_start + length > data.length() {
      raise RenderError("truncated Type 1 charstring")
    }
    let raw = Bytes::from_array(
      data.exact_view(start=data_start, end=data_start + length).to_array(),
    )
    let (nd, after_nd) = t1_token(data, data_start + length)
    if nd != "ND" {
      raise RenderError("expected ND after Type 1 charstring")
    }
    out.push((name, t1_decrypt(raw, 4330, len_iv)))
    pos = after_nd
    i = i + 1
  }
  out
}

///|
pub fn parse_type1(data : Bytes) -> Type1Font raise RenderError {
  let (_, encrypted) = t1_extract(data)
  let decrypted = t1_decrypt(encrypted, 55665, 4)
  let len_iv = match t1_find(decrypted, @utf8.encode("/lenIV"), 0) {
    -1 => 4
    marker => {
      let (value, _) = t1_int(decrypted, marker + 6)
      value
    }
  }
  let subrs_start = t1_find(decrypted, @utf8.encode("/Subrs"), 0)
  let subrs = if subrs_start >= 0 {
    t1_parse_subrs(decrypted, subrs_start, len_iv)
  } else {
    []
  }
  let charstrings_start = t1_find(decrypted, @utf8.encode("/CharStrings"), 0)
  if charstrings_start < 0 {
    raise RenderError("Type 1 font has no /CharStrings")
  }
  let charstrings = t1_parse_charstrings(decrypted, charstrings_start, len_iv)
  { charstrings, subrs, }
}

///|
fn t1_i32(data : Bytes, pos : Int32) -> Int32 {
  (data.at(pos).to_int() << 24) |
  (data.at(pos + 1).to_int() << 16) |
  (data.at(pos + 2).to_int() << 8) |
  data.at(pos + 3).to_int()
}

///|
fn t1_number(cs : Bytes, pos : Int32) -> (Double, Int32) raise RenderError {
  let b = cs.at(pos).to_int()
  if b == 28 {
    (i16(cs, pos + 1).to_double(), pos + 3)
  } else if b == 255 {
    (t1_i32(cs, pos + 1).to_double(), pos + 5)
  } else if b >= 32 && b <= 246 {
    ((b - 139).to_double(), pos + 1)
  } else if b >= 247 && b <= 250 {
    (
      (b - 247).to_double() * 256.0 +
      cs.at(pos + 1).to_int().to_double() +
      108.0,
      pos + 2,
    )
  } else if b >= 251 && b <= 254 {
    (
      -(b - 251).to_double() * 256.0 -
      cs.at(pos + 1).to_int().to_double() -
      108.0,
      pos + 2,
    )
  } else {
    raise RenderError("invalid Type 1 charstring number")
  }
}

///|
priv struct T1State {
  font : Type1Font
  path : Path
  mut x : Double
  mut y : Double
  stack : Array[Double]
  mut open : Bool
}

///|
fn t1_move(state : T1State, dx : Double, dy : Double) -> Unit {
  if state.open {
    state.path.close()
  }
  state.x = state.x + dx
  state.y = state.y + dy
  state.path.move_to({ x: state.x, y: state.y, })
  state.open = true
}

///|
fn t1_curve(
  state : T1State,
  dx1 : Double,
  dy1 : Double,
  dx2 : Double,
  dy2 : Double,
  dx3 : Double,
  dy3 : Double,
) -> Unit {
  let c1 = { x: state.x + dx1, y: state.y + dy1, }
  let c2 = { x: c1.x + dx2, y: c1.y + dy2, }
  let end = { x: c2.x + dx3, y: c2.y + dy3, }
  state.path.curve_to(c1, c2, end)
  state.x = end.x
  state.y = end.y
}

///|
fn t1_run(cs : Bytes, state : T1State, depth : Int32) -> Unit raise RenderError {
  if depth > 16 {
    raise RenderError("Type 1 charstring recursion is too deep")
  }
  let stack = state.stack
  let mut p = 0
  while p < cs.length() {
    let b = cs.at(p).to_int()
    if b >= 32 || b == 28 || b == 255 {
      let (value, next) = t1_number(cs, p)
      stack.push(value)
      p = next
      continue
    }
    p = p + 1
    if b == 12 {
      let op = cs.at(p).to_int()
      p = p + 1
      if op == 35 && stack.length() >= 13 {
        let base = stack.length() - 13
        t1_curve(
          state,
          stack[base],
          stack[base + 1],
          stack[base + 2],
          stack[base + 3],
          stack[base + 4],
          stack[base + 5],
        )
        t1_curve(
          state,
          stack[base + 6],
          stack[base + 7],
          stack[base + 8],
          stack[base + 9],
          stack[base + 10],
          stack[base + 11],
        )
      } else if op == 6 && stack.length() >= 5 {
        // seac: draw the base glyph; the accent is a later refinement.
        let base_code = stack[stack.length() - 2].to_int()
        let (name, _) = t1_glyph_name(base_code)
        for entry in state.font.charstrings {
          if entry.0 == name {
            t1_run(entry.1, state, depth + 1)
            break
          }
        }
        return
      } else if op == 7 && stack.length() >= 4 {
        state.x = stack[0]
        state.y = stack[1]
      }
      stack.clear()
      continue
    }
    match b {
      13 => {
        if stack.length() >= 2 {
          state.x = stack[0]
          state.y = 0.0
        }
        stack.clear()
      }
      21 => {
        if stack.length() >= 2 {
          let n = stack.length()
          t1_move(state, stack[n - 2], stack[n - 1])
        }
        stack.clear()
      }
      22 => {
        if stack.length() >= 1 {
          t1_move(state, stack[stack.length() - 1], 0.0)
        }
        stack.clear()
      }
      4 => {
        if stack.length() >= 1 {
          t1_move(state, 0.0, stack[stack.length() - 1])
        }
        stack.clear()
      }
      5 => {
        let mut i = 0
        while i + 1 < stack.length() {
          let nx = state.x + stack[i]
          let ny = state.y + stack[i + 1]
          state.path.line_to({ x: nx, y: ny, })
          state.x = nx
          state.y = ny
          i = i + 2
        }
        stack.clear()
      }
      6 | 7 => {
        let mut horizontal = b == 6
        for value in stack {
          if horizontal {
            state.x = state.x + value
          } else {
            state.y = state.y + value
          }
          state.path.line_to({ x: state.x, y: state.y, })
          horizontal = !horizontal
        }
        stack.clear()
      }
      8 => {
        let mut i = 0
        while i + 5 < stack.length() {
          t1_curve(
            state,
            stack[i],
            stack[i + 1],
            stack[i + 2],
            stack[i + 3],
            stack[i + 4],
            stack[i + 5],
          )
          i = i + 6
        }
        stack.clear()
      }
      30 | 31 => {
        let mut i = 0
        let mut horizontal = b == 31
        while i + 3 < stack.length() {
          if horizontal {
            t1_curve(
              state,
              stack[i],
              0.0,
              stack[i + 1],
              stack[i + 2],
              0.0,
              stack[i + 3],
            )
          } else {
            t1_curve(
              state,
              0.0,
              stack[i],
              stack[i + 1],
              stack[i + 2],
              stack[i + 3],
              0.0,
            )
          }
          horizontal = !horizontal
          i = i + 4
        }
        stack.clear()
      }
      9 => {
        if state.open {
          state.path.close()
          state.open = false
        }
        stack.clear()
      }
      10 =>
        if stack.length() > 0 {
          let index = stack.pop().unwrap_or(0.0).to_int()
          if index >= 0 && index < state.font.subrs.length() {
            t1_run(state.font.subrs[index], state, depth + 1)
          }
        }
      11 => return
      14 => {
        if state.open {
          state.path.close()
          state.open = false
        }
        stack.clear()
        return
      }
      _ => stack.clear()
    }
  }
}

///|
fn t1_glyph_name(code : Int32) -> (String, Bool) {
  if code >= 65 && code <= 90 {
    (@utf8.decode_lossy(Bytes::make(1, u8(code))), true)
  } else if code >= 97 && code <= 122 {
    (@utf8.decode_lossy(Bytes::make(1, u8(code))), true)
  } else if code >= 48 && code <= 57 {
    (
      match code {
        48 => "zero"
        49 => "one"
        50 => "two"
        51 => "three"
        52 => "four"
        53 => "five"
        54 => "six"
        55 => "seven"
        56 => "eight"
        _ => "nine"
      },
      true,
    )
  } else {
    (
      match code {
        32 => "space"
        33 => "exclam"
        34 => "quotedbl"
        35 => "numbersign"
        36 => "dollar"
        37 => "percent"
        38 => "ampersand"
        39 => "quoteright"
        40 => "parenleft"
        41 => "parenright"
        42 => "asterisk"
        43 => "plus"
        44 => "comma"
        45 => "hyphen"
        46 => "period"
        47 => "slash"
        58 => "colon"
        59 => "semicolon"
        60 => "less"
        61 => "equal"
        62 => "greater"
        63 => "question"
        64 => "at"
        91 => "bracketleft"
        92 => "backslash"
        93 => "bracketright"
        94 => "asciicircum"
        95 => "underscore"
        96 => "quoteleft"
        123 => "braceleft"
        124 => "bar"
        125 => "braceright"
        126 => "asciitilde"
        _ => ""
      },
      false,
    )
  }
}

///|
pub fn Type1Font::glyph_path(
  self : Type1Font,
  name : String,
  matrix : Matrix,
  size : Double,
) -> Path? raise RenderError {
  let mut found : Bytes? = None
  for entry in self.charstrings {
    if entry.0 == name {
      found = Some(entry.1)
      break
    }
  }
  let cs = match found {
    Some(cs) => cs
    None => return None
  }
  let state = {
    font: self,
    path: Path::new(),
    x: 0.0,
    y: 0.0,
    stack: [],
    open: false,
  }
  t1_run(cs, state, 0)
  let (subpaths, closed) = state.path.finish()
  let transformed = Path::new()
  let scale = size / 1000.0
  let mut i = 0
  while i < subpaths.length() {
    let points = subpaths[i]
    if points.length() > 0 {
      let first = points[0]
      transformed.move_to(matrix.apply(first.x * scale, first.y * scale))
      let mut j = 1
      while j < points.length() {
        let p = points[j]
        transformed.line_to(matrix.apply(p.x * scale, p.y * scale))
        j = j + 1
      }
      if closed[i] {
        transformed.close()
      }
    }
    i = i + 1
  }
  Some(transformed)
}
