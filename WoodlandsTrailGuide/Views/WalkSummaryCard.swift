import SwiftUI
import CoreLocation

/// A shareable image summarizing a completed walk — the route traced out,
/// the distance, and where it was.
///
/// This exists for reach, not for the person who just finished the walk:
/// the app's whole audience is one suburb, so the cheapest distribution we
/// have is an existing user posting a good-looking card to a local feed.
/// That's also why the card is deliberately branded and names the town.
///
/// Every color here is hardcoded rather than pulled from `Natural`. Most of
/// that palette is dynamic (it resolves against the current
/// UITraitCollection), and a shared PNG must not come out different
/// depending on whether the sharer happened to be in dark mode.
struct WalkSummary: Identifiable {
    let id = UUID()
    let distanceMeters: Double
    let durationSeconds: Double?
    let travelMode: TravelMode
    /// Named trail/pathway runs along the route.
    let segmentNames: [String]
    let parks: [String]
    /// Route geometry, used to draw the trace.
    let coordinates: [CLLocationCoordinate2D]
    let date: Date

    var miles: Double { distanceMeters / 1609.344 }

    var distanceText: String { String(format: "%.2f", miles) }

    var durationText: String? {
        guard let durationSeconds, durationSeconds > 0 else { return nil }
        let total = Int(durationSeconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(max(minutes, 1)) min"
    }

    /// Best single label for where this walk happened: a park if the route
    /// touched one (far more recognizable locally), otherwise the first
    /// named pathway run.
    var placeText: String? {
        parks.first ?? segmentNames.first
    }
}

struct WalkSummaryCard: View {
    let summary: WalkSummary

    /// Fixed 4:5 — the aspect most social feeds and stories crop kindly.
    static let size = CGSize(width: 1080, height: 1350)

    private let bg = Color(red: 0.07, green: 0.20, blue: 0.12)
    private let bgAccent = Color(red: 0.10, green: 0.28, blue: 0.16)
    private let cream = Color(red: 0.97, green: 0.96, blue: 0.91)
    private let creamDim = Color(red: 0.97, green: 0.96, blue: 0.91).opacity(0.62)
    private let trace = Color(red: 0.98, green: 0.62, blue: 0.24)

    var body: some View {
        ZStack {
            LinearGradient(colors: [bgAccent, bg],
                           startPoint: .topLeading, endPoint: .bottomTrailing)

            VStack(alignment: .leading, spacing: 0) {
                header
                Spacer(minLength: 0)
                traceView
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
            Image(systemName: "figure.hiking")
                .font(.system(size: 40, weight: .semibold))
            Text("WOODLANDS TRAIL GUIDE")
                .font(.system(size: 30, weight: .bold))
                .tracking(3)
        }
        .foregroundStyle(creamDim)
    }

    /// The route itself — the only part of this card unique to the walk, so
    /// it gets the most space.
    private var traceView: some View {
        GeometryReader { geo in
            Path { path in
                let pts = Self.projectedPoints(summary.coordinates, in: geo.size)
                guard let first = pts.first else { return }
                path.move(to: first)
                for p in pts.dropFirst() { path.addLine(to: p) }
            }
            .stroke(trace,
                    style: StrokeStyle(lineWidth: 18, lineCap: .round, lineJoin: .round))
        }
        .frame(height: 520)
    }

    private var stats: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .lastTextBaseline, spacing: 18) {
                Text(summary.distanceText)
                    .font(.system(size: 180, weight: .heavy, design: .rounded))
                    .foregroundStyle(cream)
                Text("miles")
                    .font(.system(size: 54, weight: .semibold, design: .rounded))
                    .foregroundStyle(creamDim)
            }
            HStack(spacing: 28) {
                label(summary.travelMode.label, systemImage: summary.travelMode.systemImage)
                if let durationText = summary.durationText {
                    label(durationText, systemImage: "clock")
                }
            }
        }
    }

    private func label(_ text: String, systemImage: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
            Text(text)
        }
        .font(.system(size: 40, weight: .semibold, design: .rounded))
        .foregroundStyle(creamDim)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Rectangle()
                .fill(creamDim.opacity(0.35))
                .frame(height: 2)
                .padding(.vertical, 26)
            if let placeText = summary.placeText {
                Text(placeText)
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(cream)
                    .lineLimit(1)
            }
            Text("The Woodlands, TX · \(summary.date.formatted(date: .abbreviated, time: .omitted))")
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(creamDim)
        }
    }

    // MARK: - Geometry

    /// Map coordinates into the drawing rect, preserving the route's real
    /// shape. Longitude degrees get narrower as latitude increases, so they
    /// are scaled by cos(latitude) first — without that correction a
    /// north-south route renders noticeably stretched.
    static func projectedPoints(_ coords: [CLLocationCoordinate2D],
                                in size: CGSize) -> [CGPoint] {
        guard coords.count >= 2, size.width > 0, size.height > 0 else { return [] }

        let midLat = coords.map(\.latitude).reduce(0, +) / Double(coords.count)
        let lonScale = cos(midLat * .pi / 180)

        let xs = coords.map { $0.longitude * lonScale }
        let ys = coords.map(\.latitude)
        guard let minX = xs.min(), let maxX = xs.max(),
              let minY = ys.min(), let maxY = ys.max() else { return [] }

        let spanX = maxX - minX
        let spanY = maxY - minY
        // A route that doubles back on itself can be ~zero-width in one
        // axis; fall back to a nonzero span so the divide stays finite.
        let safeSpanX = spanX > 0 ? spanX : 1
        let safeSpanY = spanY > 0 ? spanY : 1

        let inset: CGFloat = 12
        let drawW = max(size.width - inset * 2, 1)
        let drawH = max(size.height - inset * 2, 1)
        // One scale for both axes keeps the shape true rather than
        // stretching it to fill the box.
        let scale = min(drawW / safeSpanX, drawH / safeSpanY)

        let usedW = safeSpanX * scale
        let usedH = safeSpanY * scale
        let offsetX = inset + (drawW - usedW) / 2
        let offsetY = inset + (drawH - usedH) / 2

        return zip(xs, ys).map { x, y in
            CGPoint(
                x: offsetX + (x - minX) * scale,
                // Flip: latitude grows north, screen y grows down.
                y: offsetY + (maxY - y) * scale
            )
        }
    }
}

// MARK: - Rendering

extension WalkSummaryCard {
    /// Render to a PNG on disk and hand back the URL.
    ///
    /// Shares a file rather than a SwiftUI `Image` because file URLs are
    /// handled consistently by every share destination (Messages, Photos,
    /// Instagram); an in-memory Image is not.
    @MainActor
    static func renderPNG(for summary: WalkSummary) -> URL? {
        let renderer = ImageRenderer(content: WalkSummaryCard(summary: summary))
        // The card is already laid out at its final pixel size, so keep
        // scale at 1 — otherwise this renders at 3x, ~10MB.
        renderer.scale = 1
        guard let image = renderer.uiImage,
              let data = image.pngData() else { return nil }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("woodlands-walk-\(Int(summary.date.timeIntervalSince1970)).png")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}
