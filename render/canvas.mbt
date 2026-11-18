///|
/// Simple RGB raster canvas. Pixels are stored row-major, three bytes per
/// pixel. Rendering is done at a supersampled resolution and downsampled once,
/// which keeps the rasterizer itself free of coverage bookkeeping.
pub struct Canvas {
  width : Int32
  height : Int32
  data : Array[Byte]
  mut clip_x0 : Int32
  mut clip_y0 : Int32
  mut clip_x1 : Int32
  mut clip_y1 : Int32
  mut alpha : Int32
  mut blend_mode : Int32
  mut clip_mask : Array[Byte]?
}

///|
fn u8(value : Int32) -> Byte {
  value.to_byte()
}

///|
fn clamp_byte(value : Int32) -> Int32 {
  if value < 0 {
    0
  } else if value > 255 {
    255
  } else {
    value
  }
}

///|
pub fn Canvas::new(
  width : Int32,
  height : Int32,
  r : Int32,
  g : Int32,
  b : Int32,
) -> Canvas {
  let data : Array[Byte] = Array::make(width * height * 3, u8(255))
  let canvas = {
    width,
    height,
    data,
    clip_x0: 0,
    clip_y0: 0,
    clip_x1: width,
    clip_y1: height,
    alpha: 255,
    blend_mode: 0,
    clip_mask: None,
  }
  let mut i = 0
  while i < width * height {
    canvas.data[i * 3] = u8(clamp_byte(r))
    canvas.data[i * 3 + 1] = u8(clamp_byte(g))
    canvas.data[i * 3 + 2] = u8(clamp_byte(b))
    i = i + 1
  }
  canvas
}

///|
pub fn Canvas::width(self : Canvas) -> Int32 {
  self.width
}

///|
pub fn Canvas::height(self : Canvas) -> Int32 {
  self.height
}

///|
fn blend_channel(mode : Int32, backdrop : Int32, source : Int32) -> Int32 {
  let d = clamp_byte(backdrop)
  let s = clamp_byte(source)
  match mode {
    1 => d * s / 255 // Multiply
    2 => 255 - (255 - d) * (255 - s) / 255 // Screen
    3 =>
      if d < 128 {
        2 * d * s / 255
      } else {
        255 - 2 * (255 - d) * (255 - s) / 255
      } // Overlay
    4 => if d < s { d } else { s } // Darken
    5 => if d > s { d } else { s } // Lighten
    6 =>
      if s >= 255 {
        255
      } else {
        let value = d * 255 / (255 - s)
        if value > 255 {
          255
        } else {
          value
        }
      } // ColorDodge
    7 =>
      if s <= 0 {
        0
      } else {
        let value = 255 - (255 - d) * 255 / s
        if value < 0 {
          0
        } else {
          value
        }
      } // ColorBurn
    8 =>
      if s < 128 {
        2 * s * d / 255
      } else {
        255 - 2 * (255 - s) * (255 - d) / 255
      } // HardLight
    9 => {
      let value = if s < 128 {
        d - (255 - 2 * s) * d * (255 - d) / (255 * 255)
      } else {
        d +
        (2 * s - 255) *
        (if d < 64 { d * 4 } else { 255 }) *
        (255 - d) /
        (255 * 255)
      }
      clamp_byte(value)
    } // SoftLight (approximation)
    10 => {
      let value = d - s
      if value < 0 {
        -value
      } else {
        value
      }
    } // Difference
    _ => clamp_byte(d + s - 2 * d * s / 255) // Exclusion
  }
}

///|
pub fn Canvas::set_blend(self : Canvas, mode : Int32) -> Unit {
  self.blend_mode = mode
}

