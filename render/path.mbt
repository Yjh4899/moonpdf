///|
/// A path in device space. Curves are flattened as they are added, so the
/// rasterizer only ever sees polylines. This keeps fill/stroke logic small and
/// makes flattening tolerance an explicit, testable policy.
pub struct Path {
  subpaths : Array[Array[Point]]
  closed_flags : Array[Bool]
  mut current : Array[Point]
  mut current_closed : Bool
}

///|
pub fn Path::new() -> Path {
  { subpaths: [], closed_flags: [], current: [], current_closed: false, }
}

///|
fn Path::flush(self : Path) -> Unit {
  if self.current.length() > 0 {
    self.subpaths.push(self.current)
    self.closed_flags.push(self.current_closed)
    self.current = []
    self.current_closed = false
  }
}

///|
pub fn Path::move_to(self : Path, p : Point) -> Unit {
  self.flush()
  self.current.push(p)
}

///|
pub fn Path::line_to(self : Path, p : Point) -> Unit {
  if self.current.length() == 0 {
    self.current.push(p)
  } else {
    self.current.push(p)
  }
}

///|
fn flatten_cubic(
  out : Array[Point],
  p0 : Point,
  p1 : Point,
  p2 : Point,
  p3 : Point,
) -> Unit {
  let segments = 16
  let mut i = 1
  while i <= segments {
    let t = i.to_double() / segments.to_double()
    let mt = 1.0 - t
    let a = mt * mt * mt
    let b = 3.0 * mt * mt * t
    let c = 3.0 * mt * t * t
    let d = t * t * t
    out.push({
      x: a * p0.x + b * p1.x + c * p2.x + d * p3.x,
      y: a * p0.y + b * p1.y + c * p2.y + d * p3.y,
    })
    i = i + 1
  }
}

///|
pub fn Path::curve_to(self : Path, c1 : Point, c2 : Point, p : Point) -> Unit {
  let start = if self.current.length() > 0 {
    self.current[self.current.length() - 1]
  } else {
    c1
  }
  flatten_cubic(self.current, start, c1, c2, p)
}

///|
pub fn Path::quad_to(self : Path, c : Point, p : Point) -> Unit {
  let start = if self.current.length() > 0 {
    self.current[self.current.length() - 1]
  } else {
    c
  }
  let c1 = {
    x: start.x + 2.0 / 3.0 * (c.x - start.x),
    y: start.y + 2.0 / 3.0 * (c.y - start.y),
  }
  let c2 = {
    x: p.x + 2.0 / 3.0 * (c.x - p.x),
    y: p.y + 2.0 / 3.0 * (c.y - p.y),
  }
  flatten_cubic(self.current, start, c1, c2, p)
}

///|
pub fn Path::close(self : Path) -> Unit {
  self.current_closed = true
  self.flush()
}

///|
pub fn Path::rect(
  self : Path,
  x : Double,
  y : Double,
  w : Double,
  h : Double,
) -> Unit {
  self.move_to({ x, y, })
  self.line_to({ x: x + w, y, })
  self.line_to({ x: x + w, y: y + h, })
  self.line_to({ x, y: y + h, })
  self.close()
}

///|
pub fn Path::finish(self : Path) -> (Array[Array[Point]], Array[Bool]) {
  self.flush()
  (self.subpaths, self.closed_flags)
}
