///|
/// Decode a complete OSM PBF file and write its entities as JSONL.
async fn main {
  let args = @env.args()[1:]
  guard args is [input_path, output_path, ..] else {
    println(
      "usage: moon run --target wasm examples/decode_file -- <input.osm.pbf> <output.jsonl>",
    )
    return
  }
  let bytes = @fs.read_binary(input_path)
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
      @fs.write_text(output_path, @moonosm.encode_jsonl(document.entities))
      println("nodes=\{nodes} ways=\{ways} relations=\{relations}")
      println("wrote \{output_path}")
    }
    Err(problem) => {
      println("failed to decode OSM PBF file: " + problem.message())
      @env.exit(1)
    }
  }
}
