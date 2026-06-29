import SwiftUI

@main
struct WoodlandsTrailGuideApp: App {
    @State private var store = TrailStore()
    @State private var locationManager = LocationManager()
    @State private var userData = UserDataStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .environment(locationManager)
                .environment(userData)
                .onChange(of: locationManager.location) { _, newValue in
                    store.userLocation = newValue
                }
        }
    }
}
