///|
test "singular matrix cannot be inverted" {
  let m = Matrix::new(0.0, 0.0, 0.0, 0.0, 10.0, 20.0)
  assert_true(m.invert() is None)
}

///|
test "matrix inverse round-trips a point" {
  let m = Matrix::new(2.0, 0.0, 0.0, 0.5, 10.0, 20.0)
  let inv = match m.invert() {
    Some(value) => value
    None => {
      assert_true(false)
      return
    }
  }
  let p = m.apply(3.0, 4.0)
  let q = inv.apply(p.x, p.y)
  assert_true(q.x > 2.999 && q.x < 3.001)
  assert_true(q.y > 3.999 && q.y < 4.001)
}

///|
test "alpha and color components clamp at both ends" {
  assert_eq(alpha_component(-1.0), 0)
  assert_eq(alpha_component(2.0), 255)
  assert_eq(alpha_component(0.5), 127)
  assert_eq(color_component(-0.5), 0)
  assert_eq(color_component(1.5), 255)
  assert_eq(color_component(0.5), 127)
}

///|
test "fill span with reversed or empty range is a no-op" {
  let canvas = Canvas::new(4, 1, 255, 255, 255)
  fill_span(canvas, 0, 1.6, 1.4, 0, 0, 0)
  fill_span(canvas, 0, 2.0, 2.0, 0, 0, 0)
  for i in 0..<4 {
    assert_eq(canvas.data[i * 3].to_int(), 255)
  }
}

///|
test "fill span uses pixel centers at fractional boundaries" {
  let canvas = Canvas::new(4, 1, 255, 255, 255)
  fill_span(canvas, 0, 0.4, 1.6, 0, 0, 0)
  assert_eq(canvas.data[0].to_int(), 0)
  assert_eq(canvas.data[3].to_int(), 0)
  assert_eq(canvas.data[6].to_int(), 255)
  assert_eq(canvas.data[9].to_int(), 255)
}

///|
test "downsample factor one preserves the canvas" {
  let canvas = Canvas::new(2, 2, 255, 255, 255)
  canvas.set(0, 0, 10, 20, 30)
  let same = canvas.downsample(1)
  assert_eq(same.width, 2)
  assert_eq(same.height, 2)
  assert_eq(same.data[0].to_int(), 10)
  assert_eq(same.data[1].to_int(), 20)
  assert_eq(same.data[2].to_int(), 30)
}

///|
test "downsample factor three halves each axis" {
  let canvas = Canvas::new(6, 6, 255, 255, 255)
  let small = canvas.downsample(3)
  assert_eq(small.width, 2)
  assert_eq(small.height, 2)
  assert_eq(small.data.length(), 2 * 2 * 3)
}

///|
test "clip rejects pixels outside its rectangle" {
  let canvas = Canvas::new(4, 4, 255, 255, 255)
  canvas.set_clip(1, 1, 2, 2)
  let square : Array[Point] = [
    { x: 0.0, y: 0.0, },
    { x: 4.0, y: 0.0, },
    { x: 4.0, y: 4.0, },
    { x: 0.0, y: 4.0, },
  ]
  canvas.fill_polygons([square], false, 255, 0, 0)
  assert_eq(canvas.data[(1 * 4 + 1) * 3].to_int(), 255)
  assert_eq(canvas.data[(0 * 4 + 0) * 3].to_int(), 255)
  assert_eq(canvas.data[(0 * 4 + 0) * 3 + 1].to_int(), 255)
}

///|
test "multiply blend handles both channel extremes" {
  assert_eq(blend_channel(1, 0, 255), 0)
  assert_eq(blend_channel(1, 255, 255), 255)
  assert_eq(blend_channel(2, 0, 0), 0)
  assert_eq(blend_channel(2, 255, 0), 255)
}

///|
test "darken and lighten choose the expected channel" {
  assert_eq(blend_channel(4, 20, 200), 20)
  assert_eq(blend_channel(5, 20, 200), 200)
  assert_eq(blend_channel(10, 200, 20), 180)
}

///|
test "luminosity blend with white source yields white" {
  let (r, g, b) = blend_hsl(15, 255, 0, 0, 255, 255, 255)
  assert_eq(r, 255)
  assert_eq(g, 255)
  assert_eq(b, 255)
}

///|
test "image sampling clamps outside coordinates" {
  let image : ImageData = {
    width: 2,
    height: 2,
    components: 3,
    data: Bytes::from_array([
      u8(255),
      u8(0),
      u8(0),
      u8(0),
      u8(255),
      u8(0),
      u8(0),
      u8(0),
      u8(255),
      u8(255),
      u8(255),
      u8(255),
    ]),
    alpha: None,
  }
  let (r, _g, _b) = sample_rgb(image, -5, -5)
  assert_eq(r, 255)
  let (nr, ng, nb) = sample_rgb(image, 99, 99)
  assert_eq(nr, 255)
  assert_eq(ng, 255)
  assert_eq(nb, 255)
  assert_eq(sample_alpha(image, 0, 0), 255)
}

///|
test "bilinear sampling at integer coordinates matches nearest" {
  let image : ImageData = {
    width: 2,
    height: 1,
    components: 3,
    data: Bytes::from_array([u8(0), u8(0), u8(0), u8(255), u8(255), u8(255)]),
    alpha: None,
  }
  assert_eq(sample_rgb_bilinear(image, 0.0, 0.0), (0, 0, 0))
  assert_eq(sample_rgb_bilinear(image, 1.0, 0.0), (255, 255, 255))
}

///|
test "empty and comment-only content streams produce no operators" {
  assert_eq(@pdf.parse_content_stream(@utf8.encode("")).length(), 0)
  assert_eq(@pdf.parse_content_stream(@utf8.encode("  \n\t\n")).length(), 0)
  assert_eq(
    @pdf.parse_content_stream(@utf8.encode("% only a comment\n")).length(),
    0,
  )
}

///|
test "comments between operators are ignored" {
  let ops = @pdf.parse_content_stream(@utf8.encode("q % comment\n Q"))
  assert_eq(ops.length(), 2)
  assert_eq(ops.at(0).op, "q")
  assert_eq(ops.at(1).op, "Q")
}

///|
test "rotation inverse cancels rotation" {
  let angle = 0.7
  let rotation = Matrix::rotate(angle)
  let inverse = match rotation.invert() {
    Some(value) => value
    None => {
      assert_true(false)
      return
    }
  }
  let p = rotation.then(inverse).apply(3.0, 4.0)
  assert_true(p.x > 2.999 && p.x < 3.001)
  assert_true(p.y > 3.999 && p.y < 4.001)
}
