///|
test "BlobHeader rejects datasize truncation and negative int32" {
  assert_true(
    parse_blob_header(b"\x0a\x01x\x18\x80\x80\x80\x80\x10", 0) is Err(_),
  )
  assert_true(
    parse_blob_header(b"\x0a\x01x\x18\xff\xff\xff\xff\x0f", 0) is Err(_),
  )
  assert_eq(parse_blob_header(b"\x0a\x01x\x18\x00", 0).unwrap(), ("x", 0))
}

///|
test "invalid limits fail before input processing" {
  let limits = Limits::{ ..Limits::default(), max_entities: -1, }
  assert_true(read_blocks(b"", limits) is Err(_))
  assert_true(decode_primitive_block(b"", limits) is Err(_))
  assert_true(decode_raw_blob(b"\x0a\x00", limits) is Err(_))
}
