import SwiftUI
import CoreLocation

/// Detail sheet shown when the user taps a POI annotation on the map.
/// Surfaces the POI's name, category, park/village, distance from the user,
/// and a "Route here" action that plugs it into MapTabView's routing state.
struct POIDetailSheet: View {
    let poi: POI
    let category: POICategory
    let userLocation: CLLocation?
    let onRouteHere: () -> Void

    @Environment(\.dismiss) private var dismiss

    private var tintColor: Color {
        let hex = category.tintHex
        return Color(red: Double((hex >> 16) & 0xFF) / 255,
                     green: Double((hex >> 8) & 0xFF) / 255,
                     blue: Double(hex & 0xFF) / 255)
    }

    private var distanceText: String? {
        guard let userLocation else { return nil }
        let m = userLocation.distance(from: CLLocation(latitude: poi.lat, longitude: poi.lon))
        let miles = m / 1609.344
        if miles >= 0.1 { return String(format: "%.2f mi from you", miles) }
        return "\(Int((m * 3.28084).rounded())) ft from you"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        Image(systemName: category.icon)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(tintColor, in: Circle())
                        VStack(alignment: .leading, spacing: 3) {
                            Text(poi.name ?? category.label)
                                .font(.headline)
                                .foregroundStyle(Natural.ink)
                            Text(category.label)
                                .font(.caption)
                                .foregroundStyle(Natural.inkMuted)
                        }
                    }
                    .padding(.vertical, 2)
                }

                if poi.park != nil || poi.village != nil || distanceText != nil {
                    Section {
                        if let park = poi.park {
                            LabeledContent("Park", value: park)
                        }
                        if let village = poi.village {
                            LabeledContent("Village", value: village)
                        }
                        if let distanceText {
                            LabeledContent("Distance", value: distanceText)
                        }
                    }
                }

                Section {
                    Button {
                        onRouteHere()
                        dismiss()
                    } label: {
                        HStack {
                            Image(systemName: "point.topleft.down.to.point.bottomright.curvepath.fill")
                            Text("Route here")
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Natural.forest)
                    }
                }
            }
            .navigationTitle(poi.name ?? category.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
