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
  // Green body from the appended content stream, clear of the black text.
  let body = (120 * raster.width + 250) * 3
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
test "flate image xobject" {
  let raster = match
    @integration.rasterize(
      @integration.fixture_bytes("fixtures/image-flate.pdf"),
      1.0,
    ) {
    Some(raster) => raster
    None => {
      assert_true(false)
      return
    }
  }
  assert_eq(raster.width, 200)
  assert_eq(raster.height, 200)
  let left = (100 * raster.width + 70) * 3
  assert_true(raster.pixels.at(left).to_int() > 180) // red
  let right = (100 * raster.width + 130) * 3
  assert_true(raster.pixels.at(right + 2).to_int() > 180) // blue
  let center = (100 * raster.width + 100) * 3
  assert_true(raster.pixels.at(center + 1).to_int() > 150) // green
}

///|
test "baseline jpeg image xobject" {
  let raster = match
    @integration.rasterize(
      @integration.fixture_bytes("fixtures/image-jpeg.pdf"),
      1.0,
    ) {
    Some(raster) => raster
    None => {
      assert_true(false)
      return
    }
  }
  assert_eq(raster.width, 200)
  assert_eq(raster.height, 200)
  let red = (70 * raster.width + 70) * 3
  let blue = (70 * raster.width + 130) * 3
  let green = (130 * raster.width + 70) * 3
  let yellow = (130 * raster.width + 130) * 3
  assert_true(raster.pixels.at(red).to_int() > 150)
  assert_true(raster.pixels.at(blue + 2).to_int() > 150)
  assert_true(raster.pixels.at(green + 1).to_int() > 150)
  assert_true(raster.pixels.at(yellow).to_int() > 180)
}

///|
test "rotate and crop page geometry" {
  let raster = match
    @integration.rasterize(
      @integration.fixture_bytes("fixtures/rotate-crop.pdf"),
      1.0,
    ) {
    Some(raster) => raster
    None => {
      assert_true(false)
      return
    }
  }
  assert_eq(raster.width, 160)
  assert_eq(raster.height, 300)
  let top = (50 * raster.width + 20) * 3
  let bottom = (250 * raster.width + 20) * 3
  assert_true(raster.pixels.at(top).to_int() > 180) // red
  assert_true(raster.pixels.at(bottom + 2).to_int() > 150) // blue
}

///|
test "rectangular clip path" {
  let raster = match
    @integration.rasterize(@integration.fixture_bytes("fixtures/clip.pdf"), 1.0) {
    Some(raster) => raster
    None => {
      assert_true(false)
      return
    }
  }
  let corner = (10 * raster.width + 10) * 3
  let center = (100 * raster.width + 100) * 3
  assert_true(raster.pixels.at(corner).to_int() > 180) // red
  assert_true(raster.pixels.at(center + 2).to_int() > 180) // blue
}

///|
test "inline image" {
  let raster = match
    @integration.rasterize(
      @integration.fixture_bytes("fixtures/inline-image.pdf"),
      1.0,
    ) {
    Some(raster) => raster
    None => {
      assert_true(false)
      return
    }
  }
  assert_eq(raster.width, 200)
  assert_eq(raster.height, 200)
  let center = (100 * raster.width + 100) * 3
  assert_true(raster.pixels.at(center).to_int() > 180)
  assert_true(raster.pixels.at(center + 1).to_int() < 60)
}

///|
test "truetype cmap and glyph outlines" {
  let font = try! @render.parse_truetype(
    @integration.fixture_bytes("fixtures/fonts/OpenSans.ttf"),
  )
  let glyph = font.glyph_id(65) // 'A'
  assert_true(glyph > 0)
  let contours = try! font.glyph_contours(glyph)
  assert_true(contours.length() > 0)
  let accented = font.glyph_id(233) // 'é' is usually a composite glyph
  assert_true(accented > 0)
  let accented_contours = try! font.glyph_contours(accented)
  assert_true(accented_contours.length() >= 2)
  assert_true(font.units_per_em() > 0)
}

///|
test "embedded truetype font renders glyph outlines" {
  let raster = match
    @integration.rasterize(
      @integration.fixture_bytes("fixtures/font-embedded.pdf"),
      1.0,
    ) {
    Some(raster) => raster
    None => {
      assert_true(false)
      return
    }
  }
  assert_eq(raster.width, 340)
  assert_eq(raster.height, 150)
  let mut dark = 0
  let mut i = 0
  while i < raster.pixels.length() {
    if raster.pixels.at(i).to_int() < 128 {
      dark = dark + 1
    }
    i = i + 1
  }
  assert_true(dark > 500)
}

