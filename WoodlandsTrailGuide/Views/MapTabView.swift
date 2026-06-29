import SwiftUI
import MapKit
import StoreKit
import UIKit

struct MapTabView: View {
    @Environment(TrailStore.self) private var store
    @Environment(POIStore.self) private var poiStore
    @Environment(LocationManager.self) private var locationManager
    @Environment(UserDataStore.self) private var userData
    @Environment(\.requestReview) private var requestReview
    @State private var selectedWay: TrailGraph.Way?

    @State private var routingMode = false
    @State private var startNode: Int?
    @State private var endNode: Int?
    @State private var route: Router.Route?
    @State private var routePOIs: [POIAlongRoute] = []

    /// Set once the user taps "Start" on a computed route. While true:
    ///   - Map auto-follows the user with heading-up rotation
    ///   - Bottom card swaps from summary to navigation banner
    ///   - Idle timer is disabled so the screen stays on
    ///   - Taps on the map are suppressed (route is locked in)
    @State private var navigationActive = false
    /// Live progress along the active route, recomputed on every location fix.
    @State private var routeProgress: RouteProgress?
    /// First-time intro sheet explaining the routing flow.
    @State private var showingIntro = false
    /// Bumped by the recenter button. TrailMapView watches it and snaps the
    /// map back to the user's location whenever it changes.
    @State private var recenterTick: Int = 0

