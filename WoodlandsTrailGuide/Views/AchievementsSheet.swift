import SwiftUI

/// Grid of every achievement — earned ones colored + checkmarked, locked
/// ones grayed out with their unlock condition still visible (so it reads
/// as a goal, not a mystery). Presented from the About tab.
struct AchievementsSheet: View {
    @Environment(UserDataStore.self) private var userData
    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                let unlockedCount = userData.celebratedAchievementIDs.count
                Text("\(unlockedCount) of \(Achievement.all.count) earned")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Natural.inkMuted)
                    .padding(.top, 12)

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(Achievement.all) { achievement in
                        AchievementTile(
                            achievement: achievement,
                            unlocked: userData.celebratedAchievementIDs.contains(achievement.id)
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
}

private struct AchievementTile: View {
    let achievement: Achievement
    let unlocked: Bool

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(unlocked ? Natural.forest : Natural.chipBg)
                    .frame(width: 52, height: 52)
                Image(systemName: unlocked ? achievement.systemImage : "lock.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(unlocked ? .white : Natural.inkMuted)
            }
            Text(achievement.title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(unlocked ? Natural.ink : Natural.inkMuted)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            Text(achievement.subtitle)
                .font(.caption2)
                .foregroundStyle(Natural.inkMuted)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14).padding(.horizontal, 8)
        .background(Natural.buttonBg, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(unlocked ? Natural.forest.opacity(0.35) : Natural.hairline, lineWidth: 1)
        )
        .opacity(unlocked ? 1.0 : 0.75)
    }
}
