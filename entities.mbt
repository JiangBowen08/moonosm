///|
/// Decode an OSM PrimitiveBlock into its ordered entity stream.
pub fn decode_primitive_block(
  data : Bytes,
  limits : Limits,
) -> Result[Array[Entity], OsmError] {
  let reader = ProtoReader::new(data)
  match limits.validate() {
    Ok(_) => ()
    Err(e) => return Err(e)
  }
  let strings : Array[String] = []
  let groups : Array[Bytes] = []
  let mut granularity = 100
  let mut lat_offset : Int64 = 0L
  let mut lon_offset : Int64 = 0L
  while !reader.at_end() {
    let field_tag = reader.read_tag()
    if field_tag == proto_tag(1, 2) {
      match
        read_string_table(reader.read_bytes(), strings, limits.max_string_bytes) {
        Ok(_) => ()
        Err(problem) => return Err(problem)
      }
    } else if field_tag == proto_tag(2, 2) {
      groups.push(reader.read_bytes())
    } else if field_tag == proto_tag(17, 0) {
      let value = reader.read_varint()
      if value <= 0L || value > 0x7fffffffL {
        reader.failed = true
      } else {
        granularity = value.to_int()
      }
    } else if field_tag == proto_tag(19, 0) {
      lat_offset = reader.read_varint()
    } else if field_tag == proto_tag(20, 0) {
      lon_offset = reader.read_varint()
    } else {
      reader.skip(field_tag & 7)
    }
  }
  if reader.failed ||
    strings.length() == 0 ||
    strings[0] != "" ||
    granularity <= 0 {
    Err(InvalidPrimitive(reason="invalid PrimitiveBlock metadata"))
  } else {
    let entities : Array[Entity] = []
    for group in groups {
      match
        decode_primitive_group(
          group,
          strings,
          granularity,
          lat_offset,
          lon_offset,
          limits.max_entities - entities.length(),
        ) {
        Ok(decoded) =>
          for entity in decoded {
            entities.push(entity)
          }
        Err(problem) => return Err(problem)
      }
      if entities.length() > limits.max_entities {
        return Err(LimitExceeded(limit="entities", value=entities.length()))
      }
    }
    Ok(entities)
  }
}

///|
fn read_string_table(
  data : Bytes,
  strings : Array[String],
  max_bytes : Int32,
) -> Result[Unit, OsmError] {
  let reader = ProtoReader::new(data)
  let mut total_bytes = 0
  while !reader.at_end() {
    let field_tag = reader.read_tag()
    if field_tag == proto_tag(1, 2) {
      let bytes = reader.read_bytes()
      total_bytes += bytes.length()
      if total_bytes > max_bytes {
        return Err(LimitExceeded(limit="string bytes", value=total_bytes))
      }
      let text = @utf8.decode(bytes[:]) catch {
        _ => return Err(InvalidPrimitive(reason="invalid UTF-8 in StringTable"))
      }
      strings.push(text)
    } else {
      reader.skip(field_tag & 7)
    }
  }
  if reader.failed {
    Err(InvalidPrimitive(reason="malformed StringTable"))
  } else {
    Ok(())
  }
}

///|
fn decode_primitive_group(
  data : Bytes,
  strings : Array[String],
  granularity : Int32,
  lat_offset : Int64,
  lon_offset : Int64,
  remaining : Int32,
) -> Result[Array[Entity], OsmError] {
  let reader = ProtoReader::new(data)
  let entities : Array[Entity] = []
  while !reader.at_end() {
    let field_tag = reader.read_tag()
    if field_tag == proto_tag(1, 2) {
      match
        decode_node(
          reader.read_bytes(),
          strings,
          granularity,
          lat_offset,
          lon_offset,
        ) {
        Ok(entity) => entities.push(entity)
        Err(problem) => return Err(problem)
      }
    } else if field_tag == proto_tag(2, 2) {
      match
        decode_dense_nodes(
          reader.read_bytes(),
          strings,
          granularity,
          lat_offset,
          lon_offset,
          remaining - entities.length(),
        ) {
        Ok(decoded) =>
          for entity in decoded {
            entities.push(entity)
          }
        Err(problem) => return Err(problem)
      }
    } else if field_tag == proto_tag(3, 2) {
      match decode_way(reader.read_bytes(), strings) {
        Ok(entity) => entities.push(entity)
        Err(problem) => return Err(problem)
      }
    } else if field_tag == proto_tag(4, 2) {
      match decode_relation(reader.read_bytes(), strings) {
        Ok(entity) => entities.push(entity)
        Err(problem) => return Err(problem)
      }
    } else {
      reader.skip(field_tag & 7)
    }
    if reader.failed || entities.length() > remaining {
      return Err(
        InvalidPrimitive(reason="malformed or oversized PrimitiveGroup"),
      )
    }
  }
  if reader.failed {
    Err(InvalidPrimitive(reason="truncated PrimitiveGroup"))
  } else {
    Ok(entities)
  }
}

