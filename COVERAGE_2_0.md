# 2.0 — "Your Woodlands" coverage map

Scope for Pillar 1: track which of the pathway network a user has personally
walked, show it on the map, and report completion overall and per village.

Everything numeric below was measured against
`WoodlandsTrailGuide/Resources/TrailGraph.json` (version 1, 2026-10-02 pull)
on 2026-10-26, not estimated.

---

## 0. Blocker: `Way.id` is unstable for park trails

**Fix this before building anything on top of it.**

`Views/MapTabView.swift` currently defines:

```swift
extension TrailGraph.Way: Identifiable {
    var id: String {
        if let p = pathwayID { return "p:" + p }
        return "n:" + nodeIndices.prefix(4).map(String.init).joined(separator: "-")
    }
}
```

Node indices are **array positions in the regenerated graph**, not stable
identifiers. Every Township data refresh reorders them, so every `n:`-keyed id
changes. That id already backs `UserDataStore.favoriteWayIDs`, which means:

- **Favouriting a park trail is already silently broken.** The 2026-10-02
  refresh very likely detached any favourite on the 71 natural-surface trails
  — 33.3 mi of network including all of George Mitchell Nature Preserve.
- Coverage would inherit the same fault, and far more damagingly: a feature
  whose entire value is accumulating over months would quietly reset a sixth
  of itself on every data refresh.

### The fix

| Kind | Count | Key | Stability |
|---|---|---|---|
| `pathway` | 1,493 | `"p:" + pathway_id` | Township's own asset id (`PTHWY-1`…), read straight from `PathwayID`/`PATHWAYID` in `fetch_township_data.py`. Unique, zero duplicates. |
| `trail` | 71 | `"g:" + geometryHash` | Endpoints rounded to 5 dp + length to 0.1 m. |

Geometry hash = `"%.5f,%.5f,%.5f,%.5f,%.1f"` of (first node lat, lon, last
node lat, lon, `len_m`).

Measured: 1,564 ways collapse to **1,556 distinct keys**. The 8 collisions are
not a defect — they are the Township publishing the *same physical path twice*:

```
0.1 m    Mid-Loop Trail  ×3                       (degenerate stub)
107.1 m  Rob Fleming Trail Pond Overlook          + "… TEMPORARILY CLOSED"
684.1 m  Beaver Pond Loop Trail                   + "… TEMPORARILY CLOSED"
135.5 m  Rob Fleming Trail                        + "… TEMPORARILY CLOSED PORTION"
 96.7 m  Rob Fleming Trail                        + "… TEMPORARILY CLOSED PORTION"
165.4 m  Rob Fleming Trail                        + "… TEMPORARILY CLOSED PORTION"
1680.1 m Spring Creek Nature Trail MC 1           + "… TEMPORARILY CLOSED PORTION"
```

Collapsing them is **correct**: one stretch of ground, one key. Walking it
should credit it once, and the denominator must not count 684 m of Beaver Pond
Loop twice. Do not add `name` to the key to force them apart — names carry the
closure status and will drift (cf. the Rob Fleming park rename already noted in
the portfolio).

This dedupe changes the published totals: the network is **204.8 mi, not
206.6**, and Parks & Preserves is **31.5 mi across 59 keys, not 33.3 across 71
ways**. Numbers in §1 are the corrected, deduplicated ones.

Store `pathway_id` *and* the geometry hash in the coverage file, so that if
the Township ever reassigns its ids, coverage can be recovered by geometry
rather than lost. Cheap insurance against a failure that is otherwise silent.

**Migration:** existing `n:`-keyed favourites cannot be recovered — the
indices they referenced no longer mean anything. Drop them on upgrade rather
than leaving entries that will never match.

---

## 1. What the data supports

```
44,490 nodes · 1,564 ways · 45,882 segments
1,556 distinct stable keys · 1,552 after dropping ways ≤ 0.5 m · 204.8 mi
```

Way length is heavily skewed — median 75 m, but a long tail:

```
min 0 · p25 30 · median 75 · p75 267 · p90 536 · p99 1,590 · max 6,574 m
180 ways > 500 m · 46 ways > 1 km
```

