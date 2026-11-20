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

///|
test "zigzag preserves full signed 64-bit endpoints" {
  assert_eq(
    read_sint64(ProtoReader::new(b"\xff\xff\xff\xff\xff\xff\xff\xff\xff\x01")),
    -9223372036854775807L - 1L,
  )
  assert_eq(
    read_sint64(ProtoReader::new(b"\xfe\xff\xff\xff\xff\xff\xff\xff\xff\x01")),
    9223372036854775807L,
  )
  assert_eq(read_sint64(ProtoReader::new(b"\x01")), -1L)
}

///|
test "skipping unknown byte fields advances without copying their payload" {
  let reader = ProtoReader::new(b"\x03abc\x08\x2a")
  reader.skip(2)
  assert_eq(reader.pos, 4)
  assert_eq(reader.read_tag(), 8)
  assert_eq(reader.read_varint(), 42L)
  assert_true(!reader.failed)
  let truncated = ProtoReader::new(b"\x04abc")
  truncated.skip(2)
  assert_true(truncated.failed)
  assert_eq(truncated.pos, 1)
  let empty = ProtoReader::new(b"\x00\x08\x01")
  empty.skip(2)
  assert_eq(empty.read_tag(), 8)
}