    /// Google AdMob banner ad unit ID for the map bottom banner.
    /// App-level GADApplicationIdentifier lives in project.yml.
    private let bannerAdUnitID = "ca-app-pub-1927040492403163/1489998026"

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
                    mapStyle: userData.mapStyle,
                    navigationActive: navigationActive,
                    recenterTick: recenterTick
                )
                .ignoresSafeArea(edges: .top)
                .safeAreaInset(edge: .bottom) {
                    BannerAdView(adUnitID: bannerAdUnitID)
                        .frame(height: 50)
                        .frame(maxWidth: .infinity)
                        .background(Natural.cardBg)
                }
                .onChange(of: startNode) { _, _ in updateRoute(graph: graph) }
                .onChange(of: endNode) { _, _ in updateRoute(graph: graph) }
                .onChange(of: locationManager.location) { _, _ in
                    updateProgress(graph: graph)
                }
                .onChange(of: routeProgress?.isArrived ?? false) { wasArrived, isArrived in
                    // First time the user actually walks to a destination is
                    // the best possible moment to ask for a review.
                    if !wasArrived && isArrived {
                        userData.markRouteCompleted()
                        if userData.eligibleForReviewRequest {
                            Task { @MainActor in
                                try? await Task.sleep(for: .seconds(3))
                                requestReview()
                                userData.markReviewRequested()
                            }
                        }
                    }
                }

                VStack(spacing: 10) {
                    directionsToggle
                    mapStyleToggle
                    recenterButton
                }
                .padding(.top, 12)
                .padding(.trailing, 12)

                if navigationActive, let r = route {
                    VStack { Spacer(); navigationBanner(route: r) }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else if routingMode || route != nil {
                    VStack { Spacer(); routingCard }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            } else {
                loadingOrError
            }
        }
        .animation(.easeInOut(duration: 0.22), value: routingMode)
        .animation(.easeInOut(duration: 0.22), value: route != nil)
        .animation(.easeInOut(duration: 0.22), value: navigationActive)
        .onAppear { locationManager.requestPermission() }
        .onChange(of: navigationActive) { _, isOn in
            // Keep the screen on while walking; restore default on exit.
            UIApplication.shared.isIdleTimerDisabled = isOn
        }
        .sheet(item: $selectedWay) { way in
            TrailDetailSheet(way: way)
                .presentationDetents([.height(220), .medium])
        }
        .sheet(isPresented: $showingIntro, onDismiss: {
            userData.hasSeenRoutingIntro = true
            routingMode = true  // proceed into routing right after the intro
        }) {
            RoutingIntroSheet()
                .presentationDetents([.medium, .large])
        }
    }

    // MARK: - Loading / error UI

    @ViewBuilder
    private var loadingOrError: some View {
        VStack(spacing: 16) {
            if let err = store.loadError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(Natural.route)
                Text("Couldn't load trail data")
                    .font(.headline)
                    .foregroundStyle(Natural.ink)
                Text(err)
                    .font(.caption.monospaced())
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Natural.inkMuted)
                    .padding(.horizontal, 32)
                Button {
                    store.loadError = nil
                    Task { await store.refreshFromRemote() }
                } label: {
                    Text("Retry")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 20).padding(.vertical, 10)
                        .background(Natural.forest, in: Capsule())
                        .foregroundStyle(.white)
                }
            } else {
                ProgressView()
                Text("Loading trails…")
                    .font(.subheadline)
                    .foregroundStyle(Natural.inkMuted)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Natural.cardBg.ignoresSafeArea())
    }

    // MARK: - Top-right buttons

    private var directionsToggle: some View {
        Button {
            if routingMode {
                clearRoute()
            } else if !userData.hasSeenRoutingIntro {
                showingIntro = true
            } else {
                routingMode = true
            }
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

    /// Snap the map back to the user's current location. During navigation
    /// this re-enables follow-with-heading; otherwise plain follow (no
    /// rotation). The button uses MapKit's standard location glyph so it
    /// reads as "find me" at a glance.
    private var recenterButton: some View {
        Button {
            recenterTick &+= 1
        } label: {
            Image(systemName: "location.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Natural.forest)
                .frame(width: 44, height: 44)
                .background(Natural.buttonBg, in: Circle())
                .overlay(Circle().stroke(Natural.hairline, lineWidth: 0.5))
                .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
        }
        .accessibilityLabel("Recenter on my location")
    }

    // MARK: - Bottom routing card (pre-walk)

    @ViewBuilder
    private var routingCard: some View {
        // Use the loud terracotta background while we're prompting for taps,
        // and the calm cream once we have a route. That way "the orange card
        // is asking me to do something" reads at a glance.
        let asking = route == nil && routingMode
        VStack(spacing: 0) {
            if let r = route {
                routeSummaryCard(r)
            } else if routingMode {
                hintCard
            }
        }
        .background(
            asking ? Natural.route : Natural.cardBg,
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(asking ? Color.white.opacity(0.22) : Natural.hairline,
                              lineWidth: asking ? 1 : 0.5)
        )
        .shadow(color: .black.opacity(asking ? 0.22 : 0.12), radius: 12, y: 4)
        .padding(.horizontal, 12)
        .padding(.bottom, 14)
    }

    private var hintCard: some View {
        let isStart = (startNode == nil)
        return HStack(alignment: .center, spacing: 14) {
            Image(systemName: "hand.tap.fill")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Color.white.opacity(0.20), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(isStart ? "Step 1 of 2" : "Step 2 of 2")
                    .font(.caption2.weight(.heavy))
                    .tracking(0.9)
                    .foregroundStyle(.white.opacity(0.78))
                Text(isStart ? "Tap your starting point" : "Tap your destination")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                Text(isStart
                     ? "Drop a pin anywhere along a trail."
                     : "We'll route along the pathway network.")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.88))
            }
            Spacer(minLength: 0)
            Button {
                clearRoute()
            } label: {
                Text("Cancel")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .overlay(
                        Capsule().stroke(Color.white.opacity(0.7), lineWidth: 1.2)
                    )
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
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

            // Start button — flips into navigation mode.
            Button {
                startNavigation(graph: store.graph!)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "figure.walk")
                        .font(.subheadline.weight(.bold))
                    Text("Start walking")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Natural.forest, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    // MARK: - Navigation banner (during walking)

    private func navigationBanner(route r: Router.Route) -> some View {
        let progress = routeProgress
        let upcoming = progress?.upcomingInstruction ?? r.turnInstructions.first
        let isArrived = progress?.isArrived ?? false
        let remaining = progress?.remainingMeters ?? r.lengthMeters
        let distanceToNext = progress?.distanceToNext ?? r.turnInstructions.first?.legMeters ?? 0
        let offRoute = (progress?.distanceFromRoute ?? 0) > 30

        return VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: isArrived ? "checkmark.circle.fill" : (upcoming?.kind.icon ?? "arrow.up"))
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 60, height: 60)
                    .background(isArrived ? Natural.forest : Natural.route, in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    if isArrived {
                        Text("You've arrived")
                            .font(.headline)
                            .foregroundStyle(Natural.ink)
                        Text("End of the route.")
                            .font(.caption)
                            .foregroundStyle(Natural.inkMuted)
                    } else if let u = upcoming {
                        Text(u.kind.verb)
                            .font(.headline)
                            .foregroundStyle(Natural.ink)
                        if let name = u.streetName {
                            Text("\(u.kind == .arrive ? "at" : "onto") \(name)")
                                .font(.subheadline)
                                .foregroundStyle(Natural.ink)
                                .lineLimit(1)
                        }
                        Text("in \(distanceText(meters: distanceToNext))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Natural.inkMuted)
                    }
                }
                Spacer(minLength: 0)
            }

            Divider()
                .background(Natural.hairline)
                .padding(.top, 12)
                .padding(.bottom, 10)

            HStack(spacing: 6) {
                Text(String(format: "%.2f mi", remaining / 1609.344))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Natural.ink)
                Text("· \(walkingTime(meters: remaining)) remaining")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(Natural.inkMuted)
                Spacer()
                Button {
                    clearRoute()
                } label: {
                    Text("End")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(Natural.route, in: Capsule())
                }
            }

            if offRoute {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.semibold))
                    Text("Off route by \(distanceText(meters: progress?.distanceFromRoute ?? 0))")
                        .font(.caption.weight(.medium))
                }
                .foregroundStyle(Natural.route)
                .padding(.top, 8)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .background(Natural.cardBg, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Natural.hairline, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
        .padding(.horizontal, 12)
        .padding(.bottom, 14)
    }

    // MARK: - Routing logic

    private func updateRoute(graph: TrailGraph) {
        guard let s = startNode, let e = endNode else {
            route = nil
            routePOIs = []
            routeProgress = nil
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

    private func updateProgress(graph: TrailGraph) {
        guard navigationActive,
              let r = route,
              let loc = locationManager.location else {
            return
        }
        routeProgress = Router(graph: graph).progress(along: r, at: loc)
    }

    private func startNavigation(graph: TrailGraph) {
        navigationActive = true
        // Compute initial progress so the banner shows real numbers from the
        // first frame instead of placeholder values pulled from the route.
        if let loc = locationManager.location, let r = route {
            routeProgress = Router(graph: graph).progress(along: r, at: loc)
        }
    }

    private func clearRoute() {
        routingMode = false
        navigationActive = false
        startNode = nil
        endNode = nil
        route = nil
        routePOIs = []
        routeProgress = nil
    }

    private func walkingTime(meters: Double) -> String {
        let minutes = meters / 1609.344 / 3.0 * 60.0
        if minutes < 1 { return "<1 min" }
        if minutes < 60 { return "\(Int(minutes.rounded())) min" }
        let h = Int(minutes) / 60
        let m = Int(minutes) % 60
        return m == 0 ? "\(h) hr" : "\(h) hr \(m) min"
    }

    /// "0.12 mi" for ≥0.1 mi, "320 ft" below that. Walking-friendly units.
    private func distanceText(meters: Double) -> String {
        let miles = meters / 1609.344
        if miles >= 0.1 {
            return String(format: "%.2f mi", miles)
        }
        let feet = meters * 3.28084
        return "\(Int(feet.rounded())) ft"
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

/// A pill showing a POI you'll pass on the route.
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
