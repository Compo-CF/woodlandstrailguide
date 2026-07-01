import SwiftUI
import CoreLocation
import MapKit

/// Search across trails, parks, and POIs. Tapping a result closes the sheet
/// and hands back a target coordinate so MapTabView can snap the camera to
/// it. Results are ranked by rough relevance: exact-name prefix matches
/// first, then contains, then per-category buckets.
struct MapSearchSheet: View {
    let graph: TrailGraph
    let pois: POICatalog?
    let userLocation: CLLocation?
    /// Called with the target coordinate + a display label. Sheet dismisses
    /// itself on tap; the caller decides what to do (usually pan the map).
    let onSelect: (SearchResult) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            List {
                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    Section {
                        Text("Search for a trail, park, or amenity by name — 'Sawmill', 'Bear Branch', 'restroom', 'bridge'.")
                            .font(.callout)
                            .foregroundStyle(Natural.inkMuted)
                    }
                } else {
                    let results = searchResults()
                    if results.isEmpty {
                        Text("No matches for \"\(query)\"")
                            .font(.callout)
                            .foregroundStyle(Natural.inkMuted)
                    } else {
                        ForEach(results) { r in
                            Button {
                                onSelect(r)
                                dismiss()
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: r.icon)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.white)
                                        .frame(width: 30, height: 30)
                                        .background(r.tint, in: Circle())
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(r.title)
                                            .foregroundStyle(Natural.ink)
                                            .font(.subheadline)
                                        Text(r.subtitle)
                                            .font(.caption)
                                            .foregroundStyle(Natural.inkMuted)
                                    }
                                    Spacer(minLength: 0)
                                }
                            }
                        }
                    }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Trails, parks, amenities")
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    // MARK: - Search

    private func searchResults() -> [SearchResult] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        var results: [SearchResult] = []

        // Trails — match on way.name, way.park, way.village, or the parks it
        // connects to. Dedup by name so the same street doesn't appear a
        // dozen times for each of its short segments.
        var seenTrailKeys = Set<String>()
        for way in graph.ways {
            guard let name = way.name else { continue }
            let lowered = name.lowercased()
            guard lowered.contains(q) else { continue }
            let key = lowered  // Group by name
            if seenTrailKeys.contains(key) { continue }
            seenTrailKeys.insert(key)
            guard let firstNode = way.nodeIndices.first,
                  firstNode < graph.nodes.count else { continue }
            let coord = graph.nodes[firstNode].clCoord
            let subtitle = [way.village, way.park].compactMap { $0 }.joined(separator: " · ")
            results.append(SearchResult(
                id: "trail:\(key)",
                title: name,
                subtitle: subtitle.isEmpty ? "Pathway" : subtitle,
                icon: "point.topleft.down.to.point.bottomright.curvepath.fill",
                tint: Natural.forest,
                coordinate: coord,
                score: relevance(lowered, query: q, distance: distanceFromUser(coord))
            ))
        }

        // POIs — match on name, park, village, or category label.
        if let pois {
            for (_, cat) in pois.categories {
                let categoryMatches = cat.label.lowercased().contains(q)
                for poi in cat.items {
                    let name = poi.name?.lowercased() ?? ""
                    let park = poi.park?.lowercased() ?? ""
                    let village = poi.village?.lowercased() ?? ""
                    let hit = name.contains(q) || park.contains(q) || village.contains(q) || categoryMatches
                    guard hit else { continue }
                    let coord = CLLocationCoordinate2D(latitude: poi.lat, longitude: poi.lon)
                    let title = poi.name ?? cat.label
                    let subtitle = [poi.park, poi.village, cat.label].compactMap { $0 }.first ?? cat.label
                    let tint = Color(
                        red: Double((cat.tintHex >> 16) & 0xFF) / 255,
                        green: Double((cat.tintHex >> 8) & 0xFF) / 255,
                        blue: Double(cat.tintHex & 0xFF) / 255
                    )
                    results.append(SearchResult(
                        id: "poi:\(cat.key):\(poi.id)",
                        title: title,
                        subtitle: subtitle,
                        icon: cat.icon,
                        tint: tint,
                        coordinate: coord,
                        score: relevance(title.lowercased(), query: q, distance: distanceFromUser(coord))
                    ))
                }
            }
        }

        return Array(results.sorted { $0.score > $1.score }.prefix(40))
    }

    /// Simple relevance: prefix > contains, closer > farther. Not
    /// tf-idf — just a good-enough ordering.
    private func relevance(_ candidate: String, query q: String, distance: Double?) -> Double {
        var score: Double = 0
        if candidate == q { score += 100 }
        else if candidate.hasPrefix(q) { score += 60 }
        else if candidate.contains(q) { score += 20 }
        if let d = distance {
            // Closer results get bumped, but this is secondary to name match.
            score += max(0, 15 - d / 500) // full 15 pts within 0m, decays at 500m
        }
        return score
    }

    private func distanceFromUser(_ coord: CLLocationCoordinate2D) -> Double? {
        guard let u = userLocation else { return nil }
        return u.distance(from: CLLocation(latitude: coord.latitude, longitude: coord.longitude))
    }
}

struct SearchResult: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let icon: String
    let tint: Color
    let coordinate: CLLocationCoordinate2D
    let score: Double
}