///|
pub fn Canvas::set(
  self : Canvas,
  x : Int32,
  y : Int32,
  r : Int32,
  g : Int32,
  b : Int32,
) -> Unit {
  if x < self.clip_x0 ||
    y < self.clip_y0 ||
    x >= self.clip_x1 ||
    y >= self.clip_y1 {
    return
  }
  if x < 0 || y < 0 || x >= self.width || y >= self.height {
    return
  }
  match self.clip_mask {
    Some(mask) => if mask[y * self.width + x].to_int() == 0 { return }
    None => ()
  }
  let idx = (y * self.width + x) * 3
  let dr = self.data[idx].to_int()
  let dg = self.data[idx + 1].to_int()
  let db = self.data[idx + 2].to_int()
  let sr = if self.blend_mode == 0 {
    clamp_byte(r)
  } else {
    blend_channel(self.blend_mode, dr, r)
  }
  let sg = if self.blend_mode == 0 {
    clamp_byte(g)
  } else {
    blend_channel(self.blend_mode, dg, g)
  }
  let sb = if self.blend_mode == 0 {
    clamp_byte(b)
  } else {
    blend_channel(self.blend_mode, db, b)
  }
  let a = self.alpha
  if a >= 255 {
    self.data[idx] = u8(sr)
    self.data[idx + 1] = u8(sg)
    self.data[idx + 2] = u8(sb)
  } else if a > 0 {
    let inverse = 255 - a
    self.data[idx] = u8((sr * a + dr * inverse) / 255)
    self.data[idx + 1] = u8((sg * a + dg * inverse) / 255)
    self.data[idx + 2] = u8((sb * a + db * inverse) / 255)
  }
}

///|
pub fn Canvas::set_alpha(self : Canvas, alpha : Int32) -> Unit {
  self.alpha = if alpha < 0 { 0 } else if alpha > 255 { 255 } else { alpha }
}

///|
pub fn Canvas::to_rgb_bytes(self : Canvas) -> Bytes {
  Bytes::from_array(self.data)
}

///|
priv struct Crossing {
  x : Double
  wind : Int32
}

///|
fn mask_span(
  mask : Array[Byte],
  width : Int32,
  height : Int32,
  y : Int32,
  x0 : Double,
  x1 : Double,
) -> Unit {
  if y < 0 || y >= height || x1 <= x0 {
    return
  }
  let mut start = x0.to_int()
  let mut stop = x1.to_int()
  if start < 0 {
    start = 0
  }
  if stop >= width {
    stop = width - 1
  }
  let mut x = start
  while x <= stop {
    mask[y * width + x] = u8(1)
    x = x + 1
  }
}

///|
fn fill_span(
  canvas : Canvas,
  y : Int32,
  x0 : Double,
  x1 : Double,
  r : Int32,
  g : Int32,
  b : Int32,
) -> Unit {
  if x1 <= x0 {
    return
  }
  let mut start = x0.to_int()
  let mut stop = x1.to_int()
  if start < 0 {
    start = 0
  }
  if stop >= canvas.width {
    stop = canvas.width - 1
  }
  let mut x = start
  while x <= stop {
    canvas.set(x, y, r, g, b)
    x = x + 1
  }
}

///|
fn sort_crossings(items : Array[Crossing]) -> Unit {
  let mut i = 1
  while i < items.length() {
    let value = items[i]
    let mut j = i - 1
    while j >= 0 && items[j].x > value.x {
      items[j + 1] = items[j]
      j = j - 1
    }
    items[j + 1] = value
    i = i + 1
  }
}

///|
/// Scanline polygon fill with even-odd or nonzero winding.
pub fn Canvas::fill_polygons(
  self : Canvas,
  polygons : Array[Array[Point]],
  even_odd : Bool,
  r : Int32,
  g : Int32,
  b : Int32,
) -> Unit {
  let mut ymin = 1.0e30
  let mut ymax = -1.0e30
  for poly in polygons {
    for p in poly {
      if p.y < ymin {
        ymin = p.y
      }
      if p.y > ymax {
        ymax = p.y
      }
    }
  }
  if ymin > ymax {
    return
  }
  let mut y0 = ymin.to_int()
  if y0 < 0 {
    y0 = 0
  }
  let mut y1 = ymax.to_int() + 1
  if y1 > self.height {
    y1 = self.height
  }
  let mut y = y0
  while y < y1 {
    let scan = y.to_double() + 0.5
    let items : Array[Crossing] = Array(capacity=16)
    for poly in polygons {
      let n = poly.length()
      if n < 3 {
        continue
      }
      let mut i = 0
      while i < n {
        let p1 = poly[i]
        let p2 = poly[(i + 1) % n]
        let y1f = p1.y
        let y2f = p2.y
        if (y1f <= scan && y2f > scan) || (y2f <= scan && y1f > scan) {
          let t = (scan - y1f) / (y2f - y1f)
          let x = p1.x + t * (p2.x - p1.x)
          let wind = if y2f > y1f { 1 } else { -1 }
          items.push({ x, wind, })
        }
        i = i + 1
      }
    }
    if items.length() > 0 {
      sort_crossings(items)
      if even_odd {
        let mut i = 0
        while i + 1 < items.length() {
          fill_span(self, y, items[i].x, items[i + 1].x, r, g, b)
          i = i + 2
        }
      } else {
        let mut winding = 0
        let mut i = 0
        while i + 1 < items.length() {
          winding = winding + items[i].wind
          if winding != 0 {
            fill_span(self, y, items[i].x, items[i + 1].x, r, g, b)
          }
          i = i + 1
        }
      }
    }
    y = y + 1
  }
}

