import SwiftUI
import MessageUI
import CoreLocation

/// Small form for users to flag a data problem — flooded pathway, closed
/// bridge, mislabeled trail, missing amenity. Composes an email via
/// MFMailComposeViewController so the report lands in Anthony's inbox and
/// there's no backend to run for v1.
struct ReportProblemSheet: View {
    let userLocation: CLLocation?

    @Environment(\.dismiss) private var dismiss

    @State private var category: ProblemCategory = .other
    @State private var description: String = ""
    @State private var showingMailComposer = false
    @State private var showingMailUnavailable = false

    private let recipient = "anthony.compofelice@centricfiber.com"

    var body: some View {
        NavigationStack {
            Form {
                Section("What's the issue?") {
                    Picker("Category", selection: $category) {
                        ForEach(ProblemCategory.allCases) { c in
                            Text(c.label).tag(c)
                        }
                    }
                }
                Section("Details") {
                    TextEditor(text: $description)
                        .frame(minHeight: 120)
                }
                if let loc = userLocation {
                    Section("Location") {
                        LabeledContent("Latitude", value: String(format: "%.5f", loc.coordinate.latitude))
                            .monospacedDigit()
                        LabeledContent("Longitude", value: String(format: "%.5f", loc.coordinate.longitude))
                            .monospacedDigit()
                        Text("Sent along with your report so we can pinpoint the spot.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Section {
                    Button {
                        if MFMailComposeViewController.canSendMail() {
                            showingMailComposer = true
                        } else {
                            showingMailUnavailable = true
                        }
                    } label: {
                        HStack {
                            Image(systemName: "paperplane.fill")
                            Text("Send report")
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Natural.forest)
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .navigationTitle("Report a problem")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $showingMailComposer) {
                MailComposeView(
                    recipient: recipient,
                    subject: "Trail Guide report: \(category.label)",
                    body: composedBody(),
                    onSent: { dismiss() }
                )
            }
            .alert("Email not set up", isPresented: $showingMailUnavailable) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("This device doesn't have Mail configured. Please email \(recipient) directly with your report.")
            }
        }
    }

    private func composedBody() -> String {
        var lines: [String] = []
        lines.append("Category: \(category.label)")
        if let loc = userLocation {
            lines.append(String(format: "Location: %.5f, %.5f",
                                loc.coordinate.latitude, loc.coordinate.longitude))
            lines.append("Google Maps: https://maps.google.com/?q=\(loc.coordinate.latitude),\(loc.coordinate.longitude)")
        }
        lines.append("")
        lines.append("Details:")
        lines.append(description)
        lines.append("")
        lines.append("---")
        lines.append("Sent from Woodlands Trail Guide")
        return lines.joined(separator: "\n")
    }
}

enum ProblemCategory: String, CaseIterable, Identifiable {
    case flooded
    case closed
    case obstruction
    case missingTrail = "missing_trail"
    case mislabeled
    case amenity
    case other

    var id: String { rawValue }
    var label: String {
        switch self {
        case .flooded:      return "Flooded pathway"
        case .closed:       return "Closed / blocked"
        case .obstruction:  return "Fallen tree or obstruction"
        case .missingTrail: return "Trail missing from map"
        case .mislabeled:   return "Name or label is wrong"
        case .amenity:      return "Amenity issue (restroom, bench, etc.)"
        case .other:        return "Something else"
        }
    }
}

/// Bridges MFMailComposeViewController into SwiftUI. iOS 17+ has no first-
/// party SwiftUI mail composer, so this UIKit representable is the norm.
struct MailComposeView: UIViewControllerRepresentable {
    let recipient: String
    let subject: String
    let body: String
    let onSent: () -> Void

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let vc = MFMailComposeViewController()
        vc.mailComposeDelegate = context.coordinator
        vc.setToRecipients([recipient])
        vc.setSubject(subject)
        vc.setMessageBody(body, isHTML: false)
        return vc
    }

    func updateUIViewController(_ vc: MFMailComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onSent: onSent) }

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let onSent: () -> Void
        init(onSent: @escaping () -> Void) { self.onSent = onSent }

        func mailComposeController(_ controller: MFMailComposeViewController,
                                   didFinishWith result: MFMailComposeResult,
                                   error: Error?) {
            controller.dismiss(animated: true) {
                if result == .sent { self.onSent() }
            }
        }
    }
}