///|
fn decode_node(
  data : Bytes,
  strings : Array[String],
  granularity : Int32,
  lat_offset : Int64,
  lon_offset : Int64,
) -> Result[Entity, OsmError] {
  let reader = ProtoReader::new(data)
  let mut id : Int64? = None
  let mut lat : Int64? = None
  let mut lon : Int64? = None
  let keys : Array[Int32] = []
  let vals : Array[Int32] = []
  while !reader.at_end() {
    let field_tag = reader.read_tag()
    if field_tag == proto_tag(1, 0) {
      id = Some(reader.read_varint())
    } else if field_tag == proto_tag(2, 2) || field_tag == proto_tag(2, 0) {
      read_indices_field(reader, field_tag, keys)
    } else if field_tag == proto_tag(3, 2) || field_tag == proto_tag(3, 0) {
      read_indices_field(reader, field_tag, vals)
    } else if field_tag == proto_tag(8, 0) {
      lat = Some(read_sint64(reader))
    } else if field_tag == proto_tag(9, 0) {
      lon = Some(read_sint64(reader))
    } else {
      reader.skip(field_tag & 7)
    }
  }
  match (id, lat, lon) {
    (Some(node_id), Some(latitude), Some(longitude)) =>
      match decode_tags(keys, vals, strings) {
        Ok(tags) =>
          if reader.failed {
            Err(InvalidPrimitive(reason="truncated Node"))
          } else {
            Ok(
              Node(
                id=node_id,
                coordinate=match
                  make_coordinate(
                    latitude, longitude, granularity, lat_offset, lon_offset,
                  ) {
                  Ok(value) => value
                  Err(problem) => return Err(problem)
                },
                tags~,
              ),
            )
          }
        Err(problem) => Err(problem)
      }
    _ => Err(InvalidPrimitive(reason="Node missing id or coordinates"))
  }
}

