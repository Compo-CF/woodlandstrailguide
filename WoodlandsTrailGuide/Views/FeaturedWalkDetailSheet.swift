import SwiftUI
import CoreLocation

/// Full-detail sheet for a Featured Walk. Shows all metadata + highlights,
/// and a big "Walk this route" button that hands the waypoints off to
/// MapTabView via RoutingBridge.pending. ContentView watches the same value
/// and flips to the Map tab in the same frame so the user lands on the
/// routed map.
struct FeaturedWalkDetailSheet: View {
    let walk: FeaturedWalk
    @Environment(\.dismiss) private var dismiss
    @Environment(RoutingBridge.self) private var routingBridge

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    statPillsRow
                    descriptionBlock
                    locationBlock
                    highlightsBlock
                    whenToGoBlock
                    curatorBlock
                    walkButton
                    Spacer(minLength: 24)
                }
                .padding(.top, 16)
            }
            .background(Natural.cardBg)
            .navigationTitle(walk.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private var statPillsRow: some View {
        HStack(spacing: 10) {
            statPill(icon: "figure.walk",
                     text: String(format: "%.1f mi", walk.distanceMiles),
                     tint: Natural.forest)
            if let gain = walk.elevationGainFeet, gain > 0 {
                statPill(icon: "arrow.up.right",
                         text: "\(Int(gain)) ft up",
                         tint: Natural.forest)
            }
            statPill(icon: "figure.hiking",
                     text: walk.difficulty.label,
                     tint: difficultyColor)
            Spacer()
        }
        .padding(.horizontal, 20)
    }

    private var descriptionBlock: some View {
        Text(walk.description)
            .font(.callout)
            .foregroundStyle(Natural.ink)
            .padding(.horizontal, 20)
    }

    @ViewBuilder
    private var locationBlock: some View {
        if walk.village != nil || walk.park != nil {
            VStack(alignment: .leading, spacing: 6) {
                sectionTitle("Location")
                if let village = walk.village {
                    labeledRow("Village", value: village, icon: "house")
                }
                if let park = walk.park {
                    labeledRow("Park", value: park, icon: "tree.fill")
                }
            }
            .padding(.horizontal, 20)
        }
    }

    @ViewBuilder
    private var highlightsBlock: some View {
        if !walk.highlights.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("Highlights")
                ForEach(walk.highlights, id: \.self) { highlight in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "sparkle")
                            .font(.caption)
                            .foregroundStyle(Natural.forest)
                            .padding(.top, 3)
                        Text(highlight)
                            .font(.callout)
                            .foregroundStyle(Natural.ink)
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }

    @ViewBuilder
    private var whenToGoBlock: some View {
        if walk.bestTime != nil || walk.seasonality != nil {
            VStack(alignment: .leading, spacing: 6) {
                sectionTitle("When to go")
                if let best = walk.bestTime {
                    labeledRow("Best time", value: best, icon: "clock")
                }
                if let season = walk.seasonality {
                    labeledRow("Season", value: season, icon: "leaf")
                }
            }
            .padding(.horizontal, 20)
        }
    }

    @ViewBuilder
    private var curatorBlock: some View {
        if let curator = walk.curatedBy {
            Text("Curated by \(curator)")
                .font(.caption)
                .foregroundStyle(Natural.inkMuted)
                .padding(.horizontal, 20)
        }
    }

    private var walkButton: some View {
        Button {
            loadThisWalk()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "point.topleft.down.to.point.bottomright.curvepath.fill")
                Text("Walk this route")
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Natural.route, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
    }

    private func loadThisWalk() {
        guard walk.waypoints.count >= 2 else { return }
        let stops = walk.waypoints.map {
            CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon)
        }
        routingBridge.pending = RoutingBridge.PendingRoute(
            start: stops.first!,
            end: stops.last!,
            waypoints: Array(stops.dropFirst().dropLast())
        )
        dismiss()
    }

    private var difficultyColor: Color {
        let c = walk.difficulty.rgb
        return Color(red: c.r, green: c.g, blue: c.b)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Natural.ink)
    }

    private func statPill(icon: String, text: String, tint: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.caption)
            Text(text).font(.caption.weight(.semibold))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(tint.opacity(0.12), in: Capsule())
    }

    private func labeledRow(_ label: String, value: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(Natural.forest)
                .frame(width: 16)
            Text(label + ":")
                .font(.callout)
                .foregroundStyle(Natural.inkMuted)
            Text(value)
                .font(.callout)
                .foregroundStyle(Natural.ink)
            Spacer()
        }
    }
}
