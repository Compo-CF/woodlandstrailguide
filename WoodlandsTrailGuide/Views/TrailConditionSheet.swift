import SwiftUI
import CoreLocation

/// Submit + browse crowdsourced trail condition reports (flooded, muddy,
/// closed). Anonymous, CloudKit-backed. Opens from the map's "More" menu —
/// if a trail was selected on the map when opened, the report is
/// pre-attributed to it; otherwise it's just pinned to the user's location.
struct TrailConditionSheet: View {
    let wayID: String?
    let wayName: String?
    let userLocation: CLLocation?

    @State private var selectedCondition: CloudKitService.TrailCondition = .muddy
    @State private var note = ""
    @State private var isSubmitting = false
    @State private var submitError: String?
    @State private var didSubmit = false

    @State private var reports: [CloudKitService.ConditionReport] = []
    @State private var isLoadingReports = true
    @State private var loadError: String?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if let wayName {
                        Label(wayName, systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Natural.ink)
                    }
                    Picker("Condition", selection: $selectedCondition) {
                        ForEach(CloudKitService.TrailCondition.allCases) { c in
                            Label(c.label, systemImage: c.systemImage).tag(c)
                        }
                    }
                    .pickerStyle(.inline)
                    TextField("Add a note (optional)", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                } header: {
                    Text("Report a condition")
                } footer: {
                    if userLocation == nil {
                        Text("Location access is needed to pin this report — enable it in Settings.")
                            .foregroundStyle(Natural.route)
                    } else {
                        Text("Reports are anonymous and visible to other users for 14 days.")
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
                                Text("Submit report")
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

                Section("Recent reports nearby") {
                    if isLoadingReports {
                        ProgressView().frame(maxWidth: .infinity)
                    } else if let loadError {
                        Text(loadError)
                            .font(.caption)
                            .foregroundStyle(Natural.inkMuted)
                    } else if reports.isEmpty {
                        Text("No reports in the last 14 days.")
                            .font(.caption)
                            .foregroundStyle(Natural.inkMuted)
                    } else {
                        ForEach(reports) { report in
                            ConditionReportRow(report: report) {
                                Task { try? await CloudKitService.shared.flagReport(recordName: report.recordName) }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Trail Conditions")
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
        .task { await loadReports() }
    }

    private func submit() {
        guard let coord = userLocation?.coordinate else { return }
        isSubmitting = true
        submitError = nil
        Task {
            do {
                try await CloudKitService.shared.submitConditionReport(
                    wayID: wayID, wayName: wayName, condition: selectedCondition,
                    note: note.trimmingCharacters(in: .whitespacesAndNewlines),
                    coordinate: coord
                )
                isSubmitting = false
                didSubmit = true
                note = ""
                await loadReports()
            } catch {
                isSubmitting = false
                submitError = "Couldn't submit — check your connection and try again."
            }
        }
    }

    private func loadReports() async {
        isLoadingReports = true
        loadError = nil
        do {
            reports = try await CloudKitService.shared.fetchRecentConditionReports()
        } catch {
            loadError = "Couldn't load recent reports."
        }
        isLoadingReports = false
    }
}

private struct ConditionReportRow: View {
    let report: CloudKitService.ConditionReport
    let onFlag: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: report.condition.systemImage)
                .foregroundStyle(Natural.route)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(report.wayName ?? report.condition.label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Natural.ink)
                if let note = report.note, !note.isEmpty {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(Natural.inkMuted)
                        .lineLimit(2)
                }
                Text(report.createdAt, format: .relative(presentation: .named))
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
