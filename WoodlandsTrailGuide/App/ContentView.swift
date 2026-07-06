import SwiftUI
import StoreKit

struct ContentView: View {
    @Environment(UserDataStore.self) private var userData
    @Environment(\.requestReview) private var requestReview
    @State private var showingOnboarding = false
    @State private var hasRecordedLaunch = false

    var body: some View {
        TabView {
            MapTabView()
                .tabItem { Label("Map", systemImage: "map") }
            ListTabView()
                .tabItem { Label("Trails", systemImage: "list.bullet") }
            AboutTabView()
                .tabItem { Label("About", systemImage: "info.circle") }
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
