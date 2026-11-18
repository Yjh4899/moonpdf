///|
fn dmin(a : Double, b : Double) -> Double {
  if a < b {
    a
  } else {
    b
  }
}

///|
fn dmax(a : Double, b : Double) -> Double {
  if a > b {
    a
  } else {
    b
  }
}

///|
/// Decoded image samples, always 8 bits per component. The renderer converts
/// every supported color space to RGB at draw time.
pub struct ImageData {
  width : Int32
  height : Int32
  components : Int32
  data : Bytes
}

///|
fn dict_value_int(
  page : @pdf.PdfPage,
  dict : Array[(String, @pdf.PdfValue)],
  key : String,
) -> Int32? {
  match @pdf.dict_get(dict, key) {
    Some(value) =>
      match page.resolve(value).as_int() {
        Some(n) => Some(n)
        None => None
      }
    None => None
  }
}

///|
fn color_components(
  page : @pdf.PdfPage,
  value : @pdf.PdfValue,
) -> Int32 raise RenderError {
  match page.resolve(value) {
    @pdf.Name("DeviceGray") => 1
    @pdf.Name("DeviceRGB") => 3
    @pdf.Name("DeviceCMYK") => 4
    @pdf.Array(items) =>
      if items.length() > 0 {
        match items[0].as_name() {
          Some("ICCBased") => {
            if items.length() < 2 {
              raise RenderError("ICCBased color space has no stream")
            }
            match page.resolve(items[1]) {
              @pdf.Stream(stream) =>
                match dict_value_int(page, stream.dict, "N") {
                  Some(n) => n
                  None => raise RenderError("ICCBased stream has no /N")
                }
              _ => raise RenderError("ICCBased color space is not a stream")
            }
          }
          Some("Indexed") => 1
          _ => raise RenderError("unsupported image color space")
        }
      } else {
        raise RenderError("empty image color space array")
      }
    _ => raise RenderError("unsupported image color space")
  }
}

///|
fn image_filter_names(
  page : @pdf.PdfPage,
  dict : Array[(String, @pdf.PdfValue)],
) -> Array[String] {
  let out : Array[String] = []
  match @pdf.dict_get(dict, "Filter") {
    Some(value) =>
      match page.resolve(value) {
        @pdf.Name(name) => out.push(name)
        @pdf.Array(items) =>
          for item in items {
            match page.resolve(item) {
              @pdf.Name(name) => out.push(name)
              _ => ()
            }
          }
        _ => ()
      }
    None => ()
  }
  out
}

///|
fn invert_samples(data : Bytes) -> Bytes {
  let out : Array[Byte] = Array::make(data.length(), u8(0))
  let mut i = 0
  while i < data.length() {
    out[i] = (255 - data.at(i).to_int()).to_byte()
    i = i + 1
  }
  Bytes::from_array(out)
}

///|
/// Decode an image XObject into 8-bit samples. Flate/ASCII/LZW images are
/// decoded by the PDF filter layer; baseline DCT (JPEG) goes through the
/// built-in decoder.
pub fn decode_image(
  page : @pdf.PdfPage,
  stream : @pdf.PdfStream,
) -> ImageData raise RenderError {
  let width = match dict_value_int(page, stream.dict, "Width") {
    Some(n) => n
    None => raise RenderError("image has no /Width")
  }
  let height = match dict_value_int(page, stream.dict, "Height") {
    Some(n) => n
    None => raise RenderError("image has no /Height")
  }
  let bpc = match dict_value_int(page, stream.dict, "BitsPerComponent") {
    Some(n) => n
    None => 8
  }
  if width <= 0 || height <= 0 {
    raise RenderError("image has invalid dimensions")
  }
  if bpc != 8 {
    raise RenderError("only 8-bit image samples are supported")
  }
  let colorspace = match @pdf.dict_get(stream.dict, "ColorSpace") {
    Some(value) => value
    None => @pdf.pdf_name("DeviceGray")
  }
  let components = color_components(page, colorspace)
  let filters = image_filter_names(page, stream.dict)
  let mut data = if filters.length() == 1 && filters[0] == "DCTDecode" {
    let jpeg = decode_jpeg(stream.data) catch {
      _ => raise RenderError("JPEG decode failed")
    }
    if components != 3 && components != 1 {
      raise RenderError("JPEG image must be gray or RGB")
    }
    return {
      width: jpeg.width,
      height: jpeg.height,
      components: 3,
      data: jpeg.data,
    }
  } else if filters.length() == 1 && filters[0] == "JPXDecode" {
    raise RenderError("JPXDecode is not supported yet")
  } else {
    @pdf.decode_stream(stream) catch {
      _ => raise RenderError("image stream decode failed")
    }
  }
  let expected = width * height * components
  if data.length() < expected {
    raise RenderError("image data is shorter than its declared size")
  }
  // /Decode [1 0] (or per-component equivalents) inverts the samples.
  match @pdf.dict_get(stream.dict, "Decode") {
    Some(value) =>
      match page.resolve(value).as_array() {
        Some(items) =>
          if items.length() >= 2 * components {
            let mut invert = true
            let mut c = 0
            while c < components {
              let lo = items[2 * c].as_number()
              let hi = items[2 * c + 1].as_number()
              match (lo, hi) {
                (Some(1.0), Some(0.0)) => ()
                _ => invert = false
              }
              c = c + 1
            }
            if invert {
              data = invert_samples(data)
            }
          }
        None => ()
      }
    None => ()
  }
  { width, height, components, data, }
}

