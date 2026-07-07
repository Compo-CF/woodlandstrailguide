import SwiftUI

struct AboutTabView: View {
    @Environment(TrailStore.self) private var store
    @Environment(UserDataStore.self) private var userData
    @Environment(LocationManager.self) private var locationManager
    @Environment(IAPStore.self) private var iap
    @State private var showingReport = false
    @State private var showingTipJar = false
    @State private var isRestoring = false
    @State private var isPurchasingRemoveAds = false

    private let fishingGuideURL = URL(string: "https://apps.apple.com/app/id6773501518")!
    private let supportURL = URL(string: "https://compo-cf.github.io/woodlandstrailguide/support.html")!

    var body: some View {
        NavigationStack {
            List {
                Section("About this app") {
                    Text("A community-built map of The Woodlands' hike-and-bike pathways. Built by a local on weekends — feedback welcome.")
                        .font(.callout)
                }

                Section("Also from this developer") {
                    Link(destination: fishingGuideURL) {
                        HStack(spacing: 12) {
                            Image(systemName: "fish.fill")
                                .font(.title3)
                                .foregroundStyle(.white)
                                .frame(width: 42, height: 42)
                                .background(
                                    Color(red: 0.04, green: 0.42, blue: 0.45),
                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                                )
                            VStack(alignment: .leading, spacing: 2) {
                                Text("The Woodlands Fishing Guide")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Natural.ink)
                                Text("The same trail-guide treatment for 80+ fishing spots across Montgomery County.")
                                    .font(.caption)
                                    .foregroundStyle(Natural.inkMuted)
                                    .lineLimit(2)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "arrow.up.right.square")
                                .font(.footnote)
                                .foregroundStyle(Natural.inkMuted)
                        }
                        .padding(.vertical, 2)
                    }
                }

                if !userData.tripLog.isEmpty {
                    let stats = userData.tripStats
                    Section("Your walking stats") {
                        HStack(spacing: 0) {
                            StatCell(number: String(format: "%.1f", stats.totalMiles), label: "miles walked")
                            Divider().frame(height: 34)
                            StatCell(number: "\(stats.walkCount)", label: "walks")
                        }
                        HStack(spacing: 0) {
                            StatCell(number: String(format: "%.2f", stats.longestMiles), label: "longest")
                            Divider().frame(height: 34)
                            StatCell(number: "\(stats.currentStreakDays)", label: stats.currentStreakDays == 1 ? "day streak" : "day streak")
                        }
                    }

                    Section("Recent walks") {
                        ForEach(userData.tripLog.prefix(10)) { trip in
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(String(format: "%.2f mi", trip.miles))
                                        .font(.subheadline.weight(.semibold))
                                        .monospacedDigit()
                                    Spacer()
                                    Text(trip.date, format: .dateTime.day().month().year(.twoDigits))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .monospacedDigit()
                                }
                                Text("\(trip.startLabel) → \(trip.endLabel)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .padding(.vertical, 2)
                        }
                        .onDelete { indexSet in
                            let toDelete = indexSet.map { userData.tripLog[$0].id }
                            for id in toDelete { userData.deleteTrip(id: id) }
                        }
                    }
                }

                Section("Data") {
                    Text("Pathway, trail, and amenity data is sourced from The Woodlands Township GIS public services. The app refreshes its local copy every launch so newly-added trails appear automatically.")
                        .font(.callout)
                    if let g = store.graph {
                        LabeledContent("Source", value: g.source)
                            .lineLimit(2)
                            .font(.caption)
                    }
                }

                Section("Support the developer") {
                    Button {
                        showingTipJar = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "cup.and.saucer.fill")
                                .foregroundStyle(Natural.route)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Send a tip")
                                    .foregroundStyle(Natural.ink)
                                if iap.tipCount > 0 {
                                    Text("You've supported \(iap.tipCount) time\(iap.tipCount == 1 ? "" : "s") — thank you")
                                        .font(.caption)
                                        .foregroundStyle(Natural.forest)
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

                Section("Remove ads") {
                    if iap.hasRemovedAds {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(Natural.forest)
                            Text("Ads removed")
                                .foregroundStyle(Natural.ink)
                            Spacer()
                            Text("Thanks!")
                                .font(.caption)
                                .foregroundStyle(Natural.inkMuted)
                        }
                    } else if let product = iap.removeAdsProduct {
                        Button {
                            Task {
                                isPurchasingRemoveAds = true
                                await iap.purchase(product)
                                isPurchasingRemoveAds = false
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "rectangle.slash")
                                    .foregroundStyle(Natural.forest)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Remove ads")
                                        .foregroundStyle(Natural.ink)
                                    Text("Permanently hide the banner. One-time purchase.")
                                        .font(.caption)
                                        .foregroundStyle(Natural.inkMuted)
                                }
                                Spacer()
                                if isPurchasingRemoveAds {
                                    ProgressView()
                                } else {
                                    Text(product.displayPrice)
                                        .font(.subheadline.weight(.bold).monospacedDigit())
                                        .foregroundStyle(Natural.ink)
                                }
                            }
                        }
                        .disabled(isPurchasingRemoveAds)
                    } else {
                        HStack(spacing: 8) {
                            Image(systemName: "rectangle.slash")
                                .foregroundStyle(Natural.inkMuted)
                            Text("Remove ads")
                                .foregroundStyle(Natural.inkMuted)
                            Spacer()
                            if iap.isLoading {
                                ProgressView()
                            } else {
                                Text("Unavailable")
                                    .font(.caption)
                                    .foregroundStyle(Natural.inkMuted)
                            }
                        }
                    }
                    Button {
                        Task {
                            isRestoring = true
                            await iap.restorePurchases()
                            isRestoring = false
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.clockwise")
                                .foregroundStyle(Natural.forest)
                            Text("Restore purchases")
                                .foregroundStyle(Natural.ink)
                            Spacer()
                            if isRestoring {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isRestoring)
                }

                Section("Help & feedback") {
                    Button {
                        showingReport = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.bubble")
                                .foregroundStyle(Natural.route)
                            Text("Report a problem")
                                .foregroundStyle(Natural.ink)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    Link(destination: supportURL) {
                        HStack(spacing: 8) {
                            Image(systemName: "questionmark.circle")
                                .foregroundStyle(Natural.forest)
                            Text("Support & FAQ")
                                .foregroundStyle(Natural.ink)
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

                Section {
                    Text("Trail data © The Woodlands Township.\nApp by Anthony Compofelice.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("About")
            .sheet(isPresented: $showingReport) {
                ReportProblemSheet(userLocation: locationManager.location)
            }
            .sheet(isPresented: $showingTipJar) {
                TipJarSheet()
            }
        }
    }
}

private struct StatCell: View {
    let number: String
    let label: String
    var body: some View {
        VStack(spacing: 2) {
            Text(number)
                .font(.title3.weight(.bold).monospacedDigit())
                .foregroundStyle(Natural.ink)
            Text(label)
                .font(.caption2)
                .textCase(.uppercase)
                .tracking(0.5)
                .foregroundStyle(Natural.inkMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }
}

