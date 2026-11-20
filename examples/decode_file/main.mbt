///|
/// Decode a complete OSM PBF file supplied as the first command-line argument.
async fn main {
  let args = @env.args()[1:]
  guard args is [path, ..] else {
    println(
      "usage: moon run --target wasm examples/decode_file -- <file.osm.pbf>",
    )
    return
  }
  let bytes = @fs.read_binary(path)
  match @moonosm.decode_file(bytes, @moonosm.Limits::default()) {
    Ok(document) => {
      let mut nodes = 0
      let mut ways = 0
      let mut relations = 0
      for entity in document.entities {
        match entity {
          @moonosm.Node(..) => nodes += 1
          @moonosm.Way(..) => ways += 1
          @moonosm.Relation(..) => relations += 1
        }
      }
      println("nodes=\{nodes} ways=\{ways} relations=\{relations}")
    }
    Err(_) => println("failed to decode OSM PBF file")
  }
}