**This rules out a "touch = walked" rule.** Stepping on 10 m of the 6.6 km
way would credit the whole thing. Coverage must be fractional (§2).

Per-village denominators, which the UI can show directly:

Deduplicated, degenerate ways excluded:

| Village | Keys | Miles |
|---|---:|---:|
| *Parks & preserves* (`village == nil`) | 59 | 31.5 |
| Creekside Park | 290 | 28.9 |
| Sterling Ridge | 175 | 26.1 |
| Cochran's Crossing | 205 | 25.3 |
| Panther Creek | 301 | 24.2 |
| Alden Bridge | 182 | 23.5 |
| Grogan's Mill | 156 | 21.8 |
| Indian Springs | 103 | 9.5 |
| Town Center | 31 | 5.3 |
| Research Forest | 14 | 4.5 |
| College Park | 36 | 4.2 |

The `village == nil` bucket is exactly the natural-surface trails, so the UI is
cleanly "10 villages + Parks & Preserves" — eleven goals, none so large as to
feel hopeless. Parks & Preserves is the biggest at 31.5 mi, and also the one
most worth finishing.

---

## 2. Data model

Per way, store which **25 m bins** have been covered.

```swift
struct Coverage: Codable {
    var version: Int                     // 1
    var bins: [String: Set<UInt16>]      // wayKey -> covered bin indices
}
```

- Bin index = `floor(metersAlongWay / 25)`. Max bins for the longest way
  (6,574 m) is 263; the median way has 3.
- A way counts as **complete** at `coveredMeters >= 0.8 * lengthMeters`,
  where `coveredMeters = min(bins.count * 25, lengthMeters)`. The 0.8 allows
  for GPS noise at the ends and for genuinely unreachable stubs.
- Village percentage is **by distance, not by way count** — sum of covered
  metres over sum of way length. Way-count percentages would make Panther
  Creek's 301 short ways worth more than Creekside's 290 longer ones.

**Excluded from the denominator:** the 6 ways ≤ 0.5 m. They total ~0 mi and
would otherwise make 100 % unreachable. Worth logging the exclusion so the
number is explainable.

Worst-case size at full coverage: ~13,300 bins network-wide. Persist as a
**file in Documents** (`coverage.json`), not `UserDefaults` — the existing
store keeps everything in defaults, but this is the first payload large
enough and written often enough to deserve its own file.

**No retroactive seeding is possible.** `TripLogEntry` stores distance,
labels, duration and mode — no geometry. Everyone starts at 0 %, which is
arguably the better launch anyway: a fresh goal rather than a pre-filled one.

---

## 3. Matching

Reuse `Router.projectionDistance(lat:lon:aLat:aLon:bLat:bLon:)` — it already
does exactly the right thing (equirectangular point-to-segment, returns
perpendicular metres and `t` along the segment). It is currently
`private static`; make it internal.

`Router.nearestNode` is a linear scan over 44,490 nodes. That is fine for
one-shot lookups but not per GPS fix. Build a **60 m segment grid once** at
graph load (45,882 segments) and query the 3×3 cells around each fix.

Per accepted fix:

1. **Reject** fixes with `horizontalAccuracy > 20 m`, or older than 5 s.
2. Candidate segments from the grid.
3. `projectionDistance` for each; keep those within
   `max(12, horizontalAccuracy)` metres.
4. **Ambiguity rule:** if the best candidate belonging to way A is not closer
   than the best candidate of any *unconnected* way B by at least 1.5×, record
   nothing. Conservative beats wrong — a coverage map that credits the path on
   the other side of the boulevard is worse than one that is slightly
   incomplete.
5. Otherwise mark the bin at `metersAlongWay` for the winning way, plus the
   bins between it and the previous fix's bin **on the same way** (so a 3 m
   `distanceFilter` doesn't leave gaps at jogging speed).

### How bad is the ambiguity, really

Measured over 3,000 sampled segment midpoints, distance to the nearest
**unconnected** way (ways sharing a node are junction neighbours, not
ambiguity):

| Within | Share of network |
|---|---:|
| 10 m | **2.0 %** |
| 15 m | 3.7 % |
| 20 m | 5.7 % |
| 25 m | 8.1 % |
| 30 m | 10.5 % |

