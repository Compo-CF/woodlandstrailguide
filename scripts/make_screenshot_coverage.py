"""Generate a plausible coverage.json for App Store screenshots.

Walks outward from a seed node inside each village, following the real
adjacency, so covered pathways form connected runs the way actual walking
does -- scattered segments would look obviously synthetic on the map.
"""
import json, math, collections, os

HERE = os.path.dirname(os.path.abspath(__file__))

GRAPH = os.path.join(HERE, "..", "WoodlandsTrailGuide", "Resources", "TrailGraph.json")
OUT   = os.path.join(HERE, "screenshot_coverage.json")
BIN_M = 25.0

TARGET = {
    "Indian Springs":     1.00,
    "Town Center":        1.00,
    "Research Forest":    0.55,
    "College Park":       0.40,
    "Grogan's Mill":      0.65,
    "Panther Creek":      0.30,
    "Cochran's Crossing": 0.20,
    "Creekside Park":     0.15,
    "Alden Bridge":       0.10,
    "Sterling Ridge":     0.08,
}

g = json.load(open(GRAPH, encoding="utf-8"))
nodes, ways, adj = g["nodes"], g["ways"], g["adj"]

def stable_id(w):
    pid = w.get("pathway_id")
    if pid:
        return "p:" + pid
    n = w.get("n") or []
    if not n or n[0] >= len(nodes) or n[-1] >= len(nodes):
        return "x:" + (w.get("name") or "unknown")
    a, b = nodes[n[0]], nodes[n[-1]]
    return "g:%.5f,%.5f,%.5f,%.5f,%.1f" % (a[0], a[1], b[0], b[1], w["len_m"])

by_village = collections.defaultdict(list)
for i, w in enumerate(ways):
    by_village[w.get("village")].append(i)

chosen = set()
report = []
for village, frac in TARGET.items():
    idxs = by_village.get(village, [])
    if not idxs:
        continue
    member = set(idxs)
    total = sum(ways[i]["len_m"] for i in idxs)
    target = total * frac
    # Seed at the first node of the longest way -- a main pathway, so the
    # fill spreads along a spine rather than out of a dead-end stub.
    start_way = max(idxs, key=lambda i: ways[i]["len_m"])
    seed = ways[start_way]["n"][0]
    seen_w, got = set(), 0.0
    q, seen_n = collections.deque([seed]), {seed}
    while q and got < target:
        node = q.popleft()
        for nb, dist, wi in adj[node]:
            if wi in member and wi not in seen_w:
                seen_w.add(wi); got += ways[wi]["len_m"]
                if got >= target:
                    break
            if nb not in seen_n:
                seen_n.add(nb); q.append(nb)
    # A disconnected village component can stall the fill short of target.
    if got < target * 0.9:
        for i in idxs:
            if i not in seen_w:
                seen_w.add(i); got += ways[i]["len_m"]
                if got >= target:
                    break
    chosen |= seen_w
    report.append((village, got, total, got / total if total else 0))

bins = {}
for i in sorted(chosen):
    w = ways[i]
    n = max(1, int(math.ceil(w["len_m"] / BIN_M)))
    bins[stable_id(w)] = list(range(n))

json.dump({"version": 1, "bins": bins, "celebrated": []},
          open(OUT, "w", encoding="utf-8"))

net = sum(w["len_m"] for w in ways)
cov = sum(w["len_m"] for i, w in enumerate(ways) if i in chosen)
print("%-20s %8s %8s %6s" % ("village", "covered", "total", "pct"))
for v, got, total, f in sorted(report, key=lambda r: -r[3]):
    print("%-20s %7.1fmi %7.1fmi %5.0f%%" % (v, got/1609.344, total/1609.344, f*100))
print()
print("overall           %7.1f mi of %.1f mi  = %.1f%%" % (cov/1609.344, net/1609.344, cov/net*100))
print("distinct way ids written:", len(bins))
print("wrote", OUT)
