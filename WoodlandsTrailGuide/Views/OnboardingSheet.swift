import SwiftUI

struct OnboardingSheet: View {
    @Environment(\.dismiss) private var dismiss

    private let kofiURL = URL(string: "https://ko-fi.com/subtlefoodie")!

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer(minLength: 32)
                Image(systemName: "figure.hiking")
                    .font(.system(size: 64, weight: .light))
                    .foregroundStyle(Natural.forest)
                Text("Welcome")
                    .font(.largeTitle).bold()
                    .foregroundStyle(Natural.ink)
                Text("Find your way around The Woodlands' 200+ miles of hike-and-bike pathways. Browse trails by village or park, tap any trail on the map to see its name and length, and tap the directions button to route a walk.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Natural.ink)
                    .padding(.horizontal, 28)

                supportCard
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                Spacer(minLength: 32)
            }
            .frame(maxWidth: .infinity)
        }
        .background(Natural.cardBg.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            Button {
                dismiss()
            } label: {
                Text("Let's go")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Natural.forest, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
            .padding(.top, 8)
            .background(Natural.cardBg)
        }
    }

    /// The "support the developer" card — same Ko-fi target as the
    /// engagement nudge later, but framed up front so users who want to
    /// chip in early have an obvious way to do it.
    private var supportCard: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "cup.and.saucer.fill")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Natural.route, in: Circle())
                Text("Built by a local in his spare time")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Natural.ink)
                Spacer(minLength: 0)
            }
            Text("If the app's useful, a coffee on Ko-fi keeps the trail data growing and the next features coming. No pressure either way.")
                .font(.footnote)
                .foregroundStyle(Natural.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Link(destination: kofiURL) {
                HStack(spacing: 6) {
                    Image(systemName: "heart.fill")
                        .font(.caption.weight(.bold))
                    Text("Buy me a coffee on Ko-fi")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(Natural.route, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            }
            .padding(.top, 2)
        }
        .padding(16)
        .background(Natural.chipBg, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Natural.hairline, lineWidth: 0.5)
        )
    }
}
