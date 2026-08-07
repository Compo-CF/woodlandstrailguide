import SwiftUI
import CoreLocation

/// Sheet for generating a route to hit a target distance or time from the
/// user's current location, with a choice of activity (walk/jog/run —
/// drives the pace used for time-to-distance conversion), path type (any/
/// paved/natural), and shape (loop vs out-and-back). Replaces the old
/// fixed-distance-only LoopBuilderSheet.
struct RoutePlannerSheet: View {
    enum TargetKind: String, CaseIterable, Identifiable {
        case distance
        case time
        var id: String { rawValue }
        var label: String { self == .distance ? "Distance" : "Time" }
    }

    let graph: TrailGraph
    let userLocation: CLLocation
    /// Fired with (startNodeIndex, farNodeIndex, plan). MapTabView plugs
    /// both into its routing state (start = end = start, waypoint = far)
    /// and stores `plan` so updateRoute(graph:) knows to build a genuine
    /// loop (or a surface-aware out-and-back) instead of a plain tap route.
    let onGenerate: (Int, Int, RoutePlan) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var targetKind: TargetKind = .distance
    @State private var selectedMiles: Double = 2
    @State private var selectedMinutes: Double = 30
    @State private var activity: TravelMode = .walk
    @State private var surfacePreference: SurfacePreference = .any
    @State private var shape: PlannedRouteShape = .loop
    @State private var couldNotGenerate = false

    private let mileOptions: [Double] = [1, 2, 3, 5, 6.2, 10]
    private let minuteOptions: [Double] = [15, 20, 30, 45, 60, 90]
    /// Bike is a real TravelMode (nav ETA, HealthKit) but doesn't belong in
    /// a "plan a walk/jog/run" picker — left out deliberately.
    private let activities: [TravelMode] = [.walk, .jog, .run]

    private var targetMeters: Double {
        switch targetKind {
        case .distance: return selectedMiles * 1609.344
        case .time:      return selectedMinutes / 60.0 * activity.paceMph * 1609.344
        }
    }

    /// Live feedback tying the two units together so picking one target
    /// kind still shows roughly what the other would be.
    private var derivedCaption: String {
        switch targetKind {
        case .distance:
            let mins = selectedMiles / activity.paceMph * 60
            return "≈ \(Int(mins.rounded())) min at a \(activity.label.lowercased()) pace (\(paceString) mph)"
        case .time:
            let miles = selectedMinutes / 60.0 * activity.paceMph
            return "≈ \(String(format: "%.1f", miles)) mi at a \(activity.label.lowercased()) pace (\(paceString) mph)"
        }
    }

    private var paceString: String { String(format: "%.1f", activity.paceMph) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    Image(systemName: "target")
                        .font(.system(size: 52, weight: .light))
                        .foregroundStyle(Natural.forest)
                        .padding(.top, 20)

                    VStack(spacing: 6) {
                        Text("Plan a walk, jog, or run")
                            .font(.title3.bold())
                            .foregroundStyle(Natural.ink)
                        Text("Set a target and we'll build a route to match, starting from where you are.")
                            .font(.callout)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(Natural.inkMuted)
                            .padding(.horizontal, 28)
                    }

                    section("Target") {
                        chipRow(TargetKind.allCases, selection: $targetKind) { $0.label }
                        if targetKind == .distance {
                            chipRow(mileOptions, selection: $selectedMiles) { formatMiles($0) }
                        } else {
                            chipRow(minuteOptions, selection: $selectedMinutes) { "\(Int($0)) min" }
                        }
                        Text(derivedCaption)
                            .font(.caption)
                            .foregroundStyle(Natural.inkMuted)
                    }

                    section("Activity") {
                        chipRow(activities, selection: $activity) { $0.label }
                    }

                    section("Path type") {
                        chipRow(SurfacePreference.allCases, selection: $surfacePreference) { $0.label }
                    }

                    section("Shape") {
                        chipRow(PlannedRouteShape.allCases, selection: $shape) { $0.label }
                        Text(shape.blurb)
                            .font(.caption)
                            .foregroundStyle(Natural.inkMuted)
                    }

                    if couldNotGenerate {
                        Text("Couldn't find a route that long near you — try a shorter target.")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Natural.route)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }

                    Button {
                        generate()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: activity.systemImage)
                            Text("Generate route")
                        }
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Natural.forest, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                }
            }
            .background(Natural.cardBg)
            .navigationTitle("Plan a Route")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    // MARK: - Layout helpers

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Natural.inkMuted)
                .tracking(0.6)
            content()
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func chipRow<T: Hashable>(_ options: [T], selection: Binding<T>, label: @escaping (T) -> String) -> some View {
        FlowChips(options: options, selection: selection, label: label)
    }

    private func formatMiles(_ m: Double) -> String {
        m == m.rounded() ? "\(Int(m)) mi" : String(format: "%.1f mi", m)
    }

    // MARK: - Generate

    private func generate() {
        couldNotGenerate = false
        let router = Router(graph: graph)
        guard let start = router.nearestNode(to: userLocation.coordinate),
              targetMeters > 0,
              let far = router.farthestNode(
                from: start,
                atRouteDistance: targetMeters / 2,
                surfacePreference: surfacePreference
              ) else {
            couldNotGenerate = true
            return
        }
        let plan = RoutePlan(shape: shape, surfacePreference: surfacePreference,
                              targetMeters: targetMeters, activity: activity)
        onGenerate(start, far, plan)
        dismiss()
    }
}

/// A grid of selectable pill chips that wraps onto multiple rows — used for
/// every choice group in RoutePlannerSheet (target kind, distance/time,
/// activity, path type, shape) so they share one visual language.
private struct FlowChips<T: Hashable>: View {
    let options: [T]
    @Binding var selection: T
    let label: (T) -> String

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 78), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(options, id: \.self) { option in
                Button {
                    selection = option
                } label: {
                    Text(label(option))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(selection == option ? .white : Natural.forest)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            selection == option ? Natural.forest : Natural.chipBg,
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}
