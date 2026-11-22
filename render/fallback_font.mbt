///|
/// Lazily decode the embedded OpenSans subset used for standard-14 fallback.
let fallback_font_cache : Array[TrueTypeFont?] = [None]

///|
fn fallback_truetype() -> TrueTypeFont? {
  match fallback_font_cache[0] {
    Some(font) => Some(font)
    None => {
      let encoded = @buffer.Buffer::Buffer()
      for part in fallback_font_b64 {
        for byte in @utf8.encode(part) {
          encoded.write_byte(byte)
        }
      }
      let compressed = @base64.decode(@utf8.decode_lossy(encoded.to_bytes())) catch {
        _ => return None
      }
      let data = @zlib.decompress(compressed) catch { _ => return None }
      let font = parse_truetype(data) catch { _ => return None }
      fallback_font_cache[0] = Some(font)
      Some(font)
    }
  }
}
