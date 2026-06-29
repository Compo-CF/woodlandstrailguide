"""
Fetch every POI / context layer relevant to a hike-and-bike trail guide from
The Woodlands Township's public ArcGIS REST services.

Outputs:
  scripts/raw/<layer>.geojson         raw per-layer dumps (gitignored)
  WoodlandsTrailGuide/Resources/POIs.json
  WoodlandsTrailGuide/Resources/Polygons.json   (lakes, parks, villages, etc.)

POIs.json shape:
  {
    "version": 1,
    "source": "The Woodlands Township GIS",
    "categories": {
      "<key>": {
        "label": "Restrooms",
        "icon": "toilet.fill",
        "tint": "#3b82f6",
        "items": [
          {"id": "...", "name": "...", "lat": 30.16, "lon": -95.55,
           "park": "...", "meta": {...}}
        ]
      },
      ...
    }
  }

Polygons.json shape:
  {
    "version": 1,
    "polygons": {
      "<key>": [
        {"name": "...", "rings": [[[lat,lon],...], ...], "meta": {...}}
      ]
    }
  }
"""

from __future__ import annotations

import json
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RAW = ROOT / "scripts" / "raw"
RES = ROOT / "WoodlandsTrailGuide" / "Resources"
RAW.mkdir(parents=True, exist_ok=True)
RES.mkdir(parents=True, exist_ok=True)

BASE = "https://tharcgis2.thewoodlands-tx.gov/arcgis/rest/services"

UA = ("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
      "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0 Safari/537.36")


# --- Layer catalog --------------------------------------------------------
# Each entry: layer name -> category config. Layers without coords are skipped.
#   kind   "point" | "polygon" | "line"
#   label  human-friendly category label (shown in the app)
#   icon   SF Symbol name (iOS native icons — no asset work)
#   tint   accent color for the marker
#   visible_at_zoom  minimum MKMapView altitude (metres) — bigger = farther out
#   route_distance_m  meters from route polyline to consider "along the route"
#                     None = exclude from route surfacing (e.g. benches, too noisy)
POI_LAYERS = {
    "PARKING_LOTS_PARKS":      {"key": "parking_park",    "kind": "polygon", "label": "Park parking",     "icon": "p.circle.fill",         "tint": "#5b6bf2"},
    "PARKING_LOTS":            {"key": "parking",         "kind": "polygon", "label": "Parking",          "icon": "p.circle",              "tint": "#5b6bf2"},
    "PATHWAY_BRIDGES":         {"key": "bridges",         "kind": "point",   "label": "Bridges & underpasses", "icon": "road.lanes",       "tint": "#a06325"},
    "DOG_PARKS":               {"key": "dog_parks",       "kind": "polygon", "label": "Dog parks",        "icon": "pawprint.fill",         "tint": "#7c3aed"},
    "PLAY_AREAS":              {"key": "playgrounds",     "kind": "polygon", "label": "Playgrounds",      "icon": "figure.play",           "tint": "#f59e0b"},
    "PLAYGROUND_EQUIPMENT":    {"key": "playgrounds_eq",  "kind": "point",   "label": "Play equipment",   "icon": "figure.play",           "tint": "#f59e0b"},
    "RESTROOMS":               {"key": "restrooms",       "kind": "point",   "label": "Restrooms",        "icon": "toilet.fill",           "tint": "#0ea5e9"},
    "DRINKING_FOUNTAINS":      {"key": "fountains",       "kind": "point",   "label": "Water fountains",  "icon": "drop.fill",             "tint": "#06b6d4"},
    "BENCHES":                 {"key": "benches",         "kind": "point",   "label": "Benches",          "icon": "seat.fill",             "tint": "#8b8b80"},
    "PICNIC_TABLES":           {"key": "picnic_tables",   "kind": "point",   "label": "Picnic tables",    "icon": "fork.knife",            "tint": "#84cc16"},
    "PICNIC_AREAS":            {"key": "picnic_areas",    "kind": "polygon", "label": "Picnic areas",     "icon": "fork.knife.circle",     "tint": "#84cc16"},
    "PAVILIONS":               {"key": "pavilions",       "kind": "polygon", "label": "Pavilions",        "icon": "house.fill",            "tint": "#a16207"},
    "BBQ_GRILLS":              {"key": "bbq",             "kind": "point",   "label": "BBQ grills",       "icon": "flame.fill",            "tint": "#dc2626"},
    "ART_BENCHES":             {"key": "art_benches",     "kind": "point",   "label": "Art benches",      "icon": "paintpalette.fill",     "tint": "#ec4899"},
    "ART_BIKE_RACKS":          {"key": "art_bike_racks",  "kind": "point",   "label": "Art bike racks",   "icon": "paintbrush.fill",       "tint": "#ec4899"},
    "BIKE_RACKS":              {"key": "bike_racks",      "kind": "point",   "label": "Bike racks",       "icon": "bicycle",               "tint": "#16a34a"},
    "BIKE_SHARE_STATIONS":     {"key": "bike_share",      "kind": "point",   "label": "Bike share",       "icon": "bicycle.circle.fill",   "tint": "#16a34a"},
    "FISHING_ACCESS":          {"key": "fishing",         "kind": "point",   "label": "Fishing access",   "icon": "fish.fill",             "tint": "#14b8a6"},
    "ECOTOUR_MARKERS":         {"key": "ecotour",         "kind": "point",   "label": "Nature markers",   "icon": "leaf.fill",             "tint": "#15803d"},
    "TROLLEY_STOPS":           {"key": "trolley",         "kind": "point",   "label": "Trolley stops",    "icon": "tram.fill",             "tint": "#0284c7"},
    "TRAILS_MARKER_POSTS":     {"key": "trail_markers",   "kind": "point",   "label": "Trail markers",    "icon": "signpost.right.fill",   "tint": "#a06325"},
    "SPORTS_FIELDS":           {"key": "sports_fields",   "kind": "polygon", "label": "Sports fields",    "icon": "sportscourt.fill",      "tint": "#0d9488"},
    "SPORTS_COURTS":           {"key": "sports_courts",   "kind": "polygon", "label": "Sports courts",    "icon": "sportscourt",           "tint": "#0d9488"},
    "AQUATIC_POOLS":           {"key": "pools",           "kind": "polygon", "label": "Pools",            "icon": "figure.pool.swim",      "tint": "#2563eb"},
    "AQUATIC_SPRAYGROUNDS":    {"key": "spraygrounds",    "kind": "polygon", "label": "Splash pads",      "icon": "drop.circle.fill",      "tint": "#0ea5e9"},
    "FOUNTAIN_FEATURES":       {"key": "fountain_feat",   "kind": "point",   "label": "Decorative fountains", "icon": "sparkles",          "tint": "#06b6d4"},
    "DOG_BAG_STATIONS":        {"key": "dog_bag",         "kind": "point",   "label": "Dog bag stations", "icon": "pawprint",              "tint": "#7c3aed"},
    "MONUMENT_SIGNS":          {"key": "monuments",       "kind": "point",   "label": "Monuments",        "icon": "building.columns.fill", "tint": "#92400e"},
    "PIERS":                   {"key": "piers",           "kind": "polygon", "label": "Piers",            "icon": "water.waves",           "tint": "#0369a1"},
    "DOCKS":                   {"key": "docks",           "kind": "polygon", "label": "Docks",            "icon": "ferry.fill",            "tint": "#0369a1"},
    "BOAT_HOUSES":             {"key": "boat_houses",     "kind": "polygon", "label": "Boat houses",      "icon": "sailboat.fill",         "tint": "#0369a1"},
}

