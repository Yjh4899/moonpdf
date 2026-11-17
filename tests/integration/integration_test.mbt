///|
test "incremental update reuses old form resource" {
  let data = @integration.fixture_bytes("fixtures/incremental.pdf")
  let document = try! @pdf.parse_document(data)
  assert_eq(document.page_count(), 1)
  let page = match document.page(0) {
    Some(page) => page
    None => {
      assert_true(false)
      return
    }
  }
  // The updated page references [4 0 R 7 0 R]: old content plus new content.
  assert_eq(page.contents.length(), 2)
  let resources = @pdf.dict_get(page.resources, "XObject")
  assert_true(resources is Some(_))
  let raster = match @integration.rasterize(data, 1.0) {
    Some(raster) => raster
    None => {
      assert_true(false)
      return
    }
  }
  assert_eq(raster.width, 300)
  assert_eq(raster.height, 200)
  // Blue header from the reused Form XObject, around y=40.
  let header = (40 * raster.width + 150) * 3
  assert_true(raster.pixels.at(header + 2).to_int() > 150)
  // Green body from the appended content stream, around y=120.
  let body = (120 * raster.width + 150) * 3
  assert_true(raster.pixels.at(body + 1).to_int() > 120)
}

///|
test "incremental render equals full rewrite" {
  let incremental = match
    @integration.rasterize(
      @integration.fixture_bytes("fixtures/incremental.pdf"),
      1.0,
    ) {
    Some(raster) => raster
    None => {
      assert_true(false)
      return
    }
  }
  let full = match
    @integration.rasterize(
      @integration.fixture_bytes("fixtures/incremental-full.pdf"),
      1.0,
    ) {
    Some(raster) => raster
    None => {
      assert_true(false)
      return
    }
  }
  assert_eq(incremental.width, full.width)
  assert_eq(incremental.height, full.height)
  assert_eq(incremental.pixels.length(), full.pixels.length())
  let mut i = 0
  while i < incremental.pixels.length() {
    assert_eq(incremental.pixels.at(i).to_int(), full.pixels.at(i).to_int())
    i = i + 1
  }
}

///|
test "xref stream and object stream fixture" {
  let data = @integration.fixture_bytes("fixtures/xref-stream.pdf")
  let document = try! @pdf.parse_document(data)
  assert_eq(document.page_count(), 1)
  let raster = match @integration.rasterize(data, 1.0) {
    Some(raster) => raster
    None => {
      assert_true(false)
      return
    }
  }
  assert_eq(raster.width, 320)
  assert_eq(raster.height, 200)
  let blue = (100 * raster.width + 100) * 3
  assert_true(raster.pixels.at(blue + 2).to_int() > 150)
}
