///|
test "field zero and invalid wire types fail sticky reader" {
  let reader = ProtoReader::new(b"\x01\x00\x00\x00\x00\x00\x00\x00\x00")
  reader.read_tag() |> ignore
  assert_true(reader.failed)
  let group = ProtoReader::new(b"\x0b")
  let tag = group.read_tag()
  group.skip(tag & 7)
  assert_true(group.failed)
}

///|
test "overflowing and unterminated varints are rejected" {
  let reader = ProtoReader::new(b"\xff\xff\xff\xff\xff\xff\xff\xff\xff\x02")
  reader.read_varint() |> ignore
  assert_true(reader.failed)
  let truncated = ProtoReader::new(b"\x80")
  truncated.read_varint() |> ignore
  assert_true(truncated.failed)
}