# Polygon-only context layers that are NOT surfaced as POIs — drawn under
# the trails to give the map a real sense of place.
# Deliberately scoped down from the full Township catalog:
#   - OPEN_SPACE_RESERVES (3,361 polygons) and VILLAGES (867 small ones)
#     are skipped to keep Polygons.json under ~2 MB.
#   - PARKS already convey the green areas; LAKES are the water landmarks.
POLYGON_LAYERS = {
    "PARKS":                   {"key": "parks",           "label": "Parks",                 "fill": "#cee2c0"},
    "LAKES":                   {"key": "lakes",           "label": "Lakes",                 "fill": "#bcd9e0"},
    "GMNP_AREA":               {"key": "gmnp",            "label": "George Mitchell NP",    "fill": "#c5d4ab"},
    "VILLAGE_AREAS":           {"key": "village_areas",   "label": "Village areas",         "fill": None},
}

# Line-only context layers
LINE_LAYERS = {
    "CREEKS":                  {"key": "creeks",          "label": "Creeks",                "stroke": "#7da9b8"},
}


def fetch_layer(layer_name: str, page_size: int = 1000):
    """Page through a FeatureServer/0 query. Some layers reject `where=1=1`
    with a 400 — they need a real predicate. Retry with `OBJECTID > 0` in
    that case, and finally with the MapServer endpoint as a last resort."""
    queries_to_try = [
        (f"{BASE}/{layer_name}/FeatureServer/0/query", "1=1"),
        (f"{BASE}/{layer_name}/FeatureServer/0/query", "OBJECTID>0"),
        (f"{BASE}/{layer_name}/MapServer/0/query",     "1=1"),
    ]
    last_err = None
    for url, where in queries_to_try:
        try:
            return _page(url, where, page_size, layer_name)
        except Exception as e:
            last_err = e
            continue
    raise last_err if last_err else RuntimeError(f"{layer_name}: unknown failure")


