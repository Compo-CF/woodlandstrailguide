import SwiftUI

/// A grouped, searchable list of named trails, sectioned by village/park/
/// system. The Township GIS data splits most named trails into many small
/// Way segments, so rows are grouped by name (NamedTrailGroup) rather than
/// listed one-per-segment — a trail with several segments shows one row
/// with the combined distance and drills into TrailSegmentsSheet; a
/// single-segment trail (the common case) goes straight to
/// TrailDetailSheet, same as before this grouping existed.
///
/// Favorites: the toolbar heart toggles a "favorites only" filter. When on,
/// only trails the user has hearted from `TrailDetailSheet` are shown, in
/// their own single section. When off, favorites still appear at the top
/// of the normal grouping so they're easy to find. The favorites section
/// stays per-segment (not grouped by name) since favoriting is itself a
/// per-segment action.
struct ListTabView: View {
    @Environment(TrailStore.self) private var store
    @Environment(UserDataStore.self) private var userData
    @State private var search = ""
    @State private var selectedWay: TrailGraph.Way?
    @State private var selectedGroup: NamedTrailGroup?
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
            .sheet(item: $selectedGroup) { group in
                TrailSegmentsSheet(group: group)
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
                ForEach(groups, id: \.title) { bucket in
                    Section(bucket.title) {
                        ForEach(bucket.groups) { group in
                            trailGroupRow(group: group)
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

    /// One row per distinct trail NAME, not per raw Way segment — the
    /// Township data splits most named trails into many small segments,
    /// which used to show up as a run of identical-looking rows with no
    /// way to tell them apart. Shows the combined distance across every
    /// segment; single-segment trails (the common case) skip the extra
    /// drill-down tap and go straight to TrailDetailSheet, same as before.
    private func trailGroupRow(group: NamedTrailGroup) -> some View {
        Button {
            if group.ways.count == 1 {
                selectedWay = group.ways[0]
            } else {
                selectedGroup = group
            }
        } label: {
            HStack {
                if group.ways.contains(where: { userData.isFavorite($0.id) }) {
                    Image(systemName: "heart.fill")
                        .font(.caption)
                        .foregroundStyle(Natural.route)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.name)
                        .foregroundStyle(.primary)
                    if group.ways.count > 1 {
                        Text("\(group.ways.count) segments")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if let s = group.ways[0].surface {
                        Text(s.capitalized).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text(String(format: "%.2f mi", group.totalMeters / 1609.344))
                    .foregroundStyle(.secondary)
                    .font(.subheadline.monospacedDigit())
                if group.ways.count > 1 {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
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

    private struct TrailBucket { let title: String; let groups: [NamedTrailGroup] }

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
            .map { key, ways in TrailBucket(title: key, groups: namedGroups(from: ways)) }
            .sorted { $0.title < $1.title }
    }

    /// Collapses every Way sharing the same name into one NamedTrailGroup.
    /// `matching()` already filters to named ways only, so `name` is always
    /// non-nil here.
    private func namedGroups(from ways: [TrailGraph.Way]) -> [NamedTrailGroup] {
        var byName: [String: [TrailGraph.Way]] = [:]
        for w in ways {
            byName[w.name ?? "", default: []].append(w)
        }
        return byName
            .map { NamedTrailGroup(name: $0.key, ways: $0.value) }
            .sorted { $0.name < $1.name }
    }
}

/// One or more Way segments that share a display name — the Township GIS
/// data routinely splits a single named trail into many small segments.
struct NamedTrailGroup: Identifiable, Hashable {
    let name: String
    let ways: [TrailGraph.Way]
    var id: String { name }
    var totalMeters: Double { ways.reduce(0) { $0 + $1.lengthMeters } }

    static func == (lhs: NamedTrailGroup, rhs: NamedTrailGroup) -> Bool { lhs.name == rhs.name }
    func hash(into hasher: inout Hasher) { hasher.combine(name) }
}