///|
test "embedded CFF font renders charstrings" {
  let raster = match
    @integration.rasterize(
      @integration.fixture_bytes("fixtures/font-cff.pdf"),
      1.0,
    ) {
    Some(raster) => raster
    None => {
      assert_true(false)
      return
    }
  }
  assert_eq(raster.width, 340)
  assert_eq(raster.height, 150)
  let mut dark = 0
  let mut i = 0
  while i < raster.pixels.length() {
    if raster.pixels.at(i).to_int() < 128 {
      dark = dark + 1
    }
    i = i + 1
  }
  assert_true(dark > 500)
}

///|
test "standard 14 font metrics" {
  let helvetica = match @render.standard14_widths("Helvetica") {
    Some(widths) => widths
    None => {
      assert_true(false)
      return
    }
  }
  assert_eq(helvetica[0], 278) // space
  assert_eq(helvetica[33], 667) // 'A'
  let courier = match @render.standard14_widths("Courier-Bold") {
    Some(widths) => widths
    None => {
      assert_true(false)
      return
    }
  }
  assert_eq(courier[33], 600) // monospaced
}

///|
test "type0 CIDFontType2 with Identity-H" {
  let raster = match
    @integration.rasterize(
      @integration.fixture_bytes("fixtures/font-cid.pdf"),
      1.0,
    ) {
    Some(raster) => raster
    None => {
      assert_true(false)
      return
    }
  }
  assert_eq(raster.width, 340)
  assert_eq(raster.height, 150)
  let mut dark = 0
  let mut i = 0
  while i < raster.pixels.length() {
    if raster.pixels.at(i).to_int() < 128 {
      dark = dark + 1
    }
    i = i + 1
  }
  assert_true(dark > 500)
}

///|
test "type1 charstrings" {
  let font = try! @render.parse_type1(
    @integration.fixture_bytes("fixtures/fonts/lmr10.pfb"),
  )
  let path = try! font.glyph_path("A", @render.Matrix::identity(), 100.0)
  assert_true(path is Some(_))
  let accented = try! font.glyph_path(
    "eacute",
    @render.Matrix::identity(),
    100.0,
  )
  assert_true(accented is Some(_))
}

///|
test "type1 font program renders outlines" {
  let raster = match
    @integration.rasterize(
      @integration.fixture_bytes("fixtures/font-type1.pdf"),
      1.0,
    ) {
    Some(raster) => raster
    None => {
      assert_true(false)
      return
    }
  }
  assert_eq(raster.width, 340)
  assert_eq(raster.height, 150)
  let mut dark = 0
  let mut i = 0
  while i < raster.pixels.length() {
    if raster.pixels.at(i).to_int() < 128 {
      dark = dark + 1
    }
    i = i + 1
  }
  assert_true(dark > 500)
}

///|
test "CID-keyed CFF renders CJK glyphs" {
  let cff = try! @render.parse_cff(
    @integration.fixture_bytes("fixtures/fonts/NotoSansCJKsc-Subset.cff"),
  )
  assert_eq(cff.glyph_for_cid(9987), 2)
  let raster = match
    @integration.rasterize(
      @integration.fixture_bytes("fixtures/font-cid-cff.pdf"),
      1.0,
    ) {
    Some(raster) => raster
    None => {
      assert_true(false)
      return
    }
  }
  assert_eq(raster.width, 300)
  assert_eq(raster.height, 150)
  let mut dark = 0
  let mut i = 0
  while i < raster.pixels.length() {
    if raster.pixels.at(i).to_int() < 128 {
      dark = dark + 1
    }
    i = i + 1
  }
  assert_true(dark > 500)
}

///|
test "embedded Type0 encoding CMap" {
  let raster = match
    @integration.rasterize(
      @integration.fixture_bytes("fixtures/font-cid-cmap.pdf"),
      1.0,
    ) {
    Some(raster) => raster
    None => {
      assert_true(false)
      return
    }
  }
  assert_eq(raster.width, 300)
  assert_eq(raster.height, 150)
  let mut dark = 0
  let mut i = 0
  while i < raster.pixels.length() {
    if raster.pixels.at(i).to_int() < 128 {
      dark = dark + 1
    }
    i = i + 1
  }
  assert_true(dark > 500)
}

///|
test "standard 14 kerning" {
  let pairs = match @render.standard14_kerning("Helvetica") {
    Some(pairs) => pairs
    None => {
      assert_true(false)
      return
    }
  }
  let mut av = 0
  for entry in pairs {
    if entry.0 == 65 && entry.1 == 86 {
      av = entry.2
    }
  }
  assert_eq(av, -70)
  let courier = match @render.standard14_kerning("Courier") {
    Some(pairs) => pairs
    None => {
      assert_true(false)
      return
    }
  }
  assert_eq(courier.length(), 0)
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
