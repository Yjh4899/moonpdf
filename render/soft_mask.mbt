///|
fn soft_mask_components(
  page : @pdf.PdfPage,
  dict : Array[(String, @pdf.PdfValue)],
) -> (Int32, Int32, Int32) {
  match @pdf.dict_get(dict, "BC") {
    Some(value) =>
      match page.resolve(value).as_array() {
        Some(items) =>
          if items.length() >= 3 {
            match
              (items[0].as_number(), items[1].as_number(), items[2].as_number()) {
              (Some(r), Some(g), Some(b)) =>
                (color_component(r), color_component(g), color_component(b))
              _ => (0, 0, 0)
            }
          } else if items.length() == 1 {
            match items[0].as_number() {
              Some(gray) => {
                let value = color_component(gray)
                (value, value, value)
              }
              None => (0, 0, 0)
            }
          } else {
            (0, 0, 0)
          }
        None => (0, 0, 0)
      }
    None => (0, 0, 0)
  }
}

///|
/// Build a page-sized soft-mask plane from an ExtGState `/SMask` dictionary.
/// Luminosity masks use the rendered luminance; alpha masks use the same
/// white/black backdrop extraction as isolated transparency groups.
fn render_soft_mask(
  page : @pdf.PdfPage,
  mask_dict : Array[(String, @pdf.PdfValue)],
  canvas : Canvas,
  state : GState,
  depth : Int32,
) -> Array[Byte]? {
  if depth > 6 {
    return None
  }
  let form = match @pdf.dict_get(mask_dict, "G") {
    Some(value) =>
      match page.resolve(value) {
        @pdf.Stream(stream) => stream
        _ => return None
      }
    None => return None
  }
  let bbox = match group_bbox(page, form.dict) {
    Some(bbox) => bbox
    None => return None
  }
  let (bx0, by0, bx1, by1) = bbox
  let bw = bx1 - bx0
  let bh = by1 - by0
  if bw <= 0.0 || bh <= 0.0 {
    return None
  }
  let subtype = match @pdf.dict_get(mask_dict, "S") {
    Some(value) =>
      match value.as_name() {
        Some(name) => name
        None => "Luminosity"
      }
    None => "Luminosity"
  }
  let data = @pdf.decode_stream(form) catch { _ => return None }
  let matrix = form_matrix(page, form.dict)
  let prefix = @utf8.encode(
    "q\n\{matrix.a} \{matrix.b} \{matrix.c} \{matrix.d} \{matrix.e} \{matrix.f} cm\n1 0 0 1 \{(-bx0)} \{(-by0)} cm\n",
  )
  let suffix = @utf8.encode("\nQ\n")
  let buf = @buffer.Buffer::Buffer()
  buf.write_bytes(prefix)
  buf.write_bytes(data)
  buf.write_bytes(suffix)
  let resources = match @pdf.dict_get(form.dict, "Resources") {
    Some(value) => page.resolve_dict(value)
    None => page.resources
  }
  let cell = @pdf.make_page(
    bw,
    bh,
    0.0,
    0.0,
    bw,
    bh,
    0,
    [buf.to_bytes()],
    resources,
    [],
    [],
    page.objects,
  )
  let (bc_r, bc_g, bc_b) = soft_mask_components(page, mask_dict)
  let options : RenderOptions = {
    scale: 1.0,
    supersample: 1,
    bg_r: bc_r,
    bg_g: bc_g,
    bg_b: bc_b,
  }
  let rendered = render_page_inner(cell, options, depth + 1) catch {
    _ => return None
  }
  let (white, black) = if subtype == "Alpha" {
    let white_options : RenderOptions = {
      scale: 1.0,
      supersample: 1,
      bg_r: 255,
      bg_g: 255,
      bg_b: 255,
    }
    let black_options : RenderOptions = {
      scale: 1.0,
      supersample: 1,
      bg_r: 0,
      bg_g: 0,
      bg_b: 0,
    }
    let white = render_page_inner(cell, white_options, depth + 1) catch {
      _ => return None
    }
    let black = render_page_inner(cell, black_options, depth + 1) catch {
      _ => return None
    }
    (white, black)
  } else {
    (rendered, rendered)
  }
  let mask : Array[Byte] = Array::make(canvas.width * canvas.height, u8(0))
  let group_matrix = matrix.then(state.ctm)
  let inverse = match group_matrix.invert() {
    Some(inverse) => inverse
    None => return None
  }
  let p0 = group_matrix.apply(bx0, by0)
  let p1 = group_matrix.apply(bx1, by0)
  let p2 = group_matrix.apply(bx1, by1)
  let p3 = group_matrix.apply(bx0, by1)
  let dx0 = @math.floor(dmin(dmin(p0.x, p1.x), dmin(p2.x, p3.x))).to_int() - 1
  let dy0 = @math.floor(dmin(dmin(p0.y, p1.y), dmin(p2.y, p3.y))).to_int() - 1
  let dx1 = @math.ceil(dmax(dmax(p0.x, p1.x), dmax(p2.x, p3.x))).to_int() + 1
  let dy1 = @math.ceil(dmax(dmax(p0.y, p1.y), dmax(p2.y, p3.y))).to_int() + 1
  let mut y = dy0
  while y <= dy1 {
    let mut x = dx0
    while x <= dx1 {
      if x >= 0 && y >= 0 && x < canvas.width && y < canvas.height {
        let p = inverse.apply(x.to_double() + 0.5, y.to_double() + 0.5)
        if p.x >= bx0 && p.x <= bx1 && p.y >= by0 && p.y <= by1 {
          let u = (p.x - bx0) / bw
          let v = (by1 - p.y) / bh
          let mut tx = (u * bw).to_int()
          let mut ty = (v * bh).to_int()
          if tx < 0 {
            tx = 0
          }
          if ty < 0 {
            ty = 0
          }
          if tx >= rendered.width {
            tx = rendered.width - 1
          }
          if ty >= rendered.height {
            ty = rendered.height - 1
          }
          let idx = (ty * rendered.width + tx) * 3
          let value = if subtype == "Alpha" {
            group_color(white, black, tx, ty, 255, 255, 255).3
          } else {
            let r = rendered.pixels.at(idx).to_int()
            let g = rendered.pixels.at(idx + 1).to_int()
            let b = rendered.pixels.at(idx + 2).to_int()
            (r * 30 + g * 59 + b * 11) / 100
          }
          mask[y * canvas.width + x] = u8(value)
        }
      }
      x = x + 1
    }
    y = y + 1
  }
  Some(mask)
}
