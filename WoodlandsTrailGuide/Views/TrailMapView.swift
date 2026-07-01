import SwiftUI
import MapKit

/// UIKit-bridged MKMapView rendering the trail graph as MKPolyline overlays.
///
/// Layered, bottom to top:
///   1. Context polygons (parks, lakes, the GMNP boundary, village areas)
///   2. Creek lines
///   3. Trail polylines (pathways green, natural trails dashed brown)
///   4. Route polyline (orange, drawn above labels)
///   5. POI annotations (SF Symbol pins, category-tinted)
///   6. Waypoint pins (green start, red end)
///
/// In routing mode, taps snap to the nearest graph node to set start/end.
/// In default mode, taps hit-test against the base trails to surface a
/// trail's detail sheet. POI taps are not yet wired — POIs are visual
/// context only for v1.
struct TrailMapView: UIViewRepresentable {
    let graph: TrailGraph
    @Binding var selectedWay: TrailGraph.Way?

    let routingMode: Bool
    /// True while the user is picking a waypoint via the "+ Add stop" button
    /// on the route summary card. Taps in this mode append to
    /// `waypointNodes` instead of replacing start/end.
    @Binding var addingWaypoint: Bool
    @Binding var startNode: Int?
    @Binding var endNode: Int?
    @Binding var waypointNodes: [Int]
    let routeNodeIndices: [Int]?

    let pois: POICatalog?
    let polygons: PolygonCatalog?
    /// Base layer style (.standard / .hybrid / .satellite). The hybrid and
    /// satellite styles swap MapKit's base for Apple's imagery, which makes
    /// our context polygons (parks/lakes) less necessary but still useful
    /// as a transparent overlay for the village outlines.
    let mapStyle: MapStyleChoice
    /// True while the user is actively walking a computed route. Toggles
    /// MKMapView's userTrackingMode to .followWithHeading so the map rotates
    /// and pans with the user.
    let navigationActive: Bool
    /// Incremented by MapTabView's recenter button. When it changes, snap
    /// the map back to the user's location. Independent of `navigationActive`
    /// so the button works in both routing and idle modes.
    let recenterTick: Int

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.showsCompass = true
        mapView.showsScale = true
        // Hide MapKit's own POIs — we render our own from Township data.
        mapView.pointOfInterestFilter = .excludingAll
        applyConfiguration(mapView, style: mapStyle)

