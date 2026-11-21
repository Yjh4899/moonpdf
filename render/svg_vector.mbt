///|
/// A small vector SVG exporter for pages made of paths. Text, images, shadings,
/// patterns and clips return `None` so the caller can fall back to the embedded
/// PNG container.
priv struct SvgState {
  mut ctm : Matrix
  mut fill_r : Int32
  mut fill_g : Int32
  mut fill_b : Int32
  mut stroke_r : Int32
  mut stroke_g : Int32
  mut stroke_b : Int32
  mut line_width : Double
}

///|
fn svg_write(buf : @buffer.Buffer, text : String) -> Unit {
  buf.write_bytes(@utf8.encode(text))
}

///|
fn svg_double(value : Double) -> String {
  if value > -0.000001 && value < 0.000001 {
    "0"
  } else {
    "\{value}"
  }
}

///|
fn svg_color(r : Int32, g : Int32, b : Int32) -> String {
  "rgb(\{clamp_byte(r)},\{clamp_byte(g)},\{clamp_byte(b)})"
}

///|
fn svg_path_data(
  subpaths : Array[Array[Point]],
  closed : Array[Bool],
) -> String {
  let buf = @buffer.Buffer::Buffer()
  let mut i = 0
  while i < subpaths.length() {
    let points = subpaths[i]
    if points.length() > 0 {
      let first = points[0]
      svg_write(buf, "M \{svg_double(first.x)} \{svg_double(first.y)} ")
      let mut j = 1
      while j < points.length() {
        let p = points[j]
        svg_write(buf, "L \{svg_double(p.x)} \{svg_double(p.y)} ")
        j = j + 1
      }
      if closed[i] {
        svg_write(buf, "Z ")
      }
    }
    i = i + 1
  }
  @utf8.decode_lossy(buf.to_bytes())
}

///|
fn svg_paint(
  body : @buffer.Buffer,
  state : SvgState,
  path : Path,
  fill : Bool,
  stroke : Bool,
  even_odd : Bool,
) -> Unit {
  let (subpaths, closed) = path.finish()
  let data = svg_path_data(subpaths, closed)
  if data.length() == 0 {
    return
  }
  svg_write(body, "<path d=\"")
  svg_write(body, data)
  svg_write(body, "\"")
  if fill {
    svg_write(body, " fill=\"")
    svg_write(body, svg_color(state.fill_r, state.fill_g, state.fill_b))
    svg_write(body, "\"")
    if even_odd {
      svg_write(body, " fill-rule=\"evenodd\"")
    }
  } else {
    svg_write(body, " fill=\"none\"")
  }
  if stroke {
    svg_write(body, " stroke=\"")
    svg_write(body, svg_color(state.stroke_r, state.stroke_g, state.stroke_b))
    svg_write(body, "\" stroke-width=\"")
    svg_write(body, svg_double(state.line_width * state.ctm.scale_factor()))
    svg_write(body, "\"")
  }
  svg_write(body, "/>\n")
}

///|
fn svg_apply_gray(state : SvgState, value : Double, stroke : Bool) -> Unit {
  let c = color_component(value)
  if stroke {
    state.stroke_r = c
    state.stroke_g = c
    state.stroke_b = c
  } else {
    state.fill_r = c
    state.fill_g = c
    state.fill_b = c
  }
}

///|
fn svg_apply_rgb(
  state : SvgState,
  r : Double,
  g : Double,
  b : Double,
  stroke : Bool,
) -> Unit {
  let cr = color_component(r)
  let cg = color_component(g)
  let cb = color_component(b)
  if stroke {
    state.stroke_r = cr
    state.stroke_g = cg
    state.stroke_b = cb
  } else {
    state.fill_r = cr
    state.fill_g = cg
    state.fill_b = cb
  }
}

///|
fn svg_apply_cmyk(
  state : SvgState,
  c : Double,
  m : Double,
  y : Double,
  k : Double,
  stroke : Bool,
) -> Unit {
  svg_apply_rgb(
    state,
    (1.0 - c) * (1.0 - k),
    (1.0 - m) * (1.0 - k),
    (1.0 - y) * (1.0 - k),
    stroke,
  )
}
