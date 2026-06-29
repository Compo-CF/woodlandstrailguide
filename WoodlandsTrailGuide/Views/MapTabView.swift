import SwiftUI
import MapKit

struct MapTabView: View {
    @Environment(TrailStore.self) private var store
    @Environment(LocationManager.self) private var locationManager
    @State private var selectedWay: TrailGraph.Way?

    // Routing state — lives here so the map view stays thin.
    @State private var routingMode = false
    @State private var startNode: Int?
    @State private var endNode: Int?
    @State private var route: Router.Route?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let graph = store.graph {
                TrailMapView(
                    graph: graph,
                    selectedWay: $selectedWay,
                    routingMode: routingMode,
                    startNode: $startNode,
                    endNode: $endNode,
                    routeNodeIndices: route?.nodes
                )
                .ignoresSafeArea(edges: .top)
                .onChange(of: startNode) { _, _ in computeRoute(graph: graph) }
                .onChange(of: endNode) { _, _ in computeRoute(graph: graph) }

                directionsToggle
                    .padding(.top, 12)
                    .padding(.trailing, 12)

                if routingMode || route != nil {
                    VStack { Spacer(); routingCard }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            } else {
                ProgressView("Loading trails...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .animation(.easeInOut(duration: 0.22), value: routingMode)
        .animation(.easeInOut(duration: 0.22), value: route != nil)
        .onAppear { locationManager.requestPermission() }
        .sheet(item: $selectedWay) { way in
            TrailDetailSheet(way: way)
                .presentationDetents([.height(220), .medium])
        }
    }

    // MARK: - Directions toggle

    private var directionsToggle: some View {
        Button {
            if routingMode {
                clearRoute()
            } else {
                routingMode = true
            }
        } label: {
            Image(systemName: routingMode ? "xmark" : "point.topleft.down.to.point.bottomright.curvepath.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(routingMode ? .white : .accentColor)
                .frame(width: 44, height: 44)
                .background(routingMode ? Color.accentColor : Color(.systemBackground),
                            in: Circle())
                .overlay(Circle().stroke(Color.black.opacity(0.08), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
        }
        .accessibilityLabel(routingMode ? "Exit directions" : "Get directions")
    }

    // MARK: - Bottom card

    @ViewBuilder
    private var routingCard: some View {
        VStack(spacing: 0) {
            if let r = route {
                routeSummaryCard(r)
            } else if routingMode {
                hintCard
            }
        }
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.black.opacity(0.06), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
        .padding(.horizontal, 12)
        .padding(.bottom, 14)
    }

    private var hintCard: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "hand.tap")
                .font(.title3)
                .foregroundStyle(.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(startNode == nil
                     ? "Tap your starting point"
                     : "Tap your destination")
                    .font(.subheadline).fontWeight(.semibold)
                Text(startNode == nil
                     ? "Drop a pin anywhere along a trail."
                     : "We'll route along the pathway network.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Cancel") { clearRoute() }
                .font(.subheadline).fontWeight(.medium)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    private func routeSummaryCard(_ r: Router.Route) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(String(format: "%.2f mi", r.lengthMeters / 1609.344))
                    .font(.title3.bold().monospacedDigit())
                Text("• \(walkingTime(meters: r.lengthMeters)) walk")
                    .font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Button {
                    clearRoute()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Clear route")
            }
            if !r.namedSegments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(r.namedSegments.enumerated()), id: \.offset) { _, seg in
                            VStack(alignment: .leading, spacing: 1) {
                                Text(seg.name).font(.caption.weight(.semibold))
                                    .lineLimit(1)
                                Text(String(format: "%.2f mi", seg.lengthMeters / 1609.344))
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Color(.tertiarySystemBackground),
                                        in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    // MARK: - Routing

    private func computeRoute(graph: TrailGraph) {
        guard let s = startNode, let e = endNode else {
            route = nil
            return
        }
        let r = Router(graph: graph).route(from: s, to: e)
        route = r
    }

    private func clearRoute() {
        routingMode = false
        startNode = nil
        endNode = nil
        route = nil
    }

    /// Rough walking-time estimate at ~3 mph (typical relaxed pace on a path).
    private func walkingTime(meters: Double) -> String {
        let minutes = meters / 1609.344 / 3.0 * 60.0
        if minutes < 1 { return "<1 min" }
        if minutes < 60 { return "\(Int(minutes.rounded())) min" }
        let h = Int(minutes) / 60
        let m = Int(minutes) % 60
        return m == 0 ? "\(h) hr" : "\(h) hr \(m) min"
    }
}

extension TrailGraph.Way: Identifiable {
    /// Synthetic id for sheet presentation. Uses pathwayID when present (stable
    /// across data refreshes) and falls back to a hash of the node list.
    var id: String {
        if let p = pathwayID { return "p:" + p }
        return "n:" + nodeIndices.prefix(4).map(String.init).joined(separator: "-")
    }
}
