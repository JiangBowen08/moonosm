///|
/// An OSM node lookup built once for resolving many ways.
pub struct NodeIndex {
  coordinates : Map[Int64, Coordinate]
  duplicate_ids : Int32
}

///|
/// Resolved way references remain positionally aligned only when complete.
pub(all) struct WayGeometry {
  way_id : Int64
  coordinates : Array[Coordinate]
  missing_node_ids : Array[Int64]
  closed : Bool
}

///|
/// Build a lookup in O(nodes). The first occurrence of a duplicate node ID wins.
pub fn NodeIndex::from_entities(entities : Array[Entity]) -> NodeIndex {
  let coordinates : Map[Int64, Coordinate] = Map::Map([])
  let mut duplicate_ids = 0
  for entity in entities {
    match entity {
      Node(id~, coordinate~, ..) =>
        if coordinates.contains(id) {
          duplicate_ids += 1
        } else {
          coordinates.set(id, coordinate)
        }
      _ => ()
    }
  }
  { coordinates, duplicate_ids, }
}

///|
pub fn NodeIndex::node_count(self : NodeIndex) -> Int32 {
  self.coordinates.length()
}

///|
pub fn NodeIndex::duplicate_count(self : NodeIndex) -> Int32 {
  self.duplicate_ids
}

///|
pub fn NodeIndex::coordinate(self : NodeIndex, id : Int64) -> Coordinate? {
  self.coordinates.get(id)
}

///|
/// Compute the geographic extent of nodes and fully resolved ways.
/// Relations are skipped because their member geometry is not inferred.
pub fn bounds_of_entities(
  entities : Array[Entity],
  index : NodeIndex,
) -> Result[Bounds?, OsmError] {
  let mut extent : Bounds? = None
  for entity in entities {
    match entity {
      Node(coordinate~, ..) => extent = Some(extend_bounds(extent, coordinate))
      Way(..) => {
        let geometry = match resolve_way_geometry(entity, index) {
          Ok(resolved) => resolved
          Err(problem) => return Err(problem)
        }
        if geometry.missing_node_ids.length() > 0 {
          return Err(
            InvalidPrimitive(reason="cannot bound a way with missing nodes"),
          )
        }
        for coordinate in geometry.coordinates {
          extent = Some(extend_bounds(extent, coordinate))
        }
      }
      Relation(..) => ()
    }
  }
  Ok(extent)
}

///|
fn extend_bounds(current : Bounds?, coordinate : Coordinate) -> Bounds {
  let latitude = coordinate.latitude()
  let longitude = coordinate.longitude()
  match current {
    Some(bounds) =>
      {
        south: bounds.south.min(latitude),
        west: bounds.west.min(longitude),
        north: bounds.north.max(latitude),
        east: bounds.east.max(longitude),
      }
    None =>
      { south: latitude, west: longitude, north: latitude, east: longitude, }
  }
}

///|
/// Resolve a way without inventing coordinates for absent or out-of-extract nodes.
pub fn resolve_way_geometry(
  way : Entity,
  index : NodeIndex,
) -> Result[WayGeometry, OsmError] {
  match way {
    Way(id~, refs~, ..) => {
      let coordinates : Array[Coordinate] = []
      let missing_node_ids : Array[Int64] = []
      for node_id in refs {
        match index.coordinate(node_id) {
          Some(coordinate) => coordinates.push(coordinate)
          None => missing_node_ids.push(node_id)
        }
      }
      let complete = missing_node_ids.length() == 0
      let closed = complete &&
        refs.length() > 2 &&
        refs[0] == refs[refs.length() - 1]
      Ok({ way_id: id, coordinates, missing_node_ids, closed, })
    }
    _ => Err(InvalidPrimitive(reason="geometry resolution requires a Way"))
  }
}

///|
/// Clip a resolved way to a rectangle, preserving separate in-bounds runs.
pub fn clip_way_geometry(
  geometry : WayGeometry,
  bounds : Bounds,
) -> Result[Array[Array[Coordinate]], OsmError] {
  if !bounds.valid() {
    return Err(InvalidPrimitive(reason="clipping bounds are invalid"))
  }
  if geometry.missing_node_ids.length() > 0 {
    return Err(InvalidPrimitive(reason="cannot clip a way with missing nodes"))
  }
  let clipped : Array[Array[Coordinate]] = []
  let current : Array[Coordinate] = []
  if geometry.coordinates.length() < 2 {
    return Ok(clipped)
  }
  for segment in 1..<geometry.coordinates.length() {
    let start = geometry.coordinates[segment - 1]
    let finish = geometry.coordinates[segment]
    match clip_segment(start, finish, bounds) {
      Some((clipped_start, clipped_finish)) => {
        if current.length() == 0 {
          current.push(clipped_start)
        } else if !coordinates_equal(
            current[current.length() - 1],
            clipped_start,
          ) {
          if current.length() > 1 {
            clipped.push(current.copy())
          }
          current.clear()
          current.push(clipped_start)
        }
        if !coordinates_equal(current[current.length() - 1], clipped_finish) {
          current.push(clipped_finish)
        }
      }
      None => {
        if current.length() > 1 {
          clipped.push(current.copy())
        }
        current.clear()
      }
    }
  }
  if current.length() > 1 {
    clipped.push(current)
  }
  Ok(clipped)
}

