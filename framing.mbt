///|
fn read_u32_be(data : Bytes, offset : Int32) -> Int32 {
  (data[offset].to_int() << 24) |
  (data[offset + 1].to_int() << 16) |
  (data[offset + 2].to_int() << 8) |
  data[offset + 3].to_int()
}

///|
fn slice_bytes(data : Bytes, start : Int32, end : Int32) -> Bytes {
  data[start:end].to_owned()
}

///|
fn parse_blob_header(
  data : Bytes,
  offset : Int32,
) -> Result[(String, Int32), OsmError] {
  let reader = ProtoReader::new(data)
  let mut kind = ""
  let mut data_size = -1
  while !reader.at_end() {
    let tag = reader.read_tag()
    if tag == proto_tag(1, 2) {
      kind = reader.read_string()
    } else if tag == proto_tag(3, 0) {
      let size = reader.read_varint()
      if size < 0L || size > 0x7fffffffL {
        reader.failed = true
      } else {
        data_size = size.to_int()
      }
    } else {
      reader.skip(tag & 7)
    }
  }
  if reader.failed {
    Err(InvalidHeader(offset~, reason="invalid BlobHeader protobuf"))
  } else if kind == "" || data_size < 0 {
    Err(InvalidHeader(offset~, reason="missing type or negative datasize"))
  } else {
    Ok((kind, data_size))
  }
}

///|
/// Parse the file-level framing layer. Each returned payload remains compressed;
/// callers can process a block, then release it before requesting the next file.
pub fn read_blocks(
  data : Bytes,
  limits : Limits,
) -> Result[Array[FramedBlock], OsmError] {
  match limits.validate() {
    Ok(_) => ()
    Err(e) => return Err(e)
  }
  let blocks : Array[FramedBlock] = []
  let mut cursor = 0
  while cursor < data.length() {
    let frame_offset = cursor
    if data.length() - cursor < 4 {
      return Err(Truncated(offset=cursor))
    }
    let header_length = read_u32_be(data, cursor)
    cursor += 4
    if header_length <= 0 {
      return Err(InvalidHeader(offset=frame_offset, reason="empty header"))
    }
    if header_length > limits.max_header_bytes {
      return Err(HeaderTooLarge(size=header_length))
    }
    if header_length > data.length() - cursor {
      return Err(Truncated(offset=cursor))
    }
    let parsed = parse_blob_header(
      slice_bytes(data, cursor, cursor + header_length),
      frame_offset,
    )
    let header = match parsed {
      Ok(value) => value
      Err(problem) => return Err(problem)
    }
    cursor += header_length
    let (kind, payload_length) = header
    if payload_length > limits.max_blob_bytes {
      return Err(BlobTooLarge(size=payload_length))
    }
    if payload_length > data.length() - cursor {
      return Err(Truncated(offset=cursor))
    }
    blocks.push({
      kind,
      payload: slice_bytes(data, cursor, cursor + payload_length),
      offset: frame_offset,
    })
    cursor += payload_length
  }
  Ok(blocks)
}

///|
/// Read one valid OSM header block and preserve its feature declarations.
pub fn decode_header(data : Bytes) -> Result[HeaderInfo, OsmError] {
  let reader = ProtoReader::new(data)
  let required : Array[String] = []
  let optional : Array[String] = []
  let mut program = ""
  let mut source = ""
  while !reader.at_end() {
    let tag = reader.read_tag()
    if tag == proto_tag(4, 2) {
      required.push(reader.read_string())
    } else if tag == proto_tag(5, 2) {
      optional.push(reader.read_string())
    } else if tag == proto_tag(16, 2) {
      program = reader.read_string()
    } else if tag == proto_tag(17, 2) {
      source = reader.read_string()
    } else {
      reader.skip(tag & 7)
    }
  }
  if reader.failed {
    Err(InvalidPayload(offset=reader.pos, reason="invalid HeaderBlock"))
  } else {
    Ok({
      required_features: required,
      optional_features: optional,
      writing_program: program,
      source,
    })
  }
}

///|
/// Reject features that this implementation cannot safely interpret.
pub fn validate_required_features(
  header : HeaderInfo,
) -> Result[Unit, OsmError] {
  for feature in header.required_features {
    if feature != "OsmSchema-V0.6" && feature != "DenseNodes" {
      return Err(
        InvalidPayload(
          offset=0,
          reason="unsupported required feature: " + feature,
        ),
      )
    }
  }
  Ok(())
}

