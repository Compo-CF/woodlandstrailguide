import SwiftUI
import CoreLocation

/// A shareable image of how much of The Woodlands you've walked.
///
/// `WalkSummaryCard` shares one route; this shares the whole town, filling
/// in. That difference is the point. A single route is pleasant and
/// forgettable — roughly the same shape anyone's walk produces — while a
/// personal map of a place people recognise is something they look at twice,
/// and the only artefact this app makes that someone would post unprompted.
///
/// Every colour is hardcoded rather than taken from `Natural`. That palette
/// is dynamic and resolves against the current trait collection; a shared PNG
/// must not come out different depending on whether the sharer happened to be
/// in dark mode, and it leaves the app the moment it's shared.
struct CoverageCard: View {
    let graph: TrailGraph
    /// Walked stretches, as produced by `CoverageStore.coveredRuns`.
    let coveredRuns: [[CLLocationCoordinate2D]]
    let overall: CoverageProgress
    let completedVillages: Int
    let date: Date

    /// Fixed 4:5, the aspect most feeds and stories crop kindly. Matches
    /// WalkSummaryCard so the two read as a set.
    static let size = CGSize(width: 1080, height: 1350)

    private let bg = Color(red: 0.07, green: 0.20, blue: 0.12)
    private let bgAccent = Color(red: 0.10, green: 0.28, blue: 0.16)
    private let cream = Color(red: 0.97, green: 0.96, blue: 0.91)
    private let creamDim = Color(red: 0.97, green: 0.96, blue: 0.91).opacity(0.62)
    private let walked = Color(red: 0.98, green: 0.62, blue: 0.24)
    /// The unwalked network, deliberately faint. It has to read as the shape
    /// of the town — the thing being filled in — without competing with what
    /// has been done.
    private let network = Color(red: 0.97, green: 0.96, blue: 0.91).opacity(0.17)

    var body: some View {
        ZStack {
            LinearGradient(colors: [bgAccent, bg],
                           startPoint: .topLeading, endPoint: .bottomTrailing)

            VStack(alignment: .leading, spacing: 0) {
                header
                Spacer(minLength: 0)
                mapPlate
                Spacer(minLength: 0)
                stats
                footer
            }
            .padding(72)
        }
        .frame(width: Self.size.width, height: Self.size.height)
    }

    private var header: some View {
        HStack(spacing: 16) {
            Image(systemName: "map.fill")
                .font(.system(size: 38, weight: .semibold))
            Text("THE WOODLANDS TRAIL GUIDE")
                .font(.system(size: 30, weight: .bold))
                .tracking(3)
        }
        .foregroundStyle(creamDim)
    }

    /// The network, with the walked parts lit.
    ///
    /// Drawn in a Canvas rather than as stacked Paths: this is ~46,000
    /// segments, and Canvas draws them in one pass instead of SwiftUI
    /// building a view node per polyline.
    private var mapPlate: some View {
        Canvas { context, size in
            let projection = Projection(bbox: graph.bbox, size: size)

            var base = Path()
            for way in graph.ways where way.nodeIndices.count >= 2 {
                var started = false
                for index in way.nodeIndices {
                    guard graph.nodes.indices.contains(index) else { continue }
                    let point = projection.point(graph.nodes[index].clCoord)
                    if started {
                        base.addLine(to: point)
                    } else {
                        base.move(to: point)
                        started = true
                    }
                }
            }
            context.stroke(base, with: .color(network),
                           style: StrokeStyle(lineWidth: 2, lineCap: .round,
                                              lineJoin: .round))

            var done = Path()
            for run in coveredRuns where run.count >= 2 {
                done.move(to: projection.point(run[0]))
                for coord in run.dropFirst() {
                    done.addLine(to: projection.point(coord))
                }
            }
            context.stroke(done, with: .color(walked),
                           style: StrokeStyle(lineWidth: 5, lineCap: .round,
                                              lineJoin: .round))
        }
        .frame(height: 620)
    }

    private var stats: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .lastTextBaseline, spacing: 18) {
                Text(CoverageSheet.percentText(overall.fraction))
                    .font(.system(size: 170, weight: .heavy, design: .rounded))
                    .foregroundStyle(cream)
                Text("walked")
                    .font(.system(size: 54, weight: .semibold, design: .rounded))
                    .foregroundStyle(creamDim)
            }
            HStack(spacing: 28) {
                label(String(format: "%.1f of %.0f mi",
                             overall.coveredMiles, overall.totalMiles),
                      systemImage: "figure.walk")
                if completedVillages > 0 {
                    label(completedVillages == 1
                          ? "1 village done"
                          : "\(completedVillages) villages done",
                          systemImage: "checkmark.seal.fill")
                }
            }
        }
    }

    private func label(_ text: String, systemImage: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
            Text(text)
        }
        .font(.system(size: 38, weight: .semibold, design: .rounded))
        .foregroundStyle(creamDim)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Rectangle()
                .fill(creamDim.opacity(0.35))
                .frame(height: 2)
                .padding(.vertical, 26)
            Text("The Woodlands, TX · \(date.formatted(date: .abbreviated, time: .omitted))")
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(creamDim)
        }
    }

    /// Maps coordinates into the drawing rect, preserving the town's real
    /// shape. Longitude degrees narrow as latitude rises, so they're scaled by
    /// cos(latitude) first — without it The Woodlands renders noticeably
    /// stretched east-west.
    private struct Projection {
        let scale: Double
        let offsetX: Double
        let offsetY: Double
        let minX: Double
        let maxY: Double
        let lonScale: Double

        init(bbox: TrailGraph.BBox, size: CGSize) {
            let midLat = (bbox.south + bbox.north) / 2
            lonScale = cos(midLat * .pi / 180)

            minX = bbox.west * lonScale
            maxY = bbox.north
            let spanX = max((bbox.east - bbox.west) * lonScale, 1e-9)
            let spanY = max(bbox.north - bbox.south, 1e-9)

            let inset: Double = 8
            let drawW = max(Double(size.width) - inset * 2, 1)
            let drawH = max(Double(size.height) - inset * 2, 1)
            // One scale for both axes keeps the shape true rather than
            // stretching the town to fill the box.
            scale = min(drawW / spanX, drawH / spanY)
            offsetX = inset + (drawW - spanX * scale) / 2
            offsetY = inset + (drawH - spanY * scale) / 2
        }

        func point(_ coord: CLLocationCoordinate2D) -> CGPoint {
            CGPoint(
                x: offsetX + (coord.longitude * lonScale - minX) * scale,
                // Flip: latitude grows north, screen y grows down.
                y: offsetY + (maxY - coord.latitude) * scale
            )
        }
    }
}

extension CoverageCard {
    /// Render to a PNG on disk and hand back the URL.
    ///
    /// A file rather than an in-memory Image because every share destination
    /// — Messages, Photos, Instagram — handles a real file consistently.
    @MainActor
    static func renderPNG(graph: TrailGraph,
                          coveredRuns: [[CLLocationCoordinate2D]],
                          overall: CoverageProgress,
                          completedVillages: Int,
                          date: Date = .now) -> URL? {
        let card = CoverageCard(graph: graph,
                                coveredRuns: coveredRuns,
                                overall: overall,
                                completedVillages: completedVillages,
                                date: date)
        let renderer = ImageRenderer(content: card)
        // The card is already laid out at its final pixel size, so leave the
        // scale at 1 — otherwise this renders at 3x, around 10 MB.
        renderer.scale = 1
        guard let image = renderer.uiImage,
              let data = image.pngData() else { return nil }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("woodlands-coverage-\(Int(date.timeIntervalSince1970)).png")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}