So the ambiguity rule will suppress recording on roughly 2–6 % of the
network. Acceptable, and recoverable with context:

- **While navigating**, prefer the way that is on the active route.
- **While recording freely**, prefer the way matched by the previous fix if it
  is still a candidate — walks are continuous, and continuity resolves almost
  every parallel-path case.

A naïve measurement that includes junction neighbours reports 16 % within
10 m. That number is misleading and should not be used to justify design
changes.

---

## 4. The recording question — needs a product decision

Coverage is only worth having if it captures **all** walks. Today the only
thing that streams location is active navigation, and most walks are probably
not navigated — people walk their usual loop without asking for directions. A
coverage map that silently ignores those will read as broken.

Three options:

| Option | Captures | Cost |
|---|---|---|
| **A. Navigation only** | Only routed walks | Nearly free — hook the existing stream. Under-counts badly. |
| **B. Foreground only** | Walks with the app open and awake | Free-ish, but nobody walks with the screen on for 45 minutes. |
| **C. Explicit "Record walk"** | Everything the user chooses to record | `UIBackgroundModes: location`, `NSLocationAlwaysAndWhenInUseUsageDescription`, blue status bar, battery, App Store review justification. |

**Recommendation: C**, with recording auto-starting when navigation starts so
routed walks need no extra tap. This is the standard fitness-app pattern, is
well understood by reviewers when user-initiated, and is the only option where
the feature tells the truth. Ship A or B and the first question will be "why
didn't my walk count?"

Note this is a meaningful change in what the app asks of the user — it
currently requests only When-In-Use. That is a product decision, not a
technical one.

---

## 5. Map layer

A second polyline overlay beneath the existing trail network:

- Covered ways in the terracotta route accent at full opacity, uncovered in
  the current green/brown at reduced opacity — the map becomes a progress
  display at a glance without needing a legend.
- Rebuild on the same cache-invalidation pattern `TrailMapView` already uses
  for the base overlays (keyed on graph identity + a coverage revision
  counter). Do **not** rebuild per fix — batch and bump the counter at most
  once every few seconds.
- Partially covered long ways should render per-bin, not all-or-nothing;
  otherwise the 46 ways over 1 km look untouched for most of a walk.

A **Coverage** screen lists the eleven buckets with progress bars, sorted by
completion, and taps through to zoom the map to that village.

---

## 6. The share card

`WalkSummaryCard` already renders a single route at 1080×1350 and was built
explicitly as a distribution play. Coverage gives it a far better subject:
**the whole town, filling in.**

- Same dimensions and hardcoded-palette rule (a shared PNG must not vary with
  the sharer's appearance settings).
- Draw the full network faint, the covered network bright, then the headline:
  `34% of The Woodlands`, with miles walked and villages completed.
- Offer it from the Coverage screen, and automatically at milestones — first
  village finished, every 10 % overall. Milestones are the moment somebody
  wants to post, and the current card has no equivalent.

---

## 7. Suggested build order

1. **Fix `Way.id`** (§0) and migrate favourites. Standalone, shippable on its
   own, and fixes a live bug regardless of whether 2.0 proceeds.
2. Coverage store + bin model + the 60 m segment grid. Unit-testable with no
   UI.
3. Matching against **recorded navigation only** — proves the algorithm
   against real traces before committing to background location.
4. Recording mode (§4) once matching is trusted.
5. Map layer, then the Coverage screen.
6. Share card and milestones.

Steps 1–3 answer the only genuinely open technical question — whether
real-world traces match cleanly — before any of the expensive work.

---

## 8. What this scope deliberately excludes

- **Leaderboards, accounts, friends.** No backend, no login; this stays a
  private record. A social layer would drag in CloudKit identity and
  moderation for no retention gain.
- **Verified / anti-cheat coverage.** It is a personal map, not a competition.
- **Retroactive seeding.** Not possible (§2), and not worth faking.
- **Android.** The Flutter port should follow once the model is proven, but it
  has no CloudKit, no HealthKit and a separate location stack; doing both at
  once doubles the unknowns.
