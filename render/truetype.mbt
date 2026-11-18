///|
/// Minimal TrueType reader for embedded PDF fonts (`/FontFile2`).
///
/// The reader covers the tables needed for page rendering: `head`, `maxp`,
/// `loca`, `glyf`, `hmtx`, `hhea` and `cmap` formats 4/12. Composite glyphs and
/// CFF outlines are rejected with a fallback to the bitmap font.
pub struct TrueTypeFont {
  data : Bytes
  units_per_em : Int32
  num_glyphs : Int32
  loca : Array[Int32]
  glyf_offset : Int32
  hmtx_offset : Int32
  num_h_metrics : Int32
  ascent : Int32
  descent : Int32
  cmap_format : Int32
  cmap_sub : Int32
  seg_end : Array[Int32]
  seg_start : Array[Int32]
  seg_delta : Array[Int32]
  seg_range_pos : Array[Int32]
  groups : Array[(Int32, Int32, Int32)]
}

///|
fn u16(data : Bytes, offset : Int32) -> Int32 raise RenderError {
  if offset + 1 >= data.length() {
    raise RenderError("truncated TrueType table")
  }
  (data.at(offset).to_int() << 8) | data.at(offset + 1).to_int()
}

///|
fn i16(data : Bytes, offset : Int32) -> Int32 raise RenderError {
  let value = u16(data, offset)
  if value >= 0x8000 {
    value - 0x10000
  } else {
    value
  }
}

///|
fn u32(data : Bytes, offset : Int32) -> Int32 raise RenderError {
  if offset + 3 >= data.length() {
    raise RenderError("truncated TrueType table")
  }
  (data.at(offset).to_int() << 24) |
  (data.at(offset + 1).to_int() << 16) |
  (data.at(offset + 2).to_int() << 8) |
  data.at(offset + 3).to_int()
}

///|
fn tag(data : Bytes, offset : Int32) -> String {
  if offset + 3 >= data.length() {
    return ""
  }
  let buf = @buffer.Buffer::Buffer()
  let mut i = 0
  while i < 4 {
    buf.write_byte(data.at(offset + i))
    i = i + 1
  }
  @utf8.decode_lossy(buf.to_bytes())
}

///|
fn table_offset(
  data : Bytes,
  wanted : String,
) -> (Int32, Int32) raise RenderError {
  let count = u16(data, 4)
  let mut i = 0
  while i < count {
    let record = 12 + i * 16
    if tag(data, record) == wanted {
      return (u32(data, record + 8), u32(data, record + 12))
    }
    i = i + 1
  }
  raise RenderError("missing TrueType table \{wanted}")
}

///|
fn parse_cmap(
  data : Bytes,
  cmap_offset : Int32,
) -> (
  Int32,
  Int32,
  Array[Int32],
  Array[Int32],
  Array[Int32],
  Array[Int32],
  Array[(Int32, Int32, Int32)],
) raise RenderError {
  let count = u16(data, cmap_offset + 2)
  let mut chosen = -1
  let mut i = 0
  while i < count {
    let record = cmap_offset + 4 + i * 8
    let platform = u16(data, record)
    let encoding = u16(data, record + 2)
    let sub = cmap_offset + u32(data, record + 4)
    let format = u16(data, sub)
    let preferred = (platform == 3 && encoding == 1) || platform == 0
    if preferred && (format == 4 || format == 12) {
      chosen = sub
    }
    i = i + 1
  }
  if chosen < 0 {
    // Fall back to the first format 4/12 subtable.
    i = 0
    while i < count {
      let sub = cmap_offset + u32(data, cmap_offset + 4 + i * 8 + 4)
      let format = u16(data, sub)
      if format == 4 || format == 12 {
        chosen = sub
      }
      i = i + 1
    }
  }
  if chosen < 0 {
    raise RenderError("TrueType cmap has no supported subtable")
  }
  let format = u16(data, chosen)
  if format == 4 {
    let seg_count = u16(data, chosen + 6) / 2
    let end_base = chosen + 14
    let start_base = end_base + seg_count * 2 + 2
    let delta_base = start_base + seg_count * 2
    let range_base = delta_base + seg_count * 2
    let ends : Array[Int32] = Array::make(seg_count, 0)
    let starts : Array[Int32] = Array::make(seg_count, 0)
    let deltas : Array[Int32] = Array::make(seg_count, 0)
    let ranges : Array[Int32] = Array::make(seg_count, 0)
    let mut s = 0
    while s < seg_count {
      ends[s] = u16(data, end_base + s * 2)
      starts[s] = u16(data, start_base + s * 2)
      deltas[s] = i16(data, delta_base + s * 2)
      let raw_range = u16(data, range_base + s * 2)
      ranges[s] = if raw_range == 0 {
        0
      } else {
        range_base + s * 2 + raw_range
      }
      s = s + 1
    }
    (4, chosen, ends, starts, deltas, ranges, [])
  } else {
    let group_count = u32(data, chosen + 12) / 12
    let groups : Array[(Int32, Int32, Int32)] = Array::make(
      group_count,
      (0, 0, 0),
    )
    let mut g = 0
    while g < group_count {
      let base = chosen + 16 + g * 12
      groups[g] = (u32(data, base), u32(data, base + 4), u32(data, base + 8))
      g = g + 1
    }
    (12, chosen, [], [], [], [], groups)
  }
}

