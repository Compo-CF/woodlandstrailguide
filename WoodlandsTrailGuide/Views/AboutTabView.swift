import SwiftUI

struct AboutTabView: View {
    @Environment(TrailStore.self) private var store
    @Environment(UserDataStore.self) private var userData
    @Environment(LocationManager.self) private var locationManager
    @Environment(IAPStore.self) private var iap
    @Environment(CoverageStore.self) private var coverage
    @State private var showingReport = false
    @State private var showingTipJar = false
    @State private var showingAchievements = false
    @State private var showingCoverage = false
    @State private var isRestoring = false
    @State private var isPurchasingRemoveAds = false
    @State private var isRequestingHealthKit = false

    /// Studio page listing every After Hours Dev Studio app. Replaces the
    /// old per-app cross-promo rows, so new apps show up without a release.
    private let studioURL = URL(string: "https://compo-cf.github.io/afterhoursdevstudio/")!
    private let supportURL = URL(string: "https://compo-cf.github.io/woodlandstrailguide/support.html")!
    /// Deep link straight into the App Store's write-a-review sheet for this
    /// app. The system requestReview() prompt is rate-limited by Apple (3/yr,
    /// and it alone decides whether to actually show) — this row is the only
    /// path a motivated user has to leave a rating on purpose.
    private let writeReviewURL = URL(string: "https://apps.apple.com/app/id6785576912?action=write-review")!
    /// The local newsletter this app's audience overlaps with almost
    /// exactly. Costs one row here and moves readers to a channel we own,
    /// which is worth more than another App Store cross-promo.
    private let dispatchURL = URL(string: "https://thewoodlandsdispatch.com")!

    /// Prefilled mailto: link for community-submitted Featured Walk suggestions.
    /// Users tap "Suggest a Featured Walk" -> compose a pre-templated email to
    /// Anthony with the fields we need to add the walk to FeaturedWalks.json.
    private var suggestWalkMailURL: URL {
        let subject = "Featured Walk suggestion — The Woodlands Trail Guide"
        let body = """
        Suggest a walk to add to Featured Walks in The Woodlands Trail Guide.

        Name of the walk:
        (e.g. "Panther Creek Sunset Loop")

        Where it starts and ends:
        (parking lot, address, or approximate coordinates)

        Approximate distance:

        Difficulty (easy / moderate / strenuous):

        What makes it special (highlights, views, features):
        1.
        2.
        3.

        Best time of day / season to walk it:

        Anything else you want me to know:
        """
        var comps = URLComponents()
        comps.scheme = "mailto"
        comps.path = "anthony.compofelice@centricfiber.com"
        comps.queryItems = [
            .init(name: "subject", value: subject),
            .init(name: "body", value: body)
        ]
        return comps.url ?? URL(string: "mailto:anthony.compofelice@centricfiber.com")!
    }

    /// Row in the "Also from this developer" section (links to the studio page).
    private func developerAppRow(icon: String, tint: Color, name: String, tagline: String, url: URL) -> some View {
        Link(destination: url) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(tint, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Natural.ink)
                    Text(tagline)
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

    var body: some View {
        NavigationStack {
            List {
                Section("About this app") {
                    Text("A community-built map of The Woodlands' hike-and-bike pathways. Built by a local on weekends — feedback welcome.")
                        .font(.callout)
                }

                Section("Also from this developer") {
                    developerAppRow(
                        icon: "moon.stars.fill",
                        tint: Color(red: 0.24, green: 0.12, blue: 0.46),
                        name: "More from After Hours Dev Studio",
                        tagline: "S-Tier Eats, the Fishing Guide, Cosmica and more.",
                        url: studioURL
                    )
                }

                // Always shown, unlike the provisional step-3 readout this
                // replaces. A set to complete is only motivating if you can
                // see it before you've started — "0% of The Woodlands" is an
                // invitation, and hiding it until the first walk means nobody
                // discovers the feature exists.
                Section("Your Woodlands") {
                    let overall = coverage.overallProgress()
                    Button {
                        showingCoverage = true
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(CoverageSheet.percentText(overall.fraction))
                                    .font(NaturalType.display(26, weight: .bold,
                                                              relativeTo: .title))
                                    .foregroundStyle(Natural.ink)
                                Text(String(format: "of %.0f miles walked",
                                            overall.totalMiles))
                                    .font(.subheadline)
                                    .foregroundStyle(Natural.inkMuted)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(Natural.inkMuted)
                            }
                            CoverageBar(fraction: overall.fraction, height: 6)
                        }
                        .padding(.vertical, 4)
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
                        Button {
                            showingAchievements = true
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "trophy.fill")
                                    .foregroundStyle(Natural.forest)
                                Text("Achievements")
                                    .foregroundStyle(Natural.ink)
                                Spacer()
                                Text("\(userData.celebratedAchievementIDs.count)/\(Achievement.all.count)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(Natural.inkMuted)
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
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

                Section {
                    Toggle(isOn: Binding(
                        get: { userData.healthKitSyncEnabled },
                        set: { newValue in
                            if newValue {
                                isRequestingHealthKit = true
                                Task {
                                    let granted = await HealthKitService.shared.requestAuthorization()
                                    userData.healthKitSyncEnabled = granted
                                    userData.saveHealthKitSyncEnabled()
                                    isRequestingHealthKit = false
                                }
                            } else {
                                userData.healthKitSyncEnabled = false
                                userData.saveHealthKitSyncEnabled()
                            }
                        }
                    )) {
                        HStack(spacing: 8) {
                            Image(systemName: "heart.text.square.fill")
                                .foregroundStyle(Natural.route)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Sync walks to Apple Health")
                                    .foregroundStyle(Natural.ink)
                                Text("Each completed walk is logged as a workout.")
                                    .font(.caption)
                                    .foregroundStyle(Natural.inkMuted)
                            }
                        }
                    }
                    .disabled(isRequestingHealthKit)
                } header: {
                    Text("Apple Health")
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
                    Link(destination: writeReviewURL) {
                        HStack(spacing: 8) {
                            Image(systemName: "star.bubble")
                                .foregroundStyle(Natural.route)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Rate The Woodlands Trail Guide")
                                    .foregroundStyle(Natural.ink)
                                Text("Ratings help other Woodlands walkers find the app.")
                                    .font(.caption)
                                    .foregroundStyle(Natural.inkMuted)
                            }
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    Link(destination: dispatchURL) {
                        HStack(spacing: 8) {
                            Image(systemName: "newspaper")
                                .foregroundStyle(Natural.forest)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("The Woodlands Dispatch")
                                    .foregroundStyle(Natural.ink)
                                Text("Local news, trails and food — free newsletter from the same author.")
                                    .font(.caption)
                                    .foregroundStyle(Natural.inkMuted)
                            }
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
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
                    Link(destination: suggestWalkMailURL) {
                        HStack(spacing: 8) {
                            Image(systemName: "star.circle")
                                .foregroundStyle(Natural.route)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Suggest a Featured Walk")
                                    .foregroundStyle(Natural.ink)
                                Text("Know a scenic route or hidden gem? Email me your suggestion.")
                                    .font(.caption)
                                    .foregroundStyle(Natural.inkMuted)
                            }
                            Spacer()
                            Image(systemName: "envelope")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

                Section {
                    Text("Trail data © The Woodlands Township.\nMade by After Hours Dev Studio.")
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
            .sheet(isPresented: $showingAchievements) {
                AchievementsSheet()
            }
            .sheet(isPresented: $showingCoverage) {
                CoverageSheet()
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

