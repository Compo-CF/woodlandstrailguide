import SwiftUI

/// Grid of every achievement.
///
/// Earned ones are filled and checked; locked ones keep their own icon,
/// ghosted, with how far along you are. The previous version drew every
/// locked badge as an identical grey padlock, which made a screen users
/// open on purpose look like a wall of denial — and told somebody sitting
/// at 24 of 25 miles exactly as much as it told somebody at zero. Every
/// threshold in the catalog is numeric, so there was no reason not to say.
struct AchievementsSheet: View {
    @Environment(UserDataStore.self) private var userData
    @Environment(IAPStore.self) private var iap
    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                let stats = userData.tripStats
                let earned = userData.celebratedAchievementIDs
                let hasTipped = iap.tipCount > 0

                header(earnedCount: earned.count)

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(Achievement.all) { achievement in
                        AchievementTile(
                            achievement: achievement,
                            unlocked: earned.contains(achievement.id),
                            progress: achievement.progress(
                                stats: stats,
                                favoritesCount: userData.favoriteWayIDs.count,
                                hasTipped: hasTipped
                            )
                        )
                    }
                }
                .padding(16)
            }
            .background(Natural.cardBg.ignoresSafeArea())
            .navigationTitle("Achievements")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func header(earnedCount: Int) -> some View {
        let total = Achievement.all.count
        let fraction = total > 0 ? Double(earnedCount) / Double(total) : 0
        return VStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(earnedCount)")
                    .font(NaturalType.display(32, weight: .bold, relativeTo: .title))
                    .foregroundStyle(Natural.ink)
                Text("of \(total) earned")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Natural.inkMuted)
            }
            ProgressBar(fraction: fraction, height: 6)
                .frame(maxWidth: 220)
        }
        .padding(.top, 14)
        .padding(.bottom, 2)
    }
}

/// Thin capsule bar. Shared by the header and the locked tiles so a single
/// visual language carries "how far along" everywhere on this screen.
private struct ProgressBar: View {
    let fraction: Double
    var height: CGFloat = 4

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Natural.chipBg)
                Capsule()
                    .fill(Natural.forest)
                    .frame(width: max(geo.size.width * min(max(fraction, 0), 1),
                                      // Keep a sliver visible at tiny values
                                      // so "started" reads differently from
                                      // "not started".
                                      fraction > 0 ? height : 0))
            }
        }
        .frame(height: height)
    }
}

private struct AchievementTile: View {
    let achievement: Achievement
    let unlocked: Bool
    let progress: Achievement.Progress?

    var body: some View {
        VStack(spacing: 8) {
            badge
            Text(achievement.title)
                .font(NaturalType.display(15, weight: .semibold, relativeTo: .subheadline))
                .foregroundStyle(unlocked ? Natural.ink : Natural.inkMuted)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            Text(achievement.subtitle)
                .font(.caption2)
                .foregroundStyle(Natural.inkMuted)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            // Only on locked tiles: once it's earned the number is history,
            // and showing "25 / 25" next to a checkmark is just clutter.
            if !unlocked, let progress {
                VStack(spacing: 4) {
                    ProgressBar(fraction: progress.fraction)
                    Text(progress.label)
                        .font(.caption2.weight(.medium).monospacedDigit())
                        .foregroundStyle(Natural.inkMuted)
                }
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14).padding(.horizontal, 10)
        .background(Natural.buttonBg,
                    in: RoundedRectangle(cornerRadius: NaturalType.Metrics.radiusMedium,
                                         style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: NaturalType.Metrics.radiusMedium, style: .continuous)
                .strokeBorder(unlocked ? Natural.forest.opacity(0.45) : Natural.hairline,
                              lineWidth: unlocked ? 1.5 : 1)
        )
        .naturalRestingShadow()
    }

    /// The badge itself. Locked tiles keep the achievement's own symbol
    /// rather than swapping in a padlock — the grid should read as a set to
    /// complete, not a list of things withheld.
    private var badge: some View {
        ZStack {
            Circle()
                .fill(unlocked ? Natural.forest : Natural.chipBg)
                .frame(width: 52, height: 52)
            Image(systemName: achievement.systemImage)
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(unlocked ? .white : Natural.inkMuted.opacity(0.55))

            if unlocked {
                // Small earned marker, bottom-trailing, so a filled badge is
                // unambiguous at a glance even in a dense grid.
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Natural.forest)
                    .background(Circle().fill(Natural.buttonBg).frame(width: 15, height: 15))
                    .offset(x: 20, y: 18)
            }
        }
        .frame(width: 52, height: 52)
    }
}
