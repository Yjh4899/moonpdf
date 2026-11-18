///|
/// CFF (Compact Font Format) reader and Type 2 charstring interpreter used for
/// PDF `/FontFile3` fonts. Non-CID CFF fonts are supported; CID-keyed CFF fonts
/// are rejected and fall back to the bitmap font.
pub struct CffFont {
  data : Bytes
  charstrings : Array[Bytes]
  gsubrs : Array[Bytes]
  lsubrs : Array[Bytes]
  units : Int32
  cmap_format : Int32
  cmap_sub : Int32
  seg_end : Array[Int32]
  seg_start : Array[Int32]
  seg_delta : Array[Int32]
  seg_range_pos : Array[Int32]
  groups : Array[(Int32, Int32, Int32)]
}

///|
fn cff_read_offset(data : Bytes, pos : Int32, size : Int32) -> Int32 {
  let mut value = 0
  let mut i = 0
  while i < size {
    value = (value << 8) | data.at(pos + i).to_int()
    i = i + 1
  }
  value
}

///|
fn cff_index(
  data : Bytes,
  start : Int32,
) -> (Array[Bytes], Int32) raise RenderError {
  let count = be_u16(data, start)
  if count == 0 {
    return ([], start + 2)
  }
  let off_size = data.at(start + 2).to_int()
  if off_size < 1 || off_size > 4 {
    raise RenderError("invalid CFF INDEX offSize")
  }
  let offsets : Array[Int32] = Array::make(count + 1, 0)
  let mut i = 0
  while i <= count {
    offsets[i] = cff_read_offset(data, start + 3 + i * off_size, off_size)
    i = i + 1
  }
  let data_start = start + 3 + (count + 1) * off_size
  let items : Array[Bytes] = Array(capacity=count)
  i = 0
  while i < count {
    let from = data_start + offsets[i] - 1
    let to = data_start + offsets[i + 1] - 1
    if from < 0 || to < from || to > data.length() {
      raise RenderError("CFF INDEX slice is out of range")
    }
    items.push(
      Bytes::from_array(data.exact_view(start=from, end=to).to_array()),
    )
    i = i + 1
  }
  (items, data_start + offsets[count] - 1)
}

///|
fn cff_real(data : Bytes, pos : Int32) -> (Double, Int32) {
  let buf = @buffer.Buffer::Buffer()
  let mut p = pos
  let mut done = false
  while p < data.length() && !done {
    let b = data.at(p).to_int()
    p = p + 1
    let nibbles = [b >> 4, b & 15]
    let mut n = 0
    while n < 2 && !done {
      let nib = nibbles[n]
      if nib == 15 {
        done = true
      } else if nib == 10 {
        buf.write_byte(u8(46))
      } else if nib == 11 {
        buf.write_byte(u8(69))
      } else if nib == 12 {
        buf.write_byte(u8(45))
      } else if nib == 14 {
        buf.write_byte(u8(45))
      } else {
        buf.write_byte(@utf8.encode("0123456789").at(nib))
      }
      n = n + 1
    }
  }
  let text = @utf8.decode_lossy(buf.to_bytes())
  let value = @string.parse_double(text) catch { _ => 0.0 }
  (value, p)
}

///|
fn cff_dict(
  data : Bytes,
  start : Int32,
  end : Int32,
) -> Array[(Int32, Array[Double])] raise RenderError {
  let out : Array[(Int32, Array[Double])] = []
  let stack : Array[Double] = []
  let mut p = start
  while p < end {
    let b = data.at(p).to_int()
    if b == 28 {
      stack.push(i16(data, p + 1).to_double())
      p = p + 3
    } else if b == 29 {
      stack.push(u32(data, p + 1).to_double())
      p = p + 5
    } else if b == 30 {
      let (value, next) = cff_real(data, p + 1)
      stack.push(value)
      p = next
    } else if b >= 32 && b <= 246 {
      stack.push((b - 139).to_double())
      p = p + 1
    } else if b >= 247 && b <= 250 {
      let next = data.at(p + 1).to_int()
      stack.push(((b - 247) * 256 + next + 108).to_double())
      p = p + 2
    } else if b >= 251 && b <= 254 {
      let next = data.at(p + 1).to_int()
      stack.push((-(b - 251) * 256 - next - 108).to_double())
      p = p + 2
    } else if b == 12 {
      let op = 1200 + data.at(p + 1).to_int()
      out.push((op, stack.copy()))
      stack.clear()
      p = p + 2
    } else {
      out.push((b, stack.copy()))
      stack.clear()
      p = p + 1
    }
  }
  out
}

