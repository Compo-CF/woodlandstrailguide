import Foundation
import CoreLocation
import Observation

@Observable
final class LocationManager: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    var location: CLLocation?
    var authorizationStatus: CLAuthorizationStatus = .notDetermined

    override init() {
        super.init()
        manager.delegate = self
        // Best precision available — trail-by-trail navigation needs to know
        // which side of a pathway intersection the user is on, not just
        // "somewhere within 10 meters."
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 4  // re-emit roughly every 4 m walked
        authorizationStatus = manager.authorizationStatus
    }

    /// True while the user has explicitly started recording a walk.
    ///
    /// The app tracks location in the background only in this state, and only
    /// because the user asked for it. Everything else — showing your dot,
    /// planning a route — runs foreground-only on plain When-In-Use.
    private(set) var isRecording = false

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    /// Keep location running with the screen off, for the length of a walk.
    ///
    /// This needs no second permission. `allowsBackgroundLocationUpdates`
    /// works under When-In-Use authorization as long as the blue status-bar
    /// indicator is showing, which is the trade: the user can see at all
    /// times, without opening the app, that it is still tracking. Asking for
    /// Always authorization instead would be a far more intrusive prompt for
    /// a capability this app does not want — it has no reason to know where
    /// you are when you haven't started a walk.
    func startRecording() {
        guard !isRecording else { return }
        guard authorizationStatus == .authorizedWhenInUse
                || authorizationStatus == .authorizedAlways else { return }
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        // iOS otherwise pauses updates when it decides you have stopped
        // moving, and does not reliably resume. Somebody waiting at a
        // crossing, or standing still to look at something, must not quietly
        // stop being recorded.
        manager.pausesLocationUpdatesAutomatically = false
        manager.startUpdatingLocation()
        isRecording = true
    }

    func stopRecording() {
        guard isRecording else { return }
        // Drop the background entitlement immediately rather than leaving it
        // armed. The blue indicator disappearing is the user-visible proof
        // that recording really stopped.
        manager.allowsBackgroundLocationUpdates = false
        manager.pausesLocationUpdatesAutomatically = true
        isRecording = false
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        location = locations.last
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways {
            manager.startUpdatingLocation()
        }
    }
}
