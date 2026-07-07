import Foundation
import UIKit
import Observation

/// Stores user-attached photos per POI. Local-only, JPEG on disk under
/// Documents/poi_photos/<poi_id>/, keyed by "<category>:<poi_id>" so the
/// same OBJECTID across categories doesn't collide.
///
/// No upload, no cloud sync, no sharing — just personal notes-in-picture
/// for spots the user cares about. Capped at 3 photos per POI to keep the
/// storage footprint bounded.
@Observable
final class POIPhotoStore {
    /// Set of composite keys ("category:poi_id") we've observed on disk,
    /// used so the UI knows when to refresh thumbnails without re-scanning.
    private(set) var version: Int = 0

    private var baseDir: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let base = docs.appendingPathComponent("poi_photos", isDirectory: true)
        if !FileManager.default.fileExists(atPath: base.path) {
            try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        }
        return base
    }

    /// Directory for a specific POI's photos.
    private func directory(for key: PhotoKey) -> URL {
        let dir = baseDir.appendingPathComponent(key.diskName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    /// File URLs for photos attached to this POI, oldest-first.
    func photoURLs(for key: PhotoKey) -> [URL] {
        let dir = directory(for: key)
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.creationDateKey],
            options: .skipsHiddenFiles
        ) else { return [] }
        return contents
            .filter { $0.pathExtension.lowercased() == "jpg" }
            .sorted { (a, b) in
                let dA = (try? a.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                let dB = (try? b.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                return dA < dB
            }
    }

    /// Persist a UIImage as JPEG into this POI's folder. Cap at 3 photos.
    /// The image is downscaled to 1600px on the long edge before encoding —
    /// enough for on-device display, well below what iCloud Photos ships.
    @discardableResult
    func addPhoto(_ image: UIImage, for key: PhotoKey) -> URL? {
        let existing = photoURLs(for: key)
        if existing.count >= 3 {
            // Remove the oldest to make room.
            try? FileManager.default.removeItem(at: existing.first!)
        }
        let downsized = Self.downsize(image, longEdge: 1600)
        guard let data = downsized.jpegData(compressionQuality: 0.82) else { return nil }
        let filename = "\(Int(Date.now.timeIntervalSince1970 * 1000)).jpg"
        let url = directory(for: key).appendingPathComponent(filename)
        do {
            try data.write(to: url, options: .atomic)
            version &+= 1
            return url
        } catch {
            return nil
        }
    }

    func deletePhoto(at url: URL) {
        try? FileManager.default.removeItem(at: url)
        version &+= 1
    }

    private static func downsize(_ image: UIImage, longEdge: CGFloat) -> UIImage {
        let size = image.size
        let scale = min(1.0, longEdge / max(size.width, size.height))
        if scale >= 1.0 { return image }
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

/// Composite identity for a POI's photo folder — category key + POI id.
/// Different categories can share an OBJECTID (they come from separate
/// ArcGIS layers), so we prefix by category to keep them isolated on disk.
struct PhotoKey: Hashable {
    let categoryKey: String
    let poiID: String

    /// Filesystem-safe name for the POI's directory. Non-word chars stripped
    /// to avoid any surprises across HFS/APFS quirks.
    var diskName: String {
        let raw = "\(categoryKey)__\(poiID)"
        return raw.replacingOccurrences(
            of: "[^A-Za-z0-9_-]",
            with: "_",
            options: .regularExpression
        )
    }
}
