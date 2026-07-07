import SwiftUI
import MapKit
import StoreKit
import UIKit

struct MapTabView: View {
    @Environment(TrailStore.self) private var store
    @Environment(POIStore.self) private var poiStore
    @Environment(LocationManager.self) private var locationManager
    @Environment(UserDataStore.self) private var userData
    @Environment(WeatherStore.self) private var weatherStore
    @Environment(RoutingBridge.self) private var routingBridge
    @Environment(ElevationService.self) private var elevationService
    @Environment(\.requestReview) private var requestReview
    @State private var showingWeather = false
    @State private var showingSearch = false
    @State private var showingLoopBuilder = false
    /// First moment the user drifted outside `offRouteThreshold`. Cleared
    /// when they're back within range. When the drift persists past
    /// `offRouteDuration`, we silently recompute a new route from their
    /// current position.
    @State private var offRouteSince: Date?
    /// Brief "Rerouted" toast shown after an auto-reroute fires.
    @State private var showingReroutedToast = false
    private let offRouteThreshold: Double = 100    // meters
    private let offRouteDuration: TimeInterval = 8 // seconds sustained
    /// Bumped when the user picks a search result — TrailMapView watches this
    /// alongside a stored `searchTargetCoordinate` and pans the map there.
    @State private var searchFocusTick: Int = 0
    @State private var searchFocusCoordinate: CLLocationCoordinate2D?
    @State private var selectedWay: TrailGraph.Way?
    /// POI + its category pushed by TrailMapView when the user taps a
    /// POI annotation. Presented as a POIDetailSheet.
    @State private var selectedPOI: (poi: POI, category: POICategory)?

