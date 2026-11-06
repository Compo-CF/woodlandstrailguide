import SwiftUI
import GoogleMobileAds

/// Picks which banner unit to request. **Only App Store installs get the real
/// one.** Xcode (DEBUG) and TestFlight builds always use Google's test unit.
///
/// Two reasons this matters, both learned the hard way on 2026-11-06:
/// tapping your own live ads can get the AdMob account flagged, and App Store
/// screenshots shot on a TestFlight build came back carrying a third-party
/// advert ("Big Horn Lodge, Moab, Utah"), which App Review rejects.
///
/// The test: TestFlight installs carry a `sandboxReceipt`; App Store installs
/// do not. Same approach as Transmute's `AdManager.isAppStoreInstall`.
enum AdUnits {
    /// Google's public test banner — safe anywhere, never pays out.
    private static let testBanner = "ca-app-pub-3940256099942544/6300978111"
    /// Trail Guide's production banner (publisher ca-app-pub-1927040492403163).
    private static let prodBanner = "ca-app-pub-1927040492403163/1489998026"

    /// True only for builds installed from the App Store.
    static let isAppStoreInstall: Bool = {
        #if DEBUG
        return false
        #else
        return Bundle.main.appStoreReceiptURL?.lastPathComponent != "sandboxReceipt"
        #endif
    }()

    /// The banner unit this build should request.
    static var banner: String { isAppStoreInstall ? prodBanner : testBanner }
}

/// Thin SwiftUI wrapper around Google Mobile Ads' UIKit GADBannerView.
/// Sized to the standard 320x50 banner. Loads an ad on appear and silently
/// no-ops on failure so the rest of the UI is never blocked.
///
/// Mirrors the WoodlandsFishing implementation — same banner shape, same load
/// policy. ⚠️ Fishing has NOT had the `AdUnits` gate applied and still serves
/// production ads in TestFlight.
struct BannerAdView: UIViewRepresentable {
    let adUnitID: String

    func makeUIView(context: Context) -> GADBannerView {
        let banner = GADBannerView(adSize: GADAdSizeBanner)
        banner.adUnitID = adUnitID
        banner.rootViewController = Self.topViewController()
        banner.load(GADRequest())
        return banner
    }

    func updateUIView(_ uiView: GADBannerView, context: Context) {
        // Banner is one-shot per appearance; no state to push.
    }

    private static func topViewController() -> UIViewController? {
        guard
            let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
            let window = scene.windows.first(where: \.isKeyWindow)
        else { return nil }
        var top = window.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}