///|
fn coordinates_equal(left : Coordinate, right : Coordinate) -> Bool {
  left.lat_nanodegrees == right.lat_nanodegrees &&
  left.lon_nanodegrees == right.lon_nanodegrees
}

///|
/// Select nodes and complete ways intersecting a bounds rectangle, plus
/// relations selected by type/tags. Way intersection is based on its segments.
pub fn select_entities_with_geometry(
  entities : Array[Entity],
  query : Query,
  index : NodeIndex,
) -> Array[Entity] {
  if query.bounds is Some(bounds) && !bounds.valid() {
    return []
  }
  let output : Array[Entity] = []
  for entity in entities {
    if !query_includes_type(entity, query) ||
      !query_matches_tags(entity, query.required_tags) {
      continue
    }
    let matches_bounds = match (entity, query.bounds) {
      (_, None) => true
      (Node(coordinate~, ..), Some(bounds)) =>
        coordinate_in_bounds(coordinate, bounds)
      (Way(..), Some(bounds)) =>
        match resolve_way_geometry(entity, index) {
          Ok(geometry) => geometry_intersects_bounds(geometry, bounds)
          Err(_) => false
        }
      (Relation(..), Some(_)) => true
    }
    if matches_bounds {
      output.push(entity)
    }
  }
  output
}

///|
fn geometry_intersects_bounds(geometry : WayGeometry, bounds : Bounds) -> Bool {
  if geometry.missing_node_ids.length() > 0 ||
    geometry.coordinates.length() == 0 {
    return false
  }
  for coordinate in geometry.coordinates {
    if coordinate_in_bounds(coordinate, bounds) {
      return true
    }
  }
  for index in 1..<geometry.coordinates.length() {
    if segment_intersects_bounds(
        geometry.coordinates[index - 1],
        geometry.coordinates[index],
        bounds,
      ) {
      return true
    }
  }
  false
}

///|
fn segment_intersects_bounds(
  start : Coordinate,
  finish : Coordinate,
  bounds : Bounds,
) -> Bool {
  clip_segment(start, finish, bounds) is Some(_)
}

///|
fn clip_segment(
  start : Coordinate,
  finish : Coordinate,
  bounds : Bounds,
) -> (Coordinate, Coordinate)? {
  let x0 = start.longitude()
  let y0 = start.latitude()
  let dx = finish.longitude() - x0
  let dy = finish.latitude() - y0
  let p = [-dx, dx, -dy, dy]
  let q = [
    x0 - bounds.west,
    bounds.east - x0,
    y0 - bounds.south,
    bounds.north - y0,
  ]
  let mut lower = 0.0
  let mut upper = 1.0
  for edge in 0..<4 {
    if p[edge] == 0.0 {
      if q[edge] < 0.0 {
        return None
      }
    } else {
      let ratio = q[edge] / p[edge]
      if p[edge] < 0.0 {
        if ratio > upper {
          return None
        }
        lower = lower.max(ratio)
      } else {
        if ratio < lower {
          return None
        }
        upper = upper.min(ratio)
      }
    }
  }
  Some(
    (
      interpolate_coordinate(start, finish, lower),
      interpolate_coordinate(start, finish, upper),
    ),
  )
}

///|
fn interpolate_coordinate(
  start : Coordinate,
  finish : Coordinate,
  ratio : Double,
) -> Coordinate {
  let latitude = start.lat_nanodegrees.to_double() +
    (finish.lat_nanodegrees - start.lat_nanodegrees).to_double() * ratio
  let longitude = start.lon_nanodegrees.to_double() +
    (finish.lon_nanodegrees - start.lon_nanodegrees).to_double() * ratio
  {
    lat_nanodegrees: latitude.round().to_int64(),
    lon_nanodegrees: longitude.round().to_int64(),
  }
}

