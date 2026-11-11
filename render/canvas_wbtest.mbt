///|
test "fill polygon and read pixels" {
  let canvas = Canvas::new(4, 4, 255, 255, 255)
  let square : Array[Point] = [
    { x: 0.0, y: 0.0, },
    { x: 4.0, y: 0.0, },
    { x: 4.0, y: 4.0, },
    { x: 0.0, y: 4.0, },
  ]
  canvas.fill_polygons([square], false, 255, 0, 0)
  assert_eq(canvas.data[0].to_int(), 255)
  assert_eq(canvas.data[1].to_int(), 0)
  assert_eq(canvas.data[2].to_int(), 0)
}

///|
test "downsample averages pixels" {
  let canvas = Canvas::new(2, 2, 255, 255, 255)
  canvas.set(0, 0, 0, 0, 0)
  let small = canvas.downsample(2)
  assert_eq(small.width, 1)
  assert_eq(small.height, 1)
  assert_eq(small.data[0].to_int(), 191)
}

///|
test "stroke leaves pixels on both sides" {
  let canvas = Canvas::new(20, 20, 255, 255, 255)
  let line : Array[Point] = [{ x: 2.0, y: 10.0, }, { x: 18.0, y: 10.0, }]
  canvas.stroke_polyline(line, false, 4.0, false, 0, 0, 0)
  assert_eq(canvas.data[(10 * 20 + 10) * 3].to_int(), 0)
  assert_eq(canvas.data[(8 * 20 + 10) * 3].to_int(), 0)
  assert_eq(canvas.data[(2 * 20 + 10) * 3].to_int(), 255)
}
