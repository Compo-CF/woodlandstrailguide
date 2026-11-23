"""Event art for New Year Walks 2027: a dawn-sky map poster drawn from the app's own data
(TrailGraph pathways, Polygons lakes/parks, EventWalks routes). No text: the App Store overlays it.
  python scripts/gen_event_art.py   -> store/event/card_1920x1080.png, details_1080x1920.png
"""
import json, math, os, random, sys, heapq
from PIL import Image, ImageDraw, ImageFilter
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RES = os.path.join(ROOT, "WoodlandsTrailGuide", "Resources")
OUT = os.path.join(ROOT, "store", "event")
g = json.load(open(os.path.join(RES, "TrailGraph.json")))
N, A, W = g["nodes"], g["adj"], g["ways"]
P = json.load(open(os.path.join(RES, "Polygons.json")))["polygons"]
EV = json.load(open(os.path.join(RES, "EventWalks.json")))

def snap(c):
    return min(range(len(N)), key=lambda i: (N[i][0]-c[0])**2 + ((N[i][1]-c[1])*0.866)**2)
def dij(s, t):
    dist = {s: 0}; prev = {}; pq = [(0, s)]
    while pq:
        d, u = heapq.heappop(pq)
        if u == t: break
        if d > dist[u]: continue
        for v, l, w in A[u]:
            if d + l < dist.get(v, 1e18): dist[v] = d + l; prev[v] = u; heapq.heappush(pq, (d + l, v))
    p = [t]
    while p[-1] != s: p.append(prev[p[-1]])
    return p[::-1]
routes = []
for wk in EV["walks"]:
    ns = [snap((w["lat"], w["lon"])) for w in wk["waypoints"]]
    path = [ns[0]]
    for a, b in zip(ns, ns[1:]): path += dij(a, b)[1:]
    routes.append([N[i] for i in path])

def render(Wd, Ht, bbox, out, sky_frac):
    S = 2; w, h = Wd*S, Ht*S
    img = Image.new("RGB", (w, h))
    px = img.load()
    # dawn gradient: deep navy top -> plum -> warm gold at the horizon line
    stops = [(0.0, (10, 18, 40)), (0.45, (38, 34, 78)), (0.75, (150, 70, 80)), (1.0, (246, 170, 92))]
    hz = int(h*sky_frac)
    for y in range(h):
        t = min(1, y/hz) if y < hz else 1
        for (a, ca), (b, cb) in zip(stops, stops[1:]):
            if a <= t <= b:
                f = (t-a)/(b-a); col = tuple(int(ca[i]+(cb[i]-ca[i])*f) for i in range(3)); break
        if y >= hz:  # land: dark forest under the horizon
            f = min(1, (y-hz)/(h*0.08)); col = tuple(int(col[i]*(1-f) + (14, 38, 24)[i]*f) for i in range(3))
        for x in range(w): px[x, y] = col
    sky = img.copy()
    d = ImageDraw.Draw(img, "RGBA")
    s_, w_, n_, e_ = bbox
    top = hz + int(h*0.05)
    def P2(c):
        x = (c[1]-w_)/(e_-w_)*w; y = top + (n_-c[0])/(n_-s_)*(h-top)
        return (x, y)
    for it in P["parks"]["items"]:
        for r in it["rings"]: d.polygon([P2(c) for c in r], fill=(34, 80, 46, 255))
    for it in P["lakes"]["items"]:
        for r in it["rings"]: d.polygon([P2(c) for c in r], fill=(52, 92, 128, 255))
    for wy in W:
        pts = [P2(N[i]) for i in wy["n"]]
        d.line(pts, fill=(236, 226, 200, 70), width=2*S)
    glow = Image.new("RGBA", img.size, (0, 0, 0, 0)); gd = ImageDraw.Draw(glow)
    cols = [(255, 205, 96), (255, 150, 84), (255, 226, 150), (246, 120, 90)]
    for r, c in zip(routes, cols):
        gd.line([P2(p) for p in r], fill=c + (255,), width=14*S, joint="curve")
    glow = glow.filter(ImageFilter.GaussianBlur(10*S))
    img.paste(glow, (0, 0), glow)
    d = ImageDraw.Draw(img, "RGBA")
    for r, c in zip(routes, cols):
        d.line([P2(p) for p in r], fill=c + (255,), width=5*S, joint="curve")
        x, y = P2(r[0]); R = 11*S
        d.ellipse([x-R, y-R, x+R, y+R], fill=(255, 250, 236, 255), outline=c + (255,), width=4*S)
    # keep the map below the horizon, fading in over a short band
    mask = Image.new("L", img.size, 0); md = ImageDraw.Draw(mask)
    fade = int(h*0.05)
    for y in range(hz, h):
        md.line([(0, y), (w, y)], fill=min(255, int(255*(y-hz)/fade)))
    img = Image.composite(img, sky, mask)
    d = ImageDraw.Draw(img, "RGBA")
    # sky: stars + a few firework bursts, kept to the sky band
    rnd = random.Random(2027)
    for _ in range(140):
        x, y = rnd.uniform(0, w), rnd.uniform(0, hz*0.75); R = rnd.uniform(0.8, 2.2)*S
        d.ellipse([x-R, y-R, x+R, y+R], fill=(255, 248, 230, rnd.randint(90, 220)))
    bursts = [(0.18, 0.30, 70), (0.80, 0.22, 90), (0.55, 0.12, 55)] if Wd > Ht else [(0.25, 0.10, 80), (0.72, 0.07, 95), (0.55, 0.20, 60)]
    for (bx, by, br), c in zip(bursts, [(255, 205, 96), (255, 150, 84), (255, 226, 150)]):
        cx, cy, br = bx*w, by*hz/0.35*0.35 if False else by*h, br*S
        for k in range(18):
            a = k*2*math.pi/18
            x1, y1 = cx+math.cos(a)*br*0.35, cy+math.sin(a)*br*0.35
            x2, y2 = cx+math.cos(a)*br, cy+math.sin(a)*br
            d.line([(x1, y1), (x2, y2)], fill=c + (220,), width=3*S)
            d.ellipse([x2-3*S, y2-3*S, x2+3*S, y2+3*S], fill=c + (255,))
    img = img.resize((Wd, Ht), Image.LANCZOS)
    img.save(out, optimize=True)
    print("wrote", out, img.size)

# frame the four routes (+ margin) in each aspect
lats = [p[0] for r in routes for p in r]; lons = [p[1] for r in routes for p in r]
cl, cn = (min(lats)+max(lats))/2, (min(lons)+max(lons))/2
def box(Wd, Ht, sky, pad):
    span_lat = (max(lats)-min(lats))*pad; span_lon = (max(lons)-min(lons))*pad
    map_h = Ht*(1-sky-0.02); aspect = Wd/map_h  # x/y in px
    # px per degree: lon scaled by cos(lat)
    k = math.cos(math.radians(cl))
    if span_lon*k/span_lat > aspect: span_lat = span_lon*k/aspect
    else: span_lon = span_lat*aspect/k
    return (cl-span_lat/2, cn-span_lon/2, cl+span_lat/2, cn+span_lon/2)
os.makedirs(OUT, exist_ok=True)
render(1920, 1080, box(1920, 1080, 0.36, 1.18), os.path.join(OUT, "card_1920x1080.png"), 0.36)
render(1080, 1920, box(1080, 1920, 0.30, 1.12), os.path.join(OUT, "details_1080x1920.png"), 0.30)
