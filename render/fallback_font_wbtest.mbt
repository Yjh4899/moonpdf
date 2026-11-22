///|
test "embedded fallback font decodes" {
  assert_true(fallback_truetype() is Some(_))
}
