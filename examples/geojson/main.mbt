///|
fn main {
  let entities : Array[@moonosm.Entity] = [
    @moonosm.Entity::Node(
      id=1L,
      coordinate=@moonosm.Coordinate::{
        lat_nanodegrees: 41500000000L,
        lon_nanodegrees: 1500000000L,
      },
      tags=[],
    ),
  ]
  let node_index = @moonosm.NodeIndex::from_entities(entities)
  let bounds = @moonosm.Bounds::{
    south: 41.3,
    west: 1.4,
    north: 42.0,
    east: 1.8,
  }
  match @moonosm.encode_geojson_in_bounds(entities, node_index, bounds) {
    Ok(feature_collection) => println(feature_collection)
    Err(problem) => println(problem.message())
  }
}