///|
/// Export all nodes and fully resolved ways as a GeoJSON FeatureCollection.
/// Relations and ways with missing references are omitted, never guessed.
pub fn encode_geojson(entities : Array[Entity], index : NodeIndex) -> String {
  let builder = StringBuilder()
  builder.write_string("{\"type\":\"FeatureCollection\",\"features\":[")
  let mut emitted = 0
  for entity in entities {
    match entity {
      Node(id~, coordinate~, tags~) => {
        if emitted > 0 {
          builder.write_char(',')
        }
        write_geojson_feature_start(builder, "node", id, tags)
        builder.write_string(
          "\"geometry\":{\"type\":\"Point\",\"coordinates\":[",
        )
        builder.write_string(coordinate.longitude().to_string())
        builder.write_char(',')
        builder.write_string(coordinate.latitude().to_string())
        builder.write_string("]}}")
        emitted += 1
      }
      Way(id~, refs~, tags~) => {
        let way = Way(id~, refs~, tags~)
        match resolve_way_geometry(way, index) {
          Ok(geometry) =>
            if geometry.missing_node_ids.length() == 0 &&
              geometry.coordinates.length() >= 2 {
              if emitted > 0 {
                builder.write_char(',')
              }
              write_geojson_feature_start(builder, "way", id, tags)
              builder.write_string(
                "\"geometry\":{\"type\":\"LineString\",\"coordinates\":[",
              )
              for coordinate_index, coordinate in geometry.coordinates {
                if coordinate_index > 0 {
                  builder.write_char(',')
                }
                builder.write_char('[')
                builder.write_string(coordinate.longitude().to_string())
                builder.write_char(',')
                builder.write_string(coordinate.latitude().to_string())
                builder.write_char(']')
              }
              builder.write_string("]}}")
              emitted += 1
            }
          Err(_) => ()
        }
      }
      Relation(..) => ()
    }
  }
  builder.write_string("]}")
  builder.to_string()
}

///|
/// Export in-bounds nodes and clipped ways as a GeoJSON FeatureCollection.
/// Missing way references are errors so a partial line is never implied.
pub fn encode_geojson_in_bounds(
  entities : Array[Entity],
  index : NodeIndex,
  bounds : Bounds,
) -> Result[String, OsmError] {
  if !bounds.valid() {
    return Err(InvalidPrimitive(reason="GeoJSON bounds are invalid"))
  }
  let builder = StringBuilder()
  builder.write_string("{\"type\":\"FeatureCollection\",\"features\":[")
  let mut emitted = 0
  for entity in entities {
    match entity {
      Node(id~, coordinate~, tags~) =>
        if coordinate_in_bounds(coordinate, bounds) {
          if emitted > 0 {
            builder.write_char(',')
          }
          write_geojson_feature_start(builder, "node", id, tags)
          builder.write_string(
            "\"geometry\":{\"type\":\"Point\",\"coordinates\":[",
          )
          write_geojson_coordinate(builder, coordinate)
          builder.write_string("]}}")
          emitted += 1
        }
      Way(id~, refs~, tags~) => {
        let geometry = match
          resolve_way_geometry(Way(id~, refs~, tags~), index) {
          Ok(value) => value
          Err(problem) => return Err(problem)
        }
        let lines = match clip_way_geometry(geometry, bounds) {
          Ok(value) => value
          Err(problem) => return Err(problem)
        }
        if lines.length() > 0 {
          if emitted > 0 {
            builder.write_char(',')
          }
          write_geojson_feature_start(builder, "way", id, tags)
          if lines.length() == 1 {
            builder.write_string(
              "\"geometry\":{\"type\":\"LineString\",\"coordinates\":[",
            )
            write_geojson_line(builder, lines[0])
            builder.write_string("]}}")
          } else {
            builder.write_string(
              "\"geometry\":{\"type\":\"MultiLineString\",\"coordinates\":[",
            )
            for line_index, line in lines {
              if line_index > 0 {
                builder.write_char(',')
              }
              builder.write_char('[')
              write_geojson_line(builder, line)
              builder.write_char(']')
            }
            builder.write_string("]}}")
          }
          emitted += 1
        }
      }
      Relation(..) => ()
    }
  }
  builder.write_string("]}")
  Ok(builder.to_string())
}

///|
fn write_geojson_line(
  builder : StringBuilder,
  line : Array[Coordinate],
) -> Unit {
  for coordinate_index, coordinate in line {
    if coordinate_index > 0 {
      builder.write_char(',')
    }
    builder.write_char('[')
    write_geojson_coordinate(builder, coordinate)
    builder.write_char(']')
  }
}

///|
fn write_geojson_coordinate(
  builder : StringBuilder,
  coordinate : Coordinate,
) -> Unit {
  builder.write_string(coordinate.longitude().to_string())
  builder.write_char(',')
  builder.write_string(coordinate.latitude().to_string())
}

///|
fn write_geojson_feature_start(
  builder : StringBuilder,
  kind : String,
  id : Int64,
  tags : Array[Tag],
) -> Unit {
  builder.write_string("{\"type\":\"Feature\",\"properties\":{\"osm_type\":")
  builder.write_json_string(kind)
  builder.write_string(",\"osm_id\":")
  builder.write_string(id.to_string())
  builder.write_string(",\"tags\":")
  encode_tags_json(builder, tags)
  builder.write_string("},")
}