///|
pub fn parse_truetype(data : Bytes) -> TrueTypeFont raise RenderError {
  if data.length() < 12 {
    raise RenderError("font data is too short")
  }
  let version = u32(data, 0)
  if version != 0x00010000 && version != 0x74727565 {
    // 0x74727565 == 'true'; 'OTTO' (CFF) is not a glyf font.
    raise RenderError("unsupported TrueType sfnt version")
  }
  let head = table_offset(data, "head")
  let maxp = table_offset(data, "maxp")
  let hhea = table_offset(data, "hhea")
  let hmtx = table_offset(data, "hmtx")
  let loca = table_offset(data, "loca")
  let glyf = table_offset(data, "glyf")
  let cmap = table_offset(data, "cmap")
  let units_per_em = u16(data, head.0 + 18)
  let num_glyphs = u16(data, maxp.0 + 4)
  let num_h_metrics = u16(data, hhea.0 + 34)
  let ascent = i16(data, hhea.0 + 4)
  let descent = i16(data, hhea.0 + 6)
  let loca_format = i16(data, head.0 + 50)
  let loca_values : Array[Int32] = Array::make(num_glyphs + 1, 0)
  let mut i = 0
  while i <= num_glyphs {
    loca_values[i] = if loca_format == 0 {
      u16(data, loca.0 + i * 2) * 2
    } else {
      u32(data, loca.0 + i * 4)
    }
    i = i + 1
  }
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
    units_per_em,
    num_glyphs,
    loca: loca_values,
    glyf_offset: glyf.0,
    hmtx_offset: hmtx.0,
    num_h_metrics,
    ascent,
    descent,
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
fn cmap_glyph_id(
  data : Bytes,
  format : Int32,
  _sub : Int32,
  seg_end : Array[Int32],
  seg_start : Array[Int32],
  seg_delta : Array[Int32],
  seg_range_pos : Array[Int32],
  groups : Array[(Int32, Int32, Int32)],
  code : Int32,
) -> Int32 {
  if format == 4 {
    let mut i = 0
    while i < seg_end.length() {
      if code <= seg_end[i] && code >= seg_start[i] {
        if seg_range_pos[i] == 0 {
          return (code + seg_delta[i]) & 0xFFFF
        }
        let glyph = u16(data, seg_range_pos[i] + (code - seg_start[i]) * 2) catch {
          _ => 0
        }
        if glyph == 0 {
          return 0
        }
        return (glyph + seg_delta[i]) & 0xFFFF
      }
      i = i + 1
    }
    0
  } else if format == 12 {
    for group in groups {
      let (start, end, glyph) = group
      if code >= start && code <= end {
        return glyph + (code - start)
      }
    }
    0
  } else {
    0
  }
}

///|
pub fn TrueTypeFont::glyph_id(self : TrueTypeFont, code : Int32) -> Int32 {
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
pub fn TrueTypeFont::advance_width(self : TrueTypeFont, glyph : Int32) -> Int32 {
  let index = if glyph < self.num_h_metrics {
    glyph
  } else {
    self.num_h_metrics - 1
  }
  if index < 0 {
    return 0
  }
  u16(self.data, self.hmtx_offset + index * 4) catch {
    _ => 0
  }
}

///|
pub fn TrueTypeFont::ascent(self : TrueTypeFont) -> Int32 {
  self.ascent
}

///|
pub fn TrueTypeFont::descent(self : TrueTypeFont) -> Int32 {
  self.descent
}

///|
pub fn TrueTypeFont::units_per_em(self : TrueTypeFont) -> Int32 {
  self.units_per_em
}

///|
/// One point of a TrueType contour, in font units.
pub struct FontPoint {
  x : Double
  y : Double
  on_curve : Bool
}

///|
/// Return the contours of a simple glyph. Composite glyphs return an empty
/// array; the text renderer then falls back to the bitmap glyph.
pub fn TrueTypeFont::glyph_contours(
  self : TrueTypeFont,
  glyph : Int32,
) -> Array[Array[FontPoint]] raise RenderError {
  if glyph < 0 || glyph + 1 >= self.loca.length() {
    return []
  }
  let start = self.glyf_offset + self.loca[glyph]
  let end = self.glyf_offset + self.loca[glyph + 1]
  if end <= start {
    return []
  }
  let contours = i16(self.data, start)
  if contours <= 0 {
    return []
  }
  let contour_count = contours
  let end_points : Array[Int32] = Array::make(contour_count, 0)
  let mut i = 0
  while i < contour_count {
    end_points[i] = u16(self.data, start + 10 + i * 2)
    i = i + 1
  }
  let point_count = end_points[contour_count - 1] + 1
  let mut instruction_pos = start + 10 + contour_count * 2
  let instruction_len = u16(self.data, instruction_pos)
  instruction_pos = instruction_pos + 2 + instruction_len
  let flags : Array[Int32] = Array::make(point_count, 0)
  let mut p = 0
  while p < point_count {
    let flag = self.data.at(instruction_pos).to_int()
    instruction_pos = instruction_pos + 1
    flags[p] = flag
    if (flag & 0x08) != 0 {
      let repeat = self.data.at(instruction_pos).to_int()
      instruction_pos = instruction_pos + 1
      let mut r = 0
      while r < repeat && p + 1 < point_count {
        p = p + 1
        flags[p] = flag
        r = r + 1
      }
    }
    p = p + 1
  }
  let xs : Array[Int32] = Array::make(point_count, 0)
  let ys : Array[Int32] = Array::make(point_count, 0)
  let mut value = 0
  i = 0
  while i < point_count {
    let flag = flags[i]
    if (flag & 0x02) != 0 {
      let delta = self.data.at(instruction_pos).to_int()
      instruction_pos = instruction_pos + 1
      if (flag & 0x10) != 0 {
        value = value + delta
      } else {
        value = value - delta
      }
    } else if (flag & 0x10) == 0 {
      value = value + i16(self.data, instruction_pos)
      instruction_pos = instruction_pos + 2
    }
    xs[i] = value
    i = i + 1
  }
  value = 0
  i = 0
  while i < point_count {
    let flag = flags[i]
    if (flag & 0x04) != 0 {
      let delta = self.data.at(instruction_pos).to_int()
      instruction_pos = instruction_pos + 1
      if (flag & 0x20) != 0 {
        value = value + delta
      } else {
        value = value - delta
      }
    } else if (flag & 0x20) == 0 {
      value = value + i16(self.data, instruction_pos)
      instruction_pos = instruction_pos + 2
    }
    ys[i] = value
    i = i + 1
  }
  let out : Array[Array[FontPoint]] = Array(capacity=contour_count)
  let mut start_point = 0
  i = 0
  while i < contour_count {
    let contour_end = end_points[i]
    let points : Array[FontPoint] = Array(
      capacity=contour_end - start_point + 1,
    )
    let mut j = start_point
    while j <= contour_end {
      points.push({
        x: xs[j].to_double(),
        y: ys[j].to_double(),
        on_curve: (flags[j] & 0x01) != 0,
      })
      j = j + 1
    }
    out.push(points)
    start_point = contour_end + 1
    i = i + 1
  }
  out
}
