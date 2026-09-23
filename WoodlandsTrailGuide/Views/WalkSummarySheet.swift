import SwiftUI

/// Shown once a walk is completed: a preview of the shareable card plus the
/// share action.
///
/// Appears automatically on arrival, so it has to stay dismissible without
/// doing anything — somebody who just finished a 5-mile walk in August heat
/// should not have to fight a modal. Hence a plain "Done" and no gating.
struct WalkSummarySheet: View {
    let summary: WalkSummary

    @Environment(\.dismiss) private var dismiss
    @State private var imageURL: URL?
    @State private var isRendering = true

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer(minLength: 0)

                // Scaled-down preview of exactly what gets shared.
                WalkSummaryCard(summary: summary)
                    .scaleEffect(previewScale)
                    .frame(width: WalkSummaryCard.size.width * previewScale,
                           height: WalkSummaryCard.size.height * previewScale)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(color: .black.opacity(0.18), radius: 12, y: 4)

                Spacer(minLength: 0)

                if let imageURL {
                    ShareLink(
                        item: imageURL,
                        preview: SharePreview("\(summary.distanceText) mi in The Woodlands")
                    ) {
                        HStack(spacing: 8) {
                            Image(systemName: "square.and.arrow.up")
                            Text("Share this walk")
                        }
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Natural.forest,
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .padding(.horizontal, 20)
                } else if isRendering {
                    ProgressView()
                        .padding(.vertical, 22)
                } else {
                    // Rendering failed — say so rather than showing a dead
                    // button. The walk itself is already logged either way.
                    Text("Couldn't build the share image.")
                        .font(.footnote)
                        .foregroundStyle(Natural.inkMuted)
                        .padding(.vertical, 22)
                }
            }
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity)
            .background(Natural.cardBg)
            .navigationTitle("Nice walk")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                // Rendering a 1080x1350 image is quick but not free; keep it
                // off the first frame so the sheet animates in smoothly.
                imageURL = WalkSummaryCard.renderPNG(for: summary)
                isRendering = false
            }
        }
    }

    /// Fit the full-size card into roughly a phone's width.
    private var previewScale: CGFloat { 0.28 }
}
