///|
/// A PDF pattern resource. Shading patterns (type 2) are supported; tiling
/// patterns (type 1) currently fall back to the solid fill color.
pub struct Pattern {
  shading : Shading?
}

///|
pub fn load_pattern(page : @pdf.PdfPage, value : @pdf.PdfValue) -> Pattern? {
  let dict = page.resolve_dict(value)
  if dict.length() == 0 {
    return None
  }
  let kind = match @pdf.dict_get(dict, "PatternType") {
    Some(value) =>
      match value.as_int() {
        Some(n) => n
        None => 1
      }
    None => 1
  }
  if kind == 2 {
    match @pdf.dict_get(dict, "Shading") {
      Some(shading_value) => {
        let shading = load_shading(page, shading_value)
        Some({ shading, })
      }
      None => None
    }
  } else {
    Some({ shading: None, })
  }
}

///|
fn paint_pattern(
  canvas : Canvas,
  state : GState,
  subpaths : Array[Array[Point]],
  even_odd : Bool,
  pattern : Pattern,
) -> Unit {
  match pattern.shading {
    Some(shading) => {
      let previous = canvas.clip_mask()
      canvas.clip_polygons(subpaths, even_odd)
      paint_shading(canvas, state, shading)
      canvas.set_clip_mask(previous)
    }
    None => ()
  }
}
