import SwiftUI

struct ContentView: View {
    @Environment(UserDataStore.self) private var userData
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
            }
        }
    }
}
