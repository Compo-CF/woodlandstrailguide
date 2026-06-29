import SwiftUI

struct AboutTabView: View {
    @Environment(TrailStore.self) private var store

    var body: some View {
        NavigationStack {
            List {
                Section("About this app") {
                    Text("A community-built map of The Woodlands' hike-and-bike pathways. Built by a local on weekends — feedback welcome.")
                        .font(.callout)
                }
                Section("Data") {
                    Text("Pathway and trail data is sourced from The Woodlands Township GIS public services. The app refreshes its local copy every launch so newly-added trails appear automatically.")
                        .font(.callout)
                    if let g = store.graph {
                        LabeledContent("Source", value: g.source)
                            .lineLimit(2)
                            .font(.caption)
                    }
                }
                Section("Support the developer") {
                    Link("Buy me a coffee on Ko-fi", destination: URL(string: "https://ko-fi.com/subtlefoodie")!)
                }
                Section {
                    Text("Trail data © The Woodlands Township.\nApp by Anthony Compofelice.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("About")
        }
    }
}
