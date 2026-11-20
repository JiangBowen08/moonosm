// External oracle only; install osm-pbf-parser@2.3.0 in a separate directory.
// Usage: node compare_reference.cjs PARSER_DIRECTORY INPUT.pbf OUTPUT.jsonl
const fs = require("node:fs");
const path = require("node:path");
const readline = require("node:readline");
const assert = require("node:assert/strict");
async function main() {
  const [directory, input, output] = process.argv.slice(2);
  if (!output) throw new Error("expected PARSER_DIRECTORY INPUT.pbf OUTPUT.jsonl");
  const entry = require.resolve("osm-pbf-parser", {paths: [path.resolve(directory)]});
  const manifest = require(path.join(path.dirname(entry), "package.json"));
  assert.equal(manifest.version, "2.3.0", "pin the independent reference version");
  const parser = require(entry)();
  const batches = new (require("node:stream").PassThrough)({objectMode: true});
  parser.on("error", error => batches.destroy(error));
  parser.pipe(batches);
  const source = fs.createReadStream(input);
  source.on("error", error => parser.destroy(error));
  source.pipe(parser);
  const lines = readline.createInterface({input: fs.createReadStream(output), crlfDelay: Infinity});
  const records = lines[Symbol.asyncIterator]();
  const counts = {node: 0, way: 0, relation: 0};
  for await (const batch of batches) {
    for (const reference of batch) {
      const next = await records.next();
      assert(!next.done, "MoonOSM output ended early");
      const actual = JSON.parse(next.value);
      const where = `${reference.type}/${reference.id}`;
      assert.equal(actual.type, reference.type, where);
      assert.equal(actual.id, reference.id, where);
      assert.deepEqual(Object.entries(actual.tags), Object.entries(reference.tags), where);
      if (reference.type === "node") {
        assert(Math.abs(actual.lat-reference.lat) <= 1e-7, where + " latitude");
        assert(Math.abs(actual.lon-reference.lon) <= 1e-7, where + " longitude");
      } else if (reference.type === "way") {
        assert.deepEqual(actual.refs, reference.refs, where);
      } else {
        assert.deepEqual(actual.members, reference.members.map(m => ({type:m.type, ref:m.id, role:m.role})), where);
      }
      counts[reference.type]++;
    }
  }
  assert((await records.next()).done, "MoonOSM output has extra records");
  console.log(JSON.stringify({reference:manifest.version, counts, differences:0}));
}
main().catch(error => { console.error(error); process.exitCode = 1; });
