///|
/// Encode a rendered page as an SVG container with an embedded PNG. The raster
/// is currently the drawing source; vector path export is a later step.
fn base64_encode(data : Bytes) -> String {
  let alphabet = @utf8.encode(
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/",
  )
  let out = @buffer.Buffer::Buffer()
  let mut i = 0
  while i < data.length() {
    let b0 = data.at(i).to_int()
    let b1 = if i + 1 < data.length() { data.at(i + 1).to_int() } else { 0 }
    let b2 = if i + 2 < data.length() { data.at(i + 2).to_int() } else { 0 }
    out.write_byte(alphabet.at(b0 >> 2))
    out.write_byte(alphabet.at(((b0 & 3) << 4) | (b1 >> 4)))
    if i + 1 < data.length() {
      out.write_byte(alphabet.at(((b1 & 15) << 2) | (b2 >> 6)))
    } else {
      out.write_byte(u8(61))
    }
    if i + 2 < data.length() {
      out.write_byte(alphabet.at(b2 & 63))
    } else {
      out.write_byte(u8(61))
    }
    i = i + 3
  }
  @utf8.decode_lossy(out.to_bytes())
}

///|
/// Encode a rendered page as SVG. The image is embedded as a base64 PNG; this
/// keeps the output self-contained while vector path export remains future work.
pub fn encode_svg(page : RenderedPage) -> Bytes {
  let png = encode_png(page)
  let encoded = base64_encode(png)
  let text = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"\{page.width}\" height=\"\{page.height}\" viewBox=\"0 0 \{page.width} \{page.height}\">\n<image width=\"\{page.width}\" height=\"\{page.height}\" href=\"data:image/png;base64,\{encoded}\"/>\n</svg>\n"
  @utf8.encode(text)
}
