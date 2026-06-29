import SwiftUI
import MapKit

struct MapTabView: View {
    @Environment(TrailStore.self) private var store
    @Environment(POIStore.self) private var poiStore
    @Environment(LocationManager.self) private var locationManager
    @Environment(UserDataStore.self) private var userData
    @State private var selectedWay: TrailGraph.Way?

    @State private var routingMode = false
    @State private var startNode: Int?
    @State private var endNode: Int?
    @State private var route: Router.Route?
    @State private var routePOIs: [POIAlongRoute] = []

    /// Categories deliberately excluded from the "Along the way" surfacing —
    /// too granular/noisy to call out (you don't need to know about every
    /// bench you walk past).
    private let alongRouteSkip: Set<String> = [
        "benches", "picnic_tables", "bike_racks", "dog_bag",
        "trail_markers", "monuments", "fountain_feat",
    ]

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let graph = store.graph {
                TrailMapView(
                    graph: graph,
                    selectedWay: $selectedWay,
                    routingMode: routingMode,
                    startNode: $startNode,
                    endNode: $endNode,
                    routeNodeIndices: route?.nodes,
                    pois: poiStore.pois,
                    polygons: poiStore.polygons,
                    mapStyle: userData.mapStyle
                )
                .ignoresSafeArea(edges: .top)
                .onChange(of: startNode) { _, _ in updateRoute(graph: graph) }
                .onChange(of: endNode) { _, _ in updateRoute(graph: graph) }

                VStack(spacing: 10) {
                    directionsToggle
                    mapStyleToggle
                }
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
            if routingMode { clearRoute() } else { routingMode = true }
        } label: {
            Image(systemName: routingMode ? "xmark" : "point.topleft.down.to.point.bottomright.curvepath.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(routingMode ? .white : Natural.forest)
                .frame(width: 44, height: 44)
                .background(routingMode ? Natural.route : Natural.buttonBg,
                            in: Circle())
                .overlay(Circle().stroke(Natural.hairline, lineWidth: 0.5))
                .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
        }
        .accessibilityLabel(routingMode ? "Exit directions" : "Get directions")
    }

    // MARK: - Map style toggle

    /// Cycles through Standard → Hybrid → Satellite and persists the choice.
    /// The current label sits below the icon so users see what mode they're
    /// in without having to tap to find out.
    private var mapStyleToggle: some View {
        Button {
            userData.mapStyle = userData.mapStyle.next
            userData.saveMapStyle()
        } label: {
            VStack(spacing: 1) {
                Image(systemName: userData.mapStyle.systemImage)
                    .font(.system(size: 17, weight: .semibold))
                Text(userData.mapStyle.label)
                    .font(.system(size: 8, weight: .semibold))
                    .textCase(.uppercase)
                    .tracking(0.4)
            }
            .foregroundStyle(Natural.forest)
            .frame(width: 44, height: 44)
            .background(Natural.buttonBg, in: Circle())
            .overlay(Circle().stroke(Natural.hairline, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
        }
        .accessibilityLabel("Map style: \(userData.mapStyle.label). Tap to change.")
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
        .background(Natural.cardBg, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Natural.hairline, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
        .padding(.horizontal, 12)
        .padding(.bottom, 14)
    }

    private var hintCard: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "hand.tap")
                .font(.title3)
                .foregroundStyle(Natural.forest)
            VStack(alignment: .leading, spacing: 2) {
                Text(startNode == nil
                     ? "Tap your starting point"
                     : "Tap your destination")
                    .font(.subheadline).fontWeight(.semibold)
                    .foregroundStyle(Natural.ink)
                Text(startNode == nil
                     ? "Drop a pin anywhere along a trail."
                     : "We'll route along the pathway network.")
                    .font(.caption).foregroundStyle(Natural.inkMuted)
            }
            Spacer()
            Button("Cancel") { clearRoute() }
                .font(.subheadline).fontWeight(.medium)
                .foregroundStyle(Natural.route)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    private func routeSummaryCard(_ r: Router.Route) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(String(format: "%.2f mi", r.lengthMeters / 1609.344))
                    .font(.title3.bold().monospacedDigit())
                    .foregroundStyle(Natural.ink)
                Text("• \(walkingTime(meters: r.lengthMeters)) walk")
                    .font(.subheadline).foregroundStyle(Natural.inkMuted)
                Spacer()
                Button {
                    clearRoute()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Natural.inkMuted)
                }
                .accessibilityLabel("Clear route")
            }

