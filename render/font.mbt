///|
/// A compact 3x5 bitmap fallback font. It keeps the first vertical slice
/// readable without embedding a font engine; outline fonts are a later
/// milestone and live behind the same text-drawing interface.
fn glyph_rows(code : Int32) -> Array[Int32] {
  match code {
    32 => [0, 0, 0, 0, 0] // space
    33 => [2, 2, 2, 0, 2] // !
    40 => [1, 2, 2, 2, 1] // (
    41 => [4, 2, 2, 2, 4] // )
    44 => [0, 0, 0, 2, 4] // ,
    45 => [0, 0, 7, 0, 0] // -
    46 => [0, 0, 0, 0, 2] // .
    47 => [1, 1, 2, 4, 4] // /
    48 => [7, 5, 5, 5, 7] // 0
    49 => [2, 6, 2, 2, 7] // 1
    50 => [7, 1, 7, 4, 7] // 2
    51 => [7, 1, 7, 1, 7] // 3
    52 => [5, 5, 7, 1, 1] // 4
    53 => [7, 4, 7, 1, 7] // 5
    54 => [7, 4, 7, 5, 7] // 6
    55 => [7, 1, 1, 1, 1] // 7
    56 => [7, 5, 7, 5, 7] // 8
    57 => [7, 5, 7, 1, 7] // 9
    58 => [0, 2, 0, 2, 0] // :
    59 => [0, 2, 0, 2, 4] // ;
    61 => [0, 7, 0, 7, 0] // =
    63 => [7, 1, 2, 0, 2] // ?
    65 => [2, 5, 7, 5, 5] // A
    66 => [6, 5, 6, 5, 6] // B
    67 => [3, 4, 4, 4, 3] // C
    68 => [6, 5, 5, 5, 6] // D
    69 => [7, 4, 6, 4, 7] // E
    70 => [7, 4, 6, 4, 4] // F
    71 => [3, 4, 5, 5, 3] // G
    72 => [5, 5, 7, 5, 5] // H
    73 => [7, 2, 2, 2, 7] // I
    74 => [1, 1, 1, 5, 2] // J
    75 => [5, 5, 6, 5, 5] // K
    76 => [4, 4, 4, 4, 7] // L
    77 => [5, 7, 7, 5, 5] // M
    78 => [5, 7, 7, 7, 5] // N
    79 => [2, 5, 5, 5, 2] // O
    80 => [6, 5, 6, 4, 4] // P
    81 => [2, 5, 5, 6, 3] // Q
    82 => [6, 5, 6, 5, 5] // R
    83 => [3, 4, 2, 1, 6] // S
    84 => [7, 2, 2, 2, 2] // T
    85 => [5, 5, 5, 5, 7] // U
    86 => [5, 5, 5, 5, 2] // V
    87 => [5, 5, 7, 7, 5] // W
    88 => [5, 5, 2, 5, 5] // X
    89 => [5, 5, 2, 2, 2] // Y
    90 => [7, 1, 2, 4, 7] // Z
    _ => [0, 0, 0, 0, 0]
  }
}

///|
/// Draw a PDF string with the fallback font. `matrix` already includes the
/// current transformation matrix and the text matrix; `size` is in text-space
/// units. Returns the pen advance in text space.
pub fn draw_text(
  canvas : Canvas,
  bytes : Bytes,
  matrix : Matrix,
  size : Double,
  r : Int32,
  g : Int32,
  b : Int32,
) -> Double {
  let unit = size / 5.0
  let advance = unit * 4.0
  let mut pen = 0.0
  for i in 0..<bytes.length() {
    let mut code = bytes.at(i).to_int()
    if code >= 97 && code <= 122 {
      code = code - 32
    }
    let rows = glyph_rows(code)
    let mut row = 0
    while row < 5 {
      let bits = rows[row]
      let mut col = 0
      while col < 3 {
        if ((bits >> (2 - col)) & 1) == 1 {
          let x0 = pen + col.to_double() * unit
          let y0 = (5.0 - row.to_double()) * unit
          let x1 = x0 + unit
          let y1 = y0 - unit
          let quad : Array[Point] = [
            matrix.apply(x0, y0),
            matrix.apply(x1, y0),
            matrix.apply(x1, y1),
            matrix.apply(x0, y1),
          ]
          canvas.fill_polygons([quad], false, r, g, b)
        }
        col = col + 1
      }
      row = row + 1
    }
    pen = pen + advance
  }
  pen
}
