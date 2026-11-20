// Blackbox tests run against the package's public API. Use `@moonosm` to import.
// Prefer high-level behaviors over implementation details.
// Run `moon test` to execute and `moon test --update` to refresh snapshots.

///|
fn make_zlib_blob(raw : Bytes, declared_size : Int32) -> Bytes {
  let compressed = @zlib.compress(raw)
  let blob : Array[Byte] = [
    b'\x10',
    declared_size.to_byte(),
    b'\x1a',
    compressed.length().to_byte(),
  ]
  for byte in compressed {
    blob.push(byte)
  }
  Bytes::from_array(blob)
}

///|
fn push_varint(out : Array[Byte], value : Int32) -> Unit {
  let mut remaining = value
  while remaining >= 0x80 {
    out.push(((remaining & 0x7f) | 0x80).to_byte())
    remaining = remaining >> 7
  }
  out.push(remaining.to_byte())
}

///|
fn push_frame(out : Array[Byte], kind : String, payload : Bytes) -> Unit {
  let kind_bytes = @utf8.encode(kind)
  let header : Array[Byte] = [b'\x0a']
  push_varint(header, kind_bytes.length())
  for byte in kind_bytes {
    header.push(byte)
  }
  header.push(b'\x18')
  push_varint(header, payload.length())
  out.push((header.length() >> 24).to_byte())
  out.push((header.length() >> 16).to_byte())
  out.push((header.length() >> 8).to_byte())
  out.push(header.length().to_byte())
  for byte in header {
    out.push(byte)
  }
  for byte in payload {
    out.push(byte)
  }
}

///|
test "decodes a header block and rejects unknown required features" {
  let valid = Bytes::from_array([
    b'\x22', b'\x0e', b'O', b's', b'm', b'S', b'c', b'h', b'e', b'm', b'a', b'-',
    b'V', b'0', b'.', b'6',
  ])
  let header = @moonosm.decode_header(valid).unwrap()
  assert_eq(header.required_features.length(), 1)
  assert_eq(header.required_features[0], "OsmSchema-V0.6")
  assert_true(@moonosm.validate_required_features(header) is Ok(_))
  let unknown = @moonosm.decode_header(
    Bytes::from_array([b'\x22', b'\x03', b'X', b'Y', b'Z']),
  ).unwrap()
  assert_true(@moonosm.validate_required_features(unknown) is Err(_))
}

///|
test "rejects truncated protobuf length and malformed varint" {
  assert_true(
    @moonosm.decode_header(Bytes::from_array([b'\x22', b'\x04', b'X']))
    is Err(_),
  )
  assert_true(@moonosm.decode_header(Bytes::from_array([b'\x80'])) is Err(_))
}

///|
test "decodes bounded zlib Blob data and checks raw_size" {
  let raw = Bytes::from_array([
    b'\x0a', b'\x02', b'\x0a', b'\x00', b'\x12', b'\x08', b'\x0a', b'\x06', b'\x08',
    b'\x01', b'\x40', b'\x00', b'\x48', b'\x00',
  ])
  let blob = make_zlib_blob(raw, 14)
  assert_eq(
    @moonosm.decode_raw_blob(blob, @moonosm.Limits::default()).unwrap(),
    raw,
  )
  assert_true(
    @moonosm.decode_raw_blob(
      make_zlib_blob(raw, 13),
      @moonosm.Limits::default(),
    )
    is Err(_),
  )
  let damaged = blob.to_array()
  let last = damaged.length() - 1
  damaged[last] = (damaged[last].to_int() ^ 1).to_byte()
  assert_true(
    @moonosm.decode_raw_blob(
      Bytes::from_array(damaged),
      @moonosm.Limits::default(),
    )
    is Err(_),
  )
}