        let tap = UITapGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handleTap(_:)))
        tap.delegate = context.coordinator
        mapView.addGestureRecognizer(tap)

        mapView.register(WaypointAnnotationView.self,
                         forAnnotationViewWithReuseIdentifier: WaypointAnnotationView.reuseID)
        mapView.register(POIAnnotationView.self,
                         forAnnotationViewWithReuseIdentifier: POIAnnotationView.reuseID)
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        let coord = context.coordinator
        coord.parent = self

        if coord.appliedStyle != mapStyle {
            applyConfiguration(mapView, style: mapStyle)
            coord.appliedStyle = mapStyle
        }

        if coord.appliedNavigationActive != navigationActive {
            let mode: MKUserTrackingMode = navigationActive ? .followWithHeading : .none
            mapView.setUserTrackingMode(mode, animated: true)
            if navigationActive {
                mapView.camera.altitude = 600
            }
            coord.appliedNavigationActive = navigationActive
        }

        if coord.appliedRecenterTick != recenterTick {
            // Don't override .followWithHeading during navigation — just
            // re-enable plain .follow when the user has pinched away.
            if !navigationActive {
                mapView.setUserTrackingMode(.follow, animated: true)
            } else {
                mapView.setUserTrackingMode(.followWithHeading, animated: true)
            }
            coord.appliedRecenterTick = recenterTick
        }

        // ---- Polygons / creek lines (rebuild only when version changes) ----
        let polyVersion = polygons?.version ?? 0
        if coord.lastPolyVersion != polyVersion {
            mapView.removeOverlays(coord.polygonOverlays + coord.lineOverlays)
            coord.polygonOverlays = []
            coord.lineOverlays = []
            if let polygons {
                for (key, group) in polygons.polygons {
                    let fillHex = group.fillHex
                    for shape in group.items {
                        guard let outer = shape.rings.first, outer.count >= 3 else { continue }
                        let outerCoords = outer.map { $0.clCoord }
                        let interiors = shape.rings.dropFirst().compactMap { ring -> MKPolygon? in
                            guard ring.count >= 3 else { return nil }
                            let cs = ring.map { $0.clCoord }
                            return MKPolygon(coordinates: cs, count: cs.count)
                        }
                        let p = ContextPolygon(coordinates: outerCoords, count: outerCoords.count, interiorPolygons: interiors)
                        p.categoryKey = key
                        p.fillHex = fillHex
                        coord.polygonOverlays.append(p)
                    }
                }
                mapView.addOverlays(coord.polygonOverlays, level: .aboveRoads)

                for (key, group) in polygons.lines {
                    for line in group.items {
                        guard line.count >= 2 else { continue }
                        let cs = line.map { $0.clCoord }
                        let l = ContextLine(coordinates: cs, count: cs.count)
                        l.categoryKey = key
                        l.strokeHex = group.strokeHex
                        coord.lineOverlays.append(l)
                    }
                }
                mapView.addOverlays(coord.lineOverlays, level: .aboveRoads)
            }
            coord.lastPolyVersion = polyVersion
        }

        // ---- Trail polylines (graph base layer) ----
        if coord.loadedGraphVersion != graph.version || coord.baseOverlays.isEmpty {
            mapView.removeOverlays(coord.baseOverlays)
            let overlays = graph.ways.compactMap { way -> TrailPolyline? in
                buildPolyline(for: way, graph: graph)
            }
            mapView.addOverlays(overlays, level: .aboveRoads)
            coord.baseOverlays = overlays
            coord.loadedGraphVersion = graph.version

            if !coord.didFitInitial {
                let bbox = graph.bbox
                let region = MKCoordinateRegion(
                    center: CLLocationCoordinate2D(
                        latitude: (bbox.south + bbox.north) / 2,
                        longitude: (bbox.west + bbox.east) / 2
                    ),
                    span: MKCoordinateSpan(
                        latitudeDelta: (bbox.north - bbox.south) * 1.05,
                        longitudeDelta: (bbox.east - bbox.west) * 1.05
                    )
                )
                mapView.setRegion(region, animated: false)
                coord.didFitInitial = true
            }
        }

        // ---- Route overlay (rebuild when endpoint nodes change) ----
        let newRouteSig: String? = routeNodeIndices.map { nodes in
            "\(nodes.first ?? -1)-\(nodes.last ?? -1)-\(nodes.count)"
        }
        if coord.lastRouteSig != newRouteSig {
            mapView.removeOverlays(coord.routeOverlays)
            coord.routeOverlays = []
            if let nodes = routeNodeIndices, nodes.count >= 2 {
                let coords = nodes.map { graph.nodes[$0].clCoord }
                let line = RoutePolyline(coordinates: coords, count: coords.count)
                mapView.addOverlay(line, level: .aboveLabels)
                coord.routeOverlays = [line]
            }
            coord.lastRouteSig = newRouteSig
        }

        // ---- POIs ----
        let poiVersion = pois?.version ?? 0
        if coord.lastPOIVersion != poiVersion {
            mapView.removeAnnotations(coord.allPOIAnnotations)
            coord.allPOIAnnotations = []
            if let pois {
                for (_, cat) in pois.categories {
                    for poi in cat.items {
                        let a = POIAnnotation(poi: poi, category: cat)
                        coord.allPOIAnnotations.append(a)
                    }
                }
            }
            coord.lastPOIVersion = poiVersion
            coord.applyPOIVisibility(to: mapView)
        }

        // ---- Waypoint pins ----
        let oldPins = mapView.annotations.compactMap { $0 as? WaypointAnnotation }
        mapView.removeAnnotations(oldPins)
        if let s = startNode, s < graph.nodes.count {
            mapView.addAnnotation(WaypointAnnotation(
                coordinate: graph.nodes[s].clCoord, kind: .start))
        }
        for (i, w) in waypointNodes.enumerated() where w < graph.nodes.count {
            mapView.addAnnotation(WaypointAnnotation(
                coordinate: graph.nodes[w].clCoord, kind: .waypoint(number: i + 1)))
        }
        if let e = endNode, e < graph.nodes.count {
            mapView.addAnnotation(WaypointAnnotation(
                coordinate: graph.nodes[e].clCoord, kind: .end))
        }
    }

    private func buildPolyline(for way: TrailGraph.Way, graph: TrailGraph) -> TrailPolyline? {
        guard way.nodeIndices.count >= 2 else { return nil }
        let coords = way.nodeIndices.map { graph.nodes[$0].clCoord }
        let line = TrailPolyline(coordinates: coords, count: coords.count)
        line.way = way
        return line
    }

    /// Swap the map's base configuration to match the user's style choice.
    /// iOS 16+: MKMapConfiguration with three concrete subclasses. We use
    /// `.realistic` elevation everywhere for hillshading.
    private func applyConfiguration(_ mapView: MKMapView, style: MapStyleChoice) {
        let config: MKMapConfiguration
        switch style {
        case .standard:
            let c = MKStandardMapConfiguration(elevationStyle: .realistic,
                                               emphasisStyle: .default)
            c.pointOfInterestFilter = .excludingAll
            c.showsTraffic = false
            config = c
        case .hybrid:
            let c = MKHybridMapConfiguration(elevationStyle: .realistic)
            c.pointOfInterestFilter = .excludingAll
            c.showsTraffic = false
            config = c
        case .satellite:
            config = MKImageryMapConfiguration(elevationStyle: .realistic)
        }
        mapView.preferredConfiguration = config
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        var parent: TrailMapView
        var didFitInitial = false
        var loadedGraphVersion = -1
        var baseOverlays: [TrailPolyline] = []
        var routeOverlays: [MKOverlay] = []
        var lastRouteSig: String?
        var polygonOverlays: [MKOverlay] = []
        var lineOverlays: [MKOverlay] = []
        var lastPolyVersion = -1
        var allPOIAnnotations: [POIAnnotation] = []
        var lastPOIVersion = -1
        var currentAltitude: CLLocationDistance = 4000
        var appliedStyle: MapStyleChoice = .standard
        var appliedNavigationActive: Bool = false
        var appliedRecenterTick: Int = 0

        init(_ parent: TrailMapView) { self.parent = parent }

        // MARK: - Renderers

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let cp = overlay as? ContextPolygon {
                let r = MKPolygonRenderer(polygon: cp)
                if let hex = cp.fillHex {
                    r.fillColor = UIColor(rgbHex: hex).withAlphaComponent(0.55)
                    r.strokeColor = UIColor(rgbHex: hex).withAlphaComponent(0.78)
                    r.lineWidth = 0.6
                } else {
                    // Outline-only — village areas
                    r.fillColor = .clear
                    r.strokeColor = UIColor.black.withAlphaComponent(0.12)
                    r.lineWidth = 0.8
                    r.lineDashPattern = [3, 4]
                }
                return r
            }
            if let cl = overlay as? ContextLine {
                let r = MKPolylineRenderer(polyline: cl)
                if let hex = cl.strokeHex {
                    r.strokeColor = UIColor(rgbHex: hex).withAlphaComponent(0.75)
                } else {
                    r.strokeColor = UIColor.systemBlue.withAlphaComponent(0.5)
                }
                r.lineWidth = 1.4
                r.lineCap = .round
                return r
            }
            if overlay is RoutePolyline {
                let r = MKPolylineRenderer(overlay: overlay)
                r.strokeColor = Natural.routeUI
                r.lineWidth = 7
                r.lineCap = .round
                r.lineJoin = .round
                return r
            }
            if let trail = overlay as? TrailPolyline, let way = trail.way {
                let r = MKPolylineRenderer(polyline: trail)
                switch way.kind {
                case "pathway":
                    r.strokeColor = UIColor(red: 0.13, green: 0.55, blue: 0.27, alpha: 1.0)
                    r.lineWidth = 3.5
                case "trail":
                    r.strokeColor = UIColor(red: 0.55, green: 0.36, blue: 0.13, alpha: 1.0)
                    r.lineWidth = 2.5
                    r.lineDashPattern = [6, 4]
                default:
                    r.strokeColor = .systemGray
                    r.lineWidth = 2
                }
                r.lineCap = .round
                r.lineJoin = .round
                return r
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        // MARK: - Annotations

        func mapView(_ mapView: MKMapView,
                     viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation { return nil }
            if let wp = annotation as? WaypointAnnotation {
                let v = mapView.dequeueReusableAnnotationView(
                    withIdentifier: WaypointAnnotationView.reuseID,
                    for: wp
                ) as? WaypointAnnotationView
                v?.configure(for: wp.kind)
                return v
            }
            if let poi = annotation as? POIAnnotation {
                let v = mapView.dequeueReusableAnnotationView(
                    withIdentifier: POIAnnotationView.reuseID,
                    for: poi
                ) as? POIAnnotationView
                v?.configure(for: poi)
                return v
            }
            return nil
        }

        // MARK: - Zoom-based POI visibility

        func mapView(_ mapView: MKMapView,
                     regionDidChangeAnimated animated: Bool) {
            // MKMapView's camera altitude is the best zoom proxy.
            currentAltitude = mapView.camera.altitude
            applyPOIVisibility(to: mapView)
        }

        /// Show only POIs whose category is permitted at the current zoom level.
        /// Bigger altitude (zoomed out) → fewer categories visible.
        func applyPOIVisibility(to mapView: MKMapView) {
            let alt = currentAltitude
            let visibleKeys = visibleCategoryKeys(forAltitude: alt)
            let currentlyShown = Set(mapView.annotations.compactMap { ($0 as? POIAnnotation).map { "\($0.category.key):\($0.poi.id)" } })
            var toAdd: [POIAnnotation] = []
            var toRemove: [POIAnnotation] = []
            for a in allPOIAnnotations {
                let id = "\(a.category.key):\(a.poi.id)"
                let isShown = currentlyShown.contains(id)
                let shouldShow = visibleKeys.contains(a.category.key)
                if shouldShow && !isShown { toAdd.append(a) }
                if !shouldShow && isShown {
                    if let existing = mapView.annotations.first(where: {
                        ($0 as? POIAnnotation).map { "\($0.category.key):\($0.poi.id)" } == id
                    }) as? POIAnnotation {
                        toRemove.append(existing)
                    }
                }
            }
            if !toRemove.isEmpty { mapView.removeAnnotations(toRemove) }
            if !toAdd.isEmpty { mapView.addAnnotations(toAdd) }
        }

        private func visibleCategoryKeys(forAltitude altitude: CLLocationDistance) -> Set<String> {
            // Three tiers. The thresholds are roughly tuned for The Woodlands'
            // bounding box (~25 km wide), which means initial fit has altitude
            // ~25-30 km.
            let tierHigh: Set<String> = [
                "bridges", "playgrounds", "dog_parks", "sports_fields",
                "sports_courts", "pavilions", "pools", "spraygrounds",
                "monuments", "fishing", "ecotour",
            ]
            let tierMid: Set<String> = [
                "restrooms", "fountains", "trolley", "trail_markers",
                "piers", "docks", "boat_houses", "fountain_feat",
                "art_benches", "art_bike_racks", "playgrounds_eq",
                "picnic_areas",
            ]
            let tierLow: Set<String> = [
                "benches", "picnic_tables", "bbq", "bike_racks",
                "dog_bag", "parking_park", "parking", "bike_share",
            ]
            if altitude < 1500 { return tierHigh.union(tierMid).union(tierLow) }
            if altitude < 6000 { return tierHigh.union(tierMid) }
            return tierHigh
        }

        // MARK: - Taps

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard let mapView = recognizer.view as? MKMapView else { return }
            // Suppress all map taps while walking — the route is locked in,
            // and we don't want to derail the user with stray detail sheets.
            if parent.navigationActive { return }
            let point = recognizer.location(in: mapView)
            let tapCoord = mapView.convert(point, toCoordinateFrom: mapView)

            if parent.routingMode {
                let router = Router(graph: parent.graph)
                guard let nodeIdx = router.nearestNode(to: tapCoord) else { return }
                if parent.addingWaypoint {
                    // In add-waypoint mode the tap always appends a stop
                    // between start and end, then drops back to summary.
                    parent.waypointNodes.append(nodeIdx)
                    parent.addingWaypoint = false
                } else if parent.startNode == nil {
                    parent.startNode = nodeIdx
                } else if parent.endNode == nil {
                    parent.endNode = nodeIdx
                } else {
                    // Both endpoints already set — replace the end so the
                    // user can tweak destination without wiping the route.
                    parent.endNode = nodeIdx
                }
                return
            }

            let mapPoint = MKMapPoint(tapCoord)
            let tolerance = mapView.visibleMapRect.size.width / Double(mapView.bounds.width) * 8
            var best: (line: TrailPolyline, dist: Double)?
            for line in baseOverlays {
                let d = distance(from: mapPoint, to: line)
                if d < tolerance, best == nil || d < best!.dist {
                    best = (line, d)
                }
            }
            if let hit = best?.line, let way = hit.way {
                parent.selectedWay = way
            }
        }

        private func distance(from p: MKMapPoint, to line: MKPolyline) -> Double {
            let count = line.pointCount
            guard count >= 2 else { return .infinity }
            let points = line.points()
            var best = Double.infinity
            for i in 0..<(count - 1) {
                let d = pointSegmentDistance(p, points[i], points[i + 1])
                if d < best { best = d }
            }
            return best
        }

        private func pointSegmentDistance(_ p: MKMapPoint, _ a: MKMapPoint, _ b: MKMapPoint) -> Double {
            let abx = b.x - a.x, aby = b.y - a.y
            let apx = p.x - a.x, apy = p.y - a.y
            let abLen2 = abx * abx + aby * aby
            let t = abLen2 == 0 ? 0 : max(0, min(1, (apx * abx + apy * aby) / abLen2))
            let cx = a.x + t * abx
            let cy = a.y + t * aby
            let dx = p.x - cx
            let dy = p.y - cy
            return (dx * dx + dy * dy).squareRoot()
        }

        func gestureRecognizer(_ g: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }
    }
}

