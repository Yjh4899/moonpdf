///|
fn group_is_transparency(
  page : @pdf.PdfPage,
  dict : Array[(String, @pdf.PdfValue)],
) -> Bool {
  match @pdf.dict_get(dict, "Group") {
    Some(value) => {
      let group = page.resolve_dict(value)
      match @pdf.dict_get(group, "S") {
        Some(value) =>
          match value.as_name() {
            Some(name) => name == "Transparency"
            None => false
          }
        None => false
      }
    }
    None => false
  }
}

///|
fn group_bbox(
  page : @pdf.PdfPage,
  dict : Array[(String, @pdf.PdfValue)],
) -> (Double, Double, Double, Double)? {
  match @pdf.dict_get(dict, "BBox") {
    Some(value) =>
      match page.resolve(value).as_array() {
        Some(items) =>
          if items.length() >= 4 {
            match
              (
                items[0].as_number(),
                items[1].as_number(),
                items[2].as_number(),
                items[3].as_number(),
              ) {
              (Some(x0), Some(y0), Some(x1), Some(y1)) =>
                if x1 > x0 && y1 > y0 {
                  Some((x0, y0, x1, y1))
                } else {
                  None
                }
              _ => None
            }
          } else {
            None
          }
        None => None
      }
    None => None
  }
}

///|
fn group_color(
  white : RenderedPage,
  black : RenderedPage,
  tx : Int32,
  ty : Int32,
  out_r : Int32,
  out_g : Int32,
  out_b : Int32,
) -> (Int32, Int32, Int32, Int32) {
  let idx = (ty * white.width + tx) * 3
  let wr = white.pixels.at(idx).to_int()
  let wg = white.pixels.at(idx + 1).to_int()
  let wb = white.pixels.at(idx + 2).to_int()
  let br = black.pixels.at(idx).to_int()
  let bg = black.pixels.at(idx + 1).to_int()
  let bb = black.pixels.at(idx + 2).to_int()
  let diff = (wr - br + (wg - bg) + (wb - bb)) / 3
  let mut alpha = 255 - diff
  if alpha < 0 {
    alpha = 0
  }
  if alpha > 255 {
    alpha = 255
  }
  if alpha == 0 {
    (0, 0, 0, 0)
  } else {
    let r = br * 255 / alpha
    let g = bg * 255 / alpha
    let b = bb * 255 / alpha
    (
      if r < out_r {
        r
      } else {
        out_r
      },
      if g < out_g {
        g
      } else {
        out_g
      },
      if b < out_b {
        b
      } else {
        out_b
      },
      alpha,
    )
  }
}

///|
/// Render an isolated transparency Form group. The group content is rendered
/// twice, on white and black backdrops; the difference recovers per-pixel alpha
/// and the black render recovers the unpremultiplied color.
fn render_transparency_group(
  page : @pdf.PdfPage,
  stream : @pdf.PdfStream,
  canvas : Canvas,
  state : GState,
  depth : Int32,
) -> Unit {
  if depth > 6 {
    return
  }
  let bbox = match group_bbox(page, stream.dict) {
    Some(bbox) => bbox
    None => return
  }
  let (bx0, by0, bx1, by1) = bbox
  let bw = bx1 - bx0
  let bh = by1 - by0
  if bw <= 0.0 || bh <= 0.0 {
    return
  }
  let data = @pdf.decode_stream(stream) catch { _ => return }
  let matrix = form_matrix(page, stream.dict)
  let prefix = @utf8.encode(
    "q\n\{matrix.a} \{matrix.b} \{matrix.c} \{matrix.d} \{matrix.e} \{matrix.f} cm\n1 0 0 1 \{(-bx0)} \{(-by0)} cm\n",
  )
  let suffix = @utf8.encode("\nQ\n")
  let buf = @buffer.Buffer::Buffer()
  buf.write_bytes(prefix)
  buf.write_bytes(data)
  buf.write_bytes(suffix)
  let resources = match @pdf.dict_get(stream.dict, "Resources") {
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
    _ => return
  }
  let black = render_page_inner(cell, black_options, depth + 1) catch {
    _ => return
  }
  let group_matrix = matrix.then(state.ctm)
  let inverse = match group_matrix.invert() {
    Some(inverse) => inverse
    None => return
  }
  let p0 = group_matrix.apply(bx0, by0)
  let p1 = group_matrix.apply(bx1, by0)
  let p2 = group_matrix.apply(bx1, by1)
  let p3 = group_matrix.apply(bx0, by1)
  let dx0 = @math.floor(dmin(dmin(p0.x, p1.x), dmin(p2.x, p3.x))).to_int() - 1
  let dy0 = @math.floor(dmin(dmin(p0.y, p1.y), dmin(p2.y, p3.y))).to_int() - 1
  let dx1 = @math.ceil(dmax(dmax(p0.x, p1.x), dmax(p2.x, p3.x))).to_int() + 1
  let dy1 = @math.ceil(dmax(dmax(p0.y, p1.y), dmax(p2.y, p3.y))).to_int() + 1
  let group_alpha = alpha_component(state.fill_alpha)
  canvas.set_blend(state.blend_mode)
  let mut y = dy0
  while y <= dy1 {
    let mut x = dx0
    while x <= dx1 {
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
        if tx >= white.width {
          tx = white.width - 1
        }
        if ty >= white.height {
          ty = white.height - 1
        }
        let (r, g, b, alpha) = group_color(white, black, tx, ty, 255, 255, 255)
        if alpha > 0 {
          canvas.set_alpha(group_alpha * alpha / 255)
          canvas.set(x, y, r, g, b)
        }
      }
      x = x + 1
    }
    y = y + 1
  }
  canvas.set_alpha(alpha_component(state.fill_alpha))
}
