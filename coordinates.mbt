///|
fn checked_add(left : Int64, right : Int64) -> Result[Int64, OsmError] {
  let max = 9223372036854775807L
  let min = -9223372036854775807L - 1L
  if (right > 0L && left > max - right) || (right < 0L && left < min - right) {
    Err(InvalidPrimitive(reason="signed delta overflow"))
  } else {
    Ok(left + right)
  }
}

///|
fn decode_coordinate(
  value : Int64,
  granularity : Int32,
  offset : Int64,
  extent : Int64,
) -> Result[Int64, OsmError] {
  let scale = granularity.to_int64()
  let max = 9223372036854775807L
  let min = -9223372036854775807L - 1L
  if scale <= 0L || value > max / scale || value < min / scale {
    return Err(InvalidPrimitive(reason="coordinate multiplication overflow"))
  }
  let result = match checked_add(value * scale, offset) {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  if result < -extent || result > extent {
    Err(InvalidPrimitive(reason="coordinate outside geographic extent"))
  } else {
    Ok(result)
  }
}

///|
fn make_coordinate(
  lat : Int64,
  lon : Int64,
  granularity : Int32,
  lat_offset : Int64,
  lon_offset : Int64,
) -> Result[Coordinate, OsmError] {
  let lat_nanodegrees = match
    decode_coordinate(lat, granularity, lat_offset, 90000000000L) {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let lon_nanodegrees = match
    decode_coordinate(lon, granularity, lon_offset, 180000000000L) {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  Ok({ lat_nanodegrees, lon_nanodegrees, })
}
