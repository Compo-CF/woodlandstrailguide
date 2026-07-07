import SwiftUI

/// A grouped, searchable list of named trails. Unnamed connector segments
/// are aggregated by village so the list stays usable; tap a village to see
/// what's there.
///
/// Favorites: the toolbar heart toggles a "favorites only" filter. When on,
/// only trails the user has hearted from `TrailDetailSheet` are shown, in
/// their own single section. When off, favorites still appear at the top
/// of the normal grouping so they're easy to find.
struct ListTabView: View {
    @Environment(TrailStore.self) private var store
    @Environment(UserDataStore.self) private var userData
    @State private var search = ""
    @State private var selectedWay: TrailGraph.Way?
    @State private var favoritesOnly = false

    var body: some View {
        NavigationStack {
            Group {
                if let graph = store.graph {
                    list(for: graph)
                } else {
                    ProgressView("Loading trails...")
                }
            }
            .navigationTitle("Trails")
            .searchable(text: $search, prompt: "Search trails, villages, parks")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        favoritesOnly.toggle()
                    } label: {
                        Image(systemName: favoritesOnly ? "heart.fill" : "heart")
                            .foregroundStyle(favoritesOnly ? Natural.route : Natural.forest)
                    }
                    .accessibilityLabel(favoritesOnly ? "Show all trails" : "Show favorites only")
                }
            }
            .sheet(item: $selectedWay) { way in
                TrailDetailSheet(way: way)
            }
        }
    }

    @ViewBuilder
    private func list(for graph: TrailGraph) -> some View {
        let favorites = favoriteWays(graph: graph, query: search)
        let groups = grouped(graph: graph, query: search)

        if favoritesOnly {
            if favorites.isEmpty {
                emptyFavoritesState
            } else {
                List {
                    Section("Favorites") {
                        ForEach(favorites) { way in
                            trailRow(way: way)
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        } else {
            List {
                if !favorites.isEmpty {
                    Section("Favorites") {
                        ForEach(favorites) { way in
                            trailRow(way: way)
                        }
                    }
                }
                ForEach(groups, id: \.title) { group in
                    Section(group.title) {
                        ForEach(group.ways) { way in
                            trailRow(way: way)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    private func trailRow(way: TrailGraph.Way) -> some View {
        Button {
            selectedWay = way
        } label: {
            HStack {
                if userData.isFavorite(way.id) {
                    Image(systemName: "heart.fill")
                        .font(.caption)
                        .foregroundStyle(Natural.route)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(way.name ?? "Unnamed segment")
                        .foregroundStyle(.primary)
                    if let s = way.surface {
                        Text(s.capitalized).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text(String(format: "%.2f mi", way.lengthMeters / 1609.344))
                    .foregroundStyle(.secondary)
                    .font(.subheadline.monospacedDigit())
            }
        }
    }

    private var emptyFavoritesState: some View {
        VStack(spacing: 12) {
            Image(systemName: "heart.slash")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(Natural.inkMuted)
            Text("No favorites yet")
                .font(.headline)
                .foregroundStyle(Natural.ink)
            Text("Tap the heart on any trail to save it here for quick access.")
                .font(.callout)
                .foregroundStyle(Natural.inkMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private struct TrailBucket { let title: String; let ways: [TrailGraph.Way] }

    /// Named ways matching the search query.
    private func matching(graph: TrailGraph, query: String) -> [TrailGraph.Way] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let named = graph.ways.filter { $0.name != nil }
        return q.isEmpty ? named : named.filter {
            ($0.name ?? "").lowercased().contains(q)
                || ($0.village ?? "").lowercased().contains(q)
                || ($0.park ?? "").lowercased().contains(q)
                || ($0.system ?? "").lowercased().contains(q)
        }
    }

    private func favoriteWays(graph: TrailGraph, query: String) -> [TrailGraph.Way] {
        matching(graph: graph, query: query)
            .filter { userData.isFavorite($0.id) }
            .sorted { ($0.name ?? "") < ($1.name ?? "") }
    }

    private func grouped(graph: TrailGraph, query: String) -> [TrailBucket] {
        var buckets: [String: [TrailGraph.Way]] = [:]
        for w in matching(graph: graph, query: query) {
            let key = w.village ?? w.park ?? w.system ?? "Other"
            buckets[key, default: []].append(w)
        }
        return buckets
            .map { TrailBucket(title: $0.key, ways: $0.value.sorted { ($0.name ?? "") < ($1.name ?? "") }) }
            .sorted { $0.title < $1.title }
    }
}