///|
fn cff_dict_get(
  dict : Array[(Int32, Array[Double])],
  op : Int32,
) -> Array[Double]? {
  for entry in dict {
    if entry.0 == op {
      return Some(entry.1)
    }
  }
  None
}

///|
pub fn parse_cff(data : Bytes) -> CffFont raise RenderError {
  let cff = table_offset(data, "CFF ")
  let base = cff.0
  if base + 4 > data.length() {
    raise RenderError("CFF table is truncated")
  }
  let hdr_size = data.at(base + 2).to_int()
  let (names, after_names) = cff_index(data, base + hdr_size)
  if names.length() == 0 {
    raise RenderError("CFF has no name")
  }
  let (top_dicts, after_top) = cff_index(data, after_names)
  if top_dicts.length() == 0 {
    raise RenderError("CFF has no top DICT")
  }
  let (_, after_strings) = cff_index(data, after_top)
  let (gsubrs, _) = cff_index(data, after_strings)
  let top_dict = cff_dict(top_dicts[0], 0, top_dicts[0].length())
  let charstrings_offset = match cff_dict_get(top_dict, 17) {
    Some(values) =>
      if values.length() > 0 {
        values[values.length() - 1].to_int()
      } else {
        raise RenderError("CFF has no CharStrings offset")
      }
    None => raise RenderError("CFF has no CharStrings operator")
  }
  let (charstrings, _) = cff_index(data, base + charstrings_offset)
  let mut lsubrs : Array[Bytes] = []
  match cff_dict_get(top_dict, 18) {
    Some(values) =>
      if values.length() >= 2 {
        let size = values[values.length() - 2].to_int()
        let offset = values[values.length() - 1].to_int()
        let private_start = base + offset
        let private_end = private_start + size
        if private_end <= data.length() {
          let private_dict = cff_dict(data, private_start, private_end)
          match cff_dict_get(private_dict, 19) {
            Some(subrs) =>
              if subrs.length() > 0 {
                let subrs_offset = subrs[subrs.length() - 1].to_int()
                let (items, _) = cff_index(data, private_start + subrs_offset)
                lsubrs = items
              }
            None => ()
          }
        }
      }
    None => ()
  }
  let head = table_offset(data, "head")
  let units = u16(data, head.0 + 18)
  let cmap = table_offset(data, "cmap")
  let (
    cmap_format,
    cmap_sub,
    seg_end,
    seg_start,
    seg_delta,
    seg_range_pos,
    groups,
  ) = parse_cmap(data, cmap.0)
  {
    data,
    charstrings,
    gsubrs,
    lsubrs,
    units,
    cmap_format,
    cmap_sub,
    seg_end,
    seg_start,
    seg_delta,
    seg_range_pos,
    groups,
  }
}

///|
pub fn CffFont::glyph_id(self : CffFont, code : Int32) -> Int32 {
  cmap_glyph_id(
    self.data,
    self.cmap_format,
    self.cmap_sub,
    self.seg_end,
    self.seg_start,
    self.seg_delta,
    self.seg_range_pos,
    self.groups,
    code,
  )
}

///|
fn cff_bias(count : Int32) -> Int32 {
  if count < 1240 {
    107
  } else if count < 33900 {
    1131
  } else {
    32768
  }
}