///|
test "decodes a framed PBF file with a zlib OSMData block" {
  let primitive_block = Bytes::from_array([
    b'\x0a', b'\x02', b'\x0a', b'\x00', b'\x12', b'\x08', b'\x0a', b'\x06', b'\x08',
    b'\x01', b'\x40', b'\x00', b'\x48', b'\x00',
  ])
  let file : Array[Byte] = []
  push_frame(file, "OSMHeader", Bytes::from_array([b'\x0a', b'\x00']))
  push_frame(file, "OSMData", make_zlib_blob(primitive_block, 14))
  let document = @moonosm.decode_file(
    Bytes::from_array(file),
    @moonosm.Limits::default(),
  ).unwrap()
  assert_eq(document.entities.length(), 1)
  assert_eq(document.entities[0].id(), 1L)
}

///|
test "rejects malformed, oversized, and ambiguous Blob data" {
  let limits = @moonosm.Limits::{
    max_header_bytes: 1024,
    max_blob_bytes: 1024,
    max_raw_bytes: 4,
    max_string_bytes: 1024,
    max_entities: 10,
  }
  assert_true(
    @moonosm.decode_raw_blob(
      make_zlib_blob(Bytes::from_array([b'a', b'a', b'a', b'a', b'a']), 5),
      limits,
    )
    is Err(_),
  )
  assert_true(
    @moonosm.decode_raw_blob(
      Bytes::from_array([b'\x10', b'\x01', b'\x1a', b'\x01', b'\x00']),
      @moonosm.Limits::default(),
    )
    is Err(_),
  )
  let conflict = make_zlib_blob(Bytes::from_array([b'x']), 1)
  let conflict_bytes = conflict.to_array()
  conflict_bytes.push(b'\x0a')
  conflict_bytes.push(b'\x00')
  assert_true(
    @moonosm.decode_raw_blob(
      Bytes::from_array(conflict_bytes),
      @moonosm.Limits::default(),
    )
    is Err(_),
  )
}

///|
test "selects node by exact tag and inclusive bounds" {
  let node = @moonosm.Node(
    id=42L,
    coordinate=@moonosm.Coordinate::{
      lat_nanodegrees: 1000000000L,
      lon_nanodegrees: 2000000000L,
    },
    tags=[@moonosm.Tag::{ key: "amenity", value: "bench", }],
  )
  let query = @moonosm.Query::{
    include_nodes: true,
    include_ways: false,
    include_relations: false,
    bounds: Some(@moonosm.Bounds::{
      south: 1.0,
      west: 2.0,
      north: 1.0,
      east: 2.0,
    }),
    required_tags: [@moonosm.Tag::{ key: "amenity", value: "bench", }],
  }
  assert_eq(@moonosm.select_entities([node], query).length(), 1)
  let encoded = @moonosm.encode_jsonl([node])
  assert_true(encoded.contains("\"lat\":1"))
  assert_true(encoded.contains("\"amenity\":\"bench\""))
}

///|
test "JSONL escapes embedded control characters" {
  let entity = @moonosm.Way(id=9L, refs=[1L, 2L], tags=[
    @moonosm.Tag::{ key: "name", value: "a\"b\\c\n", },
  ])
  let line = @moonosm.encode_jsonl([entity])
  assert_true(line.contains("a\\\"b\\\\c\\n"))
  let control = @moonosm.Way(id=10L, refs=[], tags=[
    @moonosm.Tag::{ key: "control", value: "\u{0001}\u{001f}", },
  ])
  assert_true(@moonosm.encode_jsonl([control]).contains("\\u0001\\u001f"))
  assert_true(line.contains("\"refs\":[1,2]"))
}

///|
test "simple selection rejects invalid longitude bounds" {
  let node = @moonosm.Node(
    id=1L,
    coordinate=@moonosm.Coordinate::{
      lat_nanodegrees: 0L,
      lon_nanodegrees: 0L,
    },
    tags=[],
  )
  let query = @moonosm.Query::{
    include_nodes: true,
    include_ways: true,
    include_relations: true,
    bounds: Some(@moonosm.Bounds::{
      south: -1.0,
      west: 10.0,
      north: 1.0,
      east: -10.0,
    }),
    required_tags: [],
  }
  assert_true(!query.bounds.unwrap().valid())
  assert_eq(@moonosm.select_entities([node], query).length(), 0)
  let way = @moonosm.Way(id=2L, refs=[], tags=[])
  let relation = @moonosm.Relation(id=3L, members=[], tags=[])
  let summary = @moonosm.summarize_selection([node, way, relation], [], query)
  assert_eq(summary.rejected_by_bounds, 3)
}