// MARK: - Overlay subclasses

final class TrailPolyline: MKPolyline {
    var way: TrailGraph.Way?
}

final class RoutePolyline: MKPolyline {}

final class ContextPolygon: MKPolygon {
    var categoryKey: String?
    var fillHex: UInt32?
}

final class ContextLine: MKPolyline {
    var categoryKey: String?
    var strokeHex: UInt32?
}

// MARK: - Waypoint

final class WaypointAnnotation: NSObject, MKAnnotation {
    enum Kind: Hashable {
        case start
        case end
        /// A mid-route stop. `number` is 1-indexed order along the route.
        case waypoint(number: Int)
    }
    let coordinate: CLLocationCoordinate2D
    let kind: Kind
    init(coordinate: CLLocationCoordinate2D, kind: Kind) {
        self.coordinate = coordinate
        self.kind = kind
    }
}

final class WaypointAnnotationView: MKAnnotationView {
    static let reuseID = "Waypoint"

    func configure(for kind: WaypointAnnotation.Kind) {
        canShowCallout = false
        let size: CGFloat = 28
        frame = CGRect(x: 0, y: 0, width: size, height: size)
        centerOffset = .zero
        let color: UIColor
        var glyph: String? = nil
        switch kind {
        case .start:
            color = Natural.startPinUI
        case .end:
            color = Natural.endPinUI
        case .waypoint(let number):
            color = Natural.waypointPinUI
            glyph = "\(number)"
        }
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        image = renderer.image { _ in
            let rect = CGRect(x: 2, y: 2, width: size - 4, height: size - 4)
            Natural.pinRingUI.setFill()
            UIBezierPath(ovalIn: rect.insetBy(dx: -2, dy: -2)).fill()
            color.setFill()
            UIBezierPath(ovalIn: rect).fill()
            if let glyph {
                // Waypoint: draw the order number instead of a center dot.
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 13, weight: .heavy),
                    .foregroundColor: UIColor.white,
                ]
                let s = (glyph as NSString)
                let sz = s.size(withAttributes: attrs)
                let origin = CGPoint(
                    x: (size - sz.width) / 2,
                    y: (size - sz.height) / 2 - 0.5
                )
                s.draw(at: origin, withAttributes: attrs)
            } else {
                Natural.pinRingUI.setFill()
                UIBezierPath(ovalIn: rect.insetBy(dx: 7, dy: 7)).fill()
            }
        }
    }
}

