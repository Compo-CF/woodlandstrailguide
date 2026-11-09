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

/// The map's bottom banner, sized by the ad rather than by a hardcoded
/// constant.
///
/// ## Why this exists (2026-11-09)
/// `MapTabView` used to put `BannerAdView` in a `.safeAreaInset` with a
/// literal `.frame(height: 50)`. That reserved 50pt whether or not an ad ever
/// arrived — the same defect that showed as a permanent blank strip on
/// Android (`woodlandstrailguide_flutter@8330bf0`). It stayed invisible here
/// only because the iOS unit fills ~100% of requests, where Android was
/// matching 45%. A latent bug is still a bug, and anchored adaptive makes it
/// unavoidable: the height is whatever AdMob returns, so it cannot be a
/// constant.
///
/// Renders nothing until an ad loads, so the safe-area inset collapses to
/// zero and the map gets the space back.
struct MapBannerAd: View {
    let adUnitID: String

    /// Set from the ad's own `adSize` once it loads; nil whenever there is
    /// nothing to show.
    @State private var adSize: CGSize?

    var body: some View {
        // One representable, kept in the tree across load/fail so the ad is
        // never recreated by a frame change. Zero height when empty.
        BannerAdView(adUnitID: adUnitID) { size in
            adSize = size
        }
        .frame(width: adSize?.width, height: adSize?.height ?? 0)
        .frame(maxWidth: .infinity)
        .background(Natural.cardBg.opacity(adSize == nil ? 0 : 1))
    }
}

/// SwiftUI wrapper around Google Mobile Ads' UIKit `GADBannerView`, requesting
/// an **anchored adaptive** banner at the window's width.
///
/// Adaptive rather than the legacy fixed 320x50 (`GADAdSizeBanner`): it draws
/// on a larger inventory pool, and it spans the width instead of sitting as a
/// 320pt island on a bigger phone. The app is portrait-only and iPhone-only
/// (`UISupportedInterfaceOrientations` is Portrait alone,
/// `TARGETED_DEVICE_FAMILY: "1"`), so the width is fixed for the session and
/// there is no rotation case to handle — unlike the Android twin, which has
/// to reload on orientation change.
///
/// SPM pins `from: "11.0.0"`, so this is the **prefixed** SDK: the adaptive
/// call is `GADCurrentOrientationAnchoredAdaptiveBannerAdSizeWithWidth`. In
/// 12.x it becomes `currentOrientationAnchoredAdaptiveBanner(width:)`.
struct BannerAdView: UIViewRepresentable {
    let adUnitID: String
    /// Called with the loaded ad's size, or nil when there is no ad to show.
    let onSizeChange: (CGSize?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSizeChange: onSizeChange)
    }

    func makeUIView(context: Context) -> GADBannerView {
        let adSize = GADCurrentOrientationAnchoredAdaptiveBannerAdSizeWithWidth(
            Self.windowWidth()
        )
        let banner = GADBannerView(adSize: adSize)
        banner.adUnitID = adUnitID
        banner.rootViewController = Self.topViewController()
        banner.delegate = context.coordinator
        context.coordinator.banner = banner
        context.coordinator.load()
        return banner
    }

    func updateUIView(_ uiView: GADBannerView, context: Context) {
        // Keep the callback current: the Coordinator outlives each struct.
        context.coordinator.onSizeChange = onSizeChange
    }

    /// Reports load results and retries a no-fill.
    ///
    /// The retry matters: a newly registered AdMob app returns no-fill for
    /// days, so the first requests a real user makes are the ones most likely
    /// to fail. Without one, a single early failure means no ads for the
    /// whole session. Mirrors the Android twin's backoff and Transmute's
    /// `AdManager.retry`.
    final class Coordinator: NSObject, GADBannerViewDelegate {
        private static let backoff: [TimeInterval] = [30, 60, 120, 300]
        private static let maxAttempts = 5

        var onSizeChange: (CGSize?) -> Void
        weak var banner: GADBannerView?

        private var attempts = 0
        private var retryWork: DispatchWorkItem?

        init(onSizeChange: @escaping (CGSize?) -> Void) {
            self.onSizeChange = onSizeChange
        }

        deinit { retryWork?.cancel() }

        func load() {
            attempts += 1
            banner?.load(GADRequest())
        }

        func bannerViewDidReceiveAd(_ bannerView: GADBannerView) {
            retryWork?.cancel()
            report(bannerView.adSize.size)
        }

        func bannerView(_ bannerView: GADBannerView,
                        didFailToReceiveAdWithError error: Error) {
            report(nil)
            scheduleRetry()
        }

        /// Hands the size back on the next runloop turn. `makeUIView` runs
        /// inside SwiftUI's update pass, and a cached ad could in principle
        /// call back synchronously from `load()` — writing `@State` there is
        /// "Modifying state during view update", which is undefined
        /// behaviour. One hop makes that impossible for a cost nobody sees.
        private func report(_ size: CGSize?) {
            let callback = onSizeChange
            DispatchQueue.main.async { callback(size) }
        }

        private func scheduleRetry() {
            guard attempts < Self.maxAttempts else { return }
            let delay = Self.backoff[min(attempts - 1, Self.backoff.count - 1)]
            retryWork?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.load() }
            retryWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }
    }

    /// Width to request the adaptive banner at. The banner spans the bottom
    /// edge, so this is the window's width.
    private static func windowWidth() -> CGFloat {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive }
            ?? scenes.first
        let window = scene?.windows.first(where: \.isKeyWindow)
            ?? scene?.windows.first
        // 320 is the legacy banner width — a safe floor if no window is up
        // yet, which only happens if this is built before the scene attaches.
        return window?.bounds.width ?? 320
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
