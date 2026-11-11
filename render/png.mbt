///|
fn write_u32_be(out : @buffer.Buffer, value : UInt32) -> Unit {
  let mask : UInt32 = 0xFF
  out.write_byte(((value >> 24) & mask).reinterpret_as_int().to_byte())
  out.write_byte(((value >> 16) & mask).reinterpret_as_int().to_byte())
  out.write_byte(((value >> 8) & mask).reinterpret_as_int().to_byte())
  out.write_byte((value & mask).reinterpret_as_int().to_byte())
}

///|
fn crc32(data : Bytes) -> UInt32 {
  let poly : UInt32 = 0xEDB88320
  let one : UInt32 = 1
  let mut crc : UInt32 = 0xFFFFFFFF
  for b in data {
    crc = crc ^ b.to_uint()
    let mut bit = 0
    while bit < 8 {
      if (crc & one) == one {
        crc = poly ^ (crc >> 1)
      } else {
        crc = crc >> 1
      }
      bit = bit + 1
    }
  }
  crc ^ 0xFFFFFFFF
}

///|
fn write_chunk(out : @buffer.Buffer, kind : String, data : Bytes) -> Unit {
  write_u32_be(out, data.length().reinterpret_as_uint())
  let kind_bytes = @utf8.encode(kind)
  out.write_bytes(kind_bytes)
  out.write_bytes(data)
  let crc_data = @buffer.Buffer::Buffer()
  crc_data.write_bytes(kind_bytes)
  crc_data.write_bytes(data)
  write_u32_be(out, crc32(crc_data.to_bytes()))
}

///|
/// Encode an RGB raster as an 8-bit PNG. The IDAT payload is a standard zlib
/// stream produced by the core zlib package, so the encoder stays small.
pub fn encode_png(page : RenderedPage) -> Bytes {
  let signature : Array[Int32] = [137, 80, 78, 71, 13, 10, 26, 10]
  let out = @buffer.Buffer::Buffer()
  for b in signature {
    out.write_byte(b.to_byte())
  }
  let ihdr = @buffer.Buffer::Buffer()
  write_u32_be(ihdr, page.width.reinterpret_as_uint())
  write_u32_be(ihdr, page.height.reinterpret_as_uint())
  ihdr.write_byte(u8(8)) // bit depth
  ihdr.write_byte(u8(2)) // color type: truecolor RGB
  ihdr.write_byte(u8(0)) // compression
  ihdr.write_byte(u8(0)) // filter
  ihdr.write_byte(u8(0)) // interlace
  write_chunk(out, "IHDR", ihdr.to_bytes())
  let raw = @buffer.Buffer::Buffer()
  let mut y = 0
  while y < page.height {
    raw.write_byte(u8(0)) // filter type: none
    let start = y * page.width * 3
    raw.write_bytes(page.pixels.exact_view(start~, end=start + page.width * 3))
    y = y + 1
  }
  let compressed = @zlib.compress(raw.to_bytes())
  write_chunk(out, "IDAT", compressed)
  write_chunk(out, "IEND", Bytes::new(0))
  out.to_bytes()
}
