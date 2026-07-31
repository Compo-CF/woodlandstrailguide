import SwiftUI

/// Shown when a trail name in the Trails tab groups more than one Way
/// segment — lists each segment individually (village, surface, length)
/// so the user can drill into the specific piece they care about. Owns its
/// own TrailDetailSheet presentation rather than delegating back to the
/// parent, since SwiftUI can't cleanly present two sibling sheets from one
/// view's state at once.
struct TrailSegmentsSheet: View {
    let group: NamedTrailGroup
    @Environment(\.dismiss) private var dismiss
    @Environment(UserDataStore.self) private var userData
    @State private var selectedWay: TrailGraph.Way?

    private var totalMiles: Double { group.totalMeters / 1609.344 }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Total length", value: String(format: "%.2f mi", totalMiles))
                    LabeledContent("Segments", value: "\(group.ways.count)")
                }
                Section("Segments") {
                    ForEach(Array(group.ways.enumerated()), id: \.offset) { index, way in
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
                                    Text("Segment \(index + 1)")
                                        .foregroundStyle(.primary)
                                    if let s = way.surface {
                                        Text(s.capitalized).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Text(String(format: "%.2f mi", way.lengthMeters / 1609.344))
                                    .foregroundStyle(.secondary)
                                    .font(.subheadline.monospacedDigit())
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            }
            .navigationTitle(group.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $selectedWay) { way in
                TrailDetailSheet(way: way)
            }
        }
    }
}