///|
test "decodes a PrimitiveBlock node with empty string table entry" {
  let block = Bytes::from_array([
    b'\x0a', b'\x02', b'\x0a', b'\x00', b'\x12', b'\x08', b'\x0a', b'\x06', b'\x08',
    b'\x01', b'\x40', b'\x00', b'\x48', b'\x00',
  ])
  let entities = @moonosm.decode_primitive_block(
    block,
    @moonosm.Limits::default(),
  ).unwrap()
  assert_eq(entities.length(), 1)
  assert_eq(entities[0].id(), 1L)
  assert_true(@moonosm.encode_jsonl(entities).contains("\"lat\":0"))
}

///|
test "rejects PrimitiveBlock entity budget exhaustion" {
  let block = Bytes::from_array([
    b'\x0a', b'\x02', b'\x0a', b'\x00', b'\x12', b'\x08', b'\x0a', b'\x06', b'\x08',
    b'\x01', b'\x40', b'\x00', b'\x48', b'\x00',
  ])
  let limits = @moonosm.Limits::{
    max_header_bytes: 1024,
    max_blob_bytes: 1024,
    max_raw_bytes: 1024,
    max_string_bytes: 1024,
    max_entities: 0,
  }
  assert_true(@moonosm.decode_primitive_block(block, limits) is Err(_))
}

///|
test "resolves ways and counts duplicate node IDs deterministically" {
  let first = @moonosm.Node(
    id=11L,
    coordinate=@moonosm.Coordinate::{
      lat_nanodegrees: 1000000000L,
      lon_nanodegrees: 2000000000L,
    },
    tags=[],
  )
  let duplicate = @moonosm.Node(
    id=11L,
    coordinate=@moonosm.Coordinate::{
      lat_nanodegrees: 9000000000L,
      lon_nanodegrees: 9000000000L,
    },
    tags=[],
  )
  let index = @moonosm.NodeIndex::from_entities([first, duplicate])
  assert_eq(index.node_count(), 1)
  assert_eq(index.duplicate_count(), 1)
  assert_eq(index.coordinate(11L).unwrap().latitude(), 1.0)
  let way = @moonosm.Way(id=4L, refs=[11L, 12L], tags=[])
  let geometry = @moonosm.resolve_way_geometry(way, index).unwrap()
  assert_eq(geometry.coordinates.length(), 1)
  assert_eq(geometry.missing_node_ids, [12L])
  assert_false(geometry.closed)
}

///|
test "computes dataset bounds from nodes and ways without inferring relations" {
  let entities = [
    @moonosm.Node(
      id=1L,
      coordinate=@moonosm.Coordinate::{
        lat_nanodegrees: 1000000000L,
        lon_nanodegrees: -3000000000L,
      },
      tags=[],
    ),
    @moonosm.Node(
      id=2L,
      coordinate=@moonosm.Coordinate::{
        lat_nanodegrees: 4000000000L,
        lon_nanodegrees: 5000000000L,
      },
      tags=[],
    ),
    @moonosm.Way(id=3L, refs=[1L, 2L], tags=[]),
    @moonosm.Relation(id=4L, members=[], tags=[]),
  ]
  let index = @moonosm.NodeIndex::from_entities(entities)
  let bounds = @moonosm.bounds_of_entities(entities, index).unwrap().unwrap()
  assert_eq(bounds.south, 1.0)
  assert_eq(bounds.west, -3.0)
  assert_eq(bounds.north, 4.0)
  assert_eq(bounds.east, 5.0)
  assert_true(bounds.valid())
  assert_true(
    @moonosm.bounds_of_entities(
      [@moonosm.Relation(id=5L, members=[], tags=[])],
      index,
    ).unwrap()
    is None,
  )
}

