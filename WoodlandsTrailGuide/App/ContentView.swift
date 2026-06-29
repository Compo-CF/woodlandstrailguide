import SwiftUI

struct ContentView: View {
    @Environment(UserDataStore.self) private var userData
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
            } else if userData.shouldShowKofiPrompt {
                // Brief delay so the prompt doesn't appear instantly on
                // cold launch — gives the app a beat to settle before
                // interrupting the user.
                Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    showingKofiPrompt = true
                }
            }
        }
    }
}
