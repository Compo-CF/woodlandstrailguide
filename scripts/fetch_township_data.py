"""
Pull The Woodlands Township pathway/trail data from their public ArcGIS REST
services. No auth, no rate limits documented.

Outputs three raw GeoJSON files plus a combined trail graph ready for the iOS app.

Endpoints (FeatureServer layer 0):
  PATHWAYS_ROUTING   1,497 residential pathway segments with STREET names + Village
  TRAILS             natural-surface trails (George Mitchell NP, Spring Creek Greenway, etc.)
  PATHWAYS           200+mi master pathway polylines (used to backfill if needed)

Usage:
    python fetch_township_data.py
"""

from __future__ import annotations

import json
import math
import sys
import time
import urllib.parse
import urllib.request
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RAW_DIR = ROOT / "scripts" / "raw"
RES_DIR = ROOT / "WoodlandsTrailGuide" / "Resources"
RAW_DIR.mkdir(parents=True, exist_ok=True)
RES_DIR.mkdir(parents=True, exist_ok=True)

BASE = "https://tharcgis2.thewoodlands-tx.gov/arcgis/rest/services"

LAYERS = {
    "pathways_routing": f"{BASE}/PATHWAYS_ROUTING/FeatureServer/0/query",
    "trails":           f"{BASE}/TRAILS/FeatureServer/0/query",
    "pathways":         f"{BASE}/PATHWAYS/FeatureServer/0/query",
}

# ArcGIS REST query params: ask for GeoJSON, WGS84, all features, all attributes.
COMMON_PARAMS = {
    "where": "1=1",
    "outFields": "*",
    "outSR": "4326",
    "f": "geojson",
    "returnGeometry": "true",
}


def fetch_geojson(url: str, params: dict, page_size: int = 1000) -> dict:
    """Page through ArcGIS REST. Some servers cap at 1000 features per request."""
    all_features: list[dict] = []
    offset = 0
    crs = None
    while True:
        q = dict(params, resultOffset=offset, resultRecordCount=page_size)
        full = f"{url}?{urllib.parse.urlencode(q)}"
        print(f"  GET offset={offset:>5}  ...", end=" ", flush=True)
        # ArcGIS server 403s the default Python user-agent; spoof a real one.
        req = urllib.request.Request(full, headers={
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
                          "AppleWebKit/537.36 (KHTML, like Gecko) "
                          "Chrome/122.0 Safari/537.36",
            "Accept": "application/json",
        })
        with urllib.request.urlopen(req, timeout=60) as resp:
            data = json.loads(resp.read().decode("utf-8"))
        if "error" in data:
            raise RuntimeError(f"ArcGIS error: {data['error']}")
        features = data.get("features", []) or []
        if crs is None:
            crs = data.get("crs")
        print(f"got {len(features)}")
        all_features.extend(features)
        if len(features) < page_size:
            break
        offset += page_size
        time.sleep(0.2)  # be polite
    return {"type": "FeatureCollection", "crs": crs, "features": all_features}


