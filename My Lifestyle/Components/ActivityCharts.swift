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
        let data = segments(for: range)
        if data.isEmpty {
            emptyMessage
        } else {
            let types = typesPresent(in: data)
            Chart(data) { segment in
                // Each activity type is its own colored segment, manually positioned
                // (yStart/yEnd) so the largest sits at the bottom of the stack.
                BarMark(
                    x: .value("Date", segment.date, unit: range.bucket),
                    yStart: .value("Steps", segment.yStart),
                    yEnd: .value("Steps", segment.yEnd),
                    width: .automatic
                )
                .foregroundStyle(by: .value("Activity", segment.type.label))
                .cornerRadius(4)
                .annotation(position: .top, spacing: 4) {
                    if segment.isTop {
                        Text(compactSteps(segment.bucketTotal))
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
            }
            .chartForegroundStyleScale(
                domain: types.map(\.label),
                range: types.map(\.color)
            )
            .chartLegend(position: .bottom, spacing: 10)
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

    /// Groups activities in `range` into per-day or per-month buckets, then splits each
    /// bucket into one segment per activity type. Segments are stacked largest-first
    /// (the biggest sits at the bottom) with cumulative `yStart`/`yEnd` offsets so each
    /// type keeps its own color in the bar.
    private func segments(for range: HistoryRange) -> [ActivitySegment] {
        let calendar = Calendar.current
        let entries = filtered(range)
        let grouped = Dictionary(grouping: entries) { entry -> Date in
            if range.bucket == .month {
                return calendar.date(from: calendar.dateComponents([.year, .month], from: entry.date))
                    ?? calendar.startOfDay(for: entry.date)
            }
            return calendar.startOfDay(for: entry.date)
        }
        var result: [ActivitySegment] = []
        for (date, items) in grouped {
            let stepsByType = Dictionary(grouping: items, by: \.type)
                .mapValues { $0.reduce(0) { $0 + $1.steps } }
            // Largest first so it anchors the bottom of the stack.
            let ordered = stepsByType.sorted { $0.value > $1.value }
            let total = ordered.reduce(0) { $0 + $1.value }
            var cumulative = 0
            for (offset, pair) in ordered.enumerated() {
                let start = cumulative
                cumulative += pair.value
                result.append(ActivitySegment(
                    date: date,
                    type: pair.key,
                    steps: pair.value,
                    yStart: start,
                    yEnd: cumulative,
                    isTop: offset == ordered.count - 1,
                    bucketTotal: total
                ))
            }
        }
        return result.sorted { $0.date < $1.date }
    }

    /// The distinct activity types present in the data, in the stable enum order, so
    /// the legend and color scale are consistent across buckets.
    private func typesPresent(in segments: [ActivitySegment]) -> [ActivityType] {
        let present = Set(segments.map(\.type))
        return ActivityType.allCases.filter { present.contains($0) }
    }

    private func compactSteps(_ steps: Int) -> String {
        steps >= 1000 ? String(format: "%.1fk", Double(steps) / 1000) : "\(steps)"
    }
}

/// One colored segment of a stacked activity bar: the steps for a single activity
/// type within a day/month bucket, with its vertical position in the stack.
struct ActivitySegment: Identifiable {
    let date: Date
    let type: ActivityType
    let steps: Int
    let yStart: Int
    let yEnd: Int
    /// True for the top-most segment, which carries the bucket total annotation.
    let isTop: Bool
    let bucketTotal: Int
    var id: String { "\(date.timeIntervalSince1970)-\(type.rawValue)" }
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