///|
test "dataset bounds reject ways with unresolved node references" {
  let node = @moonosm.Node(
    id=1L,
    coordinate=@moonosm.Coordinate::{
      lat_nanodegrees: 0L,
      lon_nanodegrees: 0L,
    },
    tags=[],
  )
  let way = @moonosm.Way(id=2L, refs=[1L, 9L], tags=[])
  let index = @moonosm.NodeIndex::from_entities([node])
  assert_true(@moonosm.bounds_of_entities([node, way], index) is Err(_))
}

///|
test "way bounds detect crossing segments and GeoJSON preserves coordinate order" {
  let nodes = [
    @moonosm.Node(
      id=1L,
      coordinate=@moonosm.Coordinate::{
        lat_nanodegrees: 0L,
        lon_nanodegrees: -2000000000L,
      },
      tags=[],
    ),
    @moonosm.Node(
      id=2L,
      coordinate=@moonosm.Coordinate::{
        lat_nanodegrees: 0L,
        lon_nanodegrees: 2000000000L,
      },
      tags=[],
    ),
  ]
  let way = @moonosm.Way(id=9L, refs=[1L, 2L], tags=[
    @moonosm.Tag::{ key: "highway", value: "service", },
  ])
  let entities = [nodes[0], nodes[1], way]
  let index = @moonosm.NodeIndex::from_entities(entities)
  let query = @moonosm.Query::{
    include_nodes: false,
    include_ways: true,
    include_relations: false,
    bounds: Some(@moonosm.Bounds::{
      south: -1.0,
      west: -1.0,
      north: 1.0,
      east: 1.0,
    }),
    required_tags: [],
  }
  assert_eq(
    @moonosm.select_entities_with_geometry(entities, query, index).length(),
    1,
  )
  let json = @moonosm.encode_geojson([way], index)
  assert_true(json.contains("\"type\":\"LineString\""))
  assert_true(json.contains("[-2,0],[2,0]"))
  assert_true(json.contains("\"osm_type\":\"way\""))
}

///|
test "clips a crossing way into an in-bounds line" {
  let nodes = [
    @moonosm.Node(
      id=1L,
      coordinate=@moonosm.Coordinate::{
        lat_nanodegrees: 0L,
        lon_nanodegrees: -2000000000L,
      },
      tags=[],
    ),
    @moonosm.Node(
      id=2L,
      coordinate=@moonosm.Coordinate::{
        lat_nanodegrees: 0L,
        lon_nanodegrees: 0L,
      },
      tags=[],
    ),
    @moonosm.Node(
      id=3L,
      coordinate=@moonosm.Coordinate::{
        lat_nanodegrees: 0L,
        lon_nanodegrees: 2000000000L,
      },
      tags=[],
    ),
  ]
  let way = @moonosm.Way(id=7L, refs=[1L, 2L, 3L], tags=[])
  let index = @moonosm.NodeIndex::from_entities(nodes)
  let geometry = @moonosm.resolve_way_geometry(way, index).unwrap()
  let lines = @moonosm.clip_way_geometry(geometry, @moonosm.Bounds::{
    south: -1.0,
    west: -1.0,
    north: 1.0,
    east: 1.0,
  }).unwrap()
  assert_eq(lines.length(), 1)
  assert_eq(lines[0].length(), 3)
  assert_eq(lines[0][0].lon_nanodegrees, -1000000000L)
  assert_eq(lines[0][1].lon_nanodegrees, 0L)
  assert_eq(lines[0][2].lon_nanodegrees, 1000000000L)
}