    @State private var routingMode = false
    @State private var startNode: Int?
    @State private var endNode: Int?
    /// Ordered intermediate stops between start and end. Empty for a plain
    /// A→B route. When non-empty the router computes A→wp₁→wp₂→…→B.
    @State private var waypointNodes: [Int] = []
    /// True while the user has tapped "+ Waypoint" and the next map tap
    /// should append to `waypointNodes` instead of touching start/end.
    @State private var addingWaypoint = false
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
                    addingWaypoint: $addingWaypoint,
                    startNode: $startNode,
                    endNode: $endNode,
                    waypointNodes: $waypointNodes,
                    routeNodeIndices: route?.nodes,
                    pois: poiStore.pois,
                    polygons: poiStore.polygons,
                    mapStyle: userData.mapStyle,
                    navigationActive: navigationActive,
                    recenterTick: recenterTick,
                    searchFocusTick: searchFocusTick,
                    searchFocusCoordinate: searchFocusCoordinate,
                    onSelectPOI: { poi, category in
                        selectedPOI = (poi, category)
                    }
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
                .onChange(of: waypointNodes) { _, _ in updateRoute(graph: graph) }
                .onChange(of: locationManager.location) { _, _ in
                    updateProgress(graph: graph)
                }
                .onChange(of: routingBridge.pending) { _, newValue in
                    // Deep-link handoff — App parses the URL, sets pending;
                    // we snap each coord to the nearest graph node and pop
                    // the routing card so the user sees where they'd walk.
                    if let request = newValue {
                        applyPendingRoute(request, graph: graph)
                        routingBridge.pending = nil
                    }
                }
                .onChange(of: routeProgress?.isArrived ?? false) { wasArrived, isArrived in
                    // First time the user actually walks to a destination is
                    // the best possible moment to ask for a review.
                    if !wasArrived && isArrived {
                        userData.markRouteCompleted()
                        if let r = route {
                            userData.recordTrip(
                                distanceMeters: r.lengthMeters,
                                startLabel: r.namedSegments.first?.name ?? "Start",
                                endLabel: r.namedSegments.last?.name ?? "Destination"
                            )
                        }
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
                    loopButton
                }
                .padding(.top, 12)
                .padding(.trailing, 12)

                VStack {
                    HStack(spacing: 10) {
                        WeatherPill(snapshot: weatherStore.snapshot) {
                            showingWeather = true
                        }
                        searchButton
                        Spacer()
                    }
                    .padding(.top, 12)
                    .padding(.leading, 12)
                    Spacer()
                }

                if navigationActive, let r = route {
                    VStack { Spacer(); navigationBanner(route: r) }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else if routingMode || route != nil {
                    VStack { Spacer(); routingCard }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                if showingReroutedToast {
                    VStack {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.subheadline.weight(.bold))
                            Text("Rerouted")
                                .font(.subheadline.weight(.semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(Natural.forest, in: Capsule())
                        .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
                        .padding(.top, 76)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            } else {
                loadingOrError
            }
        }
        .animation(.easeInOut(duration: 0.22), value: routingMode)
        .animation(.easeInOut(duration: 0.22), value: route != nil)
        .animation(.easeInOut(duration: 0.22), value: navigationActive)
        .animation(.easeInOut(duration: 0.28), value: showingReroutedToast)
        .onAppear {
            locationManager.requestPermission()
            Task {
                await weatherStore.refresh(
                    latitude: locationManager.location?.coordinate.latitude,
                    longitude: locationManager.location?.coordinate.longitude
                )
            }
        }
        .onChange(of: locationManager.location) { _, newLoc in
            guard let newLoc else { return }
            Task {
                await weatherStore.refresh(
                    latitude: newLoc.coordinate.latitude,
                    longitude: newLoc.coordinate.longitude
                )
            }
        }
        .sheet(isPresented: $showingLoopBuilder) {
            if let graph = store.graph, let loc = locationManager.location {
                LoopBuilderSheet(
                    graph: graph,
                    userLocation: loc,
                    onGenerate: { startIdx, farIdx in
                        // Load into the routing state — start == end with a
                        // waypoint in between, so route(through:) generates
                        // the loop via the existing update pipeline.
                        clearRoute()
                        routingMode = true
                        waypointNodes = [farIdx]
                        startNode = startIdx
                        endNode = startIdx
                    }
                )
                .presentationDetents([.medium])
            } else {
                LoopUnavailableSheet()
                    .presentationDetents([.height(220)])
            }
        }
        .sheet(isPresented: $showingSearch) {
            if let graph = store.graph {
                MapSearchSheet(
                    graph: graph,
                    pois: poiStore.pois,
                    userLocation: locationManager.location,
                    onSelect: { result in
                        searchFocusCoordinate = result.coordinate
                        searchFocusTick &+= 1
                    }
                )
            }
        }
        .sheet(isPresented: $showingWeather) {
            WeatherDetailSheet(
                snapshot: weatherStore.snapshot,
                lastFetch: weatherStore.lastFetch,
                onRefresh: {
                    await weatherStore.refresh(
                        latitude: locationManager.location?.coordinate.latitude,
                        longitude: locationManager.location?.coordinate.longitude,
                        force: true
                    )
                }
            )
            .presentationDetents([.medium])
        }
        .onChange(of: navigationActive) { _, isOn in
            // Keep the screen on while walking; restore default on exit.
            UIApplication.shared.isIdleTimerDisabled = isOn
        }
        .sheet(item: $selectedWay) { way in
            TrailDetailSheet(way: way)
                .presentationDetents([.height(220), .medium])
        }
        .sheet(item: Binding(
            get: { selectedPOI.map { POISelection(poi: $0.poi, category: $0.category) } },
            set: { newValue in
                selectedPOI = newValue.map { ($0.poi, $0.category) }
            }
        )) { sel in
            POIDetailSheet(
                poi: sel.poi,
                category: sel.category,
                userLocation: locationManager.location,
                onRouteHere: { routeToPOI(sel.poi) }
            )
            .presentationDetents([.height(300), .medium])
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

    /// Generate a loop walk of a chosen distance from the user's location.
    /// Uses waypoint routing under the hood — start = end, with a far
    /// waypoint chosen at approximately target-distance / 2.
    private var loopButton: some View {
        Button {
            showingLoopBuilder = true
        } label: {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Natural.forest)
                .frame(width: 44, height: 44)
                .background(Natural.buttonBg, in: Circle())
                .overlay(Circle().stroke(Natural.hairline, lineWidth: 0.5))
                .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
        }
        .accessibilityLabel("Generate a loop walk from your location")
    }

    /// Full-screen search covering trails, parks, and POIs.
    private var searchButton: some View {
        Button {
            showingSearch = true
        } label: {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Natural.forest)
                .frame(width: 44, height: 44)
                .background(Natural.buttonBg, in: Circle())
                .overlay(Circle().stroke(Natural.hairline, lineWidth: 0.5))
                .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
        }
        .accessibilityLabel("Search trails, parks, and amenities")
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
        // Three variants: pick a start, pick a destination, or pick an
        // intermediate waypoint after the user tapped "+ Waypoint".
        let step: (eyebrow: String, title: String, subtitle: String)
        if addingWaypoint {
            step = (
                "ADD A STOP",
                "Tap a spot to route through",
                "We'll reroute to go via this point."
            )
        } else if startNode == nil {
            step = (
                "Step 1 of 2",
                "Tap your starting point",
                "Drop a pin anywhere along a trail."
            )
        } else {
            step = (
                "Step 2 of 2",
                "Tap your destination",
                "We'll route along the pathway network."
            )
        }
        return VStack(spacing: 10) {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: "hand.tap.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.20), in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(step.eyebrow)
                        .font(.caption2.weight(.heavy))
                        .tracking(0.9)
                        .foregroundStyle(.white.opacity(0.78))
                    Text(step.title)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                    Text(step.subtitle)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.88))
                }
                Spacer(minLength: 0)
                Button {
                    if addingWaypoint {
                        addingWaypoint = false
                    } else {
                        clearRoute()
                    }
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

            // "Use my location" shortcut — only offered before start is set
            // AND when we actually have a fix to work with.
            if startNode == nil && !addingWaypoint, let userLoc = locationManager.location {
                Button {
                    useCurrentLocationAsStart(userLoc)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "location.fill")
                        Text("Use my location as start")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Natural.route)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
    }

    /// Snap the user's location to the nearest graph node and set it as the
    /// route start. Called from the "Use my location" shortcut on the hint
    /// card and from routeToPOI when no start is set.
    private func useCurrentLocationAsStart(_ location: CLLocation) {
        guard let graph = store.graph,
              let idx = Router(graph: graph).nearestNode(to: location.coordinate) else { return }
        startNode = idx
    }

    private func routeSummaryCard(_ r: Router.Route) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(String(format: "%.2f mi", r.lengthMeters / 1609.344))
                    .font(.title3.bold().monospacedDigit())
                    .foregroundStyle(Natural.ink)
                Text("• \(walkingTime(meters: r.lengthMeters)) walk")
                    .font(.subheadline).foregroundStyle(Natural.inkMuted)
                Spacer()
                if let graph = store.graph, let shareURL = buildShareURL(graph) {
                    ShareLink(item: shareURL,
                              subject: Text("Walk in The Woodlands"),
                              message: Text(shareMessage(for: r))) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.title3)
                            .foregroundStyle(Natural.forest)
                    }
                    .accessibilityLabel("Share this route")
                }
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

