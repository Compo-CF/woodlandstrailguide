import SwiftUI

/// How much of The Woodlands you've walked, village by village.
///
/// The map shows *where*; this shows *how far along*. Eleven buckets — ten
/// villages plus the parks and preserves — chosen because they are how
/// residents already think about the town, and because 204.8 miles as one
/// number is a wall, while 23.5 miles of Alden Bridge is a weekend.
///
/// Sorted by how close each is to done, so the one worth finishing next sits
/// at the top. Untouched villages stay on the list rather than being hidden:
/// the point is a set to complete, and you cannot complete a set you can't
/// see.
struct CoverageSheet: View {
    @Environment(CoverageStore.self) private var coverage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            let overall = coverage.overallProgress()
            let villages = coverage.progressByVillage()
                .sorted { $0.fraction > $1.fraction }

            List {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(Self.percentText(overall.fraction))
                                .font(NaturalType.display(40, weight: .bold,
                                                          relativeTo: .largeTitle))
                                .foregroundStyle(Natural.ink)
                            Text("of The Woodlands")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Natural.inkMuted)
                        }
                        CoverageBar(fraction: overall.fraction, height: 8)
                        Text(String(format: "%.1f of %.1f miles walked",
                                    overall.coveredMiles, overall.totalMiles))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Natural.inkMuted)
                    }
                    .padding(.vertical, 6)
                }

                Section("By village") {
                    ForEach(villages, id: \.name) { village in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(village.name)
                                    .font(NaturalType.display(16, weight: .semibold,
                                                              relativeTo: .body))
                                    .foregroundStyle(Natural.ink)
                                if village.isComplete {
                                    Image(systemName: "checkmark.seal.fill")
                                        .font(.caption)
                                        .foregroundStyle(Natural.forest)
                                }
                                Spacer()
                                Text(Self.percentText(village.fraction))
                                    .font(.caption.monospacedDigit().weight(.semibold))
                                    .foregroundStyle(village.fraction > 0
                                                     ? Natural.ink : Natural.inkMuted)
                            }
                            CoverageBar(fraction: village.fraction, height: 5)
                            Text(String(format: "%.2f of %.1f mi",
                                        village.coveredMiles, village.totalMiles))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(Natural.inkMuted)
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section {
                    Text("A pathway counts once you've walked most of its "
                         + "length, so passing the end of one doesn't tick it "
                         + "off. Walks are recorded when you tap Record on the "
                         + "map, or whenever you navigate a route.")
                        .font(.footnote)
                        .foregroundStyle(Natural.inkMuted)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Natural.cardBg.ignoresSafeArea())
            .navigationTitle("Your Woodlands")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    /// Never round a started village down to "0%" — somebody who has walked a
    /// quarter mile has started, and being told they haven't is worse than an
    /// imprecise number.
    static func percentText(_ fraction: Double) -> String {
        if fraction <= 0 { return "0%" }
        if fraction < 0.01 { return "<1%" }
        return String(format: "%.0f%%", fraction * 100)
    }
}

/// Thin capsule bar, shared by the header and every village row so one visual
/// language carries "how far along" throughout the screen.
struct CoverageBar: View {
    let fraction: Double
    var height: CGFloat = 5

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Natural.chipBg)
                Capsule()
                    .fill(Natural.route)
                    .frame(width: max(geo.size.width * min(max(fraction, 0), 1),
                                      // Keep a sliver visible once started, so
                                      // "begun" reads differently from "not".
                                      fraction > 0 ? height : 0))
            }
        }
        .frame(height: height)
    }
}
