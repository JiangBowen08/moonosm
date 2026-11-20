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
