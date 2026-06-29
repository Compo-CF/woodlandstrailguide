import SwiftUI

/// One-time educational sheet shown the first time the user taps the
/// directions toggle. Walks through the four-step routing flow so the
/// pin-tapping interaction isn't a guessing game.
struct RoutingIntroSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "point.topleft.down.to.point.bottomright.curvepath.fill")
                    .font(.title2)
                    .foregroundStyle(Natural.forest)
                    .frame(width: 44, height: 44)
                    .background(Natural.chipBg, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("Get walking directions")
                        .font(.title3.bold())
                        .foregroundStyle(Natural.ink)
                    Text("Across the Township pathway network")
                        .font(.caption)
                        .foregroundStyle(Natural.inkMuted)
                }
                Spacer()
            }
            .padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 8)

            VStack(spacing: 18) {
                StepRow(
                    number: 1,
                    title: "Tap a starting point",
                    detail: "Anywhere along a trail. A green pin drops where you tapped."
                )
                StepRow(
                    number: 2,
                    title: "Tap your destination",
                    detail: "A red pin drops, and the app routes the shortest path between the two."
                )
                StepRow(
                    number: 3,
                    title: "Review what's ahead",
                    detail: "Total distance, walking time, the pathways you'll follow, the parks you'll pass through, and amenities along the way."
                )
                StepRow(
                    number: 4,
                    title: "Tap Start when you're ready",
                    detail: "Your phone keeps the screen on, follows your location, and tells you what comes next."
                )
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)

            Spacer(minLength: 16)

            Button {
                dismiss()
            } label: {
                Text("Got it")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Natural.forest, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
        }
        .background(Natural.cardBg)
    }
}

private struct StepRow: View {
    let number: Int
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(number)")
                .font(.subheadline.bold().monospacedDigit())
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(Natural.forest, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Natural.ink)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(Natural.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}
