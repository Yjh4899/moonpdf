///|
/// Baseline JPEG (SOF0/SOF1) decoder used for PDF DCTDecode image XObjects.
/// Progressive JPEG, arithmetic coding and CMYK/YCCK are rejected explicitly.
priv struct HuffTable {
  min_code : Array[Int32]
  max_code : Array[Int32]
  val_ptr : Array[Int32]
  values : Array[Int32]
}

///|
priv struct BitReader {
  data : Bytes
  mut pos : Int32
  mut current : Int32
  mut bits_left : Int32
}

///|
priv struct JpegComponent {
  id : Int32
  h : Int32
  v : Int32
  tq : Int32
  mut dc_table : Int32
  mut ac_table : Int32
  mut dc_pred : Int32
  width : Int32
  height : Int32
  plane : Array[Byte]
}

///|
fn zigzag_table() -> Array[Int32] {
  [
    0, 1, 8, 16, 9, 2, 3, 10, 17, 24, 32, 25, 18, 11, 4, 5, 12, 19, 26, 33, 40, 48,
    41, 34, 27, 20, 13, 6, 7, 14, 21, 28, 35, 42, 49, 56, 57, 50, 43, 36, 29, 22,
    15, 23, 30, 37, 44, 51, 58, 59, 52, 45, 38, 31, 39, 46, 53, 60, 61, 54, 47, 55,
    62, 63,
  ]
}

///|
fn be_u16(data : Bytes, pos : Int32) -> Int32 raise RenderError {
  if pos + 1 >= data.length() {
    raise RenderError("truncated JPEG segment")
  }
  (data.at(pos).to_int() << 8) | data.at(pos + 1).to_int()
}

///|
fn build_huff(counts : Array[Int32], symbols : Array[Int32]) -> HuffTable {
  let min_code : Array[Int32] = Array::make(17, 0)
  let max_code : Array[Int32] = Array::make(17, -1)
  let val_ptr : Array[Int32] = Array::make(17, 0)
  let mut code = 0
  let mut k = 0
  let mut len = 1
  while len <= 16 {
    let n = counts[len]
    if n > 0 {
      val_ptr[len] = k
      min_code[len] = code
      code = code + n
      max_code[len] = code - 1
      k = k + n
    }
    code = code << 1
    len = len + 1
  }
  { min_code, max_code, val_ptr, values: symbols, }
}

///|
fn BitReader::new(data : Bytes, pos : Int32) -> BitReader {
  { data, pos, current: 0, bits_left: 0, }
}

///|
fn BitReader::read_bit(self : BitReader) -> Int32 raise RenderError {
  if self.bits_left == 0 {
    if self.pos >= self.data.length() {
      raise RenderError("unexpected end of JPEG entropy data")
    }
    let b = self.data.at(self.pos).to_int()
    self.pos = self.pos + 1
    if b == 0xFF {
      if self.pos >= self.data.length() {
        raise RenderError("truncated JPEG marker")
      }
      let next = self.data.at(self.pos).to_int()
      self.pos = self.pos + 1
      if next == 0 {
        self.current = 0xFF
      } else {
        raise RenderError("unexpected marker in JPEG entropy data")
      }
    } else {
      self.current = b
    }
    self.bits_left = 8
  }
  self.bits_left = self.bits_left - 1
  (self.current >> self.bits_left) & 1
}

///|
fn BitReader::read_bits(
  self : BitReader,
  count : Int32,
) -> Int32 raise RenderError {
  let mut value = 0
  let mut i = 0
  while i < count {
    value = (value << 1) | self.read_bit()
    i = i + 1
  }
  value
}

///|
fn BitReader::restart(self : BitReader) -> Unit {
  self.bits_left = 0
  while self.pos + 1 < self.data.length() {
    if self.data.at(self.pos).to_int() == 0xFF {
      let marker = self.data.at(self.pos + 1).to_int()
      if marker >= 0xD0 && marker <= 0xD7 {
        self.pos = self.pos + 2
        return
      }
    }
    return
  }
}

///|
fn huff_decode(
  reader : BitReader,
  table : HuffTable,
) -> Int32 raise RenderError {
  let mut code = 0
  let mut len = 1
  while len <= 16 {
    code = (code << 1) | reader.read_bit()
    let max_code = table.max_code[len]
    if max_code >= 0 && code >= table.min_code[len] && code <= max_code {
      return table.values[table.val_ptr[len] + (code - table.min_code[len])]
    }
    len = len + 1
  }
  raise RenderError("invalid JPEG Huffman code")
}

///|
fn extend_value(value : Int32, size : Int32) -> Int32 {
  if size == 0 {
    0
  } else if value < 1 << (size - 1) {
    value - (1 << size) + 1
  } else {
    value
  }
}

