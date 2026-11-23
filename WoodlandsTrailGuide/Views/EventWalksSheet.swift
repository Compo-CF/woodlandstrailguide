import SwiftUI

/// Card at the top of the Featured tab while a seasonal event is upcoming or
/// live (WalkEventStore.featuredEvents).
struct EventBannerCard: View {
    let event: WalkEvent

    var body: some View {
        let live = event.phase() == .live
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                Text(live ? "LIMITED-TIME EVENT" : "COMING \(event.dateRangeLabel.uppercased())")
                    .tracking(0.6)
            }
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white.opacity(0.9))

            Text(event.title)
                .font(NaturalType.display(24, weight: .bold, relativeTo: .title2))
                .foregroundStyle(.white)
                .multilineTextAlignment(.leading)

            Text(event.tagline)
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.9))
                .multilineTextAlignment(.leading)

            HStack(spacing: 6) {
                Text("\(event.walks.count) walks · \(event.dateRangeLabel)")
                Spacer()
                Image(systemName: "chevron.right")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [Natural.forest, Color(red: 0.07, green: 0.21, blue: 0.12)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .accessibilityElement(children: .combine)
    }
}

/// The event's walk list. Reached from the Featured tab card or the
/// `woodlandstrailguide://event/...` deep link on the App Store event card.
struct EventWalksSheet: View {
    let event: WalkEvent
    @Environment(\.dismiss) private var dismiss
    @Environment(WalkEventStore.self) private var eventStore
    @State private var selectedWalk: FeaturedWalk?

    var body: some View {
        NavigationStack {
            List {
                header
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                ForEach(event.walks) { walk in
                    Button {
                        selectedWalk = walk
                    } label: {
                        FeaturedWalkCard(walk: walk)
                    }
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                }
            }
            .listStyle(.plain)
            .navigationTitle(event.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
            .sheet(item: $selectedWalk) { walk in
                // "Walk this route" closes this sheet too, so the user lands
                // on the routed map instead of behind two sheets.
                FeaturedWalkDetailSheet(walk: walk, onStart: {
                    eventStore.showRequested = false
                })
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(statusLine)
                .font(.caption.weight(.bold))
                .tracking(0.5)
                .foregroundStyle(Natural.forest)
            Text(event.tagline)
                .font(.callout)
                .foregroundStyle(Natural.ink)
            Text("Pick a route, tap Walk this route, and the map plans it on the pathway network from start to finish.")
                .font(.footnote)
                .foregroundStyle(Natural.inkMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statusLine: String {
        switch event.phase() {
        case .live: return "FEATURED \(event.dateRangeLabel.uppercased())"
        case .hidden, .upcoming: return "STARTS \(event.dateRangeLabel.uppercased()) · PREVIEW"
        case .ended: return "THIS EVENT HAS ENDED · ROUTES STILL WALKABLE"
        }
    }
}
