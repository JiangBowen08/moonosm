"""Independently check three extraction workflows against full JSONL output.

Usage: python verify_extracts.py VALIDATION_DIRECTORY
The full export is separately compared against osm-pbf-parser@2.3.0.
"""
import json
import sys
from pathlib import Path


def clip_segment(a, b):
    # Liang-Barsky in floating point, independent of the MoonBit nanodegree model.
    x, y = a
    dx, dy = b[0] - x, b[1] - y
    lower, upper = 0.0, 1.0
    for denominator, numerator in [(-dx, x - 1.50), (dx, 1.54 - x),
                                   (-dy, y - 42.50), (dy, 42.52 - y)]:
        if denominator == 0:
            if numerator < 0:
                return None
        elif denominator < 0:
            lower = max(lower, numerator / denominator)
        else:
            upper = min(upper, numerator / denominator)
        if lower > upper:
            return None
    return [(x + lower * dx, y + lower * dy), (x + upper * dx, y + upper * dy)]


def main(directory):
    root = Path(directory)
    with (root / "andorra.jsonl").open(encoding="utf-8") as stream:
        rows = [json.loads(line) for line in stream]
    cafes = json.loads((root / "cafes.geojson").read_text(encoding="utf-8"))["features"]
    expected = [r for r in rows if r["type"] == "node" and r["tags"].get("amenity") == "cafe"]
    assert [f["properties"]["osm_id"] for f in cafes] == [r["id"] for r in expected]
    for feature, row in zip(cafes, expected):
        assert feature["geometry"]["type"] == "Point"
        assert feature["properties"]["tags"] == row["tags"]
        assert all(abs(a - b) <= 1e-7 for a, b in
                   zip(feature["geometry"]["coordinates"], [row["lon"], row["lat"]]))
    nodes = {r["id"]: (r["lon"], r["lat"]) for r in rows if r["type"] == "node"}
    roads = json.loads((root / "residential.geojson").read_text(encoding="utf-8"))["features"]
    expected_roads, degenerate = [], []
    by_id = {}
    for row in rows:
        if row["type"] != "way" or row["tags"].get("highway") != "residential":
            continue
        points = [nodes[node] for node in row["refs"]]
        segments = [part for a, b in zip(points, points[1:])
                    if (part := clip_segment(a, b)) is not None]
        if any(a != b for a, b in segments):
            expected_roads.append(row["id"])
            by_id[row["id"]] = row
        elif segments:
            degenerate.append(row["id"])
    assert [f["properties"]["osm_id"] for f in roads] == expected_roads
    for feature in roads:
        assert feature["properties"]["tags"] == by_id[feature["properties"]["osm_id"]]["tags"]
        geometry = feature["geometry"]
        assert geometry["type"] in ("LineString", "MultiLineString")
        lines = [geometry["coordinates"]] if geometry["type"] == "LineString" else geometry["coordinates"]
        for line in lines:
            assert len(line) >= 2
            for x, y in line:
                assert 1.50 - 1e-7 <= x <= 1.54 + 1e-7 and 42.50 - 1e-7 <= y <= 42.52 + 1e-7
    with (root / "routes.jsonl").open(encoding="utf-8") as stream:
        routes = [json.loads(line) for line in stream]
    assert routes == [r for r in rows if r["type"] == "relation" and r["tags"].get("type") == "route"]
    print(json.dumps({"cafes": len(cafes), "roads": len(roads), "routes": len(routes),
                      "degenerate_roads_omitted": degenerate, "status": "passed"}))


if __name__ == "__main__":
    main(sys.argv[1])
