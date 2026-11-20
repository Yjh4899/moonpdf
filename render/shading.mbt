///|
/// Axial (type 2) and radial (type 3) shadings with a type 2 exponential
/// function. Shading coordinates live in the current user space.
pub struct Shading {
  kind : Int32
  coords : Array[Double]
  c0 : Array[Double]
  c1 : Array[Double]
  exponent : Double
  components : Int32
  extend0 : Bool
  extend1 : Bool
}

///|
fn shading_numbers(
  page : @pdf.PdfPage,
  dict : Array[(String, @pdf.PdfValue)],
  key : String,
) -> Array[Double] {
  let out : Array[Double] = []
  match @pdf.dict_get(dict, key) {
    Some(value) =>
      match page.resolve(value).as_array() {
        Some(items) =>
          for item in items {
            match page.resolve(item).as_number() {
              Some(n) => out.push(n)
              None => out.push(0.0)
            }
          }
        None => ()
      }
    None => ()
  }
  out
}

///|
fn shading_extend(
  page : @pdf.PdfPage,
  dict : Array[(String, @pdf.PdfValue)],
) -> (Bool, Bool) {
  match @pdf.dict_get(dict, "Extend") {
    Some(value) =>
      match page.resolve(value).as_array() {
        Some(items) =>
          if items.length() >= 2 {
            let first = match page.resolve(items[0]) {
              @pdf.Bool(flag) => flag
              _ => false
            }
            let second = match page.resolve(items[1]) {
              @pdf.Bool(flag) => flag
              _ => false
            }
            (first, second)
          } else {
            (false, false)
          }
        None => (false, false)
      }
    None => (false, false)
  }
}

///|
pub fn load_shading(page : @pdf.PdfPage, value : @pdf.PdfValue) -> Shading? {
  let dict = page.resolve_dict(value)
  if dict.length() == 0 {
    return None
  }
  let kind = match @pdf.dict_get(dict, "ShadingType") {
    Some(value) =>
      match value.as_int() {
        Some(n) => n
        None => 2
      }
    None => 2
  }
  if kind != 2 && kind != 3 {
    return None
  }
  let coords = shading_numbers(page, dict, "Coords")
  if kind == 2 && coords.length() < 4 {
    return None
  }
  if kind == 3 && coords.length() < 6 {
    return None
  }
  let components = match @pdf.dict_get(dict, "ColorSpace") {
    Some(value) => color_components(page, value) catch { _ => 1 }
    None => 1
  }
  let mut c0 : Array[Double] = []
  let mut c1 : Array[Double] = []
  let mut exponent = 1.0
  match @pdf.dict_get(dict, "Function") {
    Some(function_value) =>
      match page.resolve(function_value) {
        @pdf.Dict(function_dict) => {
          let function_type = match
            @pdf.dict_get(function_dict, "FunctionType") {
            Some(value) => value.as_int()
            None => None
          }
          if function_type == Some(2) {
            c0 = shading_numbers(page, function_dict, "C0")
            c1 = shading_numbers(page, function_dict, "C1")
            match @pdf.dict_get(function_dict, "N") {
              Some(value) =>
                match value.as_number() {
                  Some(n) => exponent = n
                  None => ()
                }
              None => ()
            }
          }
        }
        _ => ()
      }
    None => ()
  }
  if c0.length() == 0 {
    let mut i = 0
    while i < components {
      c0.push(0.0)
      i = i + 1
    }
  }
  if c1.length() == 0 {
    let mut i = 0
    while i < components {
      c1.push(1.0)
      i = i + 1
    }
  }
  let (extend0, extend1) = shading_extend(page, dict)
  Some({ kind, coords, c0, c1, exponent, components, extend0, extend1, })
}

///|
fn shading_t(shading : Shading, point : Point) -> Double? {
  if shading.kind == 2 {
    let x0 = shading.coords[0]
    let y0 = shading.coords[1]
    let x1 = shading.coords[2]
    let y1 = shading.coords[3]
    let dx = x1 - x0
    let dy = y1 - y0
    let denom = dx * dx + dy * dy
    if denom <= 0.0000001 {
      return Some(0.0)
    }
    let t = ((point.x - x0) * dx + (point.y - y0) * dy) / denom
    if t < 0.0 && !shading.extend0 {
      return None
    }
    if t > 1.0 && !shading.extend1 {
      return None
    }
    Some(if t < 0.0 { 0.0 } else if t > 1.0 { 1.0 } else { t })
  } else {
    let x0 = shading.coords[0]
    let y0 = shading.coords[1]
    let r0 = shading.coords[2]
    let x1 = shading.coords[3]
    let y1 = shading.coords[4]
    let r1 = shading.coords[5]
    let d0 = @math.hypot(point.x - x0, point.y - y0) - r0
    let d1 = @math.hypot(point.x - x1, point.y - y1) - r1
    let denom = d1 - d0
    if denom <= 0.0000001 && denom >= -0.0000001 {
      return Some(0.0)
    }
    let t = d0 / denom
    if t < 0.0 && !shading.extend0 {
      return None
    }
    if t > 1.0 && !shading.extend1 {
      return None
    }
    Some(if t < 0.0 { 0.0 } else if t > 1.0 { 1.0 } else { t })
  }
}

///|
fn shading_color(shading : Shading, t : Double) -> (Int32, Int32, Int32) {
  let factor = if shading.exponent == 1.0 {
    t
  } else if shading.exponent == 2.0 {
    t * t
  } else if shading.exponent == 3.0 {
    t * t * t
  } else {
    t
  }
  let components = shading.components
  let values : Array[Double] = Array(capacity=components)
  let mut i = 0
  while i < components {
    let a = if i < shading.c0.length() { shading.c0[i] } else { 0.0 }
    let b = if i < shading.c1.length() { shading.c1[i] } else { 1.0 }
    values.push(a + (b - a) * factor)
    i = i + 1
  }
  if components == 1 {
    let v = color_component(values[0])
    (v, v, v)
  } else if components == 3 {
    (
      color_component(values[0]),
      color_component(values[1]),
      color_component(values[2]),
    )
  } else if components == 4 {
    let c = values[0]
    let m = values[1]
    let y = values[2]
    let k = values[3]
    (
      color_component((1.0 - c) * (1.0 - k)),
      color_component((1.0 - m) * (1.0 - k)),
      color_component((1.0 - y) * (1.0 - k)),
    )
  } else {
    (0, 0, 0)
  }
}

///|
/// Paint a shading over the current clip region.
fn paint_shading(canvas : Canvas, state : GState, shading : Shading) -> Unit {
  let inverse = match state.ctm.invert() {
    Some(matrix) => matrix
    None => return
  }
  let (x0, y0, x1, y1) = canvas.clip_rect()
  canvas.set_alpha(alpha_component(state.fill_alpha))
  canvas.set_blend(state.blend_mode)
  let mut y = y0
  while y < y1 {
    let mut x = x0
    while x < x1 {
      let point = inverse.apply(x.to_double() + 0.5, y.to_double() + 0.5)
      match shading_t(shading, point) {
        Some(t) => {
          let (r, g, b) = shading_color(shading, t)
          canvas.set(x, y, r, g, b)
        }
        None => ()
      }
      x = x + 1
    }
    y = y + 1
  }
}
