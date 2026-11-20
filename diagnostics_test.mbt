///|
test "public diagnostics retain offset compression and budget context" {
  assert_eq(@moonosm.Truncated(offset=7).message(), "truncated input at byte 7")
  assert_eq(
    @moonosm.InvalidPayload(offset=3, reason="invalid zlib").message(),
    "invalid payload at byte 3: invalid zlib",
  )
  assert_eq(
    @moonosm.UnsupportedCompression(kind="zstd").message(),
    "unsupported compression: zstd",
  )
  assert_eq(
    @moonosm.LimitExceeded(limit="entities", value=11).message(),
    "limit exceeded (entities): 11",
  )
}
