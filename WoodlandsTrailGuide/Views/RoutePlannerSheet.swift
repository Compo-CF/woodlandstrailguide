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
    /// The user's live location, if we have a fix. Optional now — Address
    /// and Tap on Map starting points don't need one, so a missing fix no
    /// longer blocks the whole sheet (see MapTabView's presentation logic).
    let userLocation: CLLocation?
    /// Restores every selection (including a previously-picked starting
    /// point) when the sheet reopens after the user chose "Tap on Map" and
    /// left to tap the map. Nil for a fresh, from-scratch open.
    var initialDraft: RouteDraft? = nil
    /// Fired with (startNodeIndex, farNodeIndex, plan). MapTabView plugs
    /// both into its routing state (start = end = start, waypoint = far)
    /// and stores `plan` so updateRoute(graph:) knows to build a genuine
    /// loop (or a surface-aware out-and-back) instead of a plain tap route.
    let onGenerate: (Int, Int, RoutePlan) -> Void
    /// Fired when the user taps "Choose point on map" (or "Change") in the
    /// Tap on Map panel. MapTabView dismisses this sheet, drops the map into
    /// a one-shot "tap to set start" mode, and reopens the sheet (with the
    /// draft passed back as `initialDraft`) once a tap lands.
    let onRequestMapTap: (RouteDraft) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var targetKind: TargetKind
    @State private var selectedMiles: Double
    @State private var selectedMinutes: Double
    @State private var activity: TravelMode
    @State private var surfacePreference: SurfacePreference
    @State private var shape: PlannedRouteShape
    @State private var startMode: RouteStartMode
    @State private var addressText: String
    @State private var addressCoordinate: CLLocationCoordinate2D?
    @State private var addressLabel: String?
    @State private var addressError: String?
    @State private var isGeocoding = false
    @State private var tapCoordinate: CLLocationCoordinate2D?
    @State private var couldNotGenerate = false
    @State private var missingStartPoint = false

    init(graph: TrailGraph, userLocation: CLLocation?, initialDraft: RouteDraft? = nil,
         onGenerate: @escaping (Int, Int, RoutePlan) -> Void,
         onRequestMapTap: @escaping (RouteDraft) -> Void) {
        self.graph = graph
        self.userLocation = userLocation
        self.initialDraft = initialDraft
        self.onGenerate = onGenerate
        self.onRequestMapTap = onRequestMapTap
        let d = initialDraft
        _targetKind = State(initialValue: d?.targetKind ?? .distance)
        _selectedMiles = State(initialValue: d?.selectedMiles ?? 2)
        _selectedMinutes = State(initialValue: d?.selectedMinutes ?? 30)
        _activity = State(initialValue: d?.activity ?? .walk)
        _surfacePreference = State(initialValue: d?.surfacePreference ?? .any)
        _shape = State(initialValue: d?.shape ?? .loop)
        _startMode = State(initialValue: d?.startMode ?? .currentLocation)
        _addressText = State(initialValue: d?.addressText ?? "")
        _addressCoordinate = State(initialValue: d?.addressCoordinate)
        _addressLabel = State(initialValue: d?.addressLabel)
        _tapCoordinate = State(initialValue: d?.tapCoordinate)
    }

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
                        Text("Set a target and we'll build a route to match.")
                            .font(.callout)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(Natural.inkMuted)
                            .padding(.horizontal, 28)
                    }

                    section("Starting point") {
                        chipRow(RouteStartMode.allCases, selection: $startMode) { $0.label }
                        startPointPanel
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

                    if missingStartPoint {
                        Text("Choose a starting point first.")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Natural.route)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    } else if couldNotGenerate {
                        Text("Couldn't find a route that long near there — try a shorter target.")
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

    // MARK: - Starting point

    @ViewBuilder
    private var startPointPanel: some View {
        switch startMode {
        case .currentLocation:
            if userLocation == nil {
                Text("Location unavailable — try an address or tap the map instead.")
                    .font(.caption)
                    .foregroundStyle(Natural.route)
            }
        case .address:
            HStack(spacing: 8) {
                TextField("Address or place", text: $addressText)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.search)
                    .onSubmit { geocodeAddress() }
                Button {
                    geocodeAddress()
                } label: {
                    if isGeocoding {
                        ProgressView().frame(width: 20)
                    } else {
                        Text("Find").font(.subheadline.weight(.semibold))
                    }
                }
                .disabled(isGeocoding || addressText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if let addressLabel, addressCoordinate != nil {
                Label(addressLabel, systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(Natural.forest)
            } else if let addressError {
                Text(addressError)
                    .font(.caption)
                    .foregroundStyle(Natural.route)
            }
        case .tapOnMap:
            if let tapCoordinate {
                HStack {
                    Label(coordinateLabel(tapCoordinate), systemImage: "mappin.circle.fill")
                        .font(.caption)
                        .foregroundStyle(Natural.forest)
                    Spacer()
                    Button("Change") { onRequestMapTap(currentDraft()) }
                        .font(.caption.weight(.semibold))
                }
            } else {
                Button {
                    onRequestMapTap(currentDraft())
                } label: {
                    Label("Choose point on map", systemImage: "hand.tap")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Natural.forest)
                }
            }
        }
    }

    private func coordinateLabel(_ c: CLLocationCoordinate2D) -> String {
        String(format: "%.4f, %.4f", c.latitude, c.longitude)
    }

    private func currentDraft() -> RouteDraft {
        RouteDraft(
            targetKind: targetKind, selectedMiles: selectedMiles, selectedMinutes: selectedMinutes,
            activity: activity, surfacePreference: surfacePreference, shape: shape,
            startMode: .tapOnMap, addressText: addressText, addressCoordinate: addressCoordinate,
            addressLabel: addressLabel, tapCoordinate: nil
        )
    }

    private func geocodeAddress() {
        let text = addressText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isGeocoding = true
        addressError = nil
        addressCoordinate = nil
        Task {
            let placemarks = try? await CLGeocoder().geocodeAddressString(text)
            await MainActor.run {
                isGeocoding = false
                if let loc = placemarks?.first?.location {
                    addressCoordinate = loc.coordinate
                    addressLabel = placemarks?.first?.name ?? text
                } else {
                    addressError = "Couldn't find that address."
                }
            }
        }
    }

    /// The coordinate to route from, resolved from whichever starting-point
    /// mode is active. Nil means the user hasn't finished picking one yet
    /// (address not geocoded, map tap not made) — Generate shows a nudge
    /// instead of silently failing.
    private var resolvedStartCoordinate: CLLocationCoordinate2D? {
        switch startMode {
        case .currentLocation: return userLocation?.coordinate
        case .address:         return addressCoordinate
        case .tapOnMap:        return tapCoordinate
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
        missingStartPoint = false
        guard let coordinate = resolvedStartCoordinate else {
            missingStartPoint = true
            return
        }
        let router = Router(graph: graph)
        guard let start = router.nearestNode(to: coordinate),
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
