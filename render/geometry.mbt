///|
pub struct Point {
  x : Double
  y : Double
}

///|
pub fn point(x : Double, y : Double) -> Point {
  { x, y, }
}

///|
/// Affine matrix using PDF's row-vector convention:
/// `x' = a*x + c*y + e`, `y' = b*x + d*y + f`.
pub struct Matrix {
  a : Double
  b : Double
  c : Double
  d : Double
  e : Double
  f : Double
}

///|
pub fn Matrix::identity() -> Matrix {
  { a: 1.0, b: 0.0, c: 0.0, d: 1.0, e: 0.0, f: 0.0, }
}

///|
pub fn Matrix::new(
  a : Double,
  b : Double,
  c : Double,
  d : Double,
  e : Double,
  f : Double,
) -> Matrix {
  { a, b, c, d, e, f, }
}

///|
pub fn Matrix::translate(tx : Double, ty : Double) -> Matrix {
  { a: 1.0, b: 0.0, c: 0.0, d: 1.0, e: tx, f: ty, }
}

///|
pub fn Matrix::scale(sx : Double, sy : Double) -> Matrix {
  { a: sx, b: 0.0, c: 0.0, d: sy, e: 0.0, f: 0.0, }
}

///|
pub fn Matrix::rotate(radians : Double) -> Matrix {
  let cos = @math.cos(radians)
  let sin = @math.sin(radians)
  { a: cos, b: sin, c: -sin, d: cos, e: 0.0, f: 0.0, }
}

///|
/// Compose two matrices: apply `self` first, then `other`.
pub fn Matrix::then(self : Matrix, other : Matrix) -> Matrix {
  {
    a: self.a * other.a + self.b * other.c,
    b: self.a * other.b + self.b * other.d,
    c: self.c * other.a + self.d * other.c,
    d: self.c * other.b + self.d * other.d,
    e: self.e * other.a + self.f * other.c + other.e,
    f: self.e * other.b + self.f * other.d + other.f,
  }
}

///|
pub fn Matrix::apply(self : Matrix, x : Double, y : Double) -> Point {
  { x: self.a * x + self.c * y + self.e, y: self.b * x + self.d * y + self.f, }
}

///|
pub fn Matrix::scale_factor(self : Matrix) -> Double {
  let sx = @math.hypot(self.a, self.b)
  let sy = @math.hypot(self.c, self.d)
  (sx + sy) / 2.0
}
