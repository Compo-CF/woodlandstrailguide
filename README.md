# Woodlands Trail Guide

iOS guide to The Woodlands' hike-and-bike pathway network — find named pathways
across all nine villages, see what connects to what, and (soon) get walking or
biking directions across the trail system.

Built on the same SwiftUI + MapKit stack as the Woodlands Fishing Guide.
Trail data is sourced from The Woodlands Township's public GIS — this app is
a third-party guide, not an official Township product.

## Data source

The Woodlands Township publishes the pathway network as public ArcGIS REST
services. The `scripts/fetch_township_data.py` script pulls two layers:

- `PATHWAYS_ROUTING/FeatureServer/0` — ~1,500 residential pathway segments,
  named by street (`STREET` field) and tagged by village
- `TRAILS/FeatureServer/0` — natural-surface park trails (George Mitchell
  Nature Preserve, Spring Creek Greenway, etc.) with `TRAILNAME` + `PARKNAME`

It merges both layers into a single graph with deduped intersection nodes,
saves it to `WoodlandsTrailGuide/Resources/TrailGraph.json`, and bundles that
into the app.

Re-run any time the Township updates their GIS:

```sh
python scripts/fetch_township_data.py
```

Raw GeoJSON dumps land in `scripts/raw/` (gitignored).

## Build

```sh
xcodegen generate
open WoodlandsTrailGuide.xcodeproj
```

Requires Xcode 15+ and the XcodeGen tool. On MacInCloud, install XcodeGen
as a standalone binary in `~/bin` per the team setup notes.

### Bumping the build number for TestFlight / App Store uploads

XcodeGen reads `CFBundleVersion` from `project.yml` and overwrites the
generated `.xcodeproj` on every regen, so any Xcode-side auto-increment
gets wiped. ASC rejects duplicate build numbers within a version, so
every upload needs a fresh one. Run this before each archive:

```sh
python scripts/bump_build.py
xcodegen generate
```

Commit the bumped `project.yml` so the history reflects the build that
got uploaded.

## Stack

- SwiftUI + MapKit
- `MKPolyline` overlays for trail rendering (analogous to fishing app's
  `MKMarkerAnnotationView` clustering)
- Client-side Dijkstra over the trail graph for A→B routing
- Bundled JSON + remote refresh from GitHub Pages (no backend)

## Attribution

Trail data © The Woodlands Township GIS — public ArcGIS services.
This is an independent, third-party app and is not affiliated with,
endorsed by, or sponsored by The Woodlands Township.