///|
fn clamp_sample(value : Double) -> Byte {
  let v = value + 128.0
  if v <= 0.0 {
    u8(0)
  } else if v >= 255.0 {
    u8(255)
  } else {
    v.to_int().to_byte()
  }
}

///|
fn make_cos_table() -> Array[Double] {
  let table : Array[Double] = Array::make(64, 0.0)
  let mut u = 0
  while u < 8 {
    let mut x = 0
    while x < 8 {
      let angle = (2.0 * x.to_double() + 1.0) *
        u.to_double() *
        3.141592653589793 /
        16.0
      table[u * 8 + x] = @math.cos(angle)
      x = x + 1
    }
    u = u + 1
  }
  table
}

///|
fn idct_block(coeff : Array[Int32], cos_table : Array[Double]) -> Array[Byte] {
  let out : Array[Byte] = Array::make(64, u8(0))
  let mut y = 0
  while y < 8 {
    let mut x = 0
    while x < 8 {
      let mut sum = 0.0
      let mut v = 0
      while v < 8 {
        let cv = if v == 0 { 0.7071067811865476 } else { 1.0 }
        let mut u = 0
        while u < 8 {
          let cu = if u == 0 { 0.7071067811865476 } else { 1.0 }
          let f = coeff[v * 8 + u].to_double()
          sum = sum + cu * cv * f * cos_table[u * 8 + x] * cos_table[v * 8 + y]
          u = u + 1
        }
        v = v + 1
      }
      out[y * 8 + x] = clamp_sample(sum / 4.0)
      x = x + 1
    }
    y = y + 1
  }
  out
}

///|
fn decode_block(
  reader : BitReader,
  comp : JpegComponent,
  qt : Array[Int32],
  dc : HuffTable,
  ac : HuffTable,
  zigzag : Array[Int32],
  cos_table : Array[Double],
) -> Array[Byte] raise RenderError {
  let coeff : Array[Int32] = Array::make(64, 0)
  let dc_size = huff_decode(reader, dc)
  let diff = if dc_size == 0 {
    0
  } else {
    extend_value(reader.read_bits(dc_size), dc_size)
  }
  comp.dc_pred = comp.dc_pred + diff
  coeff[0] = comp.dc_pred * qt[0]
  let mut k = 1
  while k < 64 {
    let rs = huff_decode(reader, ac)
    let run = rs >> 4
    let size = rs & 15
    if size == 0 {
      if run == 15 {
        k = k + 16
      } else {
        break
      }
    } else {
      k = k + run
      if k >= 64 {
        break
      }
      let natural = zigzag[k]
      let value = extend_value(reader.read_bits(size), size)
      coeff[natural] = value * qt[natural]
      k = k + 1
    }
  }
  idct_block(coeff, cos_table)
}

///|
fn store_block(
  comp : JpegComponent,
  block_x : Int32,
  block_y : Int32,
  samples : Array[Byte],
) -> Unit {
  let base_x = block_x * 8
  let base_y = block_y * 8
  let mut y = 0
  while y < 8 {
    let py = base_y + y
    if py < comp.height {
      let mut x = 0
      while x < 8 {
        let px = base_x + x
        if px < comp.width {
          comp.plane[py * comp.width + px] = samples[y * 8 + x]
        }
        x = x + 1
      }
    }
    y = y + 1
  }
}

///|
fn component_sample(comp : JpegComponent, x : Int32, y : Int32) -> Int32 {
  let mut px = x
  let mut py = y
  if px < 0 {
    px = 0
  }
  if py < 0 {
    py = 0
  }
  if px >= comp.width {
    px = comp.width - 1
  }
  if py >= comp.height {
    py = comp.height - 1
  }
  comp.plane[py * comp.width + px].to_int()
}

///|
fn find_component(components : Array[JpegComponent], id : Int32) -> Int32 {
  let mut i = 0
  while i < components.length() {
    if components[i].id == id {
      return i
    }
    i = i + 1
  }
  -1
}