def _page(url: str, where: str, page_size: int, layer_name: str):
    features = []
    offset = 0
    while True:
        q = {
            "where": where,
            "outFields": "*",
            "outSR": "4326",
            "f": "geojson",
            "returnGeometry": "true",
            "resultOffset": offset,
            "resultRecordCount": page_size,
        }
        full = f"{url}?{urllib.parse.urlencode(q)}"
        req = urllib.request.Request(full, headers={"User-Agent": UA, "Accept": "application/json"})
        with urllib.request.urlopen(req, timeout=60) as resp:
            data = json.loads(resp.read().decode("utf-8"))
        if isinstance(data, dict) and data.get("error"):
            raise RuntimeError(f"{layer_name}: {data['error']}")
        page = data.get("features", []) or []
        features.extend(page)
        if len(page) < page_size:
            break
        offset += page_size
        time.sleep(0.15)
    return features


def polygon_centroid(coords):
    """Coords is a GeoJSON Polygon `coordinates` (list of rings, each [lon,lat])."""
    ring = coords[0]
    if len(ring) < 3:
        return None
    cx = cy = 0.0
    a = 0.0
    n = len(ring) - 1
    for i in range(n):
        x0, y0 = ring[i]
        x1, y1 = ring[(i + 1) % n]
        cross = x0 * y1 - x1 * y0
        a += cross
        cx += (x0 + x1) * cross
        cy += (y0 + y1) * cross
    a *= 0.5
    if abs(a) < 1e-12:
        x0, y0 = ring[0]
        return y0, x0
    cx /= (6 * a)
    cy /= (6 * a)
    return cy, cx


def title_case(s):
    if not s:
        return s
    s = s.strip()
    if s.isupper() or s.islower():
        small = {"of", "and", "the", "at", "in", "on", "to", "by"}
        words = s.lower().split()
        out = []
        for i, w in enumerate(words):
            if i > 0 and w in small:
                out.append(w)
            elif w == "ww" or w == "bbq":
                out.append(w.upper())
            else:
                out.append(w[:1].upper() + w[1:])
        return " ".join(out)
    return s


NAME_KEYS = (
    "NAME", "Name", "PARKNAME", "ParkName", "TRAILNAME", "TrailName",
    "FEATURE_NAME", "FACILITY_NAME", "LOCATION", "DESCRIPTION", "Description",
    "LABEL", "SiteName", "SITE_NAME", "Title", "TITLE",
)
PARK_KEYS = ("PARKNAME", "ParkName", "PARK_NAME", "SiteName", "SITE_NAME")
VILLAGE_KEYS = ("VillageName", "VILLAGENAME", "Village", "VILLAGE", "VLG")


def extract_name(props):
    for k in NAME_KEYS:
        if k in props and props[k]:
            return title_case(str(props[k]))
    return None


def extract_park(props):
    for k in PARK_KEYS:
        if k in props and props[k]:
            return title_case(str(props[k]))
    return None


def extract_village(props):
    for k in VILLAGE_KEYS:
        if k in props and props[k]:
            return title_case(str(props[k]))
    return None


