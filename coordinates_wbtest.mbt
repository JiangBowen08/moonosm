///|
test "coordinate arithmetic rejects wrap and geographic overflow" {
  assert_true(make_coordinate(9223372036854775807L, 0L, 100, 0L, 0L) is Err(_))
  assert_true(make_coordinate(0L, 0L, 100, 90000000001L, 0L) is Err(_))
  assert_eq(
    make_coordinate(-900000000L, 1800000000L, 100, 0L, 0L).unwrap().latitude(),
    -90.0,
  )
  assert_true(checked_add(9223372036854775807L, 1L) is Err(_))
}
