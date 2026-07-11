import SwiftUI

/// Discovery tab listing curator-managed "Featured Walks". Users tap a card
/// to open the detail sheet; from there they can start the route with one
/// tap (which hands off to MapTabView via RoutingBridge.pending).
struct FeaturedTabView: View {
    @Environment(FeaturedWalkStore.self) private var walkStore
    @State private var selectedWalk: FeaturedWalk?
    @State private var isRefreshing = false

    var body: some View {
        NavigationStack {
            Group {
                if walkStore.walks.isEmpty {
                    emptyState
                } else {
                    walksList
                }
            }
            .navigationTitle("Featured Walks")
            .sheet(item: $selectedWalk) { walk in
                FeaturedWalkDetailSheet(walk: walk)
            }
        }
    }

    private var walksList: some View {
        List(walkStore.walks) { walk in
            Button {
                selectedWalk = walk
            } label: {
                walkCard(walk)
            }
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
        }
        .listStyle(.plain)
        .refreshable {
            await walkStore.refresh()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "star.circle")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(Natural.inkMuted)
            Text("Loading featured walks…")
                .font(.callout)
                .foregroundStyle(Natural.inkMuted)
            if let err = walkStore.loadError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func walkCard(_ walk: FeaturedWalk) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Text(walk.name)
                    .font(.headline)
                    .foregroundStyle(Natural.ink)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                difficultyChip(walk.difficulty)
            }

            Text(walk.description)
                .font(.footnote)
                .foregroundStyle(Natural.inkMuted)
                .multilineTextAlignment(.leading)
                .lineLimit(3)

            HStack(spacing: 14) {
                metaLabel(String(format: "%.1f mi", walk.distanceMiles),
                          icon: "figure.walk")
                if let gain = walk.elevationGainFeet, gain > 0 {
                    metaLabel("\(Int(gain)) ft up", icon: "arrow.up.right")
                }
                if let village = walk.village {
                    metaLabel(village, icon: "mappin.and.ellipse")
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Natural.cardBg, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Natural.hairline, lineWidth: 0.5)
        )
    }

    private func metaLabel(_ text: String, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text(text)
                .font(.caption)
        }
        .foregroundStyle(Natural.inkMuted)
    }

    private func difficultyChip(_ difficulty: DifficultyRating) -> some View {
        let c = difficulty.rgb
        return Text(difficulty.label)
            .font(.caption2.weight(.bold))
            .textCase(.uppercase)
            .tracking(0.4)
            .foregroundStyle(.white)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Color(red: c.r, green: c.g, blue: c.b), in: Capsule())
    }
}
