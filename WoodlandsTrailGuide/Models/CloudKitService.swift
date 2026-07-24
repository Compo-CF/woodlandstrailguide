import Foundation
import CloudKit
import CoreLocation

/// Crowdsourced trail conditions + wildlife sightings, backed by the public
/// CloudKit database. Records are anonymous — we never store or read any
/// per-user identity field, just the report content + where it happened.
///
/// Moderation (required for App Review Guideline 1.2, since this is
/// user-generated content other users see): a generic `ReportFlag` record
/// lets any user flag a bad report. A report with 2+ flags is filtered out
/// client-side everywhere it's displayed. There's no separate admin queue —
/// at this scale (a single small town) a same-day flag threshold is the
/// right amount of moderation machinery, matching the lightweight pattern
/// used for WoodlandsEats' ClosureReport ("one report flags it").
///
/// Container: iCloud.com.compofelice.WoodlandsTrailGuide (new — this app
/// had no CloudKit usage before this). Record types + indexes must be
/// created in the CloudKit Dashboard's Development environment, then
/// deployed to Production before release (see project README).
@MainActor
final class CloudKitService {
    static let shared = CloudKitService()
    private let container = CKContainer(identifier: "iCloud.com.compofelice.WoodlandsTrailGuide")
    private var db: CKDatabase { container.publicCloudDatabase }

    private init() {}

    // MARK: - Trail condition reports

    enum TrailCondition: String, CaseIterable, Identifiable {
        case clear, muddy, flooded, closed
        var id: String { rawValue }

        var label: String {
            switch self {
            case .clear:   return "Clear"
            case .muddy:   return "Muddy"
            case .flooded: return "Flooded"
            case .closed:  return "Closed"
            }
        }
        var systemImage: String {
            switch self {
            case .clear:   return "checkmark.circle.fill"
            case .muddy:   return "cloud.rain.fill"
            case .flooded: return "water.waves"
            case .closed:  return "xmark.octagon.fill"
            }
        }
    }

    struct ConditionReport: Identifiable {
        let recordName: String
        let wayID: String?
        let wayName: String?
        let condition: TrailCondition
        let note: String?
        let coordinate: CLLocationCoordinate2D
        let createdAt: Date
        var id: String { recordName }
    }

    func submitConditionReport(wayID: String?, wayName: String?, condition: TrailCondition,
                                note: String?, coordinate: CLLocationCoordinate2D) async throws {
        let record = CKRecord(recordType: "TrailConditionReport")
        record["wayID"] = wayID
        record["wayName"] = wayName
        record["condition"] = condition.rawValue
        if let note, !note.isEmpty {
            record["note"] = String(note.prefix(200))
        }
        record["latitude"] = coordinate.latitude
        record["longitude"] = coordinate.longitude
        _ = try await db.save(record)
    }

    /// Reports from the last 14 days (conditions like flooding are
    /// transient — no point surfacing a month-old "flooded" tag), with
    /// anything that's accumulated 2+ flags filtered out.
    func fetchRecentConditionReports() async throws -> [ConditionReport] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -14, to: .now) ?? .now
        let predicate = NSPredicate(format: "creationDate > %@", cutoff as NSDate)
        let query = CKQuery(recordType: "TrailConditionReport", predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let (results, _) = try await db.records(matching: query, resultsLimit: 200)
        let flagged = try await flaggedRecordNames()
        return results.compactMap { _, result -> ConditionReport? in
            guard case .success(let record) = result,
                  !flagged.contains(record.recordID.recordName),
                  let rawCondition = record["condition"] as? String,
                  let condition = TrailCondition(rawValue: rawCondition),
                  let lat = record["latitude"] as? Double,
                  let lon = record["longitude"] as? Double,
                  let created = record.creationDate else { return nil }
            return ConditionReport(
                recordName: record.recordID.recordName,
                wayID: record["wayID"] as? String,
                wayName: record["wayName"] as? String,
                condition: condition,
                note: record["note"] as? String,
                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                createdAt: created
            )
        }
    }

    // MARK: - Wildlife sightings

    enum WildlifeCategory: String, CaseIterable, Identifiable {
        case alligator, snake, deer, birdOfPrey, other
        var id: String { rawValue }

        var label: String {
            switch self {
            case .alligator: return "Alligator"
            case .snake:     return "Snake"
            case .deer:      return "Deer"
            case .birdOfPrey: return "Bird of prey"
            case .other:     return "Other"
            }
        }
        var systemImage: String {
            switch self {
            case .alligator:  return "lizard.fill"
            case .snake:      return "scribble.variable"
            case .deer:       return "hare.fill"
            case .birdOfPrey: return "bird.fill"
            case .other:      return "pawprint.fill"
            }
        }
    }

    struct WildlifeSightingReport: Identifiable {
        let recordName: String
        let category: WildlifeCategory
        let note: String?
        let coordinate: CLLocationCoordinate2D
        let createdAt: Date
        var id: String { recordName }
    }

    func submitWildlifeSighting(category: WildlifeCategory, note: String?,
                                 coordinate: CLLocationCoordinate2D) async throws {
        let record = CKRecord(recordType: "WildlifeSighting")
        record["category"] = category.rawValue
        if let note, !note.isEmpty {
            record["note"] = String(note.prefix(200))
        }
        record["latitude"] = coordinate.latitude
        record["longitude"] = coordinate.longitude
        _ = try await db.save(record)
    }

    /// Sightings from the last 30 days — a little longer-lived than trail
    /// conditions since "there was a gator here last week" is still useful
    /// context, unlike a flood report.
    func fetchRecentWildlifeSightings() async throws -> [WildlifeSightingReport] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .now
        let predicate = NSPredicate(format: "creationDate > %@", cutoff as NSDate)
        let query = CKQuery(recordType: "WildlifeSighting", predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let (results, _) = try await db.records(matching: query, resultsLimit: 200)
        let flagged = try await flaggedRecordNames()
        return results.compactMap { _, result -> WildlifeSightingReport? in
            guard case .success(let record) = result,
                  !flagged.contains(record.recordID.recordName),
                  let rawCategory = record["category"] as? String,
                  let category = WildlifeCategory(rawValue: rawCategory),
                  let lat = record["latitude"] as? Double,
                  let lon = record["longitude"] as? Double,
                  let created = record.creationDate else { return nil }
            return WildlifeSightingReport(
                recordName: record.recordID.recordName,
                category: category,
                note: record["note"] as? String,
                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                createdAt: created
            )
        }
    }

    // MARK: - Moderation (shared by both report types)

    /// Flags a report as objectionable/wrong. Idempotent-ish in intent (not
    /// strictly deduped per-flagger since reports are anonymous), but the
    /// 2-flag threshold means a single mis-tap can't hide a report on its
    /// own, and one determined bad actor flagging the same thing repeatedly
    /// gains nothing beyond the second flag.
    func flagReport(recordName: String) async throws {
        let record = CKRecord(recordType: "ReportFlag")
        record["targetRecordName"] = recordName
        _ = try await db.save(record)
    }

    private func flaggedRecordNames() async throws -> Set<String> {
        let query = CKQuery(recordType: "ReportFlag", predicate: NSPredicate(value: true))
        let (results, _) = try await db.records(matching: query, resultsLimit: 500)
        var counts: [String: Int] = [:]
        for (_, result) in results {
            guard case .success(let record) = result,
                  let target = record["targetRecordName"] as? String else { continue }
            counts[target, default: 0] += 1
        }
        return Set(counts.filter { $0.value >= 2 }.keys)
    }
}