// MARK: - POI

final class POIAnnotation: NSObject, MKAnnotation {
    let poi: POI
    let category: POICategory
    var coordinate: CLLocationCoordinate2D { poi.coordinate }
    var title: String? { poi.name ?? category.label }
    var subtitle: String? { poi.park ?? poi.village }

    init(poi: POI, category: POICategory) {
        self.poi = poi
        self.category = category
    }
}

final class POIAnnotationView: MKAnnotationView {
    static let reuseID = "POI"

    func configure(for poi: POIAnnotation) {
        canShowCallout = true
        clusteringIdentifier = "poi-\(poi.category.key)"
        displayPriority = .defaultLow
        let size: CGFloat = 24
        frame = CGRect(x: 0, y: 0, width: size, height: size)
        let tint = UIColor(rgbHex: poi.category.tintHex)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        image = renderer.image { ctx in
            let bg = CGRect(x: 0, y: 0, width: size, height: size)
            Natural.pinRingUI.setFill()
            UIBezierPath(ovalIn: bg).fill()
            tint.setFill()
            UIBezierPath(ovalIn: bg.insetBy(dx: 1.5, dy: 1.5)).fill()
            if let symbol = UIImage(systemName: poi.category.icon,
                                    withConfiguration: UIImage.SymbolConfiguration(pointSize: 11,
                                                                                   weight: .semibold))?
                .withTintColor(.white, renderingMode: .alwaysOriginal) {
                let iconRect = CGRect(
                    x: (size - symbol.size.width) / 2,
                    y: (size - symbol.size.height) / 2,
                    width: symbol.size.width,
                    height: symbol.size.height
                )
                symbol.draw(in: iconRect)
            }
        }
    }
}

// MARK: - UIColor hex helper

extension UIColor {
    convenience init(rgbHex: UInt32) {
        let r = CGFloat((rgbHex >> 16) & 0xFF) / 255.0
        let g = CGFloat((rgbHex >>  8) & 0xFF) / 255.0
        let b = CGFloat(rgbHex         & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b, alpha: 1.0)
    }
}
