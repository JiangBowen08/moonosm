///|
/// Encode OSM entities as newline-delimited JSON records, preserving IDs,
/// ordered references/members and tag order for downstream tools.
pub fn encode_jsonl(entities : Array[Entity]) -> String {
  let builder = StringBuilder()
  for entity in entities {
    encode_entity_json(builder, entity)
    builder.write_char('\n')
  }
  builder.to_string()
}

///|
fn encode_entity_json(builder : StringBuilder, entity : Entity) -> Unit {
  match entity {
    Node(id~, coordinate~, tags~) => {
      builder.write_string("{\"type\":\"node\",\"id\":")
      builder.write_string(id.to_string())
      builder.write_string(",\"lat\":")
      builder.write_string(coordinate.latitude().to_string())
      builder.write_string(",\"lon\":")
      builder.write_string(coordinate.longitude().to_string())
      builder.write_string(",\"tags\":")
      encode_tags_json(builder, tags)
      builder.write_char('}')
    }
    Way(id~, refs~, tags~) => {
      builder.write_string("{\"type\":\"way\",\"id\":")
      builder.write_string(id.to_string())
      builder.write_string(",\"refs\":[")
      write_int64_array(builder, refs)
      builder.write_string("],\"tags\":")
      encode_tags_json(builder, tags)
      builder.write_char('}')
    }
    Relation(id~, members~, tags~) => {
      builder.write_string("{\"type\":\"relation\",\"id\":")
      builder.write_string(id.to_string())
      builder.write_string(",\"members\":[")
      for index, item in members {
        if index > 0 {
          builder.write_char(',')
        }
        builder.write_string("{\"type\":")
        builder.write_json_string(member_kind_json(item.kind))
        builder.write_string(",\"ref\":")
        builder.write_string(item.id.to_string())
        builder.write_string(",\"role\":")
        builder.write_json_string(item.role)
        builder.write_char('}')
      }
      builder.write_string("],\"tags\":")
      encode_tags_json(builder, tags)
      builder.write_char('}')
    }
  }
}

///|
fn encode_tags_json(builder : StringBuilder, tags : Array[Tag]) -> Unit {
  builder.write_char('{')
  for index, tag in tags {
    if index > 0 {
      builder.write_char(',')
    }
    builder.write_json_string(tag.key)
    builder.write_char(':')
    builder.write_json_string(tag.value)
  }
  builder.write_char('}')
}

///|
fn write_int64_array(builder : StringBuilder, values : Array[Int64]) -> Unit {
  for index, value in values {
    if index > 0 {
      builder.write_char(',')
    }
    builder.write_string(value.to_string())
  }
}

///|
fn member_kind_json(kind : MemberKind) -> String {
  match kind {
    NodeMember => "node"
    WayMember => "way"
    RelationMember => "relation"
  }
}

///|
fn StringBuilder::write_json_string(
  self : StringBuilder,
  value : String,
) -> Unit {
  self.write_char('"')
  for character in value {
    match character {
      '"' => self.write_string("\\\"")
      '\\' => self.write_string("\\\\")
      '\n' => self.write_string("\\n")
      '\r' => self.write_string("\\r")
      '\t' => self.write_string("\\t")
      c => self.write_char(c)
    }
  }
  self.write_char('"')
}