            if !r.namedSegments.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Route")
                        .font(.caption2.smallCaps())
                        .foregroundStyle(Natural.inkMuted)
                        .tracking(0.6)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(r.namedSegments.enumerated()), id: \.offset) { _, seg in
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(seg.name).font(.caption.weight(.semibold))
                                        .foregroundStyle(Natural.ink)
                                        .lineLimit(1)
                                    Text(String(format: "%.2f mi", seg.lengthMeters / 1609.344))
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(Natural.inkMuted)
                                }
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(Natural.chipBg,
                                            in: RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                }
            }

            if !r.parks.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Parks on this route")
                        .font(.caption2.smallCaps())
                        .foregroundStyle(Natural.inkMuted)
                        .tracking(0.6)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(r.parks, id: \.self) { park in
                                ParkChip(name: park)
                            }
                        }
                    }
                }
            }

            if !routePOIs.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Along the way")
                        .font(.caption2.smallCaps())
                        .foregroundStyle(Natural.inkMuted)
                        .tracking(0.6)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(routePOIs.prefix(20)) { rp in
                                POIChip(routePOI: rp)
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    // MARK: - Routing

    private func updateRoute(graph: TrailGraph) {
        guard let s = startNode, let e = endNode else {
            route = nil
            routePOIs = []
            return
        }
        let r = Router(graph: graph).route(from: s, to: e)
        route = r
        if let r, let catalog = poiStore.pois {
            let coords = r.nodes.map { graph.nodes[$0].clCoord }
            routePOIs = catalog.poisAlong(
                nodes: coords,
                within: 40,
                excludingKeys: alongRouteSkip
            )
        } else {
            routePOIs = []
        }
    }

    private func clearRoute() {
        routingMode = false
        startNode = nil
        endNode = nil
        route = nil
        routePOIs = []
    }

    private func walkingTime(meters: Double) -> String {
        let minutes = meters / 1609.344 / 3.0 * 60.0
        if minutes < 1 { return "<1 min" }
        if minutes < 60 { return "\(Int(minutes.rounded())) min" }
        let h = Int(minutes) / 60
        let m = Int(minutes) % 60
        return m == 0 ? "\(h) hr" : "\(h) hr \(m) min"
    }
}

/// A pill showing one named park the route passes through.
private struct ParkChip: View {
    let name: String
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "tree.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(Natural.forest, in: Circle())
            Text(name)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Natural.ink)
                .lineLimit(1)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Natural.chipBg,
                    in: RoundedRectangle(cornerRadius: 10))
    }
}

/// A pill showing a POI you'll pass on the route. Carries the category icon
/// and tint so the strip reads at a glance ("bridge, playground, restroom").
private struct POIChip: View {
    let routePOI: POIAlongRoute

    private var tint: Color {
        let hex = routePOI.category.tintHex
        return Color(red: Double((hex >> 16) & 0xFF) / 255,
                     green: Double((hex >> 8) & 0xFF) / 255,
                     blue: Double(hex & 0xFF) / 255)
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: routePOI.category.icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(tint, in: Circle())
            VStack(alignment: .leading, spacing: 0) {
                Text(routePOI.poi.name ?? routePOI.category.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Natural.ink)
                    .lineLimit(1)
                Text(String(format: "%.2f mi in", routePOI.distanceAlongRoute / 1609.344))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Natural.inkMuted)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Natural.chipBg,
                    in: RoundedRectangle(cornerRadius: 10))
    }
}

extension TrailGraph.Way: Identifiable {
    var id: String {
        if let p = pathwayID { return "p:" + p }
        return "n:" + nodeIndices.prefix(4).map(String.init).joined(separator: "-")
    }
}
