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
  alpha : Array[Byte]?
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
fn decode_soft_mask(
  page : @pdf.PdfPage,
  stream : @pdf.PdfStream,
  width : Int32,
  height : Int32,
) -> Array[Byte]? {
  let mask_stream = match @pdf.dict_get(stream.dict, "SMask") {
    Some(value) =>
      match page.resolve(value) {
        @pdf.Stream(mask) => mask
        _ => return None
      }
    None => return None
  }
  let mask_width = match dict_value_int(page, mask_stream.dict, "Width") {
    Some(n) => n
    None => width
  }
  let mask_height = match dict_value_int(page, mask_stream.dict, "Height") {
    Some(n) => n
    None => height
  }
  if mask_width <= 0 || mask_height <= 0 {
    return None
  }
  let data = @pdf.decode_stream(mask_stream) catch { _ => return None }
  if data.length() < mask_width * mask_height {
    return None
  }
  let alpha : Array[Byte] = Array::make(width * height, u8(255))
  let mut y = 0
  while y < height {
    let mut x = 0
    while x < width {
      let mx = x * mask_width / width
      let my = y * mask_height / height
      alpha[y * width + x] = data.at(my * mask_width + mx)
      x = x + 1
    }
    y = y + 1
  }
  Some(alpha)
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
  if width > 16384 || height > 16384 || width * height > 64000000 {
    raise RenderError("image dimensions are too large")
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
    let alpha = decode_soft_mask(page, stream, jpeg.width, jpeg.height)
    return {
      width: jpeg.width,
      height: jpeg.height,
      components: 3,
      data: jpeg.data,
      alpha,
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
  let alpha = decode_soft_mask(page, stream, width, height)
  { width, height, components, data, alpha, }
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
fn sample_alpha(image : ImageData, x : Int32, y : Int32) -> Int32 {
  match image.alpha {
    Some(alpha) => {
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
      alpha[py * image.width + px].to_int()
    }
    None => 255
  }
}

///|
/// Paint an image into the unit square, transformed by the current CTM. The
/// sampler is nearest-neighbour; bilinear sampling is a later refinement.

///|
fn sample_rgb_bilinear(
  image : ImageData,
  u : Double,
  v : Double,
) -> (Int32, Int32, Int32) {
  let x0 = @math.floor(u).to_int()
  let y0 = @math.floor(v).to_int()
  let fx = u - x0.to_double()
  let fy = v - y0.to_double()
  let (r00, g00, b00) = sample_rgb(image, x0, y0)
  let (r10, g10, b10) = sample_rgb(image, x0 + 1, y0)
  let (r01, g01, b01) = sample_rgb(image, x0, y0 + 1)
  let (r11, g11, b11) = sample_rgb(image, x0 + 1, y0 + 1)
  let blend = fn(a : Int32, b : Int32, c : Int32, d : Int32) -> Int32 {
    let top = a.to_double() * (1.0 - fx) + b.to_double() * fx
    let bottom = c.to_double() * (1.0 - fx) + d.to_double() * fx
    (top * (1.0 - fy) + bottom * fy).to_int()
  }
  (
    blend(r00, r10, r01, r11),
    blend(g00, g10, g01, g11),
    blend(b00, b10, b01, b11),
  )
}

///|
fn sample_alpha_bilinear(image : ImageData, u : Double, v : Double) -> Int32 {
  let x0 = @math.floor(u).to_int()
  let y0 = @math.floor(v).to_int()
  let fx = u - x0.to_double()
  let fy = v - y0.to_double()
  let top = sample_alpha(image, x0, y0).to_double() * (1.0 - fx) +
    sample_alpha(image, x0 + 1, y0).to_double() * fx
  let bottom = sample_alpha(image, x0, y0 + 1).to_double() * (1.0 - fx) +
    sample_alpha(image, x0 + 1, y0 + 1).to_double() * fx
  (top * (1.0 - fy) + bottom * fy).to_int()
}

///|
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
        let u = p.x * (image.width - 1).to_double()
        let v = (1.0 - p.y) * (image.height - 1).to_double()
        let (r, g, b) = sample_rgb_bilinear(image, u, v)
        let alpha = sample_alpha_bilinear(image, u, v)
        canvas.set_alpha(alpha_component(state.fill_alpha) * alpha / 255)
        canvas.set(x, y, r, g, b)
      }
      x = x + 1
    }
    y = y + 1
  }
  canvas.set_alpha(alpha_component(state.fill_alpha))
}
