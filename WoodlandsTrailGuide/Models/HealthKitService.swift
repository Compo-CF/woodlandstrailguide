import Foundation
import HealthKit

/// Write-only Apple Health integration — logs each completed walk/ride as an
/// HKWorkout. We never READ HealthKit data (no step count display, no
/// history import), so authorization only requests `toShare`, never `read`.
/// Opt-in, off by default (UserDataStore.healthKitSyncEnabled).
@MainActor
final class HealthKitService {
    static let shared = HealthKitService()
    private let store = HKHealthStore()

    private init() {}

    private var workoutType: HKSampleType { HKObjectType.workoutType() }

    /// Requests permission to write workouts. Returns false immediately (no
    /// prompt) on devices without HealthKit — e.g. iPad — and false if the
    /// user declines. Safe to call repeatedly.
    func requestAuthorization() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        do {
            try await store.requestAuthorization(toShare: [workoutType], read: [])
            return true
        } catch {
            return false
        }
    }

    /// Logs a completed walk/ride as an HKWorkout ending now. Fire-and-forget
    /// — a failure here (permission revoked in Settings, HealthKit
    /// unavailable) shouldn't interrupt the trip-log flow that calls this,
    /// so errors are swallowed rather than surfaced.
    func saveWorkout(distanceMeters: Double, durationSeconds: Double, travelMode: TravelMode) {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let activityType: HKWorkoutActivityType
        switch travelMode {
        case .bike:         activityType = .cycling
        case .jog, .run:    activityType = .running
        case .walk:         activityType = .walking
        }
        let end = Date()
        let start = end.addingTimeInterval(-max(durationSeconds, 1))
        let distanceQuantity = HKQuantity(unit: .meter(), doubleValue: distanceMeters)
        let workout = HKWorkout(
            activityType: activityType,
            start: start,
            end: end,
            duration: max(durationSeconds, 1),
            totalEnergyBurned: nil,
            totalDistance: distanceQuantity,
            metadata: [HKMetadataKeyIndoorWorkout: false]
        )
        store.save(workout) { _, _ in }
    }
}
