import SwiftUI
import StoreKit

/// Root tab container.
///
/// Five tabs: Map / Trails / Route / Featured / About.
///
/// - The **Route** tab is a shortcut, not a destination — tapping it switches
///   back to Map and increments `routeIntent`, which MapTabView watches to
///   enter routing mode immediately.
/// - The **Featured** tab shows curator-managed walks. Tapping "Walk this
///   route" inside a walk sheet sets `routingBridge.pending`, which this view
///   also observes to flip back to Map so MapTabView can apply the route.
struct ContentView: View {
    @Environment(UserDataStore.self) private var userData
    @Environment(RoutingBridge.self) private var routingBridge
    @Environment(\.requestReview) private var requestReview
    @State private var showingOnboarding = false
    @State private var hasRecordedLaunch = false
    @State private var selectedTab: AppTab = .map
    /// Bumped whenever the user taps the Route tab. MapTabView's .onChange
    /// picks this up and enters routing mode (respecting the first-time
    /// intro sheet).
    @State private var routeIntent: Int = 0

    enum AppTab: Hashable { case map, trails, route, featured, about }

    var body: some View {
        TabView(selection: $selectedTab) {
            MapTabView(routeIntent: routeIntent)
                .tag(AppTab.map)
                .tabItem { Label("Map", systemImage: "map") }
            ListTabView()
                .tag(AppTab.trails)
                .tabItem { Label("Trails", systemImage: "list.bullet") }
            // Route tab is a shortcut — the onChange handler flips
            // selectedTab back to .map before this content ever renders.
            Color.clear
                .tag(AppTab.route)
                .tabItem {
                    Label("Route", systemImage: "point.topleft.down.to.point.bottomright.curvepath.fill")
                }
            FeaturedTabView()
                .tag(AppTab.featured)
                .tabItem { Label("Featured", systemImage: "star.circle") }
            AboutTabView()
                .tag(AppTab.about)
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .onChange(of: selectedTab) { _, new in
            guard new == .route else { return }
            selectedTab = .map
            routeIntent &+= 1
        }
        .onChange(of: routingBridge.pending) { _, newValue in
            // A pending route was set — from a deep link, or from the
            // Featured Walk "Walk this route" button. Flip to the Map tab
            // so MapTabView can apply it and the user actually sees the
            // resulting route.
            if newValue != nil {
                selectedTab = .map
            }
        }
        .sheet(isPresented: $showingOnboarding, onDismiss: {
            userData.hasSeenOnboarding = true
        }) {
            OnboardingSheet()
        }
        .onAppear {
            guard !hasRecordedLaunch else { return }
            hasRecordedLaunch = true
            userData.recordAppLaunch()
            if !userData.hasSeenOnboarding {
                showingOnboarding = true
            } else {
                considerReviewPrompt()
            }
        }
    }

    /// On a returning user's cold launch (3+ launches and 30+ days since the
    /// last ask), let iOS decide whether to show the native review prompt.
    private func considerReviewPrompt() {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            if userData.appLaunches >= 3 && userData.eligibleForReviewRequest {
                requestReview()
                userData.markReviewRequested()
            }
        }
    }
}
