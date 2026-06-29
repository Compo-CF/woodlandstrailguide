"""
Generate a realistic map mockup for the preview page by extracting a real
bbox from TrailGraph.json + POIs.json + Polygons.json. Outputs SVG snippets
and route metadata for the preview builder.

Pipeline:
  1. Load all three datasets
  2. Pick a starting node in Sterling Ridge / Creekside Park area
  3. Run Dijkstra to find a route ~1100 m long that traverses multiple
     distinct named pathway segments
  4. Build a screen-aspect bbox covering route + padding
  5. Clip polygons, lines, and POIs to that bbox
  6. Project everything to SVG coordinates
  7. Compute POIs within 40 m of the route, ordered along-route
  8. Emit preview_map.json
"""

from __future__ import annotations

import heapq
import json
import math
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GRAPH_PATH = ROOT / "WoodlandsTrailGuide" / "Resources" / "TrailGraph.json"
POIS_PATH  = ROOT / "WoodlandsTrailGuide" / "Resources" / "POIs.json"
POLY_PATH  = ROOT / "WoodlandsTrailGuide" / "Resources" / "Polygons.json"
OUT_PATH = Path(
    r"C:\Users\ANTHON~1.COM\AppData\Local\Temp\claude"
    r"\C--Users-anthony-compofelice\3785d567-317a-49ff-aab0-259cb62b7f8c"
    r"\scratchpad\preview_map.json"
)

VIEW_W = 320
VIEW_H = 540
TARGET_DIST_M = 1100

# Categories whose markers should NOT be drawn on the map mockup — too
# numerous, would clutter the small view. Still computed for the route
# surfacing logic, then filtered there too.
MAP_SKIP_CATEGORIES = {
    "benches", "picnic_tables", "bike_racks", "dog_bag",
    "trail_markers", "monuments", "fountain_feat",
}

# Categories deliberately excluded from "Along the way" chips — too granular
# to call out by name. Bench-per-bench just isn't useful.
ALONG_ROUTE_SKIP = MAP_SKIP_CATEGORIES

# Short labels for the chips — the full category labels are too long for a
# small pill ("Bridges & underpasses" -> "Bridge").
CATEGORY_SHORT_LABELS = {
    "bridges":         "Bridge",
    "playgrounds":     "Playground",
    "playgrounds_eq":  "Play equipment",
    "dog_parks":       "Dog park",
    "restrooms":       "Restroom",
    "fountains":       "Water fountain",
    "pavilions":       "Pavilion",
    "picnic_areas":    "Picnic area",
    "bbq":             "BBQ",
    "art_benches":     "Art bench",
    "art_bike_racks":  "Art bike rack",
    "bike_share":      "Bike share",
    "ecotour":         "Nature marker",
    "trolley":         "Trolley stop",
    "fishing":         "Fishing access",
    "pools":           "Pool",
    "spraygrounds":    "Splash pad",
    "sports_fields":   "Sports field",
    "sports_courts":   "Sports court",
    "piers":           "Pier",
    "docks":           "Dock",
    "boat_houses":     "Boat house",
}


