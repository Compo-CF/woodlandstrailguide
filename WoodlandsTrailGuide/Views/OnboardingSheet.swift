import SwiftUI

struct OnboardingSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 16)
            Image(systemName: "figure.hiking")
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(.tint)
            Text("Welcome")
                .font(.largeTitle).bold()
            Text("Find your way around The Woodlands' 200+ miles of hike-and-bike pathways. Browse trails by village or park, tap any trail on the map to see its name and length, and use the search to jump to a specific path.")
                .font(.body)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
            Spacer()
            Button {
                dismiss()
            } label: {
                Text("Let's go")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }
}
