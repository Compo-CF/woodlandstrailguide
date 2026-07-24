import SwiftUI
import CoreLocation

/// Submit + browse crowdsourced wildlife sightings (alligators, snakes,
/// deer, birds of prey). Anonymous, CloudKit-backed, same moderation
/// mechanism as TrailConditionSheet. Opens from the map's "More" menu.
struct WildlifeSightingSheet: View {
    let userLocation: CLLocation?

    @State private var selectedCategory: CloudKitService.WildlifeCategory = .alligator
    @State private var note = ""
    @State private var isSubmitting = false
    @State private var submitError: String?
    @State private var didSubmit = false

    @State private var sightings: [CloudKitService.WildlifeSightingReport] = []
    @State private var isLoadingSightings = true
    @State private var loadError: String?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Category", selection: $selectedCategory) {
                        ForEach(CloudKitService.WildlifeCategory.allCases) { c in
                            Label(c.label, systemImage: c.systemImage).tag(c)
                        }
                    }
                    .pickerStyle(.inline)
                    TextField("Add a note (optional)", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                } header: {
                    Text("Report a sighting")
                } footer: {
                    if userLocation == nil {
                        Text("Location access is needed to pin this sighting — enable it in Settings.")
                            .foregroundStyle(Natural.route)
                    } else {
                        Text("Sightings are anonymous and visible to other users for 30 days.")
                    }
                }

                Section {
                    Button {
                        submit()
                    } label: {
                        HStack {
                            Spacer()
                            if isSubmitting {
                                ProgressView()
                            } else {
                                Text("Submit sighting")
                                    .font(.subheadline.weight(.semibold))
                            }
                            Spacer()
                        }
                    }
                    .disabled(isSubmitting || userLocation == nil)
                    if let submitError {
                        Text(submitError)
                            .font(.caption)
                            .foregroundStyle(Natural.route)
                    }
                }

                Section("Recent sightings nearby") {
                    if isLoadingSightings {
                        ProgressView().frame(maxWidth: .infinity)
                    } else if let loadError {
                        Text(loadError)
                            .font(.caption)
                            .foregroundStyle(Natural.inkMuted)
                    } else if sightings.isEmpty {
                        Text("No sightings reported in the last 30 days.")
                            .font(.caption)
                            .foregroundStyle(Natural.inkMuted)
                    } else {
                        ForEach(sightings) { sighting in
                            WildlifeSightingRow(sighting: sighting) {
                                Task { try? await CloudKitService.shared.flagReport(recordName: sighting.recordName) }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Wildlife Sightings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Thanks for the report", isPresented: $didSubmit) {
                Button("OK", role: .cancel) {}
            }
        }
        .task { await loadSightings() }
    }

    private func submit() {
        guard let coord = userLocation?.coordinate else { return }
        isSubmitting = true
        submitError = nil
        Task {
            do {
                try await CloudKitService.shared.submitWildlifeSighting(
                    category: selectedCategory,
                    note: note.trimmingCharacters(in: .whitespacesAndNewlines),
                    coordinate: coord
                )
                isSubmitting = false
                didSubmit = true
                note = ""
                await loadSightings()
            } catch {
                isSubmitting = false
                submitError = "Couldn't submit — check your connection and try again."
            }
        }
    }

    private func loadSightings() async {
        isLoadingSightings = true
        loadError = nil
        do {
            sightings = try await CloudKitService.shared.fetchRecentWildlifeSightings()
        } catch {
            loadError = "Couldn't load recent sightings."
        }
        isLoadingSightings = false
    }
}

private struct WildlifeSightingRow: View {
    let sighting: CloudKitService.WildlifeSightingReport
    let onFlag: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: sighting.category.systemImage)
                .foregroundStyle(Natural.forest)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(sighting.category.label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Natural.ink)
                if let note = sighting.note, !note.isEmpty {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(Natural.inkMuted)
                        .lineLimit(2)
                }
                Text(sighting.createdAt, format: .relative(presentation: .named))
                    .font(.caption2)
                    .foregroundStyle(Natural.inkMuted)
            }
            Spacer()
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive, action: onFlag) {
                Label("Report", systemImage: "flag")
            }
        }
    }
}
