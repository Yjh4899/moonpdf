///|
/// Stream filter decoding for page content, cross-reference streams and object
/// streams. Filters run in `/Filter` order; `/DecodeParms` is positional.
/// Unsupported filters raise a typed error rather than returning encoded bytes.

///|
fn filter_names(
  dict : Array[(String, PdfValue)],
) -> Array[String] raise PdfError {
  let out : Array[String] = []
  match dict_get(dict, "Filter") {
    None => ()
    Some(value) =>
      match value {
        Name(name) => out.push(name)
        Array(items) =>
          for item in items {
            match item {
              Name(name) => out.push(name)
              _ => raise PdfError("invalid /Filter array entry")
            }
          }
        _ => raise PdfError("invalid /Filter")
      }
  }
  out
}

///|
fn parm_dict_at(
  dict : Array[(String, PdfValue)],
  index : Int32,
) -> Array[(String, PdfValue)] {
  match dict_get(dict, "DecodeParms") {
    Some(value) =>
      match value {
        Dict(parms) => parms
        Array(items) =>
          match items.get(index) {
            Some(Dict(parms)) => parms
            _ => []
          }
        _ => []
      }
    None => []
  }
}

///|
fn parm_int(
  parms : Array[(String, PdfValue)],
  key : String,
  fallback : Int32,
) -> Int32 {
  match dict_get(parms, key) {
    Some(value) =>
      match value.as_int() {
        Some(n) => n
        None => fallback
      }
    None => fallback
  }
}

///|
fn apply_predictor(
  data : Bytes,
  parms : Array[(String, PdfValue)],
) -> Bytes raise PdfError {
  let predictor = parm_int(parms, "Predictor", 1)
  if predictor == 1 {
    return data
  }
  let colors = parm_int(parms, "Colors", 1)
  let bpc = parm_int(parms, "BitsPerComponent", 8)
  let columns = parm_int(parms, "Columns", 1)
  if bpc != 8 {
    raise PdfError("only 8-bit predictors are supported")
  }
  let bpp = if colors > 0 { colors } else { 1 }
  let row_len = columns * bpp
  if predictor == 2 {
    let out = @buffer.Buffer::Buffer()
    let mut offset = 0
    while offset < data.length() {
      let row : Array[Byte] = Array::make(row_len, u8(0))
      let mut i = 0
      while i < row_len && offset + i < data.length() {
        let raw = data.at(offset + i).to_int()
        let left = if i >= bpp { row[i - bpp].to_int() } else { 0 }
        row[i] = u8((raw + left) % 256)
        i = i + 1
      }
      for b in row {
        out.write_byte(b)
      }
      offset = offset + row_len
    }
    return out.to_bytes()
  }
  if predictor < 10 || predictor > 15 {
    raise PdfError("unsupported predictor \{predictor}")
  }
  let stride = row_len + 1
  let rows = data.length() / stride
  let out = @buffer.Buffer::Buffer()
  let mut previous : Array[Byte] = Array::make(row_len, u8(0))
  let mut r = 0
  while r < rows {
    let filter = data.at(r * stride).to_int()
    let row : Array[Byte] = Array::make(row_len, u8(0))
    let mut i = 0
    while i < row_len {
      let raw = data.at(r * stride + 1 + i).to_int()
      let left = if i >= bpp { row[i - bpp].to_int() } else { 0 }
      let up = previous[i].to_int()
      let up_left = if i >= bpp { previous[i - bpp].to_int() } else { 0 }
      let value = match filter {
        0 => raw
        1 => raw + left
        2 => raw + up
        3 => raw + (left + up) / 2
        4 => {
          let p = left + up - up_left
          let pa = if p > left { p - left } else { left - p }
          let pb = if p > up { p - up } else { up - p }
          let pc = if p > up_left { p - up_left } else { up_left - p }
          if pa <= pb && pa <= pc {
            raw + left
          } else if pb <= pc {
            raw + up
          } else {
            raw + up_left
          }
        }
        _ => raise PdfError("invalid PNG predictor row filter")
      }
      row[i] = u8(value % 256)
      i = i + 1
    }
    for b in row {
      out.write_byte(b)
    }
    previous = row
    r = r + 1
  }
  out.to_bytes()
}

///|
fn decode_ascii_hex(data : Bytes) -> Bytes raise PdfError {
  let out = @buffer.Buffer::Buffer()
  let mut high = -1
  let mut i = 0
  while i < data.length() {
    let b = data.at(i).to_int()
    i = i + 1
    if b == 62 {
      break
    }
    if is_white(b) {
      continue
    }
    let v = match hex_value(b) {
      Some(v) => v
      None => raise PdfError("invalid ASCIIHex digit")
    }
    if high < 0 {
      high = v
    } else {
      out.write_byte(u8(high * 16 + v))
      high = -1
    }
  }
  if high >= 0 {
    out.write_byte(u8(high * 16))
  }
  out.to_bytes()
}

