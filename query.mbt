///|
/// Return entities that satisfy the requested type, node bounds and exact tags.
/// Ways and relations are not spatially clipped because PBF references require
/// a separate geometry index; their tag and type filters remain exact.
pub fn select_entities(
  entities : Array[Entity],
  query : Query,
) -> Array[Entity] {
  if query.bounds is Some(bounds) && !bounds.valid() {
    return []
  }
  let output : Array[Entity] = []
  for entity in entities {
    if !query_includes_type(entity, query) {
      continue
    }
    if !query_matches_tags(entity, query.required_tags) {
      continue
    }
    match entity {
      Node(coordinate~, ..) =>
        match query.bounds {
          Some(bounds) =>
            if !coordinate_in_bounds(coordinate, bounds) {
              continue
            }
          None => ()
        }
      _ => ()
    }
    output.push(entity)
  }
  output
}

///|
fn query_includes_type(entity : Entity, query : Query) -> Bool {
  match entity {
    Node(..) => query.include_nodes
    Way(..) => query.include_ways
    Relation(..) => query.include_relations
  }
}

///|
fn query_matches_tags(entity : Entity, required : Array[Tag]) -> Bool {
  let tags = match entity {
    Node(tags~, ..) => tags
    Way(tags~, ..) => tags
    Relation(tags~, ..) => tags
  }
  for requirement in required {
    let mut found = false
    for tag in tags {
      if tag.key == requirement.key && tag.value == requirement.value {
        found = true
        break
      }
    }
    if !found {
      return false
    }
  }
  true
}

///|
fn coordinate_in_bounds(coordinate : Coordinate, bounds : Bounds) -> Bool {
  let latitude = coordinate.latitude()
  let longitude = coordinate.longitude()
  latitude >= bounds.south &&
  latitude <= bounds.north &&
  longitude >= bounds.west &&
  longitude <= bounds.east
}

///|
/// Summarize counts before and after selection for stable CLI/report output.
pub fn summarize_selection(
  input : Array[Entity],
  output : Array[Entity],
  query : Query,
) -> Summary {
  let mut seen_nodes = 0
  let mut seen_ways = 0
  let mut seen_relations = 0
  let mut emitted_nodes = 0
  let mut emitted_ways = 0
  let mut emitted_relations = 0
  let mut rejected_by_type = 0
  let mut rejected_by_bounds = 0
  let mut rejected_by_tags = 0
  let invalid_bounds = match query.bounds {
    Some(bounds) => !bounds.valid()
    None => false
  }
  for entity in input {
    match entity {
      Node(..) => seen_nodes += 1
      Way(..) => seen_ways += 1
      Relation(..) => seen_relations += 1
    }
    if !query_includes_type(entity, query) {
      rejected_by_type += 1
    } else if !query_matches_tags(entity, query.required_tags) {
      rejected_by_tags += 1
    } else if invalid_bounds {
      rejected_by_bounds += 1
    } else {
      match entity {
        Node(coordinate~, ..) =>
          match query.bounds {
            Some(bounds) =>
              if !coordinate_in_bounds(coordinate, bounds) {
                rejected_by_bounds += 1
              }
            None => ()
          }
        _ => ()
      }
    }
  }
  for entity in output {
    match entity {
      Node(..) => emitted_nodes += 1
      Way(..) => emitted_ways += 1
      Relation(..) => emitted_relations += 1
    }
  }
  {
    seen_nodes,
    seen_ways,
    seen_relations,
    emitted_nodes,
    emitted_ways,
    emitted_relations,
    rejected_by_type,
    rejected_by_bounds,
    rejected_by_tags,
  }
}
