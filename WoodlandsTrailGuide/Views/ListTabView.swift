import SwiftUI

/// A grouped, searchable list of named trails. Unnamed connector segments
/// are aggregated by village so the list stays usable; tap a village to see
/// what's there.
struct ListTabView: View {
    @Environment(TrailStore.self) private var store
    @State private var search = ""
    @State private var selectedWay: TrailGraph.Way?

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
            .sheet(item: $selectedWay) { way in
                TrailDetailSheet(way: way)
            }
        }
    }

    private func list(for graph: TrailGraph) -> some View {
        let groups = grouped(graph: graph, query: search)
        return List {
            ForEach(groups, id: \.title) { group in
                Section(group.title) {
                    ForEach(group.ways) { way in
                        Button {
                            selectedWay = way
                        } label: {
                            HStack {
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
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private struct TrailBucket { let title: String; let ways: [TrailGraph.Way] }

    private func grouped(graph: TrailGraph, query: String) -> [TrailBucket] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let named = graph.ways.filter { $0.name != nil }
        let filtered = q.isEmpty ? named : named.filter {
            ($0.name ?? "").lowercased().contains(q)
                || ($0.village ?? "").lowercased().contains(q)
                || ($0.park ?? "").lowercased().contains(q)
                || ($0.system ?? "").lowercased().contains(q)
        }
        var buckets: [String: [TrailGraph.Way]] = [:]
        for w in filtered {
            let key = w.village ?? w.park ?? w.system ?? "Other"
            buckets[key, default: []].append(w)
        }
        return buckets
            .map { TrailBucket(title: $0.key, ways: $0.value.sorted { ($0.name ?? "") < ($1.name ?? "") }) }
            .sorted { $0.title < $1.title }
    }
}
