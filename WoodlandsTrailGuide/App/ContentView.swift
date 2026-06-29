import SwiftUI
import StoreKit

struct ContentView: View {
    @Environment(UserDataStore.self) private var userData
    @Environment(\.requestReview) private var requestReview
    @State private var showingOnboarding = false
    @State private var showingKofiPrompt = false
    @State private var hasRecordedLaunch = false

    private let kofiURL = URL(string: "https://ko-fi.com/subtlefoodie")!

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
        .alert("Enjoying the app?", isPresented: $showingKofiPrompt) {
            Button("Maybe later", role: .cancel) {
                userData.markKofiPromptShown()
            }
            Button("Buy me a coffee") {
                userData.markKofiPromptShown()
                UIApplication.shared.open(kofiURL)
            }
        } message: {
            Text("This app is built and maintained by one local in his spare time. If it's been useful, consider buying a coffee on Ko-fi — it keeps the trail data growing. No pressure either way.")
        }
        .onAppear {
            guard !hasRecordedLaunch else { return }
            hasRecordedLaunch = true
            userData.recordAppLaunch()
            if !userData.hasSeenOnboarding {
                showingOnboarding = true
            } else {
                considerPostLaunchPrompts()
            }
        }
    }

    /// On a returning user's cold launch, after the UI has settled, either
    /// ask iOS to consider a review prompt (preferred — system-styled, no
    /// custom UI to maintain) or show the Ko-fi engagement nudge. Never
    /// both in the same session; the review request takes priority once
    /// the user has earned it.
    private func considerPostLaunchPrompts() {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            if userData.appLaunches >= 3 && userData.eligibleForReviewRequest {
                requestReview()
                userData.markReviewRequested()
            } else if userData.shouldShowKofiPrompt {
                showingKofiPrompt = true
            }
        }
    }
}
