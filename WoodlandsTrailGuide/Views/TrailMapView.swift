import SwiftUI
import MapKit

/// UIKit-bridged MKMapView rendering the trail graph as MKPolyline overlays.
///
/// We use MKMapView (not SwiftUI's Map) because:
/// 1. Polyline overlay performance at scale is better with the UIKit map
/// 2. Per-overlay stroke styling (color by surface, width by kind) is
///    straightforward via MKOverlayRenderer
/// 3. Hit testing on a polyline (tap a trail to see its name) needs the
///    delegate pattern UIViewRepresentable gives us
///
/// In routing mode, taps snap to the nearest graph node and set the route
/// endpoints. In default mode, taps select a trail polyline to surface its
/// name. The two modes are mutually exclusive — `routingMode` switches the
/// tap interpretation.
struct TrailMapView: UIViewRepresentable {
    let graph: TrailGraph
    @Binding var selectedWay: TrailGraph.Way?

    /// Tap-to-set-waypoint mode. Owned by `MapTabView`.
    let routingMode: Bool
    @Binding var startNode: Int?
    @Binding var endNode: Int?
    /// Node indices along the computed route, in order. Nil = no route to draw.
    let routeNodeIndices: [Int]?

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.showsCompass = true
        mapView.showsScale = true
        mapView.pointOfInterestFilter = .excludingAll

        // Tap recognizer. MKMapView doesn't expose taps on overlays directly;
        // we route every tap through the coordinator and decide what to do
        // based on the current mode.
        let tap = UITapGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handleTap(_:)))
        tap.delegate = context.coordinator
        mapView.addGestureRecognizer(tap)

        mapView.register(WaypointAnnotationView.self,
                         forAnnotationViewWithReuseIdentifier: WaypointAnnotationView.reuseID)

        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        let coord = context.coordinator
        coord.parent = self

        // Rebuild the base trail overlays only on first paint or when the
        // underlying graph version changes (i.e. a remote refresh landed).
        if coord.loadedGraphVersion != graph.version || coord.baseOverlays.isEmpty {
            mapView.removeOverlays(coord.baseOverlays + coord.routeOverlays)
            coord.routeOverlays = []
            let overlays = graph.ways.compactMap { way -> TrailPolyline? in
                buildPolyline(for: way, graph: graph)
            }
            mapView.addOverlays(overlays)
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

        // Refresh the route overlay whenever the route nodes change. We
        // signature the route by its endpoints + length so unchanged routes
        // don't churn the overlay layer every SwiftUI body invocation.
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

        // Refresh waypoint pins whenever start/end change.
        let oldPins = mapView.annotations.compactMap { $0 as? WaypointAnnotation }
        mapView.removeAnnotations(oldPins)
        if let s = startNode, s < graph.nodes.count {
            mapView.addAnnotation(WaypointAnnotation(
                coordinate: graph.nodes[s].clCoord, kind: .start))
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

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        var parent: TrailMapView
        var didFitInitial = false
        var loadedGraphVersion = -1
        var baseOverlays: [TrailPolyline] = []
        var routeOverlays: [MKOverlay] = []
        var lastRouteSig: String?

        init(_ parent: TrailMapView) { self.parent = parent }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            // Route overlay — bright accent on top of the base trails.
            if overlay is RoutePolyline {
                let r = MKPolylineRenderer(overlay: overlay)
                r.strokeColor = UIColor(red: 1.0, green: 0.49, blue: 0.10, alpha: 0.95)
                r.lineWidth = 7
                r.lineCap = .round
                r.lineJoin = .round
                return r
            }
            guard let trail = overlay as? TrailPolyline,
                  let way = trail.way else {
                return MKOverlayRenderer(overlay: overlay)
            }
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
            return nil
        }

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard let mapView = recognizer.view as? MKMapView else { return }
            let point = recognizer.location(in: mapView)
            let tapCoord = mapView.convert(point, toCoordinateFrom: mapView)

            if parent.routingMode {
                // Snap the tap to the nearest graph node and stuff it into
                // start or end depending on current state.
                let router = Router(graph: parent.graph)
                if let nodeIdx = router.nearestNode(to: tapCoord) {
                    if parent.startNode == nil {
                        parent.startNode = nodeIdx
                    } else if parent.endNode == nil {
                        parent.endNode = nodeIdx
                    } else {
                        // Both already set — replace the end with the new tap
                        // so it's easy to adjust the destination without
                        // resetting.
                        parent.endNode = nodeIdx
                    }
                }
                return
            }

            // Default mode: pick the closest trail polyline within a small
            // map-point tolerance and surface its name.
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

/// MKPolyline subclass that carries the source Way for hit-test feedback.
final class TrailPolyline: MKPolyline {
    var way: TrailGraph.Way?
}

/// Distinct subclass so the renderer can pick out the route overlay and
/// style it separately from the base trail polylines.
final class RoutePolyline: MKPolyline {}

/// Start/end waypoint pin for routing mode.
final class WaypointAnnotation: NSObject, MKAnnotation {
    enum Kind { case start, end }
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
        let color: UIColor = kind == .start
            ? UIColor.systemGreen
            : UIColor.systemRed
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        image = renderer.image { ctx in
            let rect = CGRect(x: 2, y: 2, width: size - 4, height: size - 4)
            UIColor.white.setFill()
            UIBezierPath(ovalIn: rect.insetBy(dx: -2, dy: -2)).fill()
            color.setFill()
            UIBezierPath(ovalIn: rect).fill()
            // Inner dot for contrast
            UIColor.white.setFill()
            let inner = rect.insetBy(dx: 7, dy: 7)
            UIBezierPath(ovalIn: inner).fill()
        }
    }
}