///|
fn decode_dense_nodes(
  data : Bytes,
  strings : Array[String],
  granularity : Int32,
  lat_offset : Int64,
  lon_offset : Int64,
  remaining : Int32,
) -> Result[Array[Entity], OsmError] {
  let reader = ProtoReader::new(data)
  let ids : Array[Int64] = []
  let lats : Array[Int64] = []
  let lons : Array[Int64] = []
  let key_values : Array[Int32] = []
  while !reader.at_end() {
    let field_tag = reader.read_tag()
    if field_tag == proto_tag(1, 2) || field_tag == proto_tag(1, 0) {
      read_packed_sints(reader, field_tag, ids)
    } else if field_tag == proto_tag(8, 2) || field_tag == proto_tag(8, 0) {
      read_packed_sints(reader, field_tag, lats)
    } else if field_tag == proto_tag(9, 2) || field_tag == proto_tag(9, 0) {
      read_packed_sints(reader, field_tag, lons)
    } else if field_tag == proto_tag(10, 2) || field_tag == proto_tag(10, 0) {
      read_indices_field(reader, field_tag, key_values)
    } else {
      reader.skip(field_tag & 7)
    }
  }
  if reader.failed ||
    ids.length() != lats.length() ||
    ids.length() != lons.length() ||
    ids.length() > remaining {
    Err(InvalidPrimitive(reason="inconsistent or oversized DenseNodes arrays"))
  } else {
    let output : Array[Entity] = []
    let mut id : Int64 = 0L
    let mut lat : Int64 = 0L
    let mut lon : Int64 = 0L
    let mut kv = 0
    for index in 0..<ids.length() {
      id = match checked_add(id, ids[index]) {
        Ok(v) => v
        Err(e) => return Err(e)
      }
      lat = match checked_add(lat, lats[index]) {
        Ok(v) => v
        Err(e) => return Err(e)
      }
      lon = match checked_add(lon, lons[index]) {
        Ok(v) => v
        Err(e) => return Err(e)
      }
      let node_tags : Array[Tag] = []
      while kv < key_values.length() && key_values[kv] != 0 {
        if kv + 1 >= key_values.length() {
          return Err(InvalidPrimitive(reason="unterminated DenseNodes tags"))
        }
        match
          (
            lookup_string(strings, key_values[kv]),
            lookup_string(strings, key_values[kv + 1]),
          ) {
          (Some(key), Some(value)) => node_tags.push({ key, value, })
          _ =>
            return Err(
              InvalidPrimitive(reason="DenseNodes string index out of range"),
            )
        }
        kv += 2
      }
      if key_values.length() > 0 {
        if kv >= key_values.length() {
          return Err(
            InvalidPrimitive(reason="missing DenseNodes tag delimiter"),
          )
        }
        kv += 1
      }
      output.push(
        Node(
          id~,
          tags=node_tags,
          coordinate=match
            make_coordinate(lat, lon, granularity, lat_offset, lon_offset) {
            Ok(value) => value
            Err(problem) => return Err(problem)
          },
        ),
      )
    }
    if kv != key_values.length() {
      Err(InvalidPrimitive(reason="trailing DenseNodes tag values"))
    } else {
      Ok(output)
    }
  }
}

///|
fn decode_way(
  data : Bytes,
  strings : Array[String],
) -> Result[Entity, OsmError] {
  let reader = ProtoReader::new(data)
  let mut id : Int64? = None
  let keys : Array[Int32] = []
  let vals : Array[Int32] = []
  let deltas : Array[Int64] = []
  while !reader.at_end() {
    let field_tag = reader.read_tag()
    if field_tag == proto_tag(1, 0) {
      id = Some(reader.read_varint())
    } else if field_tag == proto_tag(2, 2) || field_tag == proto_tag(2, 0) {
      read_indices_field(reader, field_tag, keys)
    } else if field_tag == proto_tag(3, 2) || field_tag == proto_tag(3, 0) {
      read_indices_field(reader, field_tag, vals)
    } else if field_tag == proto_tag(8, 2) || field_tag == proto_tag(8, 0) {
      read_packed_sints(reader, field_tag, deltas)
    } else {
      reader.skip(field_tag & 7)
    }
  }
  match id {
    Some(way_id) =>
      match decode_tags(keys, vals, strings) {
        Ok(tags) => {
          let refs : Array[Int64] = []
          let mut reference : Int64 = 0L
          for delta in deltas {
            reference = match checked_add(reference, delta) {
              Ok(v) => v
              Err(e) => return Err(e)
            }
            refs.push(reference)
          }
          if reader.failed {
            Err(InvalidPrimitive(reason="truncated Way"))
          } else {
            Ok(Way(id=way_id, refs~, tags~))
          }
        }
        Err(problem) => Err(problem)
      }
    None => Err(InvalidPrimitive(reason="Way missing id"))
  }
}

