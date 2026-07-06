import SwiftUI

/// First-run walkthrough — four cards covering what the app is, where the
/// data comes from, what's in it, and how to route a walk. Only shown once
/// (gated on UserDataStore.hasSeenOnboarding). Completing the sheet also
/// flips hasSeenRoutingIntro so the standalone RoutingIntroSheet doesn't
/// pop later — this covers the same ground.
struct OnboardingSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(UserDataStore.self) private var userData
    @State private var page: Int = 0

    private let totalPages = 4

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                OverviewPage().tag(0)
                DataPage().tag(1)
                FeaturesPage().tag(2)
                RoutingPage().tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .interactive))

            continueBar
        }
        .background(Natural.cardBg.ignoresSafeArea())
    }

    private var continueBar: some View {
        HStack(spacing: 12) {
            Button {
                withAnimation(.easeInOut(duration: 0.22)) { page = max(0, page - 1) }
            } label: {
                Text("Back")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Natural.inkMuted)
                    .padding(.horizontal, 20).padding(.vertical, 12)
            }
            .opacity(page > 0 ? 1 : 0)
            .disabled(page == 0)

            Spacer(minLength: 0)

            Button {
                if page < totalPages - 1 {
                    withAnimation(.easeInOut(duration: 0.22)) { page += 1 }
                } else {
                    userData.hasSeenRoutingIntro = true
                    dismiss()
                }
            } label: {
                Text(page < totalPages - 1 ? "Next" : "Let's go")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(minWidth: 120)
                    .padding(.horizontal, 20).padding(.vertical, 12)
                    .background(Natural.forest, in: Capsule())
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
        .padding(.bottom, 24)
    }
}

// MARK: - Page 1: Overview

