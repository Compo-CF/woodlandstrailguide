import SwiftUI
import MapKit
import StoreKit
import UIKit

struct MapTabView: View {
    /// Incremented by ContentView whenever the user taps the "Route" tab in
    /// the bottom tab bar. The tab acts as a shortcut into routing mode —
    /// we watch this value and enter routing mode when it changes.
    let routeIntent: Int

    @Environment(TrailStore.self) private var store
    @Environment(POIStore.self) private var poiStore
    @Environment(LocationManager.self) private var locationManager
    @Environment(UserDataStore.self) private var userData
    @Environment(WeatherStore.self) private var weatherStore
    @Environment(RoutingBridge.self) private var routingBridge
    @Environment(ElevationService.self) private var elevationService
    @Environment(IAPStore.self) private var iapStore
    @Environment(\.requestReview) private var requestReview
    @State private var showingWeather = false
    @State private var showingSearch = false
    @State private var showingRoutePlanner = false
    /// Stashed RoutePlannerSheet selections while the user is off tapping a
    /// starting point on the map (see awaitingPlannerTap below) — restored
    /// as the sheet's initialDraft when it reopens.
    @State private var plannerDraft: RouteDraft?
    /// True right after the route planner asks the user to tap a starting
    /// point on the map. The sheet is dismissed for the duration; a banner
    /// with a Cancel button takes its place, and the next map tap resolves
    /// the draft's tapCoordinate and reopens the sheet.
    @State private var awaitingPlannerTap = false
    @State private var showingConditionReport = false
    @State private var showingWildlifeSighting = false
    /// Wall-clock start of the active navigation session — used to compute
    /// a real walk duration for the trip log + HealthKit workout on arrival.
    @State private var navigationStartedAt: Date?
    /// Set right after a walk completes if it earned any new achievements.
    /// Drives a brief celebratory toast (dismisses itself after a few sec).
    @State private var toastAchievement: Achievement?
    /// First moment the user drifted outside `offRouteThreshold`. Cleared
    /// when they're back within range. When the drift persists past
    /// `offRouteDuration`, we silently recompute a new route from their
    /// current position.
    @State private var offRouteSince: Date?
    /// Brief "Rerouted" toast shown after an auto-reroute fires.
    @State private var showingReroutedToast = false
    private let offRouteThreshold: Double = 100    // meters
    private let offRouteDuration: TimeInterval = 8 // seconds sustained
    /// True once the user has come within `offRouteThreshold` of the route
    /// polyline at least once since tapping "Start". Starting navigation
    /// off-network (a driveway, a street that isn't part of the pathway
    /// graph) used to be indistinguishable from having drifted off an
    /// already-joined route — after 8 stationary seconds the off-route
    /// timer below would fire and silently replace the whole plan (loop
    /// shape, surface preference, waypoints and all) with a bare point-to-
    /// point route from wherever the user happened to be standing. Gating
    /// that logic on this flag instead shows a distinct "walk to the
    /// trail" banner state (see joiningRouteContent) until they actually
    /// reach the route, then behaves exactly as before.
    @State private var hasJoinedRoute = false
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
    /// Set when the active route came from the route planner (a distance/
    /// time target) rather than plain tap-to-route. Nil for normal routing.
    /// Read by updateRoute(graph:) so surface toggles and off-route
    /// reroutes keep recomputing consistently with the original plan —
    /// cleared by clearRoute() and routeToPOI() whenever a fresh, un-
    /// planned route begins.
    @State private var activePlan: RoutePlan?
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
                    awaitingPlannerTap: $awaitingPlannerTap,
                    onSelectPOI: { poi, category in
                        selectedPOI = (poi, category)
                    },
                    onPlannerTapCoordinate: { coordinate in
                        var draft = plannerDraft ?? RouteDraft()
                        draft.startMode = .tapOnMap
                        draft.tapCoordinate = coordinate
                        plannerDraft = draft
                        awaitingPlannerTap = false
                        showingRoutePlanner = true
                    }
                )
                .ignoresSafeArea(edges: .top)
                .safeAreaInset(edge: .bottom) {
                    if !iapStore.hasRemovedAds {
                        BannerAdView(adUnitID: bannerAdUnitID)
                            .frame(height: 50)
                            .frame(maxWidth: .infinity)
                            .background(Natural.cardBg)
                    }
                }
                .onChange(of: startNode) { _, _ in updateRoute(graph: graph) }
                .onChange(of: endNode) { _, _ in updateRoute(graph: graph) }
                .onChange(of: waypointNodes) { _, _ in updateRoute(graph: graph) }
                .onChange(of: locationManager.location) { _, _ in
                    updateProgress(graph: graph)
                }
                .onChange(of: routeIntent) { _, _ in
                    // User tapped the Route tab in the tab bar. Enter routing
                    // mode (or show the first-time intro sheet if they haven't
                    // seen it). If they're already routing, no-op.
                    guard !routingMode else { return }
                    if !userData.hasSeenRoutingIntro {
                        showingIntro = true
                    } else {
                        routingMode = true
                    }
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
                        let duration = navigationStartedAt.map { Date.now.timeIntervalSince($0) }
                        if let r = route {
                            userData.recordTrip(
                                distanceMeters: r.lengthMeters,
                                startLabel: r.namedSegments.first?.name ?? "Start",
                                endLabel: r.namedSegments.last?.name ?? "Destination",
                                durationSeconds: duration,
                                travelMode: userData.travelMode
                            )
                            if userData.healthKitSyncEnabled {
                                HealthKitService.shared.saveWorkout(
                                    distanceMeters: r.lengthMeters,
                                    durationSeconds: duration ?? (r.lengthMeters / 1609.344 / userData.travelMode.paceMph * 3600),
                                    travelMode: userData.travelMode
                                )
                            }
                        }
                        navigationStartedAt = nil

                        let newlyEarned = userData.checkForNewAchievements(hasTipped: iapStore.tipCount > 0)
                        if let first = newlyEarned.first {
                            toastAchievement = first
                            Task { @MainActor in
                                try? await Task.sleep(for: .seconds(3))
                                toastAchievement = nil
                            }
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
                    plannerButton
                    moreMenuButton
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

                if awaitingPlannerTap {
                    VStack {
                        HStack(spacing: 12) {
                            Image(systemName: "hand.tap.fill")
                                .font(.subheadline.weight(.bold))
                            Text("Tap the map to set your starting point")
                                .font(.subheadline.weight(.semibold))
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                            Button("Cancel") {
                                awaitingPlannerTap = false
                                showingRoutePlanner = true
                            }
                            .font(.subheadline.weight(.semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16).padding(.vertical, 12)
                        .background(Natural.forest, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
                        .padding(.horizontal, 16)
                        .padding(.top, 76)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                if let achievement = toastAchievement {
                    VStack {
                        HStack(spacing: 10) {
                            Image(systemName: achievement.systemImage)
                                .font(.subheadline.weight(.bold))
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Achievement unlocked")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.white.opacity(0.85))
                                Text(achievement.title)
                                    .font(.subheadline.weight(.semibold))
                            }
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
        .animation(.easeInOut(duration: 0.28), value: toastAchievement)
        .animation(.easeInOut(duration: 0.22), value: awaitingPlannerTap)
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
        .sheet(isPresented: $showingRoutePlanner) {
            if let graph = store.graph {
                RoutePlannerSheet(
                    graph: graph,
                    userLocation: locationManager.location,
                    initialDraft: plannerDraft,
                    onGenerate: { startIdx, farIdx, plan in
                        // Load into the routing state — start == end with a
                        // waypoint in between — so updateRoute(graph:) can
                        // build the planned route (loop or surface-aware
                        // out-and-back) via the existing update pipeline.
                        clearRoute()
                        routingMode = true
                        waypointNodes = [farIdx]
                        startNode = startIdx
                        endNode = startIdx
                        activePlan = plan
                        userData.travelMode = plan.activity
                        userData.saveTravelMode()
                        plannerDraft = nil
                    },
                    onRequestMapTap: { draft in
                        plannerDraft = draft
                        showingRoutePlanner = false
                        // Let the sheet's dismiss animation finish before the
                        // "tap the map" banner slides in — presenting both at
                        // once looks like a glitch.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            awaitingPlannerTap = true
                        }
                    }
                )
                .presentationDetents([.large])
            } else {
                TrailDataUnavailableSheet()
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
        .sheet(isPresented: $showingConditionReport) {
            TrailConditionSheet(
                wayID: selectedWay?.pathwayID,
                wayName: selectedWay?.name,
                userLocation: locationManager.location
            )
        }
        .sheet(isPresented: $showingWildlifeSighting) {
            WildlifeSightingSheet(userLocation: locationManager.location)
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
                .mapControlChrome(Circle(), fill: routingMode ? Natural.route : Natural.buttonBg)
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
            .mapControlChrome(Circle())
        }
        .accessibilityLabel("Map style: \(userData.mapStyle.label). Tap to change.")
    }

    /// Open the route planner — generate a walk/jog/run of a chosen
    /// distance or time from the user's location. Uses waypoint routing
    /// under the hood — start = end, with a far waypoint chosen at
    /// approximately target-distance / 2 — see updateRoute(graph:).
    private var plannerButton: some View {
        Button {
            plannerDraft = nil
            showingRoutePlanner = true
        } label: {
            Image(systemName: "figure.run")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Natural.forest)
                .frame(width: 44, height: 44)
                .mapControlChrome(Circle())
        }
        .accessibilityLabel("Plan a walk, jog, or run from your location")
    }

    /// Travel mode, paved-route preference, and the two crowdsourced report
    /// types — grouped into one menu so the top-right button stack doesn't
    /// grow a new circle for each one.
    private var moreMenuButton: some View {
        Menu {
            Menu {
                ForEach(TravelMode.allCases, id: \.self) { mode in
                    Button {
                        userData.travelMode = mode
                        userData.saveTravelMode()
                    } label: {
                        if userData.travelMode == mode {
                            Label(mode.label, systemImage: "checkmark")
                        } else {
                            Text(mode.label)
                        }
                    }
                }
            } label: {
                Label("Travel mode: \(userData.travelMode.label)", systemImage: userData.travelMode.systemImage)
            }
            Button {
                userData.preferPavedRoutes.toggle()
                userData.savePreferPavedRoutes()
                if let graph = store.graph { updateRoute(graph: graph) }
            } label: {
                Label("Prefer paved paths", systemImage: userData.preferPavedRoutes ? "checkmark.circle.fill" : "circle")
            }
            Divider()
            Button {
                showingConditionReport = true
            } label: {
                Label("Report a trail condition", systemImage: "exclamationmark.triangle")
            }
            Button {
                showingWildlifeSighting = true
            } label: {
                Label("Report a wildlife sighting", systemImage: "pawprint")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Natural.forest)
                .frame(width: 44, height: 44)
                .mapControlChrome(Circle())
        }
        .accessibilityLabel("More options")
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
                .mapControlChrome(Circle())
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
                .mapControlChrome(Circle())
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
                Text("• \(travelTime(meters: r.lengthMeters)) \(userData.travelMode.noun)")
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

            if let plan = activePlan {
                HStack(spacing: 5) {
                    Image(systemName: plan.shape.systemImage)
                    Text("Planned \(String(format: "%.1f", plan.targetMeters / 1609.344)) mi \(plan.shape.label.lowercased())")
                    if plan.surfacePreference != .any {
                        Text("· \(plan.surfacePreference.label)")
                    }
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(Natural.forest)
            }

            if let graph = store.graph, let loc = locationManager.location {
                let toRoute = Router(graph: graph).progress(along: r, at: loc).distanceFromRoute
                if toRoute > offRouteThreshold {
                    HStack(spacing: 5) {
                        Image(systemName: "signpost.right.and.left")
                        Text("\(distanceText(meters: toRoute)) to reach the trail from here")
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Natural.inkMuted)
                }
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
                        Image(systemName: userData.travelMode.systemImage)
                            .font(.subheadline.weight(.bold))
                        Text("Start \(userData.travelMode.gerund)")
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

    @ViewBuilder
    private func navigationBanner(route r: Router.Route) -> some View {
        if !hasJoinedRoute {
            bannerCard { joiningRouteContent }
        } else {
            bannerCard { activeNavigationContent(r) }
        }
    }

    /// Shared card chrome for the nav banner — factored out so both the
    /// "walk to the trail" state and the normal turn-by-turn state render
    /// identically framed.
    private func bannerCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
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

    /// Shown once "Start" is tapped but before the user has reached the
    /// route — e.g. they started from a driveway or a street off the
    /// pathway network. The app has no street geometry, so this is an
    /// honest straight-line distance to the nearest point on the route,
    /// not turn-by-turn — the map's route polyline is what actually shows
    /// the way there. Clears automatically once distanceFromRoute drops
    /// under the join threshold — see updateProgress(graph:).
    private var joiningRouteContent: some View {
        let toRoute = routeProgress?.distanceFromRoute ?? 0
        return VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "signpost.right.and.left.fill")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 60, height: 60)
                    .background(Natural.route, in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text("Head to the trail")
                        .font(.headline)
                        .foregroundStyle(Natural.ink)
                    Text("About \(distanceText(meters: toRoute)) to reach your route")
                        .font(.subheadline)
                        .foregroundStyle(Natural.ink)
                    Text("Straight-line estimate — follow the map, not turn-by-turn")
                        .font(.caption)
                        .foregroundStyle(Natural.inkMuted)
                }
                Spacer(minLength: 0)
            }

            Divider()
                .background(Natural.hairline)
                .padding(.top, 12)
                .padding(.bottom, 10)

            HStack {
                Text("Turn-by-turn starts once you reach the trail")
                    .font(.caption)
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
        }
    }

    private func activeNavigationContent(_ r: Router.Route) -> some View {
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
                Text("· \(travelTime(meters: remaining)) remaining")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(Natural.inkMuted)
                Spacer()
                if let graph = store.graph, let shareURL = buildShareURL(graph) {
                    ShareLink(item: shareURL,
                              subject: Text("Walking in The Woodlands"),
                              message: Text(liveShareMessage(remaining: remaining))) {
                        Image(systemName: "location.fill.viewfinder")
                            .font(.subheadline)
                            .foregroundStyle(Natural.forest)
                            .padding(.horizontal, 6)
                    }
                    .accessibilityLabel("Share my live ETA")
                }
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
    }

    // MARK: - Routing logic

    private func updateRoute(graph: TrailGraph) {
        guard let s = startNode, let e = endNode else {
            route = nil
            routePOIs = []
            routeProgress = nil
            return
        }
        let router = Router(graph: graph)
        let r: Router.Route?
        if let plan = activePlan, plan.shape == .loop, s == e, waypointNodes.count == 1 {
            // Planner loop: build a genuine loop (different path back) via
            // the discourage-based Dijkstra, instead of the plain through-
            // route Dijkstra below (which would just retrace the same
            // edges both ways).
            r = router.loopRoute(from: s, viaFar: waypointNodes[0], surfacePreference: plan.surfacePreference)
        } else if let plan = activePlan {
            // Planner out-and-back (or a loop that's degraded — e.g. after
            // an off-route reroute dropped the waypoint): plain through-
            // route, but honoring the plan's own surface preference rather
            // than the global prefer-paved toggle.
            r = router.route(through: [s] + waypointNodes + [e], surfacePreference: plan.surfacePreference)
        } else {
            r = router.route(through: [s] + waypointNodes + [e], avoidUnpaved: userData.preferPavedRoutes)
        }
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

        guard hasJoinedRoute else {
            // Still walking to the trail (see joiningRouteContent) — don't
            // run the off-route/reroute logic at all yet, just watch for
            // arrival. Without this gate, standing off-network for 8
            // seconds right after tapping "Start" looked identical to
            // having drifted off an already-joined route, and the block
            // below would silently replace the whole planned route.
            if progress.distanceFromRoute <= offRouteThreshold {
                hasJoinedRoute = true
            }
            return
        }

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
        navigationStartedAt = .now
        hasJoinedRoute = false
        // Compute initial progress so the banner shows real numbers from the
        // first frame instead of placeholder values pulled from the route —
        // and so hasJoinedRoute reflects reality immediately (the common
        // case: starting right at the trailhead) instead of flashing the
        // "walk to the trail" state for one frame before the next fix.
        if let loc = locationManager.location, let r = route {
            let progress = Router(graph: graph).progress(along: r, at: loc)
            routeProgress = progress
            hasJoinedRoute = progress.distanceFromRoute <= offRouteThreshold
        }
    }

    /// Start a route from the user's current location (or ask them to tap
    /// a start if we don't have one) to the given POI. Snaps both ends to
    /// their nearest graph nodes.
    private func routeToPOI(_ poi: POI) {
        guard let graph = store.graph else { return }
        let router = Router(graph: graph)
        guard let dest = router.nearestNode(to: poi.coordinate) else { return }
        // A POI-targeted route is never a "planned" route, even if one was
        // active — drop it so updateRoute(graph:) doesn't try to build a
        // loop back to a start that no longer matches this new destination.
        activePlan = nil
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

    /// Message for the live-ETA share button in the nav banner — shares
    /// current progress + a rough finish estimate, not just the plan.
    private func liveShareMessage(remaining: Double) -> String {
        let miles = String(format: "%.2f", remaining / 1609.344)
        let time = travelTime(meters: remaining)
        let verb = userData.travelMode.gerund
        return "I'm currently \(verb) in The Woodlands — \(miles) mi and about \(time) left. Open this link in Woodlands Trail Guide to see the route."
    }

    private func shareMessage(for r: Router.Route) -> String {
        let miles = String(format: "%.2f", r.lengthMeters / 1609.344)
        let time = travelTime(meters: r.lengthMeters)
        let firstLeg = r.namedSegments.first?.name
        let lastLeg = r.namedSegments.last?.name
        let verb = userData.travelMode.noun
        var msg = "A \(miles)-mile \(verb) in The Woodlands — about \(time)."
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
        activePlan = nil
        route = nil
        routePOIs = []
        routeProgress = nil
        hasJoinedRoute = false
        offRouteSince = nil
    }

    /// Duration estimate at the current travel mode's pace. Named generically
    /// (not "walkingTime") since it now covers bike pace too.
    private func travelTime(meters: Double) -> String {
        let minutes = meters / 1609.344 / userData.travelMode.paceMph * 60.0
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

/// Fallback shown when the route planner is invoked before trail data has
/// loaded. Location is no longer a blocker here — Address and Tap on Map
/// starting points in RoutePlannerSheet don't need a live fix.
private struct TrailDataUnavailableSheet: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "map.slash")
                .font(.system(size: 44))
                .foregroundStyle(Natural.route)
            Text("Trail data still loading")
                .font(.headline)
                .foregroundStyle(Natural.ink)
            Text("Give it a moment to finish loading the trail network, then try again.")
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
