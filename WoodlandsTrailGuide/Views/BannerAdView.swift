import SwiftUI
import GoogleMobileAds

/// Thin SwiftUI wrapper around Google Mobile Ads' UIKit GADBannerView.
/// Sized to the standard 320x50 banner. Loads an ad on appear and silently
/// no-ops on failure so the rest of the UI is never blocked.
///
/// Mirrors the WoodlandsFishing implementation verbatim — same banner shape,
/// same load policy. Replace the test ad unit ID in MapTabView once the
/// trails app is registered in the AdMob console.
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