///|
fn decode_relation(
  data : Bytes,
  strings : Array[String],
) -> Result[Entity, OsmError] {
  let reader = ProtoReader::new(data)
  let mut id : Int64? = None
  let keys : Array[Int32] = []
  let vals : Array[Int32] = []
  let roles : Array[Int32] = []
  let member_deltas : Array[Int64] = []
  let member_types : Array[Int32] = []
  while !reader.at_end() {
    let field_tag = reader.read_tag()
    if field_tag == proto_tag(1, 0) {
      id = Some(reader.read_varint())
    } else if field_tag == proto_tag(2, 2) || field_tag == proto_tag(2, 0) {
      read_indices_field(reader, field_tag, keys)
    } else if field_tag == proto_tag(3, 2) || field_tag == proto_tag(3, 0) {
      read_indices_field(reader, field_tag, vals)
    } else if field_tag == proto_tag(8, 2) || field_tag == proto_tag(8, 0) {
      read_indices_field(reader, field_tag, roles)
    } else if field_tag == proto_tag(9, 2) || field_tag == proto_tag(9, 0) {
      read_packed_sints(reader, field_tag, member_deltas)
    } else if field_tag == proto_tag(10, 2) || field_tag == proto_tag(10, 0) {
      read_indices_field(reader, field_tag, member_types)
    } else {
      reader.skip(field_tag & 7)
    }
  }
  match id {
    Some(relation_id) =>
      match decode_tags(keys, vals, strings) {
        Ok(tags) =>
          if reader.failed ||
            roles.length() != member_deltas.length() ||
            roles.length() != member_types.length() {
            Err(InvalidPrimitive(reason="inconsistent Relation member arrays"))
          } else {
            let members : Array[RelationMember] = []
            let mut member_id : Int64 = 0L
            for index in 0..<roles.length() {
              member_id = match checked_add(member_id, member_deltas[index]) {
                Ok(v) => v
                Err(e) => return Err(e)
              }
              let role = lookup_string(strings, roles[index])
              let kind = match member_types[index] {
                0 => Some(NodeMember)
                1 => Some(WayMember)
                2 => Some(RelationMember)
                _ => None
              }
              match (role, kind) {
                (Some(role_name), Some(member_kind)) =>
                  members.push({
                    kind: member_kind,
                    id: member_id,
                    role: role_name,
                  })
                _ =>
                  return Err(
                    InvalidPrimitive(
                      reason="invalid Relation role or member type",
                    ),
                  )
              }
            }
            Ok(Relation(id=relation_id, members~, tags~))
          }
        Err(problem) => Err(problem)
      }
    None => Err(InvalidPrimitive(reason="Relation missing id"))
  }
}

///|
fn read_sint64(reader : ProtoReader) -> Int64 {
  let encoded = reader.read_varint()
  ((encoded >> 1) & 0x7fffffffffffffffL) ^ -(encoded & 1L)
}

///|
fn read_indices_field(
  reader : ProtoReader,
  field_tag : Int32,
  output : Array[Int32],
) -> Unit {
  if (field_tag & 7) == 0 {
    let value = reader.read_varint()
    if value < 0L || value > 0x7fffffffL {
      reader.failed = true
    } else {
      output.push(value.to_int())
    }
  } else {
    let packed = ProtoReader::new(reader.read_bytes())
    while !packed.at_end() {
      let value = packed.read_varint()
      if value < 0L || value > 0x7fffffffL {
        packed.failed = true
      } else {
        output.push(value.to_int())
      }
    }
    if packed.failed {
      reader.failed = true
    }
  }
}

///|
fn read_packed_sints(
  reader : ProtoReader,
  field_tag : Int32,
  output : Array[Int64],
) -> Unit {
  if (field_tag & 7) == 0 {
    output.push(read_sint64(reader))
  } else {
    let packed = ProtoReader::new(reader.read_bytes())
    while !packed.at_end() {
      output.push(read_sint64(packed))
    }
    if packed.failed {
      reader.failed = true
    }
  }
}

///|
fn decode_tags(
  keys : Array[Int32],
  values : Array[Int32],
  strings : Array[String],
) -> Result[Array[Tag], OsmError] {
  if keys.length() != values.length() {
    Err(InvalidPrimitive(reason="tag key/value arrays differ in length"))
  } else {
    let tags : Array[Tag] = []
    for index in 0..<keys.length() {
      match
        (
          lookup_string(strings, keys[index]),
          lookup_string(strings, values[index]),
        ) {
        (Some(key), Some(value)) => tags.push({ key, value, })
        _ =>
          return Err(InvalidPrimitive(reason="tag string index out of range"))
      }
    }
    Ok(tags)
  }
}

///|
fn lookup_string(strings : Array[String], index : Int32) -> String? {
  if index < 0 || index >= strings.length() {
    None
  } else {
    Some(strings[index])
  }
}
