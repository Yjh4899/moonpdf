///|
test "matrix composition" {
  let m = Matrix::translate(10.0, 20.0).then(Matrix::scale(2.0, 2.0))
  let p = m.apply(1.0, 1.0)
  assert_eq(p.x, 22.0)
  assert_eq(p.y, 42.0)
}

///|
test "matrix rotation keeps length" {
  let m = Matrix::rotate(1.5707963267948966)
  let p = m.apply(1.0, 0.0)
  assert_true(p.x < 0.000001 && p.x > -0.000001)
  assert_true(p.y > 0.999)
}