///|
/// Decode a raw or zlib-compressed Blob within the configured output budget.
pub fn decode_raw_blob(
  data : Bytes,
  limits : Limits,
) -> Result[Bytes, OsmError] {
  let reader = ProtoReader::new(data)
  match limits.validate() {
    Ok(_) => ()
    Err(e) => return Err(e)
  }
  let mut raw : Bytes? = None
  let mut zlib_data : Bytes? = None
  let mut expected_size = -1L
  let mut has_expected_size = false
  let mut compression = ""
  let mut data_fields = 0
  while !reader.at_end() {
    let tag = reader.read_tag()
    if tag == proto_tag(1, 2) {
      data_fields += 1
      raw = Some(reader.read_bytes())
    } else if tag == proto_tag(2, 0) {
      if has_expected_size {
        reader.failed = true
      }
      expected_size = reader.read_varint()
      has_expected_size = true
    } else if tag == proto_tag(3, 2) {
      data_fields += 1
      compression = "zlib"
      zlib_data = Some(reader.read_bytes())
    } else if tag == proto_tag(4, 2) {
      data_fields += 1
      compression = "lzma"
      reader.skip(tag & 7)
    } else if tag == proto_tag(5, 2) {
      data_fields += 1
      compression = "bzip2"
      reader.skip(tag & 7)
    } else if tag == proto_tag(6, 2) {
      data_fields += 1
      compression = "lz4"
      reader.skip(tag & 7)
    } else if tag == proto_tag(7, 2) {
      data_fields += 1
      compression = "zstd"
      reader.skip(tag & 7)
    } else {
      reader.skip(tag & 7)
    }
  }
  if reader.failed {
    Err(InvalidPayload(offset=reader.pos, reason="invalid Blob"))
  } else if data_fields != 1 {
    Err(
      InvalidPayload(
        offset=0,
        reason="Blob must contain exactly one data field",
      ),
    )
  } else {
    match raw {
      Some(bytes) =>
        if bytes.length() > limits.max_raw_bytes {
          Err(LimitExceeded(limit="raw bytes", value=bytes.length()))
        } else if has_expected_size &&
          (expected_size < 0 || expected_size != bytes.length().to_int64()) {
          Err(
            InvalidPayload(
              offset=0,
              reason="raw_size does not match raw payload",
            ),
          )
        } else {
          Ok(bytes)
        }
      None =>
        match zlib_data {
          Some(compressed) =>
            if !has_expected_size || expected_size < 0 {
              Err(
                InvalidPayload(offset=0, reason="zlib Blob is missing raw_size"),
              )
            } else if expected_size > limits.max_raw_bytes.to_int64() {
              Err(
                LimitExceeded(limit="raw bytes", value=limits.max_raw_bytes + 1),
              )
            } else {
              let decoded = Ok(
                @zlib.decompress(
                  compressed,
                  max_output_bytes=limits.max_raw_bytes,
                ),
              ) catch {
                _ =>
                  Err(InvalidPayload(offset=0, reason="invalid zlib Blob data"))
              }
              match decoded {
                Ok(bytes) =>
                  if bytes.length().to_int64() != expected_size {
                    Err(
                      InvalidPayload(
                        offset=0,
                        reason="raw_size does not match decompressed payload",
                      ),
                    )
                  } else {
                    Ok(bytes)
                  }
                Err(problem) => Err(problem)
              }
            }
          None => Err(UnsupportedCompression(kind=compression))
        }
    }
  }
}

///|
/// Decode a complete PBF file containing raw or zlib-compressed OSM blobs.
pub fn decode_file(
  data : Bytes,
  limits : Limits,
) -> Result[OsmDocument, OsmError] {
  let blocks = match read_blocks(data, limits) {
    Ok(value) => value
    Err(problem) => return Err(problem)
  }
  if blocks.length() == 0 || blocks[0].kind != "OSMHeader" {
    return Err(InvalidHeader(offset=0, reason="first block must be OSMHeader"))
  }
  let header = match decode_raw_blob(blocks[0].payload, limits) {
    Ok(raw) =>
      match decode_header(raw) {
        Ok(value) => value
        Err(problem) => return Err(problem)
      }
    Err(problem) => return Err(problem)
  }
  match validate_required_features(header) {
    Ok(_) => ()
    Err(problem) => return Err(problem)
  }
  let entities : Array[Entity] = []
  for index in 1..<blocks.length() {
    let block = blocks[index]
    if block.kind == "OSMHeader" {
      return Err(
        InvalidHeader(offset=block.offset, reason="duplicate OSMHeader"),
      )
    }
    if block.kind == "OSMData" {
      let raw = match decode_raw_blob(block.payload, limits) {
        Ok(value) => value
        Err(problem) => return Err(problem)
      }
      let block_limits = Limits::{
        ..limits,
        max_entities: limits.max_entities - entities.length(),
      }
      let decoded = match decode_primitive_block(raw, block_limits) {
        Ok(value) => value
        Err(problem) => return Err(problem)
      }
      if decoded.length() > limits.max_entities - entities.length() {
        return Err(
          LimitExceeded(
            limit="entities",
            value=entities.length() + decoded.length(),
          ),
        )
      }
      for entity in decoded {
        entities.push(entity)
      }
    }
  }
  Ok({ header, entities, })
}
