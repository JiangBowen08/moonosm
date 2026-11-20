///|
/// Run a minimal in-memory PrimitiveBlock through the public decoder and JSONL API.
fn main {
  let primitive_block = Bytes::from_array([
    b'\x0a', b'\x02', b'\x0a', b'\x00', b'\x12', b'\x08', b'\x0a', b'\x06', b'\x08',
    b'\x02', b'\x40', b'\x00', b'\x48', b'\x00',
  ])
  let entities = match
    @moonosm.decode_primitive_block(primitive_block, @moonosm.Limits::default()) {
    Ok(value) => value
    Err(_) => panic()
  }
  println(@moonosm.encode_jsonl(entities))
}