///|
fn decode_scan(
  data : Bytes,
  scan_pos : Int32,
  width : Int32,
  height : Int32,
  components : Array[JpegComponent],
  max_h : Int32,
  max_v : Int32,
  qtables : Array[Array[Int32]?],
  dc_tables : Array[HuffTable?],
  ac_tables : Array[HuffTable?],
  restart_interval : Int32,
  adobe_transform : Int32,
) -> ImageData raise RenderError {
  let reader = BitReader::new(data, scan_pos)
  let zigzag = zigzag_table()
  let cos_table = make_cos_table()
  let mcu_w = 8 * max_h
  let mcu_h = 8 * max_v
  let mcu_cols = (width + mcu_w - 1) / mcu_w
  let mcu_rows = (height + mcu_h - 1) / mcu_h
  let total = mcu_cols * mcu_rows
  let mut mcu = 0
  while mcu < total {
    if restart_interval > 0 && mcu > 0 && mcu % restart_interval == 0 {
      reader.restart()
      for comp in components {
        comp.dc_pred = 0
      }
    }
    let mx = mcu % mcu_cols
    let my = mcu / mcu_cols
    for comp in components {
      let qt = match qtables[comp.tq] {
        Some(table) => table
        None => raise RenderError("JPEG quantization table is missing")
      }
      let dc = match dc_tables[comp.dc_table] {
        Some(table) => table
        None => raise RenderError("JPEG DC Huffman table is missing")
      }
      let ac = match ac_tables[comp.ac_table] {
        Some(table) => table
        None => raise RenderError("JPEG AC Huffman table is missing")
      }
      let mut by = 0
      while by < comp.v {
        let mut bx = 0
        while bx < comp.h {
          let block = decode_block(reader, comp, qt, dc, ac, zigzag, cos_table)
          store_block(comp, mx * comp.h + bx, my * comp.v + by, block)
          bx = bx + 1
        }
        by = by + 1
      }
    }
    mcu = mcu + 1
  }
  let out : Array[Byte] = Array::make(width * height * 3, u8(0))
  let mut y = 0
  while y < height {
    let mut x = 0
    while x < width {
      let i0 = find_component(components, 0)
      let mut r = 0
      let mut g = 0
      let mut b = 0
      if components.length() == 1 {
        let v = component_sample(
          components[0],
          x * components[0].width / width,
          y * components[0].height / height,
        )
        r = v
        g = v
        b = v
      } else if components.length() >= 3 {
        let ycomp = if i0 >= 0 { components[i0] } else { components[0] }
        let cbcomp = components[1]
        let crcomp = components[2]
        let yy = component_sample(
          ycomp,
          x * ycomp.width / width,
          y * ycomp.height / height,
        )
        let cb = component_sample(
            cbcomp,
            x * cbcomp.width / width,
            y * cbcomp.height / height,
          ) -
          128
        let cr = component_sample(
            crcomp,
            x * crcomp.width / width,
            y * crcomp.height / height,
          ) -
          128
        if adobe_transform == 0 {
          r = yy
          g = cb + 128
          b = cr + 128
        } else {
          let rf = yy.to_double() + 1.402 * cr.to_double()
          let gf = yy.to_double() -
            0.344136 * cb.to_double() -
            0.714136 * cr.to_double()
          let bf = yy.to_double() + 1.772 * cb.to_double()
          r = if rf <= 0.0 {
            0
          } else if rf >= 255.0 {
            255
          } else {
            rf.to_int()
          }
          g = if gf <= 0.0 {
            0
          } else if gf >= 255.0 {
            255
          } else {
            gf.to_int()
          }
          b = if bf <= 0.0 {
            0
          } else if bf >= 255.0 {
            255
          } else {
            bf.to_int()
          }
        }
      }
      let idx = (y * width + x) * 3
      out[idx] = r.to_byte()
      out[idx + 1] = g.to_byte()
      out[idx + 2] = b.to_byte()
      x = x + 1
    }
    y = y + 1
  }
  { width, height, components: 3, data: Bytes::from_array(out), }
}

