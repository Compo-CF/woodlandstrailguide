import Foundation
import StoreKit
import Observation

/// StoreKit 2 wrapper for the app's in-app purchases:
///   - One non-consumable, `removeAds` — permanently hides the banner ad.
///   - Three consumables, `tip.small` / `tip.medium` / `tip.large` — pure
///     support-the-developer tips with no in-app functionality attached.
///
/// Ownership of the non-consumable is authoritative from Apple via
/// `Transaction.currentEntitlements`. Consumables are tracked locally in
/// UserDefaults by count only — StoreKit 2 intentionally doesn't remember
/// consumables server-side, so this is our own tally.
///
/// If products fail to load (network hiccup, ASC not yet configured, sandbox
/// tester mismatch), `products` stays empty and the UI degrades gracefully
/// to a "temporarily unavailable" state rather than crashing.
@Observable
@MainActor
final class IAPStore {
    static let removeAdsID = "com.compofelice.WoodlandsTrailGuide.removeAds"
    static let tipSmallID  = "com.compofelice.WoodlandsTrailGuide.tip.small"
    static let tipMediumID = "com.compofelice.WoodlandsTrailGuide.tip.medium"
    static let tipLargeID  = "com.compofelice.WoodlandsTrailGuide.tip.large"

    static let allIDs: Set<String> = [
        removeAdsID, tipSmallID, tipMediumID, tipLargeID
    ]

    var products: [Product] = []
    var hasRemovedAds: Bool = false
    var isLoading: Bool = false
    var lastError: String?

    private let defaults = UserDefaults.standard
    private let tipCountKey = "iap.tipCount.v1"

    /// Total tips the user has left over the lifetime of the install.
    /// Persisted in UserDefaults — StoreKit doesn't remember consumables
    /// between reinstalls, so this is our own counter.
    var tipCount: Int {
        get { defaults.integer(forKey: tipCountKey) }
        set { defaults.set(newValue, forKey: tipCountKey) }
    }

    private var updatesTask: Task<Void, Never>?

    init() {
        updatesTask = listenForTransactions()
        Task { await refresh() }
    }

    deinit {
        updatesTask?.cancel()
    }

    // MARK: - Products & entitlements

    /// Load product metadata from the App Store and reconcile ownership of the
    /// non-consumable. Safe to call repeatedly (idempotent).
    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let fetched = try await Product.products(for: Self.allIDs)
            products = fetched.sorted { $0.price < $1.price }
            await updateEntitlements()
        } catch {
            lastError = "Couldn't load purchases: \(error.localizedDescription)"
        }
    }

    /// Reconcile non-consumable ownership with StoreKit's current entitlements.
    /// Consumables intentionally never appear here — that's StoreKit 2 by
    /// design, and the local tipCount handles the "how many times has this
    /// user tipped" question separately.
    func updateEntitlements() async {
        var owned = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let tx) = result, tx.productID == Self.removeAdsID {
                owned = true
            }
        }
        hasRemovedAds = owned
    }

    // MARK: - Purchase flow

    /// Attempts to purchase the given product. Returns true if the purchase
    /// completed (transaction verified + finished). Returns false on user
    /// cancel, pending state (Ask to Buy), or verification failure — the
    /// UI can distinguish these from `lastError`.
    @discardableResult
    func purchase(_ product: Product) async -> Bool {
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let tx = try verify(verification)
                await tx.finish()
                if tx.productID == Self.removeAdsID {
                    hasRemovedAds = true
                } else if product.type == .consumable {
                    tipCount += 1
                }
                return true
            case .userCancelled, .pending:
                return false
            @unknown default:
                return false
            }
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    /// Manual restore for the non-consumable. `AppStore.sync()` re-checks
    /// entitlements against the user's Apple ID — useful after a reinstall
    /// or a device swap. Consumables can't be restored (that's Apple's
    /// design, not ours).
    func restorePurchases() async {
        do {
            try await AppStore.sync()
            await updateEntitlements()
        } catch {
            lastError = "Restore failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Convenience accessors

    var removeAdsProduct: Product? {
        products.first { $0.id == Self.removeAdsID }
    }

    var tipProducts: [Product] {
        [Self.tipSmallID, Self.tipMediumID, Self.tipLargeID]
            .compactMap { id in products.first { $0.id == id } }
    }

    // MARK: - Internals

    /// Long-lived listener for transactions that arrive outside of our
    /// direct `purchase(_:)` call — App Store promotions, family sharing,
    /// StoreKit auto-renewing after a network interruption, etc.
    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached { [weak self] in
            for await result in Transaction.updates {
                guard case .verified(let tx) = result else { continue }
                await tx.finish()
                await self?.updateEntitlements()
            }
        }
    }

    private func verify<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified: throw StoreError.verificationFailed
        case .verified(let value): return value
        }
    }

    enum StoreError: LocalizedError {
        case verificationFailed
        var errorDescription: String? {
            switch self {
            case .verificationFailed: return "Purchase could not be verified."
            }
        }
    }
}