            if let graph = store.graph,
               let profile = elevationService.profile(for: r, graph: graph) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Elevation")
                        .font(.caption2.smallCaps())
                        .foregroundStyle(Natural.inkMuted)
                        .tracking(0.6)
                    ElevationChartView(profile: profile)
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

            // Bottom action row — add-waypoint on the left, start on the right.
            HStack(spacing: 10) {
                Button {
                    addingWaypoint = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.subheadline.weight(.semibold))
                        Text("Add stop")
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(Natural.forest)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Natural.chipBg, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .accessibilityLabel("Add a waypoint to route through")

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
            }
            .padding(.top, 4)

            if !waypointNodes.isEmpty {
                Text("\(waypointNodes.count) waypoint\(waypointNodes.count == 1 ? "" : "s") added")
                    .font(.caption2)
                    .foregroundStyle(Natural.inkMuted)
            }
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
        let stops = [s] + waypointNodes + [e]
        let r = Router(graph: graph).route(through: stops)
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
        let router = Router(graph: graph)
        let progress = router.progress(along: r, at: loc)
        routeProgress = progress

        // Off-route auto-reroute: if the user has drifted > threshold for
        // sustained duration, silently recompute a new route from their
        // current position to the same destination. Waypoints are dropped —
        // the user has already moved past whatever waypoint context existed.
        if progress.distanceFromRoute > offRouteThreshold, !progress.isArrived {
            if offRouteSince == nil {
                offRouteSince = .now
            } else if let since = offRouteSince,
                      Date.now.timeIntervalSince(since) > offRouteDuration,
                      let end = endNode,
                      let newStart = router.nearestNode(to: loc.coordinate),
                      let rerouted = router.route(from: newStart, to: end) {
                route = rerouted
                startNode = newStart
                waypointNodes = []
                routeProgress = router.progress(along: rerouted, at: loc)
                offRouteSince = nil
                showingReroutedToast = true
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(2.5))
                    showingReroutedToast = false
                }
            }
        } else {
            offRouteSince = nil
        }
    }

    private func startNavigation(graph: TrailGraph) {
        navigationActive = true
        // Compute initial progress so the banner shows real numbers from the
        // first frame instead of placeholder values pulled from the route.
        if let loc = locationManager.location, let r = route {
            routeProgress = Router(graph: graph).progress(along: r, at: loc)
        }
    }

    /// Start a route from the user's current location (or ask them to tap
    /// a start if we don't have one) to the given POI. Snaps both ends to
    /// their nearest graph nodes.
    private func routeToPOI(_ poi: POI) {
        guard let graph = store.graph else { return }
        let router = Router(graph: graph)
        guard let dest = router.nearestNode(to: poi.coordinate) else { return }
        endNode = dest
        if startNode == nil, let userLoc = locationManager.location {
            startNode = router.nearestNode(to: userLoc.coordinate)
        }
        routingMode = true
        addingWaypoint = false
    }

    /// Build a woodlandstrailguide:// URL for the currently-computed route
    /// so users can send it to another install of the app.
    private func buildShareURL(_ graph: TrailGraph) -> URL? {
        guard let s = startNode, let e = endNode,
              s < graph.nodes.count, e < graph.nodes.count else { return nil }
        let startCoord = graph.nodes[s].clCoord
        let endCoord = graph.nodes[e].clCoord
        let vias = waypointNodes.compactMap { i -> CLLocationCoordinate2D? in
            guard i < graph.nodes.count else { return nil }
            return graph.nodes[i].clCoord
        }
        return RoutingBridge.buildShareURL(start: startCoord, end: endCoord, waypoints: vias)
    }

    private func shareMessage(for r: Router.Route) -> String {
        let miles = String(format: "%.2f", r.lengthMeters / 1609.344)
        let time = walkingTime(meters: r.lengthMeters)
        let firstLeg = r.namedSegments.first?.name
        let lastLeg = r.namedSegments.last?.name
        var msg = "A \(miles)-mile walk in The Woodlands — about \(time)."
        if let firstLeg, let lastLeg, firstLeg != lastLeg {
            msg += " Starts on \(firstLeg), ends on \(lastLeg)."
        }
        msg += " Open this link in Woodlands Trail Guide to route it."
        return msg
    }

    /// Apply an incoming deep-link route request. Snaps each raw coordinate
    /// to the nearest graph node and drops it into the routing state so the
    /// summary card appears immediately.
    private func applyPendingRoute(_ request: RoutingBridge.PendingRoute, graph: TrailGraph) {
        let router = Router(graph: graph)
        guard let s = router.nearestNode(to: request.start),
              let e = router.nearestNode(to: request.end) else { return }
        clearRoute()
        routingMode = true
        startNode = s
        endNode = e
        waypointNodes = request.waypoints.compactMap { router.nearestNode(to: $0) }
    }

    private func clearRoute() {
        routingMode = false
        navigationActive = false
        addingWaypoint = false
        startNode = nil
        endNode = nil
        waypointNodes = []
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

/// Fallback shown when the loop builder is invoked without a location fix.
private struct LoopUnavailableSheet: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "location.slash.fill")
                .font(.system(size: 44))
                .foregroundStyle(Natural.route)
            Text("Location needed for loops")
                .font(.headline)
                .foregroundStyle(Natural.ink)
            Text("Loop generation starts from where you are. Grant location access, or move outside so your device can pick up a fix, then try again.")
                .font(.callout)
                .foregroundStyle(Natural.inkMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Button("Got it") { dismiss() }
                .buttonStyle(.borderedProminent)
                .tint(Natural.forest)
            Spacer()
        }
        .background(Natural.cardBg)
    }
}

/// Identifiable wrapper for the sheet(item:) binding — a tuple isn't
/// Identifiable on its own, and both the POI and its category are needed
/// to render the detail sheet.
private struct POISelection: Identifiable {
    let poi: POI
    let category: POICategory
    var id: String { "\(category.key):\(poi.id)" }
}

extension TrailGraph.Way: Identifiable {
    var id: String {
        if let p = pathwayID { return "p:" + p }
        return "n:" + nodeIndices.prefix(4).map(String.init).joined(separator: "-")
    }
}
