///|
/// A bounds-checked protobuf wire reader for OSM's length-delimited messages.
priv struct ProtoReader {
  bytes : Bytes
  mut pos : Int32
  mut failed : Bool
}

///|
fn ProtoReader::new(bytes : Bytes) -> ProtoReader {
  { bytes, pos: 0, failed: false, }
}

///|
fn ProtoReader::at_end(self : ProtoReader) -> Bool {
  self.failed || self.pos >= self.bytes.length()
}

///|
fn ProtoReader::read_varint(self : ProtoReader) -> Int64 {
  let mut value : Int64 = 0
  let mut shift = 0
  let mut done = false
  while !done && !self.failed && shift < 70 {
    if self.pos >= self.bytes.length() {
      self.failed = true
    } else {
      let byte = self.bytes[self.pos].to_int()
      self.pos += 1
      if shift == 63 && (byte & 0x7e) != 0 {
        self.failed = true
      } else {
        value = value | ((byte & 0x7f).to_int64() << shift)
      }
      done = (byte & 0x80) == 0
      shift += 7
    }
  }
  if !done {
    self.failed = true
  }
  value
}

///|
fn ProtoReader::read_tag(self : ProtoReader) -> Int32 {
  let raw = self.read_varint()
  if raw <= 0 || raw > 0xffffffffL || raw >> 3 == 0 {
    self.failed = true
    0
  } else {
    raw.to_int()
  }
}

///|
fn ProtoReader::read_length(self : ProtoReader) -> Int32 {
  let length = self.read_varint()
  if length < 0 || length > (self.bytes.length() - self.pos).to_int64() {
    self.failed = true
    0
  } else {
    length.to_int()
  }
}

///|
fn ProtoReader::read_bytes(self : ProtoReader) -> Bytes {
  let length = self.read_length()
  if self.failed {
    b""
  } else {
    let start = self.pos
    self.pos += length
    self.bytes[start:self.pos].to_owned()
  }
}

///|
fn ProtoReader::read_string(self : ProtoReader) -> String {
  let bytes = self.read_bytes()
  @utf8.decode(bytes[:]) catch {
    _ => {
      self.failed = true
      ""
    }
  }
}

///|
fn ProtoReader::skip(self : ProtoReader, wire : Int32) -> Unit {
  match wire {
    0 => self.read_varint() |> ignore
    1 => self.skip_fixed(8)
    2 => self.read_bytes() |> ignore
    5 => self.skip_fixed(4)
    _ => self.failed = true
  }
}

///|
fn ProtoReader::skip_fixed(self : ProtoReader, length : Int32) -> Unit {
  if self.bytes.length() - self.pos < length {
    self.failed = true
  } else {
    self.pos += length
  }
}

///|

///|
fn proto_tag(field : Int32, wire : Int32) -> Int32 {
  (field << 3) | wire
}