///|
priv struct CffState {
  font : CffFont
  path : Path
  mut x : Double
  mut y : Double
  stack : Array[Double]
  mut hints : Int32
  mut open : Bool
}

///|
fn cff_number(cs : Bytes, pos : Int32) -> (Double, Int32) raise RenderError {
  let b = cs.at(pos).to_int()
  if b == 28 {
    (i16(cs, pos + 1).to_double(), pos + 3)
  } else if b == 255 {
    (u32(cs, pos + 1).to_double() / 65536.0, pos + 5)
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
    raise RenderError("invalid CFF charstring number")
  }
}

///|
fn cff_move(state : CffState, dx : Double, dy : Double) -> Unit {
  if state.open {
    state.path.close()
  }
  state.x = state.x + dx
  state.y = state.y + dy
  state.path.move_to({ x: state.x, y: state.y, })
  state.open = true
}

///|
fn cff_curve(
  state : CffState,
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
fn cff_run(
  cs : Bytes,
  state : CffState,
  depth : Int32,
) -> Unit raise RenderError {
  if depth > 16 {
    raise RenderError("CFF charstring recursion is too deep")
  }
  let stack = state.stack
  let mut p = 0
  while p < cs.length() {
    let b = cs.at(p).to_int()
    if b >= 32 || b == 28 || b == 255 {
      let (value, next) = cff_number(cs, p)
      stack.push(value)
      p = next
      continue
    }
    p = p + 1
    if b == 12 {
      let op = cs.at(p).to_int()
      p = p + 1
      if op == 35 && stack.length() >= 13 {
        // flex: six control/end points and a flex depth.
        let base = stack.length() - 13
        cff_curve(
          state,
          stack[base],
          stack[base + 1],
          stack[base + 2],
          stack[base + 3],
          stack[base + 4],
          stack[base + 5],
        )
        cff_curve(
          state,
          stack[base + 6],
          stack[base + 7],
          stack[base + 8],
          stack[base + 9],
          stack[base + 10],
          stack[base + 11],
        )
      } else if op == 34 && stack.length() >= 7 {
        let base = stack.length() - 7
        cff_curve(
          state,
          stack[base],
          0.0,
          stack[base + 1],
          stack[base + 2],
          stack[base + 3],
          0.0,
        )
        cff_curve(
          state,
          stack[base + 4],
          0.0,
          stack[base + 5],
          -stack[base + 2],
          stack[base + 6],
          0.0,
        )
      } else if op == 36 && stack.length() >= 9 {
        let base = stack.length() - 9
        cff_curve(
          state,
          stack[base],
          0.0,
          stack[base + 1],
          stack[base + 2],
          stack[base + 3],
          0.0,
        )
        cff_curve(
          state,
          stack[base + 4],
          0.0,
          stack[base + 5],
          stack[base + 6],
          stack[base + 7],
          stack[base + 8],
        )
      } else if op == 37 && stack.length() >= 11 {
        let base = stack.length() - 11
        cff_curve(
          state,
          stack[base],
          stack[base + 1],
          stack[base + 2],
          stack[base + 3],
          stack[base + 4],
          stack[base + 5],
        )
        cff_curve(
          state,
          stack[base + 6],
          stack[base + 7],
          stack[base + 8],
          stack[base + 9],
          0.0,
          0.0,
        )
      }
      stack.clear()
      continue
    }
    match b {
      1 | 3 | 18 | 23 => {
        state.hints = state.hints + (stack.length() / 2).to_int()
        stack.clear()
      }
      19 | 20 => {
        if stack.length() > 0 {
          state.hints = state.hints + (stack.length() / 2).to_int()
          stack.clear()
        }
        p = p + (state.hints + 7) / 8
      }
      4 => {
        if stack.length() >= 1 {
          let dy = stack[stack.length() - 1]
          cff_move(state, 0.0, dy)
        }
        stack.clear()
      }
      21 => {
        if stack.length() >= 2 {
          let n = stack.length()
          cff_move(state, stack[n - 2], stack[n - 1])
        }
        stack.clear()
      }
      22 => {
        if stack.length() >= 1 {
          cff_move(state, stack[stack.length() - 1], 0.0)
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
          cff_curve(
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
      24 => {
        let mut i = 0
        while i + 7 < stack.length() {
          cff_curve(
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
        if i + 1 < stack.length() {
          let nx = state.x + stack[i]
          let ny = state.y + stack[i + 1]
          state.path.line_to({ x: nx, y: ny, })
          state.x = nx
          state.y = ny
        }
        stack.clear()
      }
      25 => {
        let mut i = 0
        let line_end = stack.length() - 6
        while i + 1 < line_end {
          let nx = state.x + stack[i]
          let ny = state.y + stack[i + 1]
          state.path.line_to({ x: nx, y: ny, })
          state.x = nx
          state.y = ny
          i = i + 2
        }
        if i + 5 < stack.length() {
          cff_curve(
            state,
            stack[i],
            stack[i + 1],
            stack[i + 2],
            stack[i + 3],
            stack[i + 4],
            stack[i + 5],
          )
        }
        stack.clear()
      }
      26 => {
        let mut i = 0
        let mut dx1 = 0.0
        if stack.length() % 4 != 0 {
          dx1 = stack[0]
          i = 1
        }
        while i + 3 < stack.length() {
          cff_curve(
            state,
            dx1,
            stack[i],
            stack[i + 1],
            stack[i + 2],
            0.0,
            stack[i + 3],
          )
          dx1 = 0.0
          i = i + 4
        }
        stack.clear()
      }
      27 => {
        let mut i = 0
        let mut dy1 = 0.0
        if stack.length() % 4 != 0 {
          dy1 = stack[0]
          i = 1
        }
        while i + 3 < stack.length() {
          cff_curve(
            state,
            stack[i],
            dy1,
            stack[i + 1],
            stack[i + 2],
            stack[i + 3],
            0.0,
          )
          dy1 = 0.0
          i = i + 4
        }
        stack.clear()
      }
      30 | 31 => {
        let mut i = 0
        let mut horizontal = b == 31
        while i + 3 < stack.length() {
          if horizontal {
            cff_curve(
              state,
              stack[i],
              0.0,
              stack[i + 1],
              stack[i + 2],
              0.0,
              stack[i + 3],
            )
          } else {
            cff_curve(
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
      10 =>
        if stack.length() > 0 {
          let index = match stack.pop() {
            Some(value) => value.to_int() + cff_bias(state.font.lsubrs.length())
            None => -1
          }
          if index >= 0 && index < state.font.lsubrs.length() {
            cff_run(state.font.lsubrs[index], state, depth + 1)
          }
        }
      29 =>
        if stack.length() > 0 {
          let index = match stack.pop() {
            Some(value) => value.to_int() + cff_bias(state.font.gsubrs.length())
            None => -1
          }
          if index >= 0 && index < state.font.gsubrs.length() {
            cff_run(state.font.gsubrs[index], state, depth + 1)
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
pub fn CffFont::glyph_path(
  self : CffFont,
  glyph : Int32,
  matrix : Matrix,
  size : Double,
) -> Path? raise RenderError {
  if glyph < 0 || glyph >= self.charstrings.length() {
    return None
  }
  let state = {
    font: self,
    path: Path::new(),
    x: 0.0,
    y: 0.0,
    stack: [],
    hints: 0,
    open: false,
  }
  cff_run(self.charstrings[glyph], state, 0)
  // The charstring produced font-unit coordinates; apply the text matrix and
  // font size in a second pass over the subpaths.
  let (subpaths, closed) = state.path.finish()
  let scale = if self.units > 0 {
    size / self.units.to_double()
  } else {
    size / 1000.0
  }
  let transformed = Path::new()
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
