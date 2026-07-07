import SwiftUI
import Charts

/// Compact elevation profile shown on the route summary card. iOS 16+
/// SwiftUI Charts — line + area fill, tinted forest green. Height fixed
/// so the card doesn't leap around when a chart loads.
struct ElevationChartView: View {
    let profile: ElevationProfile

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Label("\(Int(profile.gainFeet.rounded())) ft up",
                      systemImage: "arrow.up.right")
                    .foregroundStyle(Natural.forest)
                Label("\(Int(profile.lossFeet.rounded())) ft down",
                      systemImage: "arrow.down.right")
                    .foregroundStyle(Natural.route)
                Spacer(minLength: 0)
            }
            .font(.caption.weight(.semibold).monospacedDigit())

            Chart {
                ForEach(Array(zip(profile.distancesMeters, profile.elevationsMeters).enumerated()), id: \.offset) { _, pair in
                    let (d, e) = pair
                    AreaMark(
                        x: .value("Distance", d / 1609.344),
                        y: .value("Elevation", e * 3.28084)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Natural.forest.opacity(0.35), Natural.forest.opacity(0.05)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    LineMark(
                        x: .value("Distance", d / 1609.344),
                        y: .value("Elevation", e * 3.28084)
                    )
                    .foregroundStyle(Natural.forest)
                    .lineStyle(StrokeStyle(lineWidth: 1.6, lineJoin: .round))
                }
            }
            .chartXAxis {
                AxisMarks(preset: .aligned, values: .automatic(desiredCount: 3)) { value in
                    AxisValueLabel {
                        if let d = value.as(Double.self) {
                            Text(String(format: "%.1f mi", d))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(Natural.inkMuted)
                        }
                    }
                    AxisGridLine().foregroundStyle(Natural.hairline)
                }
            }
            .chartYAxis {
                AxisMarks(preset: .aligned, values: .automatic(desiredCount: 3)) { value in
                    AxisValueLabel {
                        if let e = value.as(Double.self) {
                            Text("\(Int(e.rounded())) ft")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(Natural.inkMuted)
                        }
                    }
                    AxisGridLine().foregroundStyle(Natural.hairline)
                }
            }
            .frame(height: 90)
        }
    }
}
