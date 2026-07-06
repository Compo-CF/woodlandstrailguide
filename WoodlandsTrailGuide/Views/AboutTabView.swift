import SwiftUI

struct AboutTabView: View {
    @Environment(TrailStore.self) private var store
    @Environment(UserDataStore.self) private var userData
    @Environment(LocationManager.self) private var locationManager
    @State private var showingReport = false

    private let fishingGuideURL = URL(string: "https://apps.apple.com/app/id6773501518")!
    private let supportURL = URL(string: "https://compo-cf.github.io/woodlandstrailguide/support.html")!

    var body: some View {
        NavigationStack {
            List {
                Section("About this app") {
                    Text("A community-built map of The Woodlands' hike-and-bike pathways. Built by a local on weekends — feedback welcome.")
                        .font(.callout)
                }

                Section("Also from this developer") {
                    Link(destination: fishingGuideURL) {
                        HStack(spacing: 12) {
                            Image(systemName: "fish.fill")
                                .font(.title3)
                                .foregroundStyle(.white)
                                .frame(width: 42, height: 42)
                                .background(
                                    Color(red: 0.04, green: 0.42, blue: 0.45),
                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                                )
                            VStack(alignment: .leading, spacing: 2) {
                                Text("The Woodlands Fishing Guide")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Natural.ink)
                                Text("The same trail-guide treatment for 80+ fishing spots across Montgomery County.")
                                    .font(.caption)
                                    .foregroundStyle(Natural.inkMuted)
                                    .lineLimit(2)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "arrow.up.right.square")
                                .font(.footnote)
                                .foregroundStyle(Natural.inkMuted)
                        }
                        .padding(.vertical, 2)
                    }
                }

                if !userData.tripLog.isEmpty {
                    Section("Recent walks") {
                        ForEach(userData.tripLog.prefix(10)) { trip in
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(String(format: "%.2f mi", trip.miles))
                                        .font(.subheadline.weight(.semibold))
                                        .monospacedDigit()
                                    Spacer()
                                    Text(trip.date, format: .dateTime.day().month().year(.twoDigits))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .monospacedDigit()
                                }
                                Text("\(trip.startLabel) → \(trip.endLabel)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .padding(.vertical, 2)
                        }
                        .onDelete { indexSet in
                            let toDelete = indexSet.map { userData.tripLog[$0].id }
                            for id in toDelete { userData.deleteTrip(id: id) }
                        }
                    }
                }

                Section("Data") {
                    Text("Pathway, trail, and amenity data is sourced from The Woodlands Township GIS public services. The app refreshes its local copy every launch so newly-added trails appear automatically.")
                        .font(.callout)
                    if let g = store.graph {
                        LabeledContent("Source", value: g.source)
                            .lineLimit(2)
                            .font(.caption)
                    }
                }

                Section("Help & feedback") {
                    Button {
                        showingReport = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.bubble")
                                .foregroundStyle(Natural.route)
                            Text("Report a problem")
                                .foregroundStyle(Natural.ink)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    Link(destination: supportURL) {
                        HStack(spacing: 8) {
                            Image(systemName: "questionmark.circle")
                                .foregroundStyle(Natural.forest)
                            Text("Support & FAQ")
                                .foregroundStyle(Natural.ink)
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

                Section {
                    Text("Trail data © The Woodlands Township.\nApp by Anthony Compofelice.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("About")
            .sheet(isPresented: $showingReport) {
                ReportProblemSheet(userLocation: locationManager.location)
            }
        }
    }
}