private struct OverviewPage: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Spacer(minLength: 32)
                Image(systemName: "figure.hiking")
                    .font(.system(size: 72, weight: .light))
                    .foregroundStyle(Natural.forest)
                    .padding(.bottom, 4)
                Text("Welcome")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(Natural.ink)
                Text("An independent guide to The Woodlands' 200+ miles of hike-and-bike pathways — every named segment across all nine villages, plus the parks, bridges, playgrounds, and water fountains you'll pass along the way.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Natural.ink)
                    .padding(.horizontal, 28)

                HStack(spacing: 22) {
                    StatBadge(number: "200+", label: "miles")
                    StatBadge(number: "1,500+", label: "trails")
                    StatBadge(number: "9", label: "villages")
                    StatBadge(number: "3,400+", label: "POIs")
                }
                .padding(.top, 12)
                Spacer(minLength: 48)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

private struct StatBadge: View {
    let number: String
    let label: String
    var body: some View {
        VStack(spacing: 2) {
            Text(number)
                .font(.headline.bold().monospacedDigit())
                .foregroundStyle(Natural.forest)
            Text(label)
                .font(.caption2.weight(.semibold))
                .textCase(.uppercase)
                .tracking(0.6)
                .foregroundStyle(Natural.inkMuted)
        }
    }
}

// MARK: - Page 2: Data sources

private struct DataPage: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Spacer(minLength: 32)
                Image(systemName: "building.columns.fill")
                    .font(.system(size: 60, weight: .light))
                    .foregroundStyle(Natural.forest)
                Text("Built on public data")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Natural.ink)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                Text("Trail and amenity data comes from The Woodlands Township's public ArcGIS services — the same database the Township uses internally. The app bundles a copy for offline use and refreshes over the air when the Township updates. Weather is from Open-Meteo.")
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Natural.ink)
                    .padding(.horizontal, 28)

                VStack(spacing: 10) {
                    SourceRow(icon: "map.fill", title: "The Woodlands Township GIS",
                              detail: "Pathways, trails, parks, bridges, playgrounds, restrooms, and more — 30 categories.")
                    SourceRow(icon: "cloud.sun.fill", title: "Open-Meteo",
                              detail: "Current temperature, condition, and wind. Free, no account.")
                    SourceRow(icon: "map.circle.fill", title: "Apple Maps",
                              detail: "Base tiles, imagery, and Standard/Hybrid/Satellite styles.")
                }
                .padding(.horizontal, 20)

                Text("Nothing you do in the app leaves your phone unless you tap \"Report a problem.\"")
                    .font(.footnote)
                    .foregroundStyle(Natural.inkMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.top, 4)

                Text("Independently built by a local. Not affiliated with, endorsed by, or sponsored by The Woodlands Township.")
                    .font(.caption)
                    .foregroundStyle(Natural.inkMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Spacer(minLength: 48)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

private struct SourceRow: View {
    let icon: String
    let title: String
    let detail: String
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(Natural.forest, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                    .foregroundStyle(Natural.ink)
                Text(detail).font(.caption)
                    .foregroundStyle(Natural.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Natural.chipBg, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Page 3: Feature tour

private struct FeaturesPage: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Spacer(minLength: 32)
                Image(systemName: "sparkles")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(Natural.forest)
                Text("What's here")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Natural.ink)

                VStack(spacing: 10) {
                    FeatureRow(icon: "hand.tap.fill",
                               title: "Tap any trail",
                               detail: "See its name, surface, length, and which parks it connects to.")
                    FeatureRow(icon: "magnifyingglass",
                               title: "Search",
                               detail: "Find any pathway, park, or amenity by name — jump straight there.")
                    FeatureRow(icon: "cloud.sun.fill",
                               title: "Weather at a glance",
                               detail: "Current temp and condition in the top-left. Tap for advisories.")
                    FeatureRow(icon: "mappin.and.ellipse",
                               title: "Every amenity is tappable",
                               detail: "Bridges, playgrounds, restrooms, fountains — tap for distance from you and route-here.")
                    FeatureRow(icon: "globe.americas.fill",
                               title: "Three map styles",
                               detail: "Standard, Hybrid (satellite + labels), or Satellite. Toggle top-right.")
                    FeatureRow(icon: "list.bullet.rectangle",
                               title: "Trip log",
                               detail: "Every completed walk is saved to the About tab.")
                }
                .padding(.horizontal, 20)

                Spacer(minLength: 48)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

private struct FeatureRow: View {
    let icon: String
    let title: String
    let detail: String
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Natural.forest)
                .frame(width: 32, height: 32)
                .background(Natural.chipBg, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                    .foregroundStyle(Natural.ink)
                Text(detail).font(.caption)
                    .foregroundStyle(Natural.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Page 4: Routing walkthrough

private struct RoutingPage: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Spacer(minLength: 32)
                Image(systemName: "point.topleft.down.to.point.bottomright.curvepath.fill")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(Natural.forest)
                Text("Get walking directions")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(Natural.ink)
                    .multilineTextAlignment(.center)

                VStack(spacing: 12) {
                    RouteStep(number: 1,
                              title: "Tap the directions button",
                              detail: "Top-right of the map — curving-path icon.")
                    RouteStep(number: 2,
                              title: "Tap a starting point, then a destination",
                              detail: "Green pin drops on the start, red on the end.")
                    RouteStep(number: 3,
                              title: "Optional: add a waypoint",
                              detail: "Tap \"Add stop\" to route via a specific trail.")
                    RouteStep(number: 4,
                              title: "Tap Start walking",
                              detail: "Live turn-by-turn with the screen kept on.")
                }
                .padding(.horizontal, 20)

                Spacer(minLength: 48)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

// A support card previously lived on this last page linking to Ko-fi.
// Removed to comply with App Store Review Guideline 3.1.1 — donations
// associated with the app itself must go through In-App Purchase, not
// external payment mechanisms. Revisit with a Tip Jar IAP if we want
// tips back.

private struct RouteStep: View {
    let number: Int
    let title: String
    let detail: String
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.subheadline.bold().monospacedDigit())
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(Natural.forest, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                    .foregroundStyle(Natural.ink)
                Text(detail).font(.footnote)
                    .foregroundStyle(Natural.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}
