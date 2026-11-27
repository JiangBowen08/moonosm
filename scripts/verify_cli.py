"""Exercise file CLI exit codes and output safety using synthetic PBF bytes.

Usage: python scripts/verify_cli.py [--moon PATH_TO_MOON]
No network, third-party Python packages, or external datasets are needed after
MoonBit's project dependencies have been installed.
"""
import argparse
import json
import struct
import subprocess
import tempfile
from pathlib import Path


def field(number, value):
    """Length-delimited protobuf field; fixtures intentionally stay below 128B."""
    assert len(value) < 128 and 0 < number < 16
    return bytes([(number << 3) | 2, len(value)]) + value


def frame(kind, payload):
    blob = field(1, payload)
    assert len(blob) < 128
    header = field(1, kind.encode("ascii")) + b"\x18" + bytes([len(blob)])
    return struct.pack(">I", len(header)) + header + blob


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--moon", default="moon")
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    cases = []
    with tempfile.TemporaryDirectory(prefix="moonosm-cli-") as directory:
        work = Path(directory).resolve()
        output = work / "output.jsonl"
        invalid = work / "invalid.pbf"
        invalid.write_bytes(bytes([0, 0, 0, 8, 1]))
        valid = work / "node.pbf"
        # HeaderBlock.required_features = OsmSchema-V0.6. PrimitiveBlock has an
        # empty string table and one ordinary Node: sint64 id=1, lat=lon=0.
        primitive = bytes.fromhex("0a020a0012080a06080240004800")
        valid.write_bytes(frame("OSMHeader", field(4, b"OsmSchema-V0.6"))
                          + frame("OSMData", primitive))
        sentinel = b"existing output must survive rejected input\n"

        def run(name, arguments, expected_exit, diagnostic=None):
            command = [args.moon, "run", "--target", "wasm",
                       "examples/decode_file", "--"] + [str(a) for a in arguments]
            result = subprocess.run(command, cwd=str(root), stdin=subprocess.DEVNULL,
                                    stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                    encoding="utf8", errors="replace", timeout=180)
            assert result.returncode == expected_exit, (name, result.returncode, result.stdout)
            if diagnostic:
                assert diagnostic in result.stdout, (name, result.stdout)
            cases.append({"case": name, "exit_code": result.returncode})

        run("missing both paths", [], 2, "usage:")
        run("missing output path", [valid], 2, "usage:")
        output.write_bytes(sentinel)
        run("reject excess argument", [valid, output, "extra"], 2, "usage:")
        assert output.read_bytes() == sentinel
        run("invalid PBF preserves existing output", [invalid, output], 1, "failed to decode")
        assert output.read_bytes() == sentinel
        output.unlink()
        run("invalid PBF creates no output", [invalid, output], 1, "failed to decode")
        assert not output.exists()
        run("valid ordinary node", [valid, output], 0, "nodes=1 ways=0 relations=0")
        records = [json.loads(line) for line in output.read_text(encoding="utf8").splitlines()]
        assert records == [{"type": "node", "id": 1, "lat": 0, "lon": 0, "tags": {}}]
    print(json.dumps({"status": "passed", "cases": cases}, ensure_ascii=False))


if __name__ == "__main__":
    main()
