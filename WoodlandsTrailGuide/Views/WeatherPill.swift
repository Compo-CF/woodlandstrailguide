import SwiftUI

/// Compact weather badge that sits in the map's top-left. Shows a condition
/// icon + temperature at a glance. Tap → expands to a small sheet with the
/// full summary and any walking advisory ("hot — bring water", etc).
struct WeatherPill: View {
    let snapshot: WeatherService.Snapshot?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            if let s = snapshot {
                HStack(spacing: 6) {
                    Image(systemName: s.conditionSymbol)
                        .font(.system(size: 15, weight: .semibold))
                    Text("\(Int(s.temperatureF.rounded()))°")
                        .font(.system(size: 15, weight: .semibold).monospacedDigit())
                }
                .foregroundStyle(Natural.forest)
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(Natural.buttonBg, in: Capsule())
                .overlay(Capsule().stroke(Natural.hairline, lineWidth: 0.5))
                .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
            } else {
                Image(systemName: "cloud")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Natural.inkMuted)
                    .frame(width: 44, height: 34)
                    .background(Natural.buttonBg, in: Capsule())
                    .overlay(Capsule().stroke(Natural.hairline, lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
            }
        }
        .accessibilityLabel(snapshot?.summary ?? "Weather unavailable")
    }
}

/// Expanded weather detail — the sheet that opens when the pill is tapped.
struct WeatherDetailSheet: View {
    let snapshot: WeatherService.Snapshot?
    let lastFetch: Date?
    let onRefresh: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var refreshing = false

    var body: some View {
        NavigationStack {
            List {
                if let s = snapshot {
                    Section {
                        HStack(spacing: 16) {
                            Image(systemName: s.conditionSymbol)
                                .font(.system(size: 40, weight: .light))
                                .foregroundStyle(Natural.forest)
                                .frame(width: 60, height: 60)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(Int(s.temperatureF.rounded()))°F")
                                    .font(.system(size: 34, weight: .semibold).monospacedDigit())
                                    .foregroundStyle(Natural.ink)
                                Text(s.conditionLabel)
                                    .font(.subheadline)
                                    .foregroundStyle(Natural.inkMuted)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 6)
                    }

                    Section {
                        LabeledContent("Wind") {
                            Text("\(Int(s.windMph.rounded())) mph \(s.windCardinal)")
                                .monospacedDigit()
                        }
                        if let advisory = s.walkingAdvisory {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(Natural.route)
                                Text(advisory).foregroundStyle(Natural.ink)
                            }
                        }
                    }

                    if let lastFetch {
                        Section {
                            HStack {
                                Text("Last updated")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(lastFetch, style: .relative)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                            .font(.caption)
                        }
                    }
                } else {
                    Section {
                        Text("Weather unavailable right now. Try refreshing when you have a signal.")
                            .font(.callout)
                            .foregroundStyle(Natural.inkMuted)
                    }
                }
            }
            .navigationTitle("Weather")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        Task {
                            refreshing = true
                            await onRefresh()
                            refreshing = false
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .symbolEffect(.pulse, isActive: refreshing)
                    }
                    .disabled(refreshing)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

/// Font source: Open-Meteo (open-meteo.com), free public API, no key.
/// This attribution lives in the Weather section of the About tab.