def process_poi_features(features, layer_name, cfg):
    items = []
    for f in features:
        geom = f.get("geometry") or {}
        props = f.get("properties") or {}
        gtype = geom.get("type")
        coords_raw = geom.get("coordinates")
        if not coords_raw:
            continue
        lat = lon = None
        # ArcGIS sometimes ships 3D coords [lon, lat, z]; take the first two.
        if gtype == "Point":
            lon, lat = coords_raw[0], coords_raw[1]
        elif gtype == "MultiPoint" and coords_raw:
            lon, lat = coords_raw[0][0], coords_raw[0][1]
        elif gtype == "Polygon":
            c = polygon_centroid(coords_raw)
            if c is None:
                continue
            lat, lon = c
        elif gtype == "MultiPolygon" and coords_raw:
            biggest = max(coords_raw, key=lambda p: len(p[0]) if p and p[0] else 0)
            c = polygon_centroid(biggest)
            if c is None:
                continue
            lat, lon = c
        elif gtype == "LineString" and coords_raw:
            mid = coords_raw[len(coords_raw) // 2]
            lon, lat = mid[0], mid[1]
        else:
            continue
        item = {
            "id": str(props.get("OBJECTID") or props.get("GlobalID") or f"{layer_name}-{len(items)}"),
            "lat": round(lat, 6),
            "lon": round(lon, 6),
        }
        name = extract_name(props)
        if name:
            item["name"] = name
        park = extract_park(props)
        if park and park != name:
            item["park"] = park
        village = extract_village(props)
        if village:
            item["village"] = village
        items.append(item)
    return items


def process_polygon_features(features, layer_name):
    polys = []
    for f in features:
        geom = f.get("geometry") or {}
        props = f.get("properties") or {}
        gtype = geom.get("type")
        coords_raw = geom.get("coordinates")
        if not coords_raw:
            continue
        rings_groups = []
        if gtype == "Polygon":
            rings_groups = [coords_raw]
        elif gtype == "MultiPolygon":
            rings_groups = coords_raw
        else:
            continue
        for poly in rings_groups:
            simplified = []
            for ring in poly:
                if len(ring) < 4:
                    continue
                if len(ring) > 200:
                    step = max(1, len(ring) // 200)
                    ring = ring[::step] + [ring[-1]]
                # Coords may be 2D [lon,lat] or 3D [lon,lat,z]; take first 2.
                simplified.append([[round(c[1], 5), round(c[0], 5)] for c in ring])
            if not simplified:
                continue
            rec = {"rings": simplified}
            name = extract_name(props)
            if name:
                rec["name"] = name
            village = extract_village(props)
            if village:
                rec["village"] = village
            polys.append(rec)
    return polys


def process_line_features(features):
    lines = []
    for f in features:
        geom = f.get("geometry") or {}
        gtype = geom.get("type")
        coords_raw = geom.get("coordinates")
        if not coords_raw:
            continue
        groups = []
        if gtype == "LineString":
            groups = [coords_raw]
        elif gtype == "MultiLineString":
            groups = coords_raw
        else:
            continue
        for line in groups:
            if len(line) < 2:
                continue
            if len(line) > 200:
                step = max(1, len(line) // 200)
                line = line[::step] + [line[-1]]
            lines.append([[round(c[1], 5), round(c[0], 5)] for c in line])
    return lines


def main():
    pois_out = {"version": 1, "source": "The Woodlands Township GIS (public ArcGIS REST).",
                "categories": {}}
    polys_out = {"version": 1, "source": "The Woodlands Township GIS (public ArcGIS REST).",
                 "polygons": {}, "lines": {}}

    failures = []
    poi_count = 0
    poly_count = 0
    line_count = 0

    for layer, cfg in POI_LAYERS.items():
        print(f"POI  {layer:30s}", end=" ", flush=True)
        try:
            features = fetch_layer(layer)
            items = process_poi_features(features, layer, cfg)
            pois_out["categories"][cfg["key"]] = {
                "label": cfg["label"],
                "icon": cfg["icon"],
                "tint": cfg["tint"],
                "items": items,
            }
            poi_count += len(items)
            print(f"  {len(items):>5} items")
            (RAW / f"{layer}.geojson").write_text(
                json.dumps({"type": "FeatureCollection", "features": features}),
                encoding="utf-8",
            )
        except Exception as e:
            print(f"  FAILED: {e}")
            failures.append((layer, str(e)))

    for layer, cfg in POLYGON_LAYERS.items():
        print(f"POLY {layer:30s}", end=" ", flush=True)
        try:
            features = fetch_layer(layer)
            polys = process_polygon_features(features, layer)
            polys_out["polygons"][cfg["key"]] = {
                "label": cfg["label"],
                "fill": cfg["fill"],
                "items": polys,
            }
            poly_count += len(polys)
            print(f"  {len(polys):>5} polys")
            (RAW / f"{layer}.geojson").write_text(
                json.dumps({"type": "FeatureCollection", "features": features}),
                encoding="utf-8",
            )
        except Exception as e:
            print(f"  FAILED: {e}")
            failures.append((layer, str(e)))

    for layer, cfg in LINE_LAYERS.items():
        print(f"LINE {layer:30s}", end=" ", flush=True)
        try:
            features = fetch_layer(layer)
            lines = process_line_features(features)
            polys_out["lines"][cfg["key"]] = {
                "label": cfg["label"],
                "stroke": cfg["stroke"],
                "items": lines,
            }
            line_count += len(lines)
            print(f"  {len(lines):>5} lines")
            (RAW / f"{layer}.geojson").write_text(
                json.dumps({"type": "FeatureCollection", "features": features}),
                encoding="utf-8",
            )
        except Exception as e:
            print(f"  FAILED: {e}")
            failures.append((layer, str(e)))

    # Compact JSON for the bundle.
    (RES / "POIs.json").write_text(
        json.dumps(pois_out, separators=(",", ":")),
        encoding="utf-8",
    )
    (RES / "Polygons.json").write_text(
        json.dumps(polys_out, separators=(",", ":")),
        encoding="utf-8",
    )

    print()
    print(f"POIs.json:     {(RES / 'POIs.json').stat().st_size/1024:.0f} KB, {poi_count} points across {len(pois_out['categories'])} categories")
    print(f"Polygons.json: {(RES / 'Polygons.json').stat().st_size/1024:.0f} KB, {poly_count} polygons + {line_count} lines")
    if failures:
        print(f"Failures: {len(failures)}")
        for n, err in failures:
            print(f"  {n}: {err[:80]}")


if __name__ == "__main__":
    sys.exit(main())
