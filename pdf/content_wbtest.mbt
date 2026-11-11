///|
test "parse content stream operators" {
  let ops = parse_content_stream(
    @utf8.encode("q 1 0 0 1 10 20 cm 0 0 100 50 re f Q"),
  )
  assert_eq(ops.length(), 5)
  assert_eq(ops.at(0).op, "q")
  assert_eq(ops.at(1).op, "cm")
  assert_eq(ops.at(1).operands.length(), 6)
  assert_eq(ops.at(2).op, "re")
  assert_eq(ops.at(3).op, "f")
  assert_eq(ops.at(4).op, "Q")
}

///|
test "parse text operators and strings" {
  let ops = parse_content_stream(
    @utf8.encode("BT /F1 12 Tf 1 0 0 1 20 40 Tm (Hi) Tj ET"),
  )
  assert_eq(ops.length(), 5)
  assert_eq(ops.at(0).op, "BT")
  assert_eq(ops.at(1).op, "Tf")
  assert_eq(ops.at(2).op, "Tm")
  assert_eq(ops.at(3).op, "Tj")
  assert_eq(ops.at(4).op, "ET")
  match ops.at(3).operands.at(0) {
    Str(bytes) => assert_eq(@utf8.decode_lossy(bytes), "Hi")
    _ => assert_true(false)
  }
}
