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
struct TrailMapView: UIViewRepresentable {
    let graph: TrailGraph
    @Binding var selectedWay: TrailGraph.Way?

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.showsCompass = true
        mapView.showsScale = true
        mapView.pointOfInterestFilter = .excludingAll

        // Tap recognizer for selecting a trail polyline. MKMapView doesn't
        // expose taps on overlays directly; we hit-test against rendered
        // overlay paths inside the coordinator.
        let tap = UITapGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handleTap(_:)))
        tap.delegate = context.coordinator
        mapView.addGestureRecognizer(tap)

        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        if context.coordinator.loadedGraphVersion != graph.version
            || mapView.overlays.isEmpty {
            mapView.removeOverlays(mapView.overlays)
            let overlays = graph.ways.compactMap { way -> TrailPolyline? in
                buildPolyline(for: way, graph: graph)
            }
            mapView.addOverlays(overlays)
            context.coordinator.loadedGraphVersion = graph.version
            context.coordinator.overlays = overlays

            if !context.coordinator.didFitInitial {
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
                context.coordinator.didFitInitial = true
            }
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
        let parent: TrailMapView
        var didFitInitial = false
        var loadedGraphVersion = -1
        var overlays: [TrailPolyline] = []
        init(_ parent: TrailMapView) { self.parent = parent }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
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
                // Natural-surface — dashed to differentiate visually
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

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard let mapView = recognizer.view as? MKMapView else { return }
            let point = recognizer.location(in: mapView)
            let coord = mapView.convert(point, toCoordinateFrom: mapView)
            let mapPoint = MKMapPoint(coord)
            // Tolerance in map-points: scale with current zoom so taps remain
            // comfortable at any altitude.
            let tolerance = mapView.visibleMapRect.size.width / Double(mapView.bounds.width) * 8

            var best: (line: TrailPolyline, dist: Double)?
            for line in overlays {
                let d = distance(from: mapPoint, to: line)
                if d < tolerance, best == nil || d < best!.dist {
                    best = (line, d)
                }
            }
            if let hit = best?.line, let way = hit.way {
                parent.selectedWay = way
            }
        }

        /// Minimum distance (in map points) from a point to any segment of a polyline.
        /// MKPolyline exposes its underlying MKMapPoint buffer directly, so no
        /// coordinate conversion is needed here.
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
