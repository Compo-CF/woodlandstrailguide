import SwiftUI
import StoreKit

/// Root tab container.
///
/// Four tabs: Map / Trails / Route / About. The Route tab is a shortcut —
/// tapping it switches back to Map and increments `routeIntent`, which
/// MapTabView watches to enter routing mode immediately. It never stays
/// "selected" visually because we flip `selectedTab` back to .map inside
/// the onChange handler.
struct ContentView: View {
    @Environment(UserDataStore.self) private var userData
    @Environment(\.requestReview) private var requestReview
    @State private var showingOnboarding = false
    @State private var hasRecordedLaunch = false
    @State private var selectedTab: AppTab = .map
    /// Bumped whenever the user taps the Route tab. MapTabView's .onChange
    /// picks this up and enters routing mode (respecting the first-time
    /// intro sheet).
    @State private var routeIntent: Int = 0

    enum AppTab: Hashable { case map, trails, route, about }

    var body: some View {
        TabView(selection: $selectedTab) {
            MapTabView(routeIntent: routeIntent)
                .tag(AppTab.map)
                .tabItem { Label("Map", systemImage: "map") }
            ListTabView()
                .tag(AppTab.trails)
                .tabItem { Label("Trails", systemImage: "list.bullet") }
            // The Route tab is a shortcut, not a destination — the onChange
            // handler flips selectedTab back to .map before this content
            // ever renders. The Color.clear is a required placeholder.
            Color.clear
                .tag(AppTab.route)
                .tabItem {
                    Label("Route", systemImage: "point.topleft.down.to.point.bottomright.curvepath.fill")
                }
            AboutTabView()
                .tag(AppTab.about)
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .onChange(of: selectedTab) { _, new in
            guard new == .route else { return }
            selectedTab = .map
            routeIntent &+= 1
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