def haversine(la1, lo1, la2, lo2):
    R = 6371000.0
    p1, p2 = math.radians(la1), math.radians(la2)
    dp = math.radians(la2 - la1)
    dl = math.radians(lo2 - lo1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * R * math.asin(math.sqrt(a))


def dijkstra(adj, source):
    n = len(adj)
    dists = [math.inf] * n
    prev = [-1] * n
    prev_way = [-1] * n
    dists[source] = 0
    heap = [(0.0, source)]
    while heap:
        d, u = heapq.heappop(heap)
        if d > dists[u]:
            continue
        for v, edge_len, wi in adj[u]:
            nd = d + edge_len
            if nd < dists[v]:
                dists[v] = nd
                prev[v] = u
                prev_way[v] = wi
                heapq.heappush(heap, (nd, v))
    return dists, prev, prev_way


def collapse_segments(ways, adj, path, edge_ways):
    out = []
    cur_name = None
    cur_kind = None
    cur_len = 0.0
    for i, wi in enumerate(edge_ways):
        way = ways[wi]
        label = way.get("name") or way.get("park") or "unnamed pathway"
        kind = way.get("kind", "pathway")
        edge_len = 0.0
        for nbr, ln, wjx in adj[path[i]]:
            if nbr == path[i + 1] and wjx == wi:
                edge_len = ln
                break
        if label != cur_name:
            if cur_name is not None and cur_len > 0:
                out.append({"name": cur_name, "meters": cur_len, "kind": cur_kind})
            cur_name = label
            cur_kind = kind
            cur_len = edge_len
        else:
            cur_len += edge_len
    if cur_name is not None and cur_len > 0:
        out.append({"name": cur_name, "meters": cur_len, "kind": cur_kind})
    return out


def fit_aspect(bbox_s, bbox_w, bbox_n, bbox_e, target_w, target_h):
    mid_lat = (bbox_s + bbox_n) / 2
    m_per_lat = 111_319
    m_per_lon = 111_319 * math.cos(math.radians(mid_lat))
    width_m = (bbox_e - bbox_w) * m_per_lon
    height_m = (bbox_n - bbox_s) * m_per_lat
    aspect = target_w / target_h
    if width_m / height_m < aspect:
        needed_w = height_m * aspect
        extra_deg = (needed_w - width_m) / 2 / m_per_lon
        bbox_w -= extra_deg
        bbox_e += extra_deg
    else:
        needed_h = width_m / aspect
        extra_deg = (needed_h - height_m) / 2 / m_per_lat
        bbox_s -= extra_deg
        bbox_n += extra_deg
    return bbox_s, bbox_w, bbox_n, bbox_e


def pick_route(graph, pois_catalog):
    """Pick a starting node and a destination such that the route between them
    is interesting — multiple named pathways AND meaningful POIs nearby. We
    sample candidate destinations and score on both axes."""
    nodes = graph["nodes"]
    adj = graph["adj"]
    ways = graph["ways"]

    # Coarse spatial index of POIs by their grid cell, for fast nearby lookup.
    PROX_M = 80
    cell_lat = 0.001  # ~111 m
    cell_lon = 0.0011
    poi_grid: dict[tuple[int, int], list[tuple[float, float, str]]] = {}
    for key, cat in pois_catalog["categories"].items():
        if key in MAP_SKIP_CATEGORIES:
            continue
        for poi in cat["items"]:
            ck = (int(poi["lat"] / cell_lat), int(poi["lon"] / cell_lon))
            poi_grid.setdefault(ck, []).append((poi["lat"], poi["lon"], key))

    def pois_near_path(path):
        seen = set()
        for i in range(len(path) - 1):
            la1, lo1 = nodes[path[i]]
            la2, lo2 = nodes[path[i + 1]]
            mid_la, mid_lo = (la1 + la2) / 2, (lo1 + lo2) / 2
            ck = (int(mid_la / cell_lat), int(mid_lo / cell_lon))
            for dla in (-1, 0, 1):
                for dlo in (-1, 0, 1):
                    cell = (ck[0] + dla, ck[1] + dlo)
                    for pla, plo, key in poi_grid.get(cell, []):
                        if haversine(la1, lo1, pla, plo) < PROX_M or haversine(la2, lo2, pla, plo) < PROX_M:
                            seen.add((key, round(pla, 5), round(plo, 5)))
        return seen

    # Iterate a few candidate starting villages to find the best overall route.
    candidate_centers = [
        (30.166, -95.531),   # Panther Creek / Lake Woodlands south
        (30.155, -95.555),   # Creekside Park
        (30.179, -95.508),   # Town Center / Waterway
        (30.143, -95.510),   # Indian Springs
        (30.162, -95.470),   # East Shore
        (30.197, -95.539),   # Alden Bridge
    ]
    best_overall = None
    best_overall_score = -1
    for tlat, tlon in candidate_centers:
        center_idx = min(
            range(len(nodes)),
            key=lambda i: haversine(tlat, tlon, nodes[i][0], nodes[i][1]),
        )
        dists, prev, prev_way = dijkstra(adj, center_idx)
        for end_idx, d in enumerate(dists):
            if not math.isfinite(d):
                continue
            if abs(d - TARGET_DIST_M) > 400:
                continue
            path = []
            edge_ways = []
            cur = end_idx
            while cur != -1:
                path.append(cur)
                if prev_way[cur] != -1:
                    edge_ways.append(prev_way[cur])
                cur = prev[cur]
            path.reverse()
            edge_ways.reverse()
            distinct_names = len({ways[wi].get("name") for wi in edge_ways if ways[wi].get("name")})
            villages = {ways[wi].get("village") for wi in edge_ways if ways[wi].get("village")}
            if len(villages) > 1:
                distinct_names -= 1
            last_named = next((ways[wi].get("name") for wi in reversed(edge_ways) if ways[wi].get("name")), None)
            if last_named is None:
                continue
            nearby = pois_near_path(path)
            # Score = POI diversity (most weight) + name diversity + length fit.
            score = len(nearby) * 6 + distinct_names * 4 - abs(d - TARGET_DIST_M) / 100
            if score > best_overall_score:
                best_overall_score = score
                best_overall = (end_idx, path, edge_ways, d)
    if best_overall is None:
        raise RuntimeError("No suitable route found")
    return best_overall


def project_pt(lat, lon, bbox_s, bbox_w, bbox_n, bbox_e):
    x = (lon - bbox_w) / (bbox_e - bbox_w) * VIEW_W
    y = (bbox_n - lat) / (bbox_n - bbox_s) * VIEW_H
    return x, y


def bbox_contains(lat, lon, s, w, n, e, pad=0.0):
    return (s - pad) <= lat <= (n + pad) and (w - pad) <= lon <= (e + pad)


def segment_distance_m(p_lat, p_lon, a_lat, a_lon, b_lat, b_lon):
    """Approximate perpendicular distance (meters) from p to segment ab,
    using local equirectangular projection at the midpoint latitude."""
    mid_lat = (a_lat + b_lat) / 2
    m_per_lon = 111_319 * math.cos(math.radians(mid_lat))
    m_per_lat = 111_319
    ax = a_lon * m_per_lon
    ay = a_lat * m_per_lat
    bx = b_lon * m_per_lon
    by = b_lat * m_per_lat
    px = p_lon * m_per_lon
    py = p_lat * m_per_lat
    dx = bx - ax
    dy = by - ay
    seg2 = dx * dx + dy * dy
    if seg2 < 1e-6:
        d2 = (px - ax) ** 2 + (py - ay) ** 2
        return math.sqrt(d2), 0.0, 0.0
    t = max(0, min(1, ((px - ax) * dx + (py - ay) * dy) / seg2))
    cx = ax + t * dx
    cy = ay + t * dy
    d = math.hypot(px - cx, py - cy)
    seg_len = math.sqrt(seg2)
    return d, t, seg_len


def _pretty_name(s):
    """Township source data is inconsistent (AQUATIC SPRAYGROUND - Foo,
    Pathway Bridge - Bar, all-caps phrases). Normalize for display."""
    if not s:
        return s
    s = s.strip()
    # Strip known category-prefixes that the icon already conveys.
    PREFIX_STRIPS = (
        "Pathway Bridge - ",
        "PATHWAY BRIDGE - ",
        "AQUATIC SPRAYGROUND - ",
        "AQUATIC POOL - ",
        "PAVILION - ",
        "PIER - ",
        "DOCK - ",
        "BOAT HOUSE - ",
    )
    for p in PREFIX_STRIPS:
        if s.startswith(p):
            s = s[len(p):]
            break
    # SHOUTING → Title Case
    if s.isupper():
        small = {"of", "and", "the", "at", "in", "on", "to", "by"}
        words = s.lower().split()
        out = []
        for i, w in enumerate(words):
            if i > 0 and w in small:
                out.append(w)
            elif w in ("bbq",):
                out.append(w.upper())
            else:
                out.append(w[:1].upper() + w[1:])
        s = " ".join(out)
    return s


def _dedupe_along_route(items, same_category_window_m=80, same_name_window_m=200):
    """A real pathway often has several Township records for what users
    perceive as one feature (a four-deck bridge complex shows up as six rows).
    Collapse those: same category within `same_category_window_m`, OR same
    cleaned name within `same_name_window_m`, drop later entries."""
    out = []
    last_by_cat: dict[str, float] = {}
    last_by_name: dict[str, float] = {}
    for it in items:
        d = it["distance_along_m"]
        cat_last = last_by_cat.get(it["key"])
        if cat_last is not None and (d - cat_last) < same_category_window_m:
            continue
        name_key = (it.get("name") or "").lower()
        if name_key:
            name_last = last_by_name.get(name_key)
            if name_last is not None and (d - name_last) < same_name_window_m:
                continue
            last_by_name[name_key] = d
        last_by_cat[it["key"]] = d
        out.append(it)
    return out


def compute_route_pois(pois_catalog, route_coords_ll, max_m=40):
    """POIs within max_m meters of the route polyline, ordered by along-route
    distance. route_coords_ll is a list of (lat, lon)."""
    if len(route_coords_ll) < 2:
        return []
    # Cumulative meters along the route to each node
    cum = [0.0]
    for i in range(1, len(route_coords_ll)):
        la1, lo1 = route_coords_ll[i - 1]
        la2, lo2 = route_coords_ll[i]
        cum.append(cum[-1] + haversine(la1, lo1, la2, lo2))

    out = []
    for key, cat in pois_catalog["categories"].items():
        if key in ALONG_ROUTE_SKIP:
            continue
        for poi in cat["items"]:
            best = None
            for i in range(len(route_coords_ll) - 1):
                a_lat, a_lon = route_coords_ll[i]
                b_lat, b_lon = route_coords_ll[i + 1]
                d, t, seg_len = segment_distance_m(
                    poi["lat"], poi["lon"], a_lat, a_lon, b_lat, b_lon
                )
                if best is None or d < best[0]:
                    best = (d, cum[i] + t * seg_len)
            if best and best[0] <= max_m:
                out.append({
                    "key": key,
                    "label": cat["label"],
                    "short_label": CATEGORY_SHORT_LABELS.get(key, cat["label"]),
                    "tint": cat["tint"],
                    "icon": cat["icon"],
                    "name": _pretty_name(poi.get("name")),
                    "distance_along_m": best[1],
                    "distance_from_route_m": best[0],
                    "lat": poi["lat"],
                    "lon": poi["lon"],
                })
    out.sort(key=lambda x: x["distance_along_m"])
    return _dedupe_along_route(out)


def main():
    graph = json.loads(GRAPH_PATH.read_text(encoding="utf-8"))
    pois = json.loads(POIS_PATH.read_text(encoding="utf-8"))
    polys = json.loads(POLY_PATH.read_text(encoding="utf-8"))
    nodes = graph["nodes"]
    ways = graph["ways"]
    adj = graph["adj"]

    end_idx, path, edge_ways, total_m = pick_route(graph, pois)

    # Bbox
    rlats = [nodes[i][0] for i in path]
    rlons = [nodes[i][1] for i in path]
    pad_lat = (max(rlats) - min(rlats)) * 0.6 + 0.0011
    pad_lon = (max(rlons) - min(rlons)) * 0.6 + 0.0014
    bbox_s = min(rlats) - pad_lat
    bbox_n = max(rlats) + pad_lat
    bbox_w = min(rlons) - pad_lon
    bbox_e = max(rlons) + pad_lon
    bbox_s, bbox_w, bbox_n, bbox_e = fit_aspect(bbox_s, bbox_w, bbox_n, bbox_e, VIEW_W, VIEW_H)

    def proj(lat, lon):
        return project_pt(lat, lon, bbox_s, bbox_w, bbox_n, bbox_e)

    # --- Polygons (parks, lakes, GMNP, village areas) ---
    polygon_svg_parts = []
    poly_layer_order = ["parks", "gmnp", "lakes", "ponds", "waterbodies", "village_areas"]
    for key in poly_layer_order:
        group = polys.get("polygons", {}).get(key)
        if not group:
            continue
        fill = group.get("fill")
        items_in_bbox = []
        for shape in group["items"]:
            rings = shape.get("rings") or []
            if not rings:
                continue
            outer = rings[0]
            # Quick reject: any vertex in bbox?
            if not any(bbox_contains(la, lo, bbox_s, bbox_w, bbox_n, bbox_e) for la, lo in outer):
                continue
            items_in_bbox.append(shape)
        if not items_in_bbox:
            continue
        if fill:
            polygon_svg_parts.append(
                f'<g fill="{fill}" fill-opacity="0.62" stroke="{fill}" stroke-opacity="0.85" stroke-width="0.4">'
            )
        else:
            polygon_svg_parts.append(
                '<g fill="none" stroke="rgba(0,0,0,0.18)" stroke-width="0.7" stroke-dasharray="3 3">'
            )
        for shape in items_in_bbox:
            for ring in shape["rings"]:
                pts = " ".join(f"{x:.1f},{y:.1f}" for x, y in (proj(la, lo) for la, lo in ring))
                polygon_svg_parts.append(f'<polygon points="{pts}"/>')
        polygon_svg_parts.append("</g>")

    polygon_svg = "".join(polygon_svg_parts)

    # --- Creek lines ---
    line_svg_parts = []
    for key, group in polys.get("lines", {}).items():
        stroke = group.get("stroke") or "#7da9b8"
        line_svg_parts.append(
            f'<g fill="none" stroke="{stroke}" stroke-width="1.2" stroke-opacity="0.7" stroke-linecap="round">'
        )
        for line in group["items"]:
            if not any(bbox_contains(la, lo, bbox_s, bbox_w, bbox_n, bbox_e) for la, lo in line):
                continue
            pts = " ".join(
                f"{'M' if i == 0 else 'L'} {x:.1f} {y:.1f}"
                for i, (x, y) in enumerate(proj(la, lo) for la, lo in line)
            )
            line_svg_parts.append(f'<path d="{pts}"/>')
        line_svg_parts.append("</g>")
    line_svg = "".join(line_svg_parts)

    # --- Trail polylines ---
    def bbox_hits_way(way):
        for ni in way["n"]:
            la, lo = nodes[ni]
            if bbox_contains(la, lo, bbox_s, bbox_w, bbox_n, bbox_e):
                return True
        return False

    visible_ways = [(wi, w) for wi, w in enumerate(ways) if bbox_hits_way(w)]
    route_set = set(edge_ways)

    road_paths = []
    pathway_paths = []
    trail_paths = []
    for wi, w in visible_ways:
        if wi in route_set:
            continue
        coords = [proj(*nodes[ni]) for ni in w["n"]]
        d = " ".join(
            f"{'M' if i == 0 else 'L'} {x:.1f} {y:.1f}"
            for i, (x, y) in enumerate(coords)
        )
        if w.get("kind", "pathway") == "pathway":
            road_paths.append(d)
            pathway_paths.append(d)
        else:
            trail_paths.append(d)

    trail_svg_parts = []
    if road_paths:
        # Wider beige underlay simulates the road the pathway parallels.
        trail_svg_parts.append(
            '<g stroke="#F8F2E2" stroke-width="10" stroke-linecap="round" '
            'stroke-linejoin="round" fill="none">'
            + "".join(f'<path d="{d}"/>' for d in road_paths)
            + "</g>"
        )
        trail_svg_parts.append(
            '<g stroke="#E5DCC7" stroke-width="10.6" stroke-linecap="round" '
            'stroke-linejoin="round" fill="none" opacity="0.5">'
            + "".join(f'<path d="{d}"/>' for d in road_paths)
            + "</g>"
        )
        trail_svg_parts.append(
            '<g stroke="#F8F2E2" stroke-width="8.2" stroke-linecap="round" '
            'stroke-linejoin="round" fill="none">'
            + "".join(f'<path d="{d}"/>' for d in road_paths)
            + "</g>"
        )
        trail_svg_parts.append(
            '<g stroke="#2C8E48" stroke-width="1.4" stroke-linecap="round" '
            'stroke-linejoin="round" fill="none" opacity="0.92">'
            + "".join(f'<path d="{d}"/>' for d in pathway_paths)
            + "</g>"
        )
    if trail_paths:
        trail_svg_parts.append(
            '<g stroke="#a06325" stroke-width="1.4" stroke-dasharray="4 3" '
            'stroke-linecap="round" fill="none" opacity="0.75">'
            + "".join(f'<path d="{d}"/>' for d in trail_paths)
            + "</g>"
        )
    trail_svg = "".join(trail_svg_parts)

    # --- Route path ---
    route_coords_xy = [proj(*nodes[i]) for i in path]
    route_d = " ".join(
        f"{'M' if i == 0 else 'L'} {x:.1f} {y:.1f}"
        for i, (x, y) in enumerate(route_coords_xy)
    )
    # Softened terracotta — matches Natural.route in the iOS app.
    route_svg = (
        f'<path d="{route_d}" fill="none" stroke="#DF7127" stroke-width="7" '
        f'stroke-linecap="round" stroke-linejoin="round" opacity="0.96"/>'
    )

    # --- POI markers ---
    poi_svg_parts = []
    poi_count = 0
    for key, cat in pois["categories"].items():
        if key in MAP_SKIP_CATEGORIES:
            continue
        tint = cat.get("tint", "#888888")
        cat_parts = []
        for poi in cat["items"]:
            if not bbox_contains(poi["lat"], poi["lon"], bbox_s, bbox_w, bbox_n, bbox_e):
                continue
            x, y = proj(poi["lat"], poi["lon"])
            cat_parts.append(
                f'<circle cx="{x:.1f}" cy="{y:.1f}" r="4.2" fill="white"/>'
                f'<circle cx="{x:.1f}" cy="{y:.1f}" r="3" fill="{tint}"/>'
            )
            poi_count += 1
        if cat_parts:
            poi_svg_parts.append("".join(cat_parts))
    poi_svg = "".join(poi_svg_parts)

    # --- POIs along route ---
    route_coords_ll = [tuple(nodes[i]) for i in path]
    along_route = compute_route_pois(pois, route_coords_ll, max_m=70)

    # User dot
    user_idx = max(1, int(len(path) * 0.35))
    user_dot = list(proj(*nodes[path[user_idx]]))

    sx, sy = proj(*nodes[path[0]])
    ex, ey = proj(*nodes[path[-1]])

    miles = total_m / 1609.344
    segments = collapse_segments(ways, adj, path, edge_ways)
    start_name = next((s["name"] for s in segments), "Trail")
    end_name = next((s["name"] for s in reversed(segments)), "Trail")
    start_village = ways[edge_ways[0]].get("village") if edge_ways else None
    end_village = ways[edge_ways[-1]].get("village") if edge_ways else None

    # Parks the route passes through, in first-encounter order. Mirrors
    # Router.swift's uniqueParks helper.
    route_parks = []
    seen_parks = set()
    for wi in edge_ways:
        for p in (ways[wi].get("parks") or []):
            if p not in seen_parks:
                seen_parks.add(p)
                route_parks.append(p)

    out = {
        "polygon_svg": polygon_svg,
        "line_svg": line_svg,
        "bbox_svg": trail_svg,
        "poi_svg": poi_svg,
        "route_svg": route_svg,
        "start": [round(sx, 1), round(sy, 1)],
        "end": [round(ex, 1), round(ey, 1)],
        "user_dot": [round(user_dot[0], 1), round(user_dot[1], 1)],
        "total_miles": round(miles, 2),
        "walking_min": int(round(miles / 3.0 * 60)),
        "named_segments": [
            {
                "name": s["name"],
                "miles": round(s["meters"] / 1609.344, 2),
                "kind": s["kind"],
            }
            for s in segments
        ],
        "along_route": [
            {
                "key": p["key"],
                "label": p["short_label"],
                "tint": p["tint"],
                "name": p.get("name") or p["short_label"],
                "miles_in": round(p["distance_along_m"] / 1609.344, 2),
            }
            for p in along_route[:24]
        ],
        "start_label": start_name,
        "end_label": end_name,
        "start_village": start_village,
        "end_village": end_village,
        "route_parks": route_parks,
        "poi_count_on_map": poi_count,
        "poi_count_along_route": len(along_route),
    }
    OUT_PATH.write_text(json.dumps(out, indent=2), encoding="utf-8")
    print(f"Wrote {OUT_PATH}")
    print(f"  Route:        {miles:.2f} mi over {len(edge_ways)} edges, {len(segments)} named segments")
    print(f"  Parks:        {len(route_parks)}  {route_parks[:5]}")
    print(f"  POIs on map:  {poi_count}")
    print(f"  POIs along:   {len(along_route)}  (showing first 24 in chips)")
    print(f"  Polygon SVG length: {len(polygon_svg)}")
    print(f"  POI SVG length:     {len(poi_svg)}")
    for p in along_route[:8]:
        nm = p.get("name") or p["short_label"]
        print(f"    {nm[:30]:30s}  {p['short_label']:15s}  {p['distance_along_m']:6.0f} m in  ({p['distance_from_route_m']:4.0f} m off)")


if __name__ == "__main__":
    sys.exit(main())