///|
fn circle_polygon(
  cx : Double,
  cy : Double,
  radius : Double,
  segments : Int32,
) -> Array[Point] {
  let pts : Array[Point] = Array(capacity=segments)
  let mut i = 0
  while i < segments {
    let angle = 6.283185307179586 * i.to_double() / segments.to_double()
    pts.push({
      x: cx + radius * @math.cos(angle),
      y: cy + radius * @math.sin(angle),
    })
    i = i + 1
  }
  pts
}

///|
/// Stroke a polyline by filling one quad per segment and round joins/caps.
/// This is deliberately an approximation: it is correct for the common case
/// and much simpler than a full stroker with miter/bevel joins.
pub fn Canvas::stroke_polyline(
  self : Canvas,
  points : Array[Point],
  closed : Bool,
  width : Double,
  round_caps : Bool,
  r : Int32,
  g : Int32,
  b : Int32,
) -> Unit {
  if points.length() < 2 || width <= 0.0 {
    return
  }
  let half = width / 2.0
  let n = points.length()
  let segment_count = if closed { n } else { n - 1 }
  let mut i = 0
  while i < segment_count {
    let p1 = points[i]
    let p2 = points[(i + 1) % n]
    let dx = p2.x - p1.x
    let dy = p2.y - p1.y
    let len = @math.hypot(dx, dy)
    if len > 0.000001 {
      let nx = -dy / len * half
      let ny = dx / len * half
      let quad : Array[Point] = [
        { x: p1.x + nx, y: p1.y + ny, },
        { x: p2.x + nx, y: p2.y + ny, },
        { x: p2.x - nx, y: p2.y - ny, },
        { x: p1.x - nx, y: p1.y - ny, },
      ]
      self.fill_polygons([quad], false, r, g, b)
    }
    i = i + 1
  }
  let mut j = 0
  while j < n {
    let p = points[j]
    let at_end = !closed && (j == 0 || j == n - 1)
    if !at_end || round_caps {
      self.fill_polygons([circle_polygon(p.x, p.y, half, 12)], false, r, g, b)
    }
    j = j + 1
  }
}

///|
/// Box-filter downsample by an integer factor.
pub fn Canvas::downsample(self : Canvas, factor : Int32) -> Canvas {
  if factor <= 1 {
    return self
  }
  let out_w = self.width / factor
  let out_h = self.height / factor
  let out = Canvas::new(out_w, out_h, 255, 255, 255)
  let mut y = 0
  while y < out_h {
    let mut x = 0
    while x < out_w {
      let mut rs = 0
      let mut gs = 0
      let mut bs = 0
      let mut sy = 0
      while sy < factor {
        let mut sx = 0
        while sx < factor {
          let px = x * factor + sx
          let py = y * factor + sy
          let idx = (py * self.width + px) * 3
          rs = rs + self.data[idx].to_int()
          gs = gs + self.data[idx + 1].to_int()
          bs = bs + self.data[idx + 2].to_int()
          sx = sx + 1
        }
        sy = sy + 1
      }
      let count = factor * factor
      out.set(x, y, rs / count, gs / count, bs / count)
      x = x + 1
    }
    y = y + 1
  }
  out
}