///|
test "exports clipped GeoJSON with visible node and crossing way" {
  let nodes = [
    @moonosm.Node(
      id=1L,
      coordinate=@moonosm.Coordinate::{
        lat_nanodegrees: 0L,
        lon_nanodegrees: -2000000000L,
      },
      tags=[],
    ),
    @moonosm.Node(
      id=2L,
      coordinate=@moonosm.Coordinate::{
        lat_nanodegrees: 500000000L,
        lon_nanodegrees: 0L,
      },
      tags=[@moonosm.Tag::{ key: "name", value: "inside", }],
    ),
    @moonosm.Node(
      id=3L,
      coordinate=@moonosm.Coordinate::{
        lat_nanodegrees: 0L,
        lon_nanodegrees: 2000000000L,
      },
      tags=[],
    ),
  ]
  let way = @moonosm.Way(id=7L, refs=[1L, 2L, 3L], tags=[])
  let index = @moonosm.NodeIndex::from_entities(nodes)
  let bounds = @moonosm.Bounds::{
    south: -1.0,
    west: -1.0,
    north: 1.0,
    east: 1.0,
  }
  let json = @moonosm.encode_geojson_in_bounds(
    [nodes[0], nodes[1], nodes[2], way],
    index,
    bounds,
  ).unwrap()
  assert_true(json.has_prefix("{\"type\":\"FeatureCollection\",\"features\":["))
  assert_true(json.contains("\"osm_id\":2"))
  assert_true(json.contains("\"osm_id\":7"))
  assert_true(!json.contains("\"osm_id\":1"))
  assert_true(!json.contains("\"osm_id\":3"))
  assert_true(json.contains("\"type\":\"LineString\""))
  assert_true(json.contains("\"tags\":{}},\"geometry\":"))
  assert_true(json.contains("\"coordinates\":[[-1,0.25],[0,0.5],[1,0.25]]"))
}

///|
test "clipping rejects incomplete geometry and invalid bounds" {
  let node = @moonosm.Node(
    id=1L,
    coordinate=@moonosm.Coordinate::{
      lat_nanodegrees: 0L,
      lon_nanodegrees: 0L,
    },
    tags=[],
  )
  let index = @moonosm.NodeIndex::from_entities([node])
  let incomplete = @moonosm.resolve_way_geometry(
    @moonosm.Way(id=8L, refs=[1L, 2L], tags=[]),
    index,
  ).unwrap()
  assert_true(
    @moonosm.clip_way_geometry(incomplete, @moonosm.Bounds::{
      south: -1.0,
      west: -1.0,
      north: 1.0,
      east: 1.0,
    })
    is Err(_),
  )
  let complete = @moonosm.resolve_way_geometry(
    @moonosm.Way(id=9L, refs=[1L], tags=[]),
    index,
  ).unwrap()
  assert_true(
    @moonosm.clip_way_geometry(complete, @moonosm.Bounds::{
      south: 2.0,
      west: -1.0,
      north: 1.0,
      east: 1.0,
    })
    is Err(_),
  )
  assert_eq(
    @moonosm.clip_way_geometry(complete, @moonosm.Bounds::{
      south: -1.0,
      west: -1.0,
      north: 1.0,
      east: 1.0,
    })
    .unwrap()
    .length(),
    0,
  )
}

///|
test "geometry selection rejects invalid bounds including relations" {
  let relation = @moonosm.Relation(id=3L, members=[], tags=[])
  let query = @moonosm.Query::{
    include_nodes: false,
    include_ways: false,
    include_relations: true,
    bounds: Some(@moonosm.Bounds::{
      south: 2.0,
      west: -1.0,
      north: 1.0,
      east: 1.0,
    }),
    required_tags: [],
  }
  assert_eq(
    @moonosm.select_entities_with_geometry(
      [relation],
      query,
      @moonosm.NodeIndex::from_entities([]),
    ).length(),
    0,
  )
}

///|
test "file decoder rejects a repeated header block" {
  let file : Array[Byte] = []
  let blob = b"\x0a\x00"
  push_frame(file, "OSMHeader", blob)
  push_frame(file, "OSMHeader", blob)
  assert_true(
    @moonosm.decode_file(Bytes::from_array(file), @moonosm.Limits::default())
    is Err(_),
  )
}
