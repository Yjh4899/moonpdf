///|
test "ascii hex filter" {
  let stream : PdfStream = {
    dict: [("Filter", Name("ASCIIHexDecode"))],
    data: @utf8.encode("48656C6C6F>"),
  }
  assert_eq(@utf8.decode_lossy(decode_stream(stream)), "Hello")
}

///|
test "flate filter" {
  let compressed = @zlib.compress(@utf8.encode("hello flate"))
  let stream : PdfStream = {
    dict: [("Filter", Name("FlateDecode"))],
    data: compressed,
  }
  assert_eq(@utf8.decode_lossy(decode_stream(stream)), "hello flate")
}

///|
test "ascii85 z shortcut" {
  let stream : PdfStream = {
    dict: [("Filter", Name("ASCII85Decode"))],
    data: @utf8.encode("z~>"),
  }
  let decoded = decode_stream(stream)
  assert_eq(decoded.length(), 4)
  assert_eq(decoded.at(0).to_int(), 0)
}

///|
test "run length filter" {
  let stream : PdfStream = {
    dict: [("Filter", Name("RunLengthDecode"))],
    data: Bytes::from_array([u8(2), u8(65), u8(66), u8(67), u8(128)]),
  }
  assert_eq(@utf8.decode_lossy(decode_stream(stream)), "ABC")
}
