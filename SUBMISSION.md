# App Store submission — Woodlands Trail Guide

Every text field, URL, and questionnaire answer ASC will ask for during the
first public submission. Copy-paste into the matching field; nothing here
needs editing for the initial review pass.

---

## App Information (set once, persists across versions)

**Name** (App Store listing title — must be globally unique on the Store)
```
Woodlands Trail Guide
```

**Subtitle** (30 char max, shown under the name in search/listing)
```
Hike & bike The Woodlands
```

**Primary category**
```
Navigation
```

**Secondary category**
```
Health & Fitness
```

**Support URL**
```
https://github.com/Compo-CF/woodlandstrailguide/issues
```

**Marketing URL** *(optional, can leave blank)*
```
https://github.com/Compo-CF/woodlandstrailguide
```

**Privacy Policy URL**
```
https://compo-cf.github.io/woodlandstrailguide/privacy.html
```

---

## Version metadata (set per version — fill these on the 1.0 version page)

**Promotional Text** (170 char max — editable any time without re-review)
```
200+ miles of named pathways across The Woodlands. Routing, parks, bridges, playgrounds, and live walking directions — fully offline once loaded.
```

**Description** (4000 char max)
```
Woodlands Trail Guide is an independent, locally-built guide to The Woodlands' 200+ miles of hike-and-bike pathways. Every named segment across all nine villages is on the map, along with the parks, bridges, playgrounds, water fountains, and pavilions you'll pass along the way.

WHAT'S INSIDE
• 1,500+ named pathway segments across Alden Bridge, Cochran's Crossing, College Park, Creekside Park, Grogan's Mill, Indian Springs, Panther Creek, Sterling Ridge, and Town Center
• 3,000+ points of interest from The Woodlands Township: bridges, restrooms, fountains, playgrounds, pavilions, picnic areas, BBQ grills, bike racks, art benches, trolley stops, sports fields, and more
• Real walking routes between any two points on the network — tap a start, tap a destination, and the app computes the shortest path
• Live turn-by-turn directions: continue straight, turn left, bear right, arrive at destination. Your phone keeps the screen on and follows your location while you walk.
• Park-by-park view: see which parks each trail connects to, and which parks your route passes through
• "Along the way" preview: every bridge, playground, restroom, and pavilion your route passes — surfaced before you start walking
• Switch between Standard, Hybrid (satellite + labels), and Satellite map styles
• Recenter button to snap back to your location at any time

HOW IT'S BUILT
Trail and amenity data come from The Woodlands Township's public ArcGIS GIS services — the same database the Township uses internally. The data is bundled with the app for offline use and refreshed over the air when the Township updates its records, so new pathways and amenities show up without an app update.

This app is built and maintained independently by a local — not by The Woodlands Township, and not affiliated with or endorsed by the Township. Feedback and issue reports are welcome via the in-app "Report a problem" flow.

ATTRIBUTION
Trail data © The Woodlands Township GIS, used under public-records availability. Map base by Apple Maps. Built with SwiftUI and MapKit.
```

**Keywords** (100 char max, comma-separated, no spaces after commas)
```
woodlands,trails,pathway,hiking,biking,walking,parks,map,texas,houston,navigation,outdoor
```

**What's New in This Version** (4000 char max — for v1, the inaugural notes)
```
Initial release.

• 200+ miles of named pathways, all nine villages
• 3,000+ points of interest from the Township GIS
• Real walking routes with live turn-by-turn directions
• Park connections shown on every trail
• Standard, Hybrid, and Satellite map styles

Built independently by a local. Feedback welcome via the GitHub issues page.
```

**Copyright**
```
2026 Anthony Compofelice
```

---

## Privacy Questionnaire (App Information → App Privacy)

Click **"Get Started"** → **Yes, we collect data from this app** → then for each data type:

### Location → Precise Location
- **Linked to user?** No
- **Used for tracking?** No
- **Purposes:** App Functionality

### Identifiers → Device ID
- **Linked to user?** No
- **Used for tracking?** **Yes**
- **Purposes:** Third-Party Advertising

> The Device ID disclosure covers Apple's IDFA, which Google AdMob uses to
> serve banner ads. "Tracking = Yes" is required because AdMob can link
> device ID to other apps' data. This is the same disclosure pattern
> used by Woodlands Fishing Guide.

