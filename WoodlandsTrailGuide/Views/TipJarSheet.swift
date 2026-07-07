import SwiftUI
import StoreKit

/// Three-tier tip picker. Opens from the About tab. Tapping a tier fires the
/// StoreKit purchase flow; on success we increment the local tipCount and
/// show a thank-you alert.
struct TipJarSheet: View {
    @Environment(IAPStore.self) private var iap
    @Environment(\.dismiss) private var dismiss

    @State private var isProcessing = false
    @State private var showingThanks = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    Image(systemName: "cup.and.saucer.fill")
                        .font(.system(size: 54, weight: .light))
                        .foregroundStyle(Natural.route)
                        .padding(.top, 20)

                    VStack(spacing: 8) {
                        Text("Support the app")
                            .font(.title2.bold())
                            .foregroundStyle(Natural.ink)
                        Text("Built and maintained by one local on weekends. Every tip goes toward keeping the trail data current and building new features.")
                            .font(.callout)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(Natural.inkMuted)
                            .padding(.horizontal, 24)
                    }

                    if iap.tipProducts.isEmpty {
                        if iap.isLoading {
                            ProgressView().padding(.vertical, 32)
                        } else {
                            VStack(spacing: 6) {
                                Text("Tips are temporarily unavailable")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Natural.inkMuted)
                                Text("Check back in a moment, or reach out via Support & FAQ if this keeps happening.")
                                    .font(.caption)
                                    .foregroundStyle(Natural.inkMuted)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 32)
                            }
                            .padding(.vertical, 24)
                        }
                    } else {
                        VStack(spacing: 10) {
                            ForEach(iap.tipProducts, id: \.id) { product in
                                tipButton(for: product)
                            }
                        }
                        .padding(.horizontal, 20)
                    }

                    if iap.tipCount > 0 {
                        Text("You've supported the app \(iap.tipCount) time\(iap.tipCount == 1 ? "" : "s") — thank you.")
                            .font(.caption)
                            .foregroundStyle(Natural.forest)
                    }

                    Text("Tips are processed by Apple and are non-refundable through the app. Contact Apple Support if you need a refund.")
                        .font(.caption2)
                        .foregroundStyle(Natural.inkMuted)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .padding(.top, 8)
                }
                .padding(.bottom, 32)
            }
            .background(Natural.cardBg)
            .navigationTitle("Send a tip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
            .alert("Thank you!", isPresented: $showingThanks) {
                Button("You're welcome", role: .cancel) {}
            } message: {
                Text("Every tip goes toward keeping the trail data current and building new features. It means a lot.")
            }
        }
    }

    private func tipButton(for product: Product) -> some View {
        Button {
            Task {
                isProcessing = true
                let ok = await iap.purchase(product)
                isProcessing = false
                if ok { showingThanks = true }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: tipIcon(for: product))
                    .font(.callout)
                    .foregroundStyle(Natural.forest)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(tipLabel(for: product))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Natural.ink)
                    Text(tipCaption(for: product))
                        .font(.caption)
                        .foregroundStyle(Natural.inkMuted)
                }
                Spacer()
                Text(product.displayPrice)
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(Natural.ink)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(Natural.chipBg, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .disabled(isProcessing)
    }

    private func tipLabel(for product: Product) -> String {
        switch product.id {
        case IAPStore.tipSmallID:  return "Small tip"
        case IAPStore.tipMediumID: return "Regular tip"
        case IAPStore.tipLargeID:  return "Generous tip"
        default: return product.displayName
        }
    }

    private func tipCaption(for product: Product) -> String {
        switch product.id {
        case IAPStore.tipSmallID:  return "A quick thanks"
        case IAPStore.tipMediumID: return "Covers hosting for a while"
        case IAPStore.tipLargeID:  return "Funds a new feature"
        default: return ""
        }
    }

    private func tipIcon(for product: Product) -> String {
        switch product.id {
        case IAPStore.tipSmallID:  return "heart"
        case IAPStore.tipMediumID: return "heart.fill"
        case IAPStore.tipLargeID:  return "heart.circle.fill"
        default: return "heart"
        }
    }
}
