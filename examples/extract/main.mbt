///|
/// A complete regional extract workflow; keep the original index when tags
/// select ways independently of their untagged supporting nodes.
async fn main {
  let args = @env.args()[1:]
  if args.length() != 6 && args.length() != 10 {
    println(
      "usage: moon run --target wasm examples/extract -- INPUT OUTPUT jsonl|geojson all|nodes|ways|relations KEY VALUE [SOUTH WEST NORTH EAST]",
    )
    println("use - - for no tag filter; bounds use WGS84 degrees")
    @env.exit(2)
  }
  let format = args[2]
  let kind = args[3]
  if (format != "jsonl" && format != "geojson") ||
    (kind != "all" && kind != "nodes" && kind != "ways" && kind != "relations") {
    println("invalid output format or entity type")
    @env.exit(2)
  }
  if (args[4] == "-") != (args[5] == "-") {
    println("an unfiltered tag requires both KEY and VALUE to be -")
    @env.exit(2)
  }
  let bounds = if args.length() == 10 {
    let rectangle = @moonosm.Bounds::{
      south: @string.parse_double(args[6][:]),
      west: @string.parse_double(args[7][:]),
      north: @string.parse_double(args[8][:]),
      east: @string.parse_double(args[9][:]),
    }
    if !rectangle.valid() {
      println(
        "invalid bounds; antimeridian-crossing rectangles are unsupported",
      )
      @env.exit(2)
    }
    if kind == "relations" {
      println(
        "relation geometry is not resolved; spatial relation extracts are unsupported",
      )
      @env.exit(2)
    }
    Some(rectangle)
  } else {
    None
  }
  if format == "geojson" && kind == "relations" {
    println(
      "GeoJSON relation geometry is unsupported; use JSONL without bounds",
    )
    @env.exit(2)
  }
  let tags = if args[4] == "-" {
    []
  } else {
    [@moonosm.Tag::{ key: args[4], value: args[5], }]
  }
  let query = @moonosm.Query::{
    include_nodes: kind == "all" || kind == "nodes",
    include_ways: kind == "all" || kind == "ways",
    include_relations: (kind == "all" || kind == "relations") &&
    bounds is None &&
    format == "jsonl",
    bounds,
    required_tags: tags,
  }
  let bytes = @fs.read_binary(args[0])
  let document = match @moonosm.decode_file(bytes, @moonosm.Limits::default()) {
    Ok(value) => value
    Err(problem) => {
      println("PBF decode failed: " + problem.message())
      @env.exit(1)
    }
  }
  let index = @moonosm.NodeIndex::from_entities(document.entities)
  let selected = @moonosm.select_entities_with_geometry(
    document.entities,
    query,
    index,
  )
  let output = if format == "jsonl" {
    @moonosm.encode_jsonl(selected)
  } else {
    match bounds {
      Some(rectangle) =>
        match @moonosm.encode_geojson_in_bounds(selected, index, rectangle) {
          Ok(value) => value
          Err(problem) => {
            println("GeoJSON export failed: " + problem.message())
            @env.exit(1)
          }
        }
      None => @moonosm.encode_geojson(selected, index)
    }
  }
  @fs.write_text(args[1], output)
  println(
    "decoded=\{document.entities.length()} selected=\{selected.length()} format=\{format}",
  )
}
