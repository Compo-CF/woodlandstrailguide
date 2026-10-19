import SwiftUI

/// Animated splash shown over the app while the trail graph loads.
///
/// Two things make this worth having rather than decoration:
///
/// 1. There is real work to cover. TrailStore parses ~1,500 ways and
///    ~44,000 nodes on launch; before this, users got a white flash and
///    then a half-drawn map. The splash is sized to that work rather than
///    padded to look busy — it leaves as soon as the graph is ready.
/// 2. iOS cannot animate the launch screen itself. The system renders
///    UILaunchScreen before any app code runs, so the only way to get
///    motion at startup is to hand off from a static launch screen to a
///    view like this one. The LaunchBackground color asset is the same
///    green used here precisely so that handoff is invisible — the
///    animation appears to begin on the system's own screen.
///
/// The motion is a trail drawing itself, which is the most honest summary
/// of what the app does, followed by the wordmark.
struct SplashView: View {
    /// Drives the path's trim. Animating `trim` is what produces the
    /// "drawing itself" effect rather than a fade or a slide.
    @State private var trailProgress: CGFloat = 0
    @State private var markerScale: CGFloat = 0.1
    @State private var wordmarkOpacity: Double = 0
    @State private var wordmarkOffset: CGFloat = 8

    private let background = Color(red: 0.071, green: 0.208, blue: 0.122)
    private let cream = Color(red: 0.965, green: 0.930, blue: 0.842)
    private let trail = Color(red: 0.875, green: 0.445, blue: 0.165)

    var body: some View {
        ZStack {
            background.ignoresSafeArea()

            VStack(spacing: 34) {
                trailMark
                    .frame(width: 190, height: 96)

                VStack(spacing: 6) {
                    Text("The Woodlands Trail Guide")
                        .font(NaturalType.display(26, weight: .semibold, relativeTo: .title2))
                        .foregroundStyle(cream)
                    Text("THE WOODLANDS, TEXAS")
                        .font(.caption2.weight(.semibold))
                        .tracking(2.2)
                        .foregroundStyle(cream.opacity(0.55))
                }
                .opacity(wordmarkOpacity)
                .offset(y: wordmarkOffset)
            }
        }
        .onAppear(perform: animate)
        // One announcement to VoiceOver rather than a pile of decorative
        // fragments.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("The Woodlands Trail Guide, loading")
    }

    /// A meandering path with a marker at its end — a trail, drawn.
    private var trailMark: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            ZStack {
                // Faint full path underneath, so the stroke reads as
                // travelling a route that already exists rather than
                // conjuring one out of nothing.
                TrailPath()
                    .stroke(cream.opacity(0.14),
                            style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))

                TrailPath()
                    .trim(from: 0, to: trailProgress)
                    .stroke(trail,
                            style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))

                // Marker pops once the path has finished drawing.
                Circle()
                    .fill(cream)
                    .frame(width: 16, height: 16)
                    .overlay(Circle().fill(trail).frame(width: 7, height: 7))
                    .scaleEffect(markerScale)
                    .position(x: w * TrailPath.endPoint.x, y: h * TrailPath.endPoint.y)
            }
        }
    }

    private func animate() {
        withAnimation(.easeInOut(duration: 0.85)) {
            trailProgress = 1
        }
        withAnimation(.spring(response: 0.42, dampingFraction: 0.55).delay(0.78)) {
            markerScale = 1
        }
        withAnimation(.easeOut(duration: 0.45).delay(0.52)) {
            wordmarkOpacity = 1
            wordmarkOffset = 0
        }
    }
}

/// The path shape, in unit space so it scales to whatever frame it's given.
///
/// Separate from the view so the end point is a single published value —
/// the marker has to land exactly where the stroke stops, and duplicating
/// the curve maths in two places is how that quietly drifts apart.
private struct TrailPath: Shape {
    /// Unit-space location of the path's final point.
    static let endPoint = CGPoint(x: 0.92, y: 0.30)

    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        var p = Path()
        p.move(to: CGPoint(x: w * 0.06, y: h * 0.74))
        p.addCurve(to: CGPoint(x: w * 0.40, y: h * 0.56),
                   control1: CGPoint(x: w * 0.17, y: h * 0.92),
                   control2: CGPoint(x: w * 0.27, y: h * 0.44))
        p.addCurve(to: CGPoint(x: w * 0.66, y: h * 0.64),
                   control1: CGPoint(x: w * 0.52, y: h * 0.66),
                   control2: CGPoint(x: w * 0.55, y: h * 0.84))
        p.addCurve(to: CGPoint(x: w * TrailPath.endPoint.x, y: h * TrailPath.endPoint.y),
                   control1: CGPoint(x: w * 0.78, y: h * 0.46),
                   control2: CGPoint(x: w * 0.82, y: h * 0.30))
        return p
    }
}

/// Decides how long the splash stays up.
///
/// Bounded at both ends, deliberately. A minimum so a fast launch doesn't
/// flash something unreadable for 200ms, and a hard maximum so a slow or
/// failed data load can never strand the user staring at a logo — the app
/// behind this has its own loading and error states, and is a better place
/// to be than here.
struct SplashGate<Content: View>: View {
    let isReady: Bool
    @ViewBuilder let content: () -> Content

    @State private var isFinished = false
    @State private var minimumElapsed = false

    private let minimumDuration: Duration = .milliseconds(1400)
    private let maximumDuration: Duration = .milliseconds(3500)

    var body: some View {
        ZStack {
            content()

            if !isFinished {
                SplashView()
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .animation(.easeOut(duration: 0.35), value: isFinished)
        .task {
            try? await Task.sleep(for: minimumDuration)
            minimumElapsed = true
            finishIfPossible()
        }
        .task {
            try? await Task.sleep(for: maximumDuration)
            // Hard ceiling — fires regardless of readiness.
            isFinished = true
        }
        .onChange(of: isReady) { _, _ in finishIfPossible() }
    }

    private func finishIfPossible() {
        if isReady && minimumElapsed { isFinished = true }
    }
}