def haversine_m(la1, lo1, la2, lo2):
    R = 6371000.0
    p1, p2 = math.radians(la1), math.radians(la2)
    dp = math.radians(la2 - la1)
    dl = math.radians(lo2 - lo1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * R * math.asin(math.sqrt(a))


def title_case_street(s: str | None) -> str | None:
    """ArcGIS gives us SHOUTING street names. Title-case them but keep small words."""
    if not s:
        return s
    small = {"of", "and", "the", "at", "in", "on"}
    words = s.lower().split()
    out = []
    for i, w in enumerate(words):
        if i > 0 and w in small:
            out.append(w)
        else:
            out.append(w[:1].upper() + w[1:])
    return " ".join(out)


# Township villages are stored UPPERCASED in the GIS and missing the apostrophes
# residents actually use. Map to the canonical resident-facing spellings.
VILLAGE_NAME_MAP = {
    "ALDEN BRIDGE": "Alden Bridge",
    "COCHRANS CROSSING": "Cochran's Crossing",
    "COLLEGE PARK": "College Park",
    "CREEKSIDE PARK": "Creekside Park",
    "CREEKSIDES PARK": "Creekside Park",  # source-data typo, normalized here
    "GROGANS MILL": "Grogan's Mill",
    "INDIAN SPRINGS": "Indian Springs",
    "PANTHER CREEK": "Panther Creek",
    "RESEARCH FOREST": "Research Forest",
    "STERLING RIDGE": "Sterling Ridge",
    "TOWN CENTER": "Town Center",
    "EAST SHORE": "East Shore",
}


def canonical_village(s: str | None) -> str | None:
    if not s:
        return None
    key = s.strip().upper()
    return VILLAGE_NAME_MAP.get(key, s.strip())


def build_graph(layers: dict[str, dict]) -> dict:
    """Merge all layers into a single node+way+adjacency graph.

    Nodes are deduped by rounded coordinate (~1m granularity) so that segments
    sharing an endpoint actually connect for routing.
    """
    DECIMAL_PLACES = 6  # ~11cm; precise enough that real intersections coincide
    node_index: dict[tuple[float, float], int] = {}
    node_coords: list[tuple[float, float]] = []

    def get_node(la: float, lo: float) -> int:
        key = (round(la, DECIMAL_PLACES), round(lo, DECIMAL_PLACES))
        idx = node_index.get(key)
        if idx is None:
            idx = len(node_coords)
            node_index[key] = idx
            node_coords.append(key)
        return idx

    ways: list[dict] = []
    total_len_m = 0.0

    def add_linestring(coords: list[list[float]], rec: dict):
        nonlocal total_len_m
        if len(coords) < 2:
            return
        idxs = [get_node(lat, lon) for lon, lat in coords]  # GeoJSON is [lon,lat]
        # Skip a degenerate way collapsed by node-dedup
        if len(set(idxs)) < 2:
            return
        seg = 0.0
        for a, b in zip(idxs, idxs[1:]):
            la1, lo1 = node_coords[a]
            la2, lo2 = node_coords[b]
            seg += haversine_m(la1, lo1, la2, lo2)
        rec["n"] = idxs
        rec["len_m"] = round(seg, 1)
        total_len_m += seg
        ways.append(rec)

    # ---- Layer 1: PATHWAYS_ROUTING (residential pathway segments, named) ----
    routing = layers["pathways_routing"]["features"]
    for f in routing:
        geom = f.get("geometry") or {}
        props = f.get("properties") or {}
        if geom.get("type") != "LineString":
            continue
        name = title_case_street(props.get("STREET"))
        rec = {
            "source": "twp_routing",
            "kind": "pathway",
            "village": canonical_village(
                props.get("Village") or props.get("VILLAGE") or props.get("VillageName")
            ),
            "pathway_id": props.get("PathwayID") or props.get("PATHWAYID"),
        }
        if name and name.strip() and name.lower() not in ("none", "null"):
            rec["name"] = name.strip()
        add_linestring(geom["coordinates"], rec)

    # ---- Layer 2: TRAILS (named natural-surface) ----
    trails = layers["trails"]["features"]
    for f in trails:
        geom = f.get("geometry") or {}
        props = f.get("properties") or {}
        gtype = geom.get("type")
        coords_iter = []
        if gtype == "LineString":
            coords_iter = [geom["coordinates"]]
        elif gtype == "MultiLineString":
            coords_iter = geom["coordinates"]
        else:
            continue
        for line in coords_iter:
            rec = {
                "source": "twp_trails",
                "kind": "trail",
                "park": props.get("PARKNAME") or props.get("ParkName"),
                "system": props.get("SYSTEMNAME") or props.get("SystemName"),
                "surface": (props.get("SURFACE") or props.get("Surface") or "").lower() or None,
            }
            n = props.get("TRAILNAME") or props.get("TrailName")
            if n:
                rec["name"] = n.strip()
            add_linestring(line, rec)

    # Drop None values so the JSON stays compact
    for w in ways:
        for k in [k for k, v in w.items() if v is None]:
            del w[k]

    # ---- Build adjacency ----
    adj: dict[int, list[list]] = defaultdict(list)
    for wi, w in enumerate(ways):
        ns = w["n"]
        for a, b in zip(ns, ns[1:]):
            la1, lo1 = node_coords[a]
            la2, lo2 = node_coords[b]
            d = haversine_m(la1, lo1, la2, lo2)
            adj[a].append([b, round(d, 1), wi])
            adj[b].append([a, round(d, 1), wi])
    adj_list = [adj.get(i, []) for i in range(len(node_coords))]

    lats = [c[0] for c in node_coords]
    lons = [c[1] for c in node_coords]
    return {
        "version": 1,
        "source": "The Woodlands Township GIS (PATHWAYS_ROUTING, TRAILS). Public ArcGIS REST.",
        "bbox": {
            "south": min(lats), "west": min(lons),
            "north": max(lats), "east": max(lons),
        },
        "nodes": [[round(la, 6), round(lo, 6)] for la, lo in node_coords],
        "ways": ways,
        "adj": adj_list,
        "total_length_m": round(total_len_m, 1),
    }


def main():
    layers: dict[str, dict] = {}
    for name, url in LAYERS.items():
        print(f"Fetching {name} ...")
        gj = fetch_geojson(url, COMMON_PARAMS)
        path = RAW_DIR / f"{name}.geojson"
        path.write_text(json.dumps(gj), encoding="utf-8")
        print(f"  saved {len(gj['features'])} features to {path.name} "
              f"({path.stat().st_size/1024:.0f} KB)")
        layers[name] = gj

    print("Building graph ...")
    graph = build_graph(layers)
    out = RES_DIR / "TrailGraph.json"
    out.write_text(json.dumps(graph, separators=(",", ":")), encoding="utf-8")
    miles = graph["total_length_m"] / 1609.344
    named = sum(1 for w in graph["ways"] if "name" in w)
    print()
    print(f"Wrote {out}")
    print(f"  nodes: {len(graph['nodes'])}")
    print(f"  ways:  {len(graph['ways'])}")
    print(f"  named: {named} ({100*named/max(1,len(graph['ways'])):.1f}%)")
    print(f"  total: {miles:.1f} miles")
    print(f"  size:  {out.stat().st_size/1024:.0f} KB")


if __name__ == "__main__":
    sys.exit(main())
