///|
test "parse basic values" {
  let int_value = parse_value_from_bytes(@utf8.encode("42"))
  assert_true(int_value is Int(42))
  let real_value = parse_value_from_bytes(@utf8.encode("-3.5"))
  assert_true(real_value is Real(-3.5))
  let name_value = parse_value_from_bytes(@utf8.encode("/Type"))
  assert_true(name_value is Name("Type"))
  let bool_value = parse_value_from_bytes(@utf8.encode("true"))
  assert_true(bool_value is Bool(true))
  let null_value = parse_value_from_bytes(@utf8.encode("null"))
  assert_true(null_value is Null)
}

///|
test "parse reference" {
  let value = parse_value_from_bytes(@utf8.encode("12 0 R"))
  match value {
    Ref(num, gen) => {
      assert_eq(num, 12)
      assert_eq(gen, 0)
    }
    _ => assert_true(false)
  }
}

///|
test "parse array and dictionary" {
  let value = parse_value_from_bytes(
    @utf8.encode("<< /Type /Page /MediaBox [0 0 200 100] /Count 1 >>"),
  )
  let dict = match value {
    Dict(d) => d
    _ => {
      assert_true(false)
      []
    }
  }
  assert_eq(dict.length(), 3)
  let media = match dict_get(dict, "MediaBox") {
    Some(v) => v
    None => {
      assert_true(false)
      Null
    }
  }
  match media {
    Array(items) => assert_eq(items.length(), 4)
    _ => assert_true(false)
  }
}

///|
test "parse literal string escapes" {
  let value = parse_value_from_bytes(@utf8.encode("(a\\(b\\)\\n)"))
  match value {
    Str(bytes) => {
      assert_eq(bytes.length(), 5)
      assert_eq(bytes.at(0).to_int(), 97) // a
      assert_eq(bytes.at(1).to_int(), 40) // (
    }
    _ => assert_true(false)
  }
}

///|
test "parse indirect stream object" {
  let data = @utf8.encode(
    "5 0 obj\n<< /Length 4 >>\nstream\nABCD\nendstream\nendobj\n",
  )
  let (num, gen, value) = parse_indirect_object(data, 0)
  assert_eq(num, 5)
  assert_eq(gen, 0)
  match value {
    Stream(stream) => {
      assert_eq(stream.data.length(), 4)
      assert_eq(@utf8.decode_lossy(stream.data), "ABCD")
    }
    _ => assert_true(false)
  }
}
