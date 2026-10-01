import SwiftUI
import Charts

/// A seven-day step bar chart, rendered from Health-style `DailySteps`. Callers wrap
/// it in their own `SectionBox`/card. Shared by the Fitness tab and member profiles.
struct StepsWeekChart: View {
    let data: [DailySteps]

    var body: some View {
        if data.isEmpty {
            Text("No step data yet.")
                .font(.system(size: 14))
                .foregroundStyle(Theme.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 20)
        } else {
            Chart(data) { day in
                BarMark(
                    x: .value("Day", day.date, unit: .day),
                    y: .value("Steps", day.steps)
                )
                .foregroundStyle(AppTab.fitness.selectedColor.gradient)
                .cornerRadius(6)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.narrow))
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .frame(height: 180)
            .padding(.top, 4)
        }
    }
}

/// Ranged activity graph: a Day/Week/Month/Year/All selector over a set of logged
/// activities. Day shows the individual sessions; the wider ranges show a bar per
/// bucket tagged with the dominant sport's icon and step total. Supplying `onDelete`
/// makes rows deletable (the owner's own view); omit it for read-only profiles.
struct ActivityGraphCard: View {
    let activities: [LoggedActivity]
    var onDelete: ((LoggedActivity) -> Void)? = nil

    @State private var range: HistoryRange = .week

    var body: some View {
        VStack(spacing: 12) {
            SegmentedSelector(
                options: HistoryRange.allCases.map { ($0, $0.rawValue) },
                selection: $range
            )

            if range == .day {
                dayList
            } else {
                rangedChart
            }
        }
        .card(padding: 16)
    }

    // MARK: - Day list

    @ViewBuilder
    private var dayList: some View {
        let entries = filtered(.day)
        if entries.isEmpty {
            emptyMessage
        } else {
            VStack(spacing: 0) {
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, activity in
                    if index > 0 { RowDivider() }
                    ActivityRow(activity: activity, onDelete: onDelete.map { delete in { delete(activity) } })
                }
            }
        }
    }

    // MARK: - Ranged bar chart

    @ViewBuilder
    private var rangedChart: some View {
        let data = buckets(for: range)
        if data.isEmpty {
            emptyMessage
        } else {
            Chart(data) { bucket in
                BarMark(
                    x: .value("Date", bucket.date, unit: range.bucket),
                    y: .value("Steps", bucket.steps)
                )
                .foregroundStyle(bucket.dominantType.color.gradient)
                .cornerRadius(6)
                .annotation(position: .top, spacing: 4) {
                    VStack(spacing: 1) {
                        Image(systemName: bucket.dominantType.icon)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(bucket.dominantType.color)
                        Text(compactSteps(bucket.steps))
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: range.bucket)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: axisFormat)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .frame(height: 200)
            .padding(.top, 14)
        }
    }

    private var emptyMessage: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 26))
                .foregroundStyle(Theme.secondaryText.opacity(0.6))
            Text("No activities logged in this period.")
                .font(.system(size: 14))
                .foregroundStyle(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    private var axisFormat: Date.FormatStyle {
        switch range {
        case .week:       return .dateTime.weekday(.narrow)
        case .month:      return .dateTime.day()
        case .year, .all: return .dateTime.month(.narrow)
        case .day:        return .dateTime.hour()
        }
    }

    // MARK: - Data shaping

    private func filtered(_ range: HistoryRange) -> [LoggedActivity] {
        guard let start = range.startDate else { return activities.sorted { $0.date > $1.date } }
        return activities.filter { $0.date >= start }.sorted { $0.date > $1.date }
    }

    /// Groups activities in `range` into per-day or per-month buckets, each tagged
    /// with the sport that contributed the most steps.
    private func buckets(for range: HistoryRange) -> [ActivityBucket] {
        let calendar = Calendar.current
        let entries = filtered(range)
        let grouped = Dictionary(grouping: entries) { entry -> Date in
            if range.bucket == .month {
                return calendar.date(from: calendar.dateComponents([.year, .month], from: entry.date))
                    ?? calendar.startOfDay(for: entry.date)
            }
            return calendar.startOfDay(for: entry.date)
        }
        return grouped.map { date, items in
            let total = items.reduce(0) { $0 + $1.steps }
            let stepsByType = Dictionary(grouping: items, by: \.type)
                .mapValues { $0.reduce(0) { $0 + $1.steps } }
            let dominant = stepsByType.max { $0.value < $1.value }?.key ?? .other
            return ActivityBucket(date: date, steps: total, dominantType: dominant)
        }
        .sorted { $0.date < $1.date }
    }

    private func compactSteps(_ steps: Int) -> String {
        steps >= 1000 ? String(format: "%.1fk", Double(steps) / 1000) : "\(steps)"
    }
}

/// One bucket (day or month) of the activity graph.
struct ActivityBucket: Identifiable {
    let date: Date
    let steps: Int
    let dominantType: ActivityType
    var id: Date { date }
}

/// A single logged-activity row. Shows a trash button only when `onDelete` is set.
struct ActivityRow: View {
    let activity: LoggedActivity
    var onDelete: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: activity.type.icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(activity.type.color)
                .frame(width: 40, height: 40)
                .background(Circle().fill(activity.type.color.opacity(0.15)))

            VStack(alignment: .leading, spacing: 2) {
                Text(activity.type.label)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.primaryText)
                Text(activity.countsAsAdditional ? "Added to total" : "Part of total")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondaryText)
            }

            Spacer()

            Text("\(activity.steps.formatted()) steps")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.primaryText)

            if let onDelete {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.danger)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }
}
