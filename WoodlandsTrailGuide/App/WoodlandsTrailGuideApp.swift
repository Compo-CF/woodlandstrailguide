import SwiftUI
import GoogleMobileAds
import AppTrackingTransparency

@main
struct WoodlandsTrailGuideApp: App {
    @State private var store = TrailStore()
    @State private var poiStore = POIStore()
    @State private var locationManager = LocationManager()
    @State private var userData = UserDataStore()
    @State private var weatherStore = WeatherStore()
    @State private var routingBridge = RoutingBridge()
    @State private var elevationService = ElevationService()
    @State private var poiPhotoStore = POIPhotoStore()
    @State private var iapStore = IAPStore()

    init() {
        // Initialize Google Mobile Ads SDK. Ads start loading immediately;
        // the BannerAdView call sites kick off individual requests when shown.
        GADMobileAds.sharedInstance().start(completionHandler: nil)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .environment(poiStore)
                .environment(locationManager)
                .environment(userData)
                .environment(weatherStore)
                .environment(routingBridge)
                .environment(elevationService)
                .environment(poiPhotoStore)
                .environment(iapStore)
                .onOpenURL { url in
                    // woodlandstrailguide://route?start=…&end=…&via=…
                    if let pending = RoutingBridge.parse(url) {
                        routingBridge.pending = pending
                    }
                }
                .onChange(of: locationManager.location) { _, newValue in
                    store.userLocation = newValue
                }
                .task(id: locationManager.authorizationStatus) {
                    // Chain the App Tracking Transparency request to fire AFTER
                    // the location-permission prompt is resolved. iOS 17/18
                    // suppresses one system prompt when another is already up,
                    // and the map's location prompt fires first — so a pure
                    // time-based ATT request gets silently dropped on first
                    // launch. Sequencing them via .task(id:) on the location
                    // authorization status guarantees the ATT prompt actually
                    // appears.
                    guard locationManager.authorizationStatus != .notDetermined else { return }
                    try? await Task.sleep(nanoseconds: 700_000_000)
                    if ATTrackingManager.trackingAuthorizationStatus == .notDetermined {
                        _ = await ATTrackingManager.requestTrackingAuthorization()
                    }
                }
        }
    }
}
