///|
test "png signature and ihdr" {
  let pixels = Bytes::make(2 * 2 * 3, 0)
  let page : RenderedPage = { width: 2, height: 2, pixels, }
  let png = encode_png(page)
  assert_eq(png.at(0).to_int(), 137)
  assert_eq(png.at(1).to_int(), 80)
  assert_eq(png.at(2).to_int(), 78)
  assert_eq(png.at(3).to_int(), 71)
  assert_eq(@utf8.decode_lossy(png.exact_view(start=12, end=16)), "IHDR")
}