///|
fn sample_rgb(image : ImageData, x : Int32, y : Int32) -> (Int32, Int32, Int32) {
  let mut px = x
  let mut py = y
  if px < 0 {
    px = 0
  }
  if py < 0 {
    py = 0
  }
  if px >= image.width {
    px = image.width - 1
  }
  if py >= image.height {
    py = image.height - 1
  }
  let idx = (py * image.width + px) * image.components
  match image.components {
    1 => {
      let v = image.data.at(idx).to_int()
      (v, v, v)
    }
    3 =>
      (
        image.data.at(idx).to_int(),
        image.data.at(idx + 1).to_int(),
        image.data.at(idx + 2).to_int(),
      )
    _ => {
      let c = image.data.at(idx).to_int()
      let m = image.data.at(idx + 1).to_int()
      let yv = image.data.at(idx + 2).to_int()
      let k = image.data.at(idx + 3).to_int()
      let ck = if c + k > 255 { 255 } else { c + k }
      let mk = if m + k > 255 { 255 } else { m + k }
      let yk = if yv + k > 255 { 255 } else { yv + k }
      let r = 255 - ck
      let g = 255 - mk
      let b = 255 - yk
      (r, g, b)
    }
  }
}

///|
/// Paint an image into the unit square, transformed by the current CTM. The
/// sampler is nearest-neighbour; bilinear sampling is a later refinement.
fn draw_image(canvas : Canvas, state : GState, image : ImageData) -> Unit {
  let inverse = match state.ctm.invert() {
    Some(m) => m
    None => return
  }
  let p0 = state.ctm.apply(0.0, 0.0)
  let p1 = state.ctm.apply(1.0, 0.0)
  let p2 = state.ctm.apply(1.0, 1.0)
  let p3 = state.ctm.apply(0.0, 1.0)
  let x0 = @math.floor(dmin(dmin(p0.x, p1.x), dmin(p2.x, p3.x))).to_int() - 1
  let y0 = @math.floor(dmin(dmin(p0.y, p1.y), dmin(p2.y, p3.y))).to_int() - 1
  let x1 = @math.ceil(dmax(dmax(p0.x, p1.x), dmax(p2.x, p3.x))).to_int() + 1
  let y1 = @math.ceil(dmax(dmax(p0.y, p1.y), dmax(p2.y, p3.y))).to_int() + 1
  let mut y = y0
  while y <= y1 {
    let mut x = x0
    while x <= x1 {
      let p = inverse.apply(x.to_double() + 0.5, y.to_double() + 0.5)
      if p.x >= 0.0 && p.x <= 1.0 && p.y >= 0.0 && p.y <= 1.0 {
        let col = (p.x * (image.width - 1).to_double()).to_int()
        let row = ((1.0 - p.y) * (image.height - 1).to_double()).to_int()
        let (r, g, b) = sample_rgb(image, col, row)
        canvas.set(x, y, r, g, b)
      }
      x = x + 1
    }
    y = y + 1
  }
}