///|
fn decode_ascii85(data : Bytes) -> Bytes raise PdfError {
  let out = @buffer.Buffer::Buffer()
  let group : Array[Int32] = Array(capacity=5)
  let mut i = 0
  while i < data.length() {
    let b = data.at(i).to_int()
    i = i + 1
    if is_white(b) {
      continue
    }
    if b == 126 {
      break
    }
    if b == 122 && group.length() == 0 {
      let mut k = 0
      while k < 4 {
        out.write_byte(u8(0))
        k = k + 1
      }
      continue
    }
    if b < 33 || b > 117 {
      raise PdfError("invalid ASCII85 byte")
    }
    group.push(b - 33)
    if group.length() == 5 {
      let mut value = 0
      for digit in group {
        value = value * 85 + digit
      }
      out.write_byte(u8((value >> 24) & 0xFF))
      out.write_byte(u8((value >> 16) & 0xFF))
      out.write_byte(u8((value >> 8) & 0xFF))
      out.write_byte(u8(value & 0xFF))
      group.clear()
    }
  }
  if group.length() > 1 {
    let count = group.length()
    while group.length() < 5 {
      group.push(84)
    }
    let mut value = 0
    for digit in group {
      value = value * 85 + digit
    }
    let bytes : Array[Int32] = [
      (value >> 24) & 0xFF,
      (value >> 16) & 0xFF,
      (value >> 8) & 0xFF,
      value & 0xFF,
    ]
    let mut k = 0
    while k < count - 1 {
      out.write_byte(u8(bytes[k]))
      k = k + 1
    }
  }
  out.to_bytes()
}

///|
fn decode_run_length(data : Bytes) -> Bytes raise PdfError {
  let out = @buffer.Buffer::Buffer()
  let mut i = 0
  while i < data.length() {
    let length = data.at(i).to_int()
    i = i + 1
    if length == 128 {
      break
    } else if length <= 127 {
      let count = length + 1
      let mut k = 0
      while k < count && i < data.length() {
        out.write_byte(data.at(i))
        i = i + 1
        k = k + 1
      }
    } else {
      if i >= data.length() {
        raise PdfError("truncated RunLengthDecode")
      }
      let count = 257 - length
      let value = data.at(i)
      i = i + 1
      let mut k = 0
      while k < count {
        out.write_byte(value)
        k = k + 1
      }
    }
  }
  out.to_bytes()
}

///|
fn read_bits(data : Bytes, bit_pos : Int32, count : Int32) -> Int32 {
  let mut value = 0
  let mut k = 0
  while k < count {
    let byte_index = (bit_pos + k) / 8
    let bit_index = 7 - (bit_pos + k) % 8
    let bit = (data.at(byte_index).to_int() >> bit_index) & 1
    value = (value << 1) | bit
    k = k + 1
  }
  value
}

///|
/// PDF LZWDecode with the default EarlyChange=1.
fn decode_lzw(data : Bytes) -> Bytes raise PdfError {
  let out = @buffer.Buffer::Buffer()
  let table : Array[Bytes] = Array(capacity=4096)
  let mut code_len = 9
  let mut next_code = 258
  let mut previous : Bytes? = None
  let mut bit_pos = 0
  let total_bits = data.length() * 8
  let mut i = 0
  while i < 256 {
    table.push(Bytes::make(1, u8(i)))
    i = i + 1
  }
  table.push(Bytes::make(0, u8(0)))
  table.push(Bytes::make(0, u8(0)))
  while bit_pos + code_len <= total_bits {
    let code = read_bits(data, bit_pos, code_len)
    bit_pos = bit_pos + code_len
    if code == 256 {
      code_len = 9
      next_code = 258
      table.clear()
      let mut k = 0
      while k < 256 {
        table.push(Bytes::make(1, u8(k)))
        k = k + 1
      }
      table.push(Bytes::make(0, u8(0)))
      table.push(Bytes::make(0, u8(0)))
      previous = None
      continue
    }
    if code == 257 {
      break
    }
    let entry = if code < table.length() {
      table[code]
    } else if code == next_code {
      match previous {
        Some(prev) => {
          let buf = @buffer.Buffer::Buffer()
          buf.write_bytes(prev)
          buf.write_byte(prev.at(0))
          buf.to_bytes()
        }
        None => raise PdfError("invalid LZW code")
      }
    } else {
      raise PdfError("invalid LZW code")
    }
    out.write_bytes(entry)
    match previous {
      Some(prev) =>
        if next_code < 4096 {
          let buf = @buffer.Buffer::Buffer()
          buf.write_bytes(prev)
          buf.write_byte(entry.at(0))
          table.push(buf.to_bytes())
          next_code = next_code + 1
        }
      None => ()
    }
    previous = Some(entry)
    if next_code == (1 << code_len) - 1 && code_len < 12 {
      code_len = code_len + 1
    }
  }
  out.to_bytes()
}

///|
fn decode_one_filter(
  name : String,
  data : Bytes,
  parms : Array[(String, PdfValue)],
) -> Bytes raise PdfError {
  match name {
    "FlateDecode" | "Fl" => {
      let inflated = @zlib.decompress(data) catch {
        _ => raise PdfError("FlateDecode failed")
      }
      apply_predictor(inflated, parms)
    }
    "ASCIIHexDecode" | "AHx" => decode_ascii_hex(data)
    "ASCII85Decode" | "A85" => decode_ascii85(data)
    "RunLengthDecode" | "RL" => decode_run_length(data)
    "LZWDecode" | "LZW" => decode_lzw(data)
    "Crypt" => data
    _ => raise PdfError("unsupported stream filter: \{name}")
  }
}

///|
/// Decode a stream to its logical bytes, applying `/Filter` in order.
pub fn decode_stream(stream : PdfStream) -> Bytes raise PdfError {
  let filters = filter_names(stream.dict)
  if filters.length() == 0 {
    return stream.data
  }
  let mut current = stream.data
  let mut index = 0
  for name in filters {
    current = decode_one_filter(name, current, parm_dict_at(stream.dict, index))
    index = index + 1
  }
  current
}

///|
/// Decode a stream and return an empty stream on filter failure.
pub fn decode_stream_lossy(stream : PdfStream) -> Bytes {
  decode_stream(stream) catch {
    _ => Bytes::make(0, u8(0))
  }
}