That's everything. No other categories (Contact Info, Health & Fitness,
Financial, Browsing, Search, Purchases, etc.) should be checked.

---

## Age Rating Questionnaire

Set everything to **None** / **No**. The app contains no:

- Cartoon or fantasy violence — None
- Realistic violence — None
- Prolonged graphic or sadistic realistic violence — None
- Sexual content or nudity — None
- Profanity or crude humor — None
- Alcohol, tobacco, or drug use or references — None
- Mature/suggestive themes — None
- Simulated gambling — None
- Horror/fear themes — None
- Medical/treatment information — None
- Unrestricted web access — No
- Gambling and contests — No

Result: **4+**

---

## Pricing & Availability

- **Price**: USD 0.00 (Free)
- **Availability**: All territories (default)
- **Pre-orders**: No

---

## App Review Information

**Contact Information**
```
First Name: Anthony
Last Name: Compofelice
Phone: <fill in your number>
Email: anthony.compofelice@centricfiber.com
```

**Demo Account** — leave blank (no login required)

**Notes for Reviewer**
```
This is an independent, free guide to The Woodlands, Texas hike-and-bike pathway network. It is not affiliated with The Woodlands Township; trail and amenity data come from the Township's public ArcGIS GIS services, with attribution in-app and in the privacy policy.

No account or login is required. To test routing:
1. Tap the directions button (top right of the map — a curving-path icon)
2. The first-time intro sheet appears; dismiss with "Got it"
3. Tap any point on a trail to set your starting point (a green pin drops)
4. Tap another point to set your destination (a red pin drops)
5. The route appears in orange with a summary card at the bottom showing distance, walking time, segments, parks, and amenities along the way
6. Tap "Start walking" to enter live navigation mode (the map follows your location, turn-by-turn directions appear)
7. Tap "End" to exit

Location permission is requested for showing your position on the trails and following the route — no location data is transmitted off the device.

App Tracking Transparency is requested for advertising attribution (Google AdMob banner). Granting tracking is not required for any app functionality.

For testing in Cupertino or anywhere outside The Woodlands, please use the iOS Simulator's "Custom Location" feature with coordinates around 30.165, -95.49 (the heart of The Woodlands, TX). The map auto-centers on the trail network's bounding box at launch.
```

**Attachment** — leave blank

**Sign-In Information** — N/A (no login)

**Notes** — none

---

## Build

Pick the most recent **1.0 (N)** build from the Builds section of the 1.0
version page. As of this writing the latest TestFlight build is the one
to ship.

---

## Export Compliance

Already declared in `Info.plist` via `ITSAppUsesNonExemptEncryption: false`.
The version page should auto-fill this; no action needed.

---

## Screenshots

Apple requires at minimum one set of screenshots for one of these device sizes:
- **6.9" iPhone** (iPhone 16 Pro Max — 1320 × 2868 px) — preferred for current devices
- **6.7" iPhone** (iPhone 15 Pro Max — 1290 × 2796 px) — also accepted

You only need to upload ONE set — Apple uses the largest size you provide
across the listing.

### Recommended captures (3–5 frames)

From the running TestFlight build on your phone (volume-up + side button):

1. **Map view at default zoom** — the trail network filling the screen, all the right-side buttons visible
2. **Active route** — tap to drop two pins, summary card showing distance + walking time + Route chips + Parks chips + Along-the-way chips
3. **Live navigation banner** — tap Start, screenshot the big turn-arrow banner with the remaining-distance row underneath
4. **Trails list view** — second tab, scroll to show grouped-by-village headers
5. **Trail detail sheet** — tap any trail on the map, screenshot with name, surface, length, and Connects-to parks visible

Crop nothing — Apple wants the full frame. Drop them into the ASC upload widget on the version page in the order you want them displayed.

---

## Submission flow

Once everything above is filled in:

1. ASC → My Apps → Woodlands Trail Guide → **App Store** tab → version 1.0
2. Confirm the build is attached under **Build**
3. Confirm screenshots are uploaded
4. Top of the page → **Add for Review**
5. Answer the on-screen routing questions (export compliance, content rights, advertising IDs) — all should already be filled
6. **Submit for Review**

Apple's review window is typically 24–72 hours. The status will move through
*Waiting for Review → In Review → Pending Developer Release / Ready for Sale*.

If you select **Manually release this version** on the pricing page, you
control when it goes public after approval. If you select **Automatically
release**, it goes live the moment Apple approves.
