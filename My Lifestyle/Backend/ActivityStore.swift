import SwiftUI

/// A sport / workout the user can log. Each case carries its display name, an SF
/// Symbol used in the activity graph, and a tint color.
enum ActivityType: String, CaseIterable, Codable, Identifiable {
    case running, walking, cycling, tennis, basketball, soccer
    case swimming, hiking, yoga, strength, dance, other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .running:    return "Running"
        case .walking:    return "Walking"
        case .cycling:    return "Cycling"
        case .tennis:     return "Tennis"
        case .basketball: return "Basketball"
        case .soccer:     return "Soccer"
        case .swimming:   return "Swimming"
        case .hiking:     return "Hiking"
        case .yoga:       return "Yoga"
        case .strength:   return "Strength"
        case .dance:      return "Dance"
        case .other:      return "Other"
        }
    }

    /// SF Symbol shown on the activity graph for this sport.
    var icon: String {
        switch self {
        case .running:    return "figure.run"
        case .walking:    return "figure.walk"
        case .cycling:    return "figure.outdoor.cycle"
        case .tennis:     return "figure.tennis"
        case .basketball: return "figure.basketball"
        case .soccer:     return "figure.soccer"
        case .swimming:   return "figure.pool.swim"
        case .hiking:     return "figure.hiking"
        case .yoga:       return "figure.yoga"
        case .strength:   return "figure.strengthtraining.traditional"
        case .dance:      return "figure.dance"
        case .other:      return "figure.mixed.cardio"
        }
    }

    var color: Color {
        switch self {
        case .running:    return Color(red: 0.95, green: 0.30, blue: 0.36)
        case .walking:    return Color(red: 0.15, green: 0.72, blue: 0.54)
        case .cycling:    return Color(red: 0.28, green: 0.52, blue: 1.0)
        case .tennis:     return Color(red: 0.78, green: 0.85, blue: 0.16)
        case .basketball: return Color(red: 1.0,  green: 0.50, blue: 0.16)
        case .soccer:     return Color(red: 0.20, green: 0.60, blue: 0.30)
        case .swimming:   return Color(red: 0.16, green: 0.70, blue: 0.85)
        case .hiking:     return Color(red: 0.55, green: 0.42, blue: 0.24)
        case .yoga:       return Color(red: 0.72, green: 0.38, blue: 0.86)
        case .strength:   return Color(red: 0.45, green: 0.45, blue: 0.52)
        case .dance:      return Color(red: 0.90, green: 0.30, blue: 0.72)
        case .other:      return Color(red: 0.50, green: 0.55, blue: 0.60)
        }
    }
}

/// One logged activity session. `countsAsAdditional` distinguishes steps that Health
/// didn't already capture (add them on top of the day's total) from steps that are
/// a subset of the Health total (just attributed to this sport, not added again).
struct LoggedActivity: Identifiable, Codable, Hashable {
    var id = UUID()
    var type: ActivityType
    var steps: Int
    var countsAsAdditional: Bool
    var date: Date
}

/// Persisted, observable collection of the user's logged activities. Backed by
/// `UserDefaults` (JSON) — local only for now; can move to the Amplify backend later
/// alongside recipes, mirroring the shared-store pattern used by [[pantry-store]].
@Observable
final class ActivityStore {
    private(set) var activities: [LoggedActivity] = []

    private let defaultsKey = "loggedActivities.v1"

    init() { load() }

    // MARK: - Mutations

    func add(_ activity: LoggedActivity) {
        activities.append(activity)
        save()
    }

    func delete(_ activity: LoggedActivity) {
        activities.removeAll { $0.id == activity.id }
        save()
    }

    // MARK: - Today's contribution to the step ring

    private func isToday(_ date: Date) -> Bool {
        Calendar.current.isDateInToday(date)
    }

    var todayActivities: [LoggedActivity] {
        activities
            .filter { isToday($0.date) }
            .sorted { $0.date > $1.date }
    }

    /// Steps logged today that should be added on top of the Health count.
    var todayAdditionalSteps: Int {
        todayActivities.filter(\.countsAsAdditional).reduce(0) { $0 + $1.steps }
    }

    /// All steps attributed to a logged activity today (additional + already-counted).
    /// This is the portion the ring paints in the activity color.
    var todayActivitySteps: Int {
        todayActivities.reduce(0) { $0 + $1.steps }
    }

    // MARK: - History queries

    /// Activities within `range`, most recent first.
    func activities(in range: HistoryRange) -> [LoggedActivity] {
        guard let start = range.startDate else { return activities.sorted { $0.date > $1.date } }
        return activities
            .filter { $0.date >= start }
            .sorted { $0.date > $1.date }
    }

    // MARK: - Persistence

    private func save() {
        if let data = try? JSONEncoder().encode(activities) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([LoggedActivity].self, from: data) else { return }
        activities = decoded
    }
}

/// Time window for the activity graph.
enum HistoryRange: String, CaseIterable, Identifiable {
    case day = "Day"
    case week = "Week"
    case month = "Month"
    case year = "Year"
    case all = "All"

    var id: String { rawValue }

    /// Inclusive lower bound for the window, or nil for "all time".
    var startDate: Date? {
        let calendar = Calendar.current
        let now = Date()
        switch self {
        case .day:   return calendar.startOfDay(for: now)
        case .week:  return calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now))
        case .month: return calendar.date(byAdding: .day, value: -29, to: calendar.startOfDay(for: now))
        case .year:  return calendar.date(byAdding: .month, value: -11, to: calendar.startOfDay(for: now))
        case .all:   return nil
        }
    }

    /// Larger ranges bucket entries by month; shorter ones by day.
    var bucket: Calendar.Component {
        switch self {
        case .year, .all: return .month
        default:          return .day
        }
    }
}
