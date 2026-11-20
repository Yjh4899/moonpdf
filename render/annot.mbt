///|
fn annotation_normal_form(
  page : @pdf.PdfPage,
  annot : Array[(String, @pdf.PdfValue)],
  ap : Array[(String, @pdf.PdfValue)],
) -> @pdf.PdfStream? {
  let normal = match @pdf.dict_get(ap, "N") {
    Some(value) => page.resolve(value)
    None => return None
  }
  match normal {
    @pdf.Stream(stream) => Some(stream)
    @pdf.Dict(states) => {
      let state = match @pdf.dict_get(annot, "AS") {
        Some(value) =>
          match value.as_name() {
            Some(name) => name
            None => ""
          }
        None => ""
      }
      if state != "" {
        match @pdf.dict_get(states, state) {
          Some(value) =>
            match page.resolve(value) {
              @pdf.Stream(stream) => Some(stream)
              _ => None
            }
          None => None
        }
      } else {
        let mut found : @pdf.PdfStream? = None
        for entry in states {
          match page.resolve(entry.1) {
            @pdf.Stream(stream) => {
              found = Some(stream)
              break
            }
            _ => ()
          }
        }
        found
      }
    }
    _ => None
  }
}

///|
/// Render annotation appearance streams on top of page content.
pub fn draw_annotations(
  page : @pdf.PdfPage,
  canvas : Canvas,
  base : Matrix,
  depth : Int32,
) -> Unit {
  if depth > 4 {
    return
  }
  canvas.reset_clip(0, 0, canvas.width, canvas.height)
  canvas.set_clip_mask(None)
  canvas.set_alpha(255)
  canvas.set_blend(0)
  for item in page.annots {
    let annot = page.resolve_dict(item)
    if annot.length() == 0 {
      continue
    }
    let rect = match @pdf.dict_get(annot, "Rect") {
      Some(value) =>
        match page.resolve(value).as_array() {
          Some(items) =>
            if items.length() >= 4 {
              match
                (
                  page.resolve(items[0]).as_number(),
                  page.resolve(items[1]).as_number(),
                  page.resolve(items[2]).as_number(),
                  page.resolve(items[3]).as_number(),
                ) {
                (Some(x0), Some(y0), Some(x1), Some(y1)) =>
                  Some((x0, y0, x1, y1))
                _ => None
              }
            } else {
              None
            }
          None => None
        }
      None => None
    }
    let (rx0, ry0, rx1, ry1) = match rect {
      Some(rect) => rect
      None => continue
    }
    let rw = if rx1 > rx0 { rx1 - rx0 } else { rx0 - rx1 }
    let rh = if ry1 > ry0 { ry1 - ry0 } else { ry0 - ry1 }
    if rw <= 0.0 || rh <= 0.0 {
      continue
    }
    let ap = match @pdf.dict_get(annot, "AP") {
      Some(value) => page.resolve_dict(value)
      None => []
    }
    let form = match annotation_normal_form(page, annot, ap) {
      Some(stream) => stream
      None => continue
    }
    let bbox = match @pdf.dict_get(form.dict, "BBox") {
      Some(value) =>
        match page.resolve(value).as_array() {
          Some(items) =>
            if items.length() >= 4 {
              match
                (
                  page.resolve(items[0]).as_number(),
                  page.resolve(items[1]).as_number(),
                  page.resolve(items[2]).as_number(),
                  page.resolve(items[3]).as_number(),
                ) {
                (Some(x0), Some(y0), Some(x1), Some(y1)) => (x0, y0, x1, y1)
                _ => (0.0, 0.0, rw, rh)
              }
            } else {
              (0.0, 0.0, rw, rh)
            }
          None => (0.0, 0.0, rw, rh)
        }
      None => (0.0, 0.0, rw, rh)
    }
    let (bx0, by0, bx1, by1) = bbox
    let bw = bx1 - bx0
    let bh = by1 - by0
    if bw <= 0.0 || bh <= 0.0 {
      continue
    }
    let data = @pdf.decode_stream(form) catch { _ => continue }
    let sx = rw / bw
    let sy = rh / bh
    let prefix = @utf8.encode(
      "q\n\{sx} 0 0 \{sy} \{(-bx0 * sx)} \{(-by0 * sy)} cm\n",
    )
    let buf = @buffer.Buffer::Buffer()
    buf.write_bytes(prefix)
    buf.write_bytes(data)
    buf.write_bytes(@utf8.encode("\nQ\n"))
    let resources = match @pdf.dict_get(form.dict, "Resources") {
      Some(value) => page.resolve_dict(value)
      None => page.resources
    }
    let synthetic = @pdf.make_page(
      rw,
      rh,
      0.0,
      0.0,
      rw,
      rh,
      0,
      [buf.to_bytes()],
      resources,
      [],
      page.objects,
    )
    let tile = render_page_inner(
      synthetic,
      RenderOptions::with_scale(1.0),
      depth + 1,
    ) catch {
      _ => continue
    }
    let p0 = base.apply(rx0, ry0)
    let p1 = base.apply(rx1, ry1)
    let dx0 = (if p0.x < p1.x { p0.x } else { p1.x }).to_int()
    let dy0 = (if p0.y < p1.y { p0.y } else { p1.y }).to_int()
    let dx1 = (if p0.x > p1.x { p0.x } else { p1.x }).to_int() + 1
    let dy1 = (if p0.y > p1.y { p0.y } else { p1.y }).to_int() + 1
    let mut y = dy0
    while y < dy1 {
      let mut x = dx0
      while x < dx1 {
        let u = (x.to_double() + 0.5 - dx0.to_double()) /
          (dx1 - dx0).to_double()
        let v = (y.to_double() + 0.5 - dy0.to_double()) /
          (dy1 - dy0).to_double()
        let mut tx = (u * tile.width.to_double()).to_int()
        let mut ty = (v * tile.height.to_double()).to_int()
        if tx < 0 {
          tx = 0
        }
        if ty < 0 {
          ty = 0
        }
        if tx >= tile.width {
          tx = tile.width - 1
        }
        if ty >= tile.height {
          ty = tile.height - 1
        }
        let idx = (ty * tile.width + tx) * 3
        canvas.set(
          x,
          y,
          tile.pixels.at(idx).to_int(),
          tile.pixels.at(idx + 1).to_int(),
          tile.pixels.at(idx + 2).to_int(),
        )
        x = x + 1
      }
      y = y + 1
    }
  }
}
