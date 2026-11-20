///|
test "StringTable errors and byte budgets are propagated" {
  assert_true(read_string_table(b"\x0a\x02x", [], 10) is Err(_))
  assert_true(read_string_table(b"\x0a\x01\xff", [], 10) is Err(_))
  assert_true(read_string_table(b"\x0a\x02ab", [], 1) is Err(_))
  assert_true(
    decode_primitive_block(b"\x0a\x03\x0a\x01x", Limits::default()) is Err(_),
  )
}

///|
test "granularity does not wrap from large protobuf integer" {
  assert_true(
    decode_primitive_block(
      b"\x0a\x02\x0a\x00\x88\x01\x81\x80\x80\x80\x10",
      Limits::default(),
    )
    is Err(_),
  )
  assert_true(
    decode_primitive_block(b"\x0a\x02\x0a\x00\x88\x01\x00", Limits::default())
    is Err(_),
  )
}

///|
test "DenseNodes requires one delimiter per tagged node" {
  let strings = ["", "k", "v"]
  assert_true(
    decode_dense_nodes(
      b"\x08\x02\x40\x00\x48\x00\x50\x01\x50\x02", strings, 100, 0L, 0L, 10,
    )
    is Err(_),
  )
  assert_eq(
    decode_dense_nodes(b"\x08\x02\x40\x00\x48\x00", strings, 100, 0L, 0L, 10)
    .unwrap()
    .length(),
    1,
  )
}