///|
/// Intersect the current canvas clip with a device-space rectangle.
pub fn Canvas::set_clip(
  self : Canvas,
  x0 : Int32,
  y0 : Int32,
  x1 : Int32,
  y1 : Int32,
) -> Unit {
  let nx0 = if x0 > self.clip_x0 { x0 } else { self.clip_x0 }
  let ny0 = if y0 > self.clip_y0 { y0 } else { self.clip_y0 }
  let nx1 = if x1 < self.clip_x1 { x1 } else { self.clip_x1 }
  let ny1 = if y1 < self.clip_y1 { y1 } else { self.clip_y1 }
  self.clip_x0 = nx0
  self.clip_y0 = ny0
  self.clip_x1 = if nx1 > nx0 { nx1 } else { nx0 }
  self.clip_y1 = if ny1 > ny0 { ny1 } else { ny0 }
}

///|
pub fn Canvas::reset_clip(
  self : Canvas,
  x0 : Int32,
  y0 : Int32,
  x1 : Int32,
  y1 : Int32,
) -> Unit {
  self.clip_x0 = x0
  self.clip_y0 = y0
  self.clip_x1 = x1
  self.clip_y1 = y1
}

///|
pub fn Canvas::clip_rect(self : Canvas) -> (Int32, Int32, Int32, Int32) {
  (self.clip_x0, self.clip_y0, self.clip_x1, self.clip_y1)
}

///|
fn rasterize_mask(
  width : Int32,
  height : Int32,
  polygons : Array[Array[Point]],
  even_odd : Bool,
) -> Array[Byte] {
  let mask : Array[Byte] = Array::make(width * height, u8(0))
  let mut ymin = 1.0e30
  let mut ymax = -1.0e30
  for poly in polygons {
    for p in poly {
      if p.y < ymin {
        ymin = p.y
      }
      if p.y > ymax {
        ymax = p.y
      }
    }
  }
  if ymin > ymax {
    return mask
  }
  let mut y0 = ymin.to_int()
  if y0 < 0 {
    y0 = 0
  }
  let mut y1 = ymax.to_int() + 1
  if y1 > height {
    y1 = height
  }
  let mut y = y0
  while y < y1 {
    let scan = y.to_double() + 0.5
    let items : Array[Crossing] = Array(capacity=16)
    for poly in polygons {
      let n = poly.length()
      if n < 3 {
        continue
      }
      let mut i = 0
      while i < n {
        let p1 = poly[i]
        let p2 = poly[(i + 1) % n]
        let y1f = p1.y
        let y2f = p2.y
        if (y1f <= scan && y2f > scan) || (y2f <= scan && y1f > scan) {
          let t = (scan - y1f) / (y2f - y1f)
          let x = p1.x + t * (p2.x - p1.x)
          let wind = if y2f > y1f { 1 } else { -1 }
          items.push({ x, wind, })
        }
        i = i + 1
      }
    }
    if items.length() > 0 {
      sort_crossings(items)
      if even_odd {
        let mut i = 0
        while i + 1 < items.length() {
          mask_span(mask, width, height, y, items[i].x, items[i + 1].x)
          i = i + 2
        }
      } else {
        let mut winding = 0
        let mut i = 0
        while i + 1 < items.length() {
          winding = winding + items[i].wind
          if winding != 0 {
            mask_span(mask, width, height, y, items[i].x, items[i + 1].x)
          }
          i = i + 1
        }
      }
    }
    y = y + 1
  }
  mask
}

///|
/// Intersect the current clip with a filled path, using a per-pixel mask.
pub fn Canvas::clip_polygons(
  self : Canvas,
  polygons : Array[Array[Point]],
  even_odd : Bool,
) -> Unit {
  let next = rasterize_mask(self.width, self.height, polygons, even_odd)
  match self.clip_mask {
    Some(previous) => {
      let mut i = 0
      while i < next.length() {
        if previous[i].to_int() == 0 {
          next[i] = u8(0)
        }
        i = i + 1
      }
    }
    None => ()
  }
  self.clip_mask = Some(next)
}

///|
pub fn Canvas::clip_mask(self : Canvas) -> Array[Byte]? {
  self.clip_mask
}

///|
pub fn Canvas::set_clip_mask(self : Canvas, mask : Array[Byte]?) -> Unit {
  self.clip_mask = mask
}
