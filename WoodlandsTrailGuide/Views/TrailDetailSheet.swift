import SwiftUI

struct TrailDetailSheet: View {
    let way: TrailGraph.Way
    @Environment(\.dismiss) private var dismiss
    @Environment(UserDataStore.self) private var userData

    private var miles: Double { way.lengthMeters / 1609.344 }
    private var isFavorited: Bool { userData.isFavorite(way.id) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Length", value: String(format: "%.2f mi", miles))
                    LabeledContent("Type", value: way.kind == "pathway" ? "Paved pathway" : "Natural trail")
                    if let surface = way.surface {
                        LabeledContent("Surface", value: surface.capitalized)
                    }
                }
                if way.village != nil || way.park != nil || way.system != nil {
                    Section("Location") {
                        if let v = way.village { LabeledContent("Village", value: v) }
                        if let p = way.park { LabeledContent("Park", value: p) }
                        if let s = way.system { LabeledContent("System", value: s) }
                    }
                }
                if let parks = way.parks, !parks.isEmpty {
                    Section("Connects to") {
                        ForEach(parks, id: \.self) { park in
                            HStack(spacing: 10) {
                                Image(systemName: "tree.fill")
                                    .foregroundStyle(Color(red: 0.13, green: 0.55, blue: 0.27))
                                    .frame(width: 18)
                                Text(park)
                                Spacer()
                            }
                        }
                    }
                }
                if let pid = way.pathwayID {
                    Section("Township reference") {
                        Text(pid).font(.system(.body, design: .monospaced))
                    }
                }
            }
            .navigationTitle(way.name ?? "Trail segment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        userData.toggleFavorite(way.id)
                    } label: {
                        Image(systemName: isFavorited ? "heart.fill" : "heart")
                            .foregroundStyle(isFavorited ? Natural.route : Natural.forest)
                    }
                    .accessibilityLabel(isFavorited ? "Remove from favorites" : "Add to favorites")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
