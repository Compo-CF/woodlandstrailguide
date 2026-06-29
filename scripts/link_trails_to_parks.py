"""
Enrich TrailGraph.json with park associations.

For every Way in the trail graph, find which named parks its nodes fall
inside. Writes the result back to TrailGraph.json — each way gains an
optional `parks` field (list of park names, deduplicated, ordered by how
many of the way's nodes were inside the park so the most-relevant park
comes first).

This is a one-shot build step. Re-run after fetch_township_data.py or
fetch_pois.py refresh the underlying data.
"""

from __future__ import annotations

import json
import math
import sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GRAPH_PATH = ROOT / "WoodlandsTrailGuide" / "Resources" / "TrailGraph.json"
POLY_PATH  = ROOT / "WoodlandsTrailGuide" / "Resources" / "Polygons.json"
DOCS_GRAPH = ROOT / "docs" / "TrailGraph.json"

# Which polygon layers count as "parks" for this linkage. We include the
# Township parks layer plus George Mitchell NP (a single big polygon),
# since walkers would say "the trail goes through GMNP" the same way they
# say "the trail goes through Bear Branch Park."
PARK_POLY_KEYS = ("parks", "gmnp")


def point_in_ring(px: float, py: float, ring: list[list[float]]) -> bool:
    """Standard ray-casting PIP. Ring is a list of [lat, lon] points; we
    treat lon as x, lat as y."""
    n = len(ring)
    if n < 3:
        return False
    inside = False
    j = n - 1
    for i in range(n):
        # ring stores [lat, lon], so x=lon, y=lat
        yi, xi = ring[i]
        yj, xj = ring[j]
        if ((yi > py) != (yj > py)) and (
            px < (xj - xi) * (py - yi) / ((yj - yi) or 1e-12) + xi
        ):
            inside = not inside
        j = i
    return inside


def point_in_polygon(px: float, py: float, rings: list[list[list[float]]]) -> bool:
    """Outer ring at index 0, holes follow. A point inside a hole is not in
    the polygon."""
    if not rings:
        return False
    if not point_in_ring(px, py, rings[0]):
        return False
    for hole in rings[1:]:
        if point_in_ring(px, py, hole):
            return False
    return True


def ring_bbox(ring: list[list[float]]) -> tuple[float, float, float, float]:
    """Returns (south, west, north, east) over a ring of [lat, lon]."""
    lats = [r[0] for r in ring]
    lons = [r[1] for r in ring]
    return min(lats), min(lons), max(lats), max(lons)


def main():
    graph = json.loads(GRAPH_PATH.read_text(encoding="utf-8"))
    polys = json.loads(POLY_PATH.read_text(encoding="utf-8"))

    nodes = graph["nodes"]
    ways = graph["ways"]

    # Collect (park_name, rings, bbox) for all eligible park polygons. Skip
    # any without a name — anonymous polygons aren't useful as labels.
    parks: list[tuple[str, list, tuple]] = []
    for key in PARK_POLY_KEYS:
        group = polys.get("polygons", {}).get(key)
        if not group:
            continue
        for shape in group["items"]:
            name = shape.get("name")
            if not name:
                continue
            rings = shape.get("rings") or []
            if not rings:
                continue
            bbox = ring_bbox(rings[0])
            parks.append((name, rings, bbox))

    print(f"Loaded {len(parks)} named park polygons")

    # For each node in the graph, find which parks contain it. We cache by
    # node index so a way that touches the same node twice doesn't retest.
    node_parks: dict[int, list[str]] = {}

    def parks_for_node(idx: int) -> list[str]:
        cached = node_parks.get(idx)
        if cached is not None:
            return cached
        lat, lon = nodes[idx]
        hits = []
        for name, rings, (s, w, n, e) in parks:
            if not (s <= lat <= n and w <= lon <= e):
                continue
            if point_in_polygon(lon, lat, rings):
                hits.append(name)
        node_parks[idx] = hits
        return hits

    # For each way, count node-hits per park; sort and dedupe.
    enriched = 0
    for w in ways:
        counts: dict[str, int] = defaultdict(int)
        for ni in w["n"]:
            for park in parks_for_node(ni):
                counts[park] += 1
        if not counts:
            continue
        # Order: most-overlapping park first
        ranked = sorted(counts.items(), key=lambda kv: (-kv[1], kv[0]))
        w["parks"] = [p for p, _ in ranked]
        enriched += 1

    # Stats
    total_ways = len(ways)
    park_links = {p[0] for p in parks}
    parks_seen = set()
    for w in ways:
        for p in w.get("parks", []) or []:
            parks_seen.add(p)

    print(f"Enriched {enriched}/{total_ways} ways with park links")
    print(f"Parks reached by at least one trail: {len(parks_seen)}/{len(park_links)}")
    if parks_seen:
        sample = sorted(parks_seen)[:10]
        print(f"Sample parks: {sample}")

    # Write back to the resource and the docs mirror so the next remote
    # refresh picks it up too.
    GRAPH_PATH.write_text(json.dumps(graph, separators=(",", ":")), encoding="utf-8")
    if DOCS_GRAPH.exists():
        DOCS_GRAPH.write_text(json.dumps(graph, separators=(",", ":")), encoding="utf-8")
        print(f"Updated {DOCS_GRAPH}")
    print(f"Updated {GRAPH_PATH} ({GRAPH_PATH.stat().st_size/1024:.0f} KB)")


if __name__ == "__main__":
    sys.exit(main())
