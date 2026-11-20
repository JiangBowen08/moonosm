///|
/// An error raised while inspecting an OSM PBF stream.
pub(all) suberror OsmError {
  Truncated(offset~ : Int32)
  HeaderTooLarge(size~ : Int32)
  BlobTooLarge(size~ : Int32)
  InvalidHeader(offset~ : Int32, reason~ : String)
  UnsupportedCompression(kind~ : String)
  InvalidPayload(offset~ : Int32, reason~ : String)
  InvalidPrimitive(reason~ : String)
  LimitExceeded(limit~ : String, value~ : Int32)
}

///|
/// Stable, credential-free diagnostics for command-line and host applications.
pub fn OsmError::message(self : OsmError) -> String {
  match self {
    Truncated(offset~) => "truncated input at byte \{offset}"
    HeaderTooLarge(size~) => "BlobHeader exceeds byte limit: \{size}"
    BlobTooLarge(size~) => "Blob exceeds byte limit: \{size}"
    InvalidHeader(offset~, reason~) =>
      "invalid header at byte \{offset}: \{reason}"
    UnsupportedCompression(kind~) => "unsupported compression: \{kind}"
    InvalidPayload(offset~, reason~) =>
      "invalid payload at byte \{offset}: \{reason}"
    InvalidPrimitive(reason~) => "invalid primitive: \{reason}"
    LimitExceeded(limit~, value~) => "limit exceeded (\{limit}): \{value}"
  }
}

///|
/// A raw framed block returned by the file layer.
pub(all) struct FramedBlock {
  kind : String
  payload : Bytes
  offset : Int32
}

///|
/// Bounds are checked before allocation or decompression.
pub(all) struct Limits {
  max_header_bytes : Int32
  max_blob_bytes : Int32
  max_raw_bytes : Int32
  max_string_bytes : Int32
  max_entities : Int32
}

///|
pub fn Limits::default() -> Limits {
  {
    max_header_bytes: 64 * 1024,
    max_blob_bytes: 32 * 1024 * 1024,
    max_raw_bytes: 64 * 1024 * 1024,
    max_string_bytes: 1024 * 1024,
    max_entities: 2_000_000,
  }
}

///|
pub(all) struct HeaderInfo {
  required_features : Array[String]
  optional_features : Array[String]
  writing_program : String
  source : String
}

///|
/// A decoded file header and its ordered primitive entities.
pub(all) struct OsmDocument {
  header : HeaderInfo
  entities : Array[Entity]
}

///|
pub(all) struct Coordinate {
  lat_nanodegrees : Int64
  lon_nanodegrees : Int64
}

///|
pub fn Coordinate::latitude(self : Coordinate) -> Double {
  self.lat_nanodegrees.to_double() / 1_000_000_000.0
}

///|
pub fn Coordinate::longitude(self : Coordinate) -> Double {
  self.lon_nanodegrees.to_double() / 1_000_000_000.0
}

///|
pub(all) struct Tag {
  key : String
  value : String
}

///|
pub(all) enum MemberKind {
  NodeMember
  WayMember
  RelationMember
}

///|
pub(all) struct RelationMember {
  kind : MemberKind
  id : Int64
  role : String
}

///|
pub(all) enum Entity {
  Node(id~ : Int64, coordinate~ : Coordinate, tags~ : Array[Tag])
  Way(id~ : Int64, refs~ : Array[Int64], tags~ : Array[Tag])
  Relation(id~ : Int64, members~ : Array[RelationMember], tags~ : Array[Tag])
}

///|
pub fn Entity::id(self : Entity) -> Int64 {
  match self {
    Node(id~, ..) => id
    Way(id~, ..) => id
    Relation(id~, ..) => id
  }
}

///|
pub fn Entity::kind_name(self : Entity) -> String {
  match self {
    Node(..) => "node"
    Way(..) => "way"
    Relation(..) => "relation"
  }
}

///|
pub(all) struct Bounds {
  south : Double
  west : Double
  north : Double
  east : Double
}

///|
pub fn Bounds::valid(self : Bounds) -> Bool {
  self.south >= -90.0 &&
  self.north <= 90.0 &&
  self.south <= self.north &&
  self.west >= -180.0 &&
  self.west <= 180.0 &&
  self.west <= self.east &&
  self.east >= -180.0 &&
  self.east <= 180.0
}

///|
pub(all) struct Query {
  include_nodes : Bool
  include_ways : Bool
  include_relations : Bool
  bounds : Bounds?
  required_tags : Array[Tag]
}

///|
pub fn Query::all() -> Query {
  {
    include_nodes: true,
    include_ways: true,
    include_relations: true,
    bounds: None,
    required_tags: [],
  }
}

///|
pub(all) struct Summary {
  seen_nodes : Int32
  seen_ways : Int32
  seen_relations : Int32
  emitted_nodes : Int32
  emitted_ways : Int32
  emitted_relations : Int32
  rejected_by_type : Int32
  rejected_by_bounds : Int32
  rejected_by_tags : Int32
}

///|
pub fn Summary::empty() -> Summary {
  {
    seen_nodes: 0,
    seen_ways: 0,
    seen_relations: 0,
    emitted_nodes: 0,
    emitted_ways: 0,
    emitted_relations: 0,
    rejected_by_type: 0,
    rejected_by_bounds: 0,
    rejected_by_tags: 0,
  }
}

///|
/// Validate resource ceilings before consuming untrusted bytes. Zero entity and
/// string budgets are allowed; frame/blob/output budgets must be positive.
pub fn Limits::validate(self : Limits) -> Result[Unit, OsmError] {
  if self.max_header_bytes <= 0 ||
    self.max_header_bytes > 65536 ||
    self.max_blob_bytes <= 0 ||
    self.max_raw_bytes <= 0 ||
    self.max_string_bytes < 0 ||
    self.max_entities < 0 {
    Err(InvalidPrimitive(reason="invalid decode limits"))
  } else {
    Ok(())
  }
}