///|
pub fn decode_jpeg(data : Bytes) -> ImageData raise RenderError {
  if data.length() < 2 ||
    data.at(0).to_int() != 0xFF ||
    data.at(1).to_int() != 0xD8 {
    raise RenderError("not a JPEG file")
  }
  let qtables : Array[Array[Int32]?] = Array::make(4, None)
  let dc_tables : Array[HuffTable?] = Array::make(4, None)
  let ac_tables : Array[HuffTable?] = Array::make(4, None)
  let components : Array[JpegComponent] = Array(capacity=4)
  let mut width = 0
  let mut height = 0
  let mut max_h = 1
  let mut max_v = 1
  let mut restart_interval = 0
  let mut adobe_transform = -1
  let mut pos = 2
  while pos + 1 < data.length() {
    if data.at(pos).to_int() != 0xFF {
      pos = pos + 1
      continue
    }
    while pos < data.length() && data.at(pos).to_int() == 0xFF {
      pos = pos + 1
    }
    if pos >= data.length() {
      raise RenderError("JPEG ended before SOS")
    }
    let marker = data.at(pos).to_int()
    pos = pos + 1
    if marker == 0xD9 {
      raise RenderError("JPEG ended before SOS")
    }
    if marker == 0xD8 {
      continue
    }
    if marker == 0xDA {
      let len = be_u16(data, pos)
      let end = pos + len
      let mut p = pos + 2
      if p >= end {
        raise RenderError("truncated JPEG SOS")
      }
      let count = data.at(p).to_int()
      p = p + 1
      let mut i = 0
      while i < count {
        let id = data.at(p).to_int()
        let tables = data.at(p + 1).to_int()
        p = p + 2
        let index = find_component(components, id)
        if index >= 0 {
          components[index].dc_table = tables >> 4
          components[index].ac_table = tables & 15
        }
        i = i + 1
      }
      return decode_scan(
        data, end, width, height, components, max_h, max_v, qtables, dc_tables, ac_tables,
        restart_interval, adobe_transform,
      )
    }
    let len = be_u16(data, pos)
    if len < 2 {
      raise RenderError("invalid JPEG segment length")
    }
    let end = pos + len
    if end > data.length() {
      raise RenderError("truncated JPEG segment")
    }
    if marker == 0xDB {
      let mut p = pos + 2
      while p < end {
        let info = data.at(p).to_int()
        p = p + 1
        let precision = info >> 4
        let id = info & 15
        if id >= 4 {
          raise RenderError("invalid JPEG quantization table id")
        }
        let table : Array[Int32] = Array::make(64, 0)
        let mut k = 0
        while k < 64 {
          let value = if precision == 0 {
            let v = data.at(p).to_int()
            p = p + 1
            v
          } else {
            let v = be_u16(data, p)
            p = p + 2
            v
          }
          table[zigzag_table()[k]] = value
          k = k + 1
        }
        qtables[id] = Some(table)
      }
    } else if marker == 0xC4 {
      let mut p = pos + 2
      while p < end {
        let info = data.at(p).to_int()
        p = p + 1
        let class = info >> 4
        let id = info & 15
        if id >= 4 {
          raise RenderError("invalid JPEG Huffman table id")
        }
        let counts : Array[Int32] = Array::make(17, 0)
        let mut total = 0
        let mut i = 1
        while i <= 16 {
          let n = data.at(p).to_int()
          p = p + 1
          counts[i] = n
          total = total + n
          i = i + 1
        }
        let symbols : Array[Int32] = Array::make(total, 0)
        let mut s = 0
        while s < total {
          symbols[s] = data.at(p).to_int()
          p = p + 1
          s = s + 1
        }
        let table = build_huff(counts, symbols)
        if class == 0 {
          dc_tables[id] = Some(table)
        } else {
          ac_tables[id] = Some(table)
        }
      }
    } else if marker == 0xC0 || marker == 0xC1 {
      let mut p = pos + 2
      let precision = data.at(p).to_int()
      p = p + 1
      if precision != 8 {
        raise RenderError("only 8-bit baseline JPEG is supported")
      }
      height = be_u16(data, p)
      width = be_u16(data, p + 2)
      p = p + 4
      let count = data.at(p).to_int()
      p = p + 1
      let mut i = 0
      let specs : Array[(Int32, Int32, Int32, Int32)] = Array(capacity=count)
      while i < count {
        let id = data.at(p).to_int()
        let hv = data.at(p + 1).to_int()
        let tq = data.at(p + 2).to_int()
        p = p + 3
        let h = hv >> 4
        let v = hv & 15
        if h < 1 || v < 1 {
          raise RenderError("invalid JPEG sampling factor")
        }
        if h > max_h {
          max_h = h
        }
        if v > max_v {
          max_v = v
        }
        specs.push((id, h, v, tq))
        i = i + 1
      }
      for spec in specs {
        let (id, h, v, tq) = spec
        let comp_w = (width * h + max_h - 1) / max_h
        let comp_h = (height * v + max_v - 1) / max_v
        components.push({
          id,
          h,
          v,
          tq,
          dc_table: 0,
          ac_table: 0,
          dc_pred: 0,
          width: comp_w,
          height: comp_h,
          plane: Array::make(comp_w * comp_h, u8(0)),
        })
      }
    } else if marker == 0xDD {
      restart_interval = be_u16(data, pos + 2)
    } else if marker == 0xEE {
      if len >= 14 && end - (pos + 2) >= 12 {
        let start = pos + 2
        if data.at(start).to_int() == 65 &&
          data.at(start + 1).to_int() == 100 &&
          data.at(start + 2).to_int() == 111 &&
          data.at(start + 3).to_int() == 98 &&
          data.at(start + 4).to_int() == 101 {
          adobe_transform = data.at(start + 11).to_int()
        }
      }
    } else if marker == 0xC2 ||
      marker == 0xC3 ||
      marker == 0xC5 ||
      marker == 0xC6 ||
      marker == 0xC7 ||
      marker == 0xC9 ||
      marker == 0xCA ||
      marker == 0xCB ||
      marker == 0xCD ||
      marker == 0xCE ||
      marker == 0xCF {
      raise RenderError("progressive/arithmetic JPEG is not supported")
    }
    pos = end
  }
  raise RenderError("JPEG has no SOS scan")
}
