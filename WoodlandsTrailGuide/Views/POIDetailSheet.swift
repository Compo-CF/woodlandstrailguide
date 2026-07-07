import SwiftUI
import CoreLocation
import PhotosUI

/// Detail sheet shown when the user taps a POI annotation on the map.
/// Surfaces name, category, park/village, distance from user, personal
/// photos, and a "Route here" action that plugs it into MapTabView's
/// routing state.
struct POIDetailSheet: View {
    let poi: POI
    let category: POICategory
    let userLocation: CLLocation?
    let onRouteHere: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(POIPhotoStore.self) private var photoStore
    @State private var pickerItem: PhotosPickerItem?
    @State private var photoURLs: [URL] = []
    @State private var viewingURL: URL?

    private var photoKey: PhotoKey {
        PhotoKey(categoryKey: category.key, poiID: poi.id)
    }

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

                Section("Your photos") {
                    if photoURLs.isEmpty {
                        Text("Attach a photo of this spot to remember what it looks like. Stored on your device only — not shared.")
                            .font(.footnote)
                            .foregroundStyle(Natural.inkMuted)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(photoURLs, id: \.self) { url in
                                    if let img = UIImage(contentsOfFile: url.path) {
                                        Button {
                                            viewingURL = url
                                        } label: {
                                            Image(uiImage: img)
                                                .resizable()
                                                .aspectRatio(contentMode: .fill)
                                                .frame(width: 88, height: 88)
                                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                        }
                                        .contextMenu {
                                            Button(role: .destructive) {
                                                photoStore.deletePhoto(at: url)
                                                refreshPhotos()
                                            } label: {
                                                Label("Delete photo", systemImage: "trash")
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    if photoURLs.count < 3 {
                        PhotosPicker(selection: $pickerItem,
                                     matching: .images,
                                     photoLibrary: .shared()) {
                            HStack(spacing: 8) {
                                Image(systemName: "photo.badge.plus")
                                    .foregroundStyle(Natural.forest)
                                Text("Add a photo")
                                    .foregroundStyle(Natural.ink)
                                Spacer()
                                Text("\(photoURLs.count) / 3")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(Natural.inkMuted)
                            }
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
            .task { refreshPhotos() }
            .onChange(of: pickerItem) { _, newItem in
                guard let newItem else { return }
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        photoStore.addPhoto(image, for: photoKey)
                        await MainActor.run {
                            pickerItem = nil
                            refreshPhotos()
                        }
                    }
                }
            }
            .sheet(item: Binding(
                get: { viewingURL.map { PhotoViewerItem(url: $0) } },
                set: { viewingURL = $0?.url }
            )) { item in
                PhotoViewerSheet(url: item.url)
            }
        }
    }

    private func refreshPhotos() {
        photoURLs = photoStore.photoURLs(for: photoKey)
    }
}

private struct PhotoViewerItem: Identifiable {
    let url: URL
    var id: URL { url }
}

/// Full-screen viewer for a single stored POI photo.
private struct PhotoViewerSheet: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Color.black.ignoresSafeArea()
                .overlay {
                    if let img = UIImage(contentsOfFile: url.path) {
                        Image(uiImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { dismiss() }
                            .foregroundStyle(.white)
                    }
                }
                .toolbarBackground(.black, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
        }
    }
}
