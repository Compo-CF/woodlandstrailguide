import SwiftUI
import CoreLocation

/// Small sheet for generating a loop walk of a chosen distance from the
/// user's current location. Uses the waypoint routing machinery under
/// the hood: pick a graph node approximately `target/2` away, then
/// route(through: [start, farNode, start]) — Dijkstra may pick the same
/// path out and back for v1, which is fine ("a 3-mile walk from here").
struct LoopBuilderSheet: View {
    let graph: TrailGraph
    let userLocation: CLLocation
    /// Fired with (startNodeIndex, farNodeIndex). MapTabView plugs both
    /// into its routing state (start = start, waypoint = far, end = start)
    /// and the existing updateRoute flow generates the loop.
    let onGenerate: (Int, Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedMiles: Double = 2

    private let options: [Double] = [1, 2, 3, 5, 8]

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 60, weight: .light))
                    .foregroundStyle(Natural.forest)
                    .padding(.top, 32)

                Text("Loop from here")
                    .font(.title2.bold())
                    .foregroundStyle(Natural.ink)

                Text("Pick a rough distance. We'll route you to a point about halfway there and back.")
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Natural.inkMuted)
                    .padding(.horizontal, 32)

                HStack(spacing: 8) {
                    ForEach(options, id: \.self) { m in
                        Button {
                            selectedMiles = m
                        } label: {
                            Text("\(Int(m)) mi")
                                .font(.subheadline.weight(.semibold).monospacedDigit())
                                .foregroundStyle(selectedMiles == m ? .white : Natural.forest)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(
                                    selectedMiles == m ? Natural.forest : Natural.chipBg,
                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                                )
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)

                Button {
                    generate()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "figure.walk")
                        Text("Generate loop")
                    }
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Natural.forest, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)

                Spacer(minLength: 0)
            }
            .background(Natural.cardBg)
            .navigationTitle("Loop")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func generate() {
        let router = Router(graph: graph)
        guard let start = router.nearestNode(to: userLocation.coordinate),
              let far = router.farthestNode(
                from: start,
                atRouteDistance: selectedMiles * 1609.344 / 2
              ) else {
            return
        }
        onGenerate(start, far)
        dismiss()
    }
}
