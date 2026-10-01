import Foundation
import HealthKit

/// A single day's step count, used to drive the weekly chart.
struct DailySteps: Identifiable, Codable {
    let date: Date
    let steps: Int
    var id: Date { date }
}

/// Owns the app's single `HKHealthStore` and exposes today's fitness metrics plus
/// a seven-day step history. Reads only — the app never writes to Health. Queries
/// use the modern async `…QueryDescriptor` APIs so no completion-handler juggling
/// is needed. The class is `@Observable` (and MainActor-isolated by the project's
/// default actor isolation) so SwiftUI views update as values load in.
@Observable
final class HealthKitManager {
    /// Whether HealthKit exists on this device (false on iPad / Mac Catalyst).
    let isAvailable = HKHealthStore.isHealthDataAvailable()

    /// True once the user has been shown the permission sheet at least once.
    private(set) var hasRequestedAuthorization = false

    // Today's totals. Nil means "not loaded yet"; zero is a real value.
    private(set) var todaySteps: Int?
    private(set) var todayDistanceMeters: Double?
    private(set) var todayActiveEnergy: Double?
    private(set) var todayExerciseMinutes: Int?

    /// Step totals for each of the last seven days, oldest first.
    private(set) var weeklySteps: [DailySteps] = []

    /// Set when a load fails so the view can show a friendly message.
    private(set) var errorMessage: String?

    private let store = HKHealthStore()

    // The quantity types we read. Kept together so authorization and refresh stay in sync.
    private let stepType = HKQuantityType(.stepCount)
    private let distanceType = HKQuantityType(.distanceWalkingRunning)
    private let energyType = HKQuantityType(.activeEnergyBurned)
    private let exerciseType = HKQuantityType(.appleExerciseTime)

    private var readTypes: Set<HKObjectType> {
        [stepType, distanceType, energyType, exerciseType]
    }

    /// Presents the Health permission sheet (a no-op if already answered) and then
    /// loads the latest data. Safe to call every time the tab appears.
    func requestAuthorizationAndLoad() async {
        guard isAvailable else {
            errorMessage = "Health data isn't available on this device."
            return
        }
        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
            hasRequestedAuthorization = true
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Re-reads every metric. Individual failures are ignored so one denied type
    /// doesn't blank out the others.
    func refresh() async {
        guard isAvailable else { return }
        async let steps = sumToday(stepType, unit: .count())
        async let distance = sumToday(distanceType, unit: .meter())
        async let energy = sumToday(energyType, unit: .kilocalorie())
        async let exercise = sumToday(exerciseType, unit: .minute())
        async let week = lastSevenDaysSteps()

        let (s, d, e, x, w) = await (steps, distance, energy, exercise, week)
        todaySteps = s.map { Int($0) }
        todayDistanceMeters = d
        todayActiveEnergy = e
        todayExerciseMinutes = x.map { Int($0) }
        weeklySteps = w
    }

    // MARK: - Queries

    /// Cumulative sum of `type` since midnight, in `unit`. Returns nil on failure.
    private func sumToday(_ type: HKQuantityType, unit: HKUnit) async -> Double? {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: Date())
        let samplePredicate = HKSamplePredicate.quantitySample(type: type, predicate: predicate)
        let descriptor = HKStatisticsQueryDescriptor(predicate: samplePredicate, options: .cumulativeSum)
        do {
            let stats = try await descriptor.result(for: store)
            return stats?.sumQuantity()?.doubleValue(for: unit)
        } catch {
            return nil
        }
    }

    /// Daily step totals for the trailing seven days (including today), oldest first.
    private func lastSevenDaysSteps() async -> [DailySteps] {
        let calendar = Calendar.current
        let endDate = Date()
        guard let startDate = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: endDate)) else {
            return []
        }
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate)
        let samplePredicate = HKSamplePredicate.quantitySample(type: stepType, predicate: predicate)
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: samplePredicate,
            options: .cumulativeSum,
            anchorDate: calendar.startOfDay(for: endDate),
            intervalComponents: DateComponents(day: 1)
        )
        do {
            let result = try await descriptor.result(for: store)
            var days: [DailySteps] = []
            result.enumerateStatistics(from: startDate, to: endDate) { stats, _ in
                let steps = stats.sumQuantity()?.doubleValue(for: .count()) ?? 0
                days.append(DailySteps(date: stats.startDate, steps: Int(steps)))
            }
            return days
        } catch {
            return []
        }
    }
}
