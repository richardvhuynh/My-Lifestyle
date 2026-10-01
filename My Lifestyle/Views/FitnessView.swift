import SwiftUI
import Charts
import Amplify

/// Fitness dashboard driven by Apple Health and the user's own logged workouts.
/// Shows today's step progress (with activity-sourced steps highlighted in a
/// separate color), supporting activity stats, and a ranged activity graph. Health
/// data is read-only via `HealthKitManager`; logged activities live in `ActivityStore`.
struct FitnessView: View {
    /// Daily step target used for the progress ring.
    private let stepGoal = 10_000
    /// Color for the slice of the ring contributed by logged activities.
    private let activityRingColor = Theme.fat

    @State private var health = HealthKitManager()
    @State private var activities = ActivityStore()
    @State private var showingLog = false
    /// Resolved once so the user's shared profile is keyed and named consistently.
    @State private var currentUserId: String?
    @State private var currentDisplayName = "You"

    var body: some View {
        ZStack(alignment: .top) {
            Theme.background.ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 16) {
                    AppHeader(
                        title: "Fitness",
                        subtitle: subtitle,
                        trailingIcon: "arrow.clockwise",
                        trailingAction: { Task { await health.refresh() } }
                    )

                    if !health.isAvailable {
                        unavailableCard
                    } else if !health.hasRequestedAuthorization && health.todaySteps == nil {
                        connectCard
                    } else {
                        stepRing
                        logButton
                        todaysActivities
                        statsGrid
                        SectionBox(title: "Activity history") {
                            ActivityGraphCard(
                                activities: activities.activities,
                                onDelete: { activities.delete($0); publish() }
                            )
                        }
                        SectionBox(title: "Steps · last 7 days") {
                            StepsWeekChart(data: health.weeklySteps)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 120)
            }
        }
        .task {
            currentUserId = await FitnessCloudService.currentUserId()
            if let user = try? await Amplify.Auth.getCurrentUser() {
                currentDisplayName = user.username
            }
            await health.requestAuthorizationAndLoad()
            publish()
        }
        .sheet(isPresented: $showingLog) {
            LogActivitySheet { activities.add($0); publish() }
        }
    }

    /// Publishes the user's current step history and logged activities to the cloud
    /// so other members can view them from the Community feed. No-op until an id is
    /// resolved; failures are ignored (sharing is best-effort).
    private func publish() {
        guard let currentUserId else { return }
        let profile = SharedFitness(
            userId: currentUserId,
            displayName: currentDisplayName,
            weeklySteps: health.weeklySteps,
            activities: activities.activities
        )
        Task { try? await FitnessCloudService.publish(profile) }
    }

    // MARK: - Step math

    private var healthSteps: Int { health.todaySteps ?? 0 }
    /// Steps that count toward the goal: Health's count plus any "additional" logged steps.
    private var totalSteps: Int { healthSteps + activities.todayAdditionalSteps }
    /// Portion of the total attributed to logged activities (capped to the total).
    private var activityPortion: Int { min(activities.todayActivitySteps, totalSteps) }

    private var subtitle: String {
        health.todaySteps != nil ? "\(totalSteps.formatted()) steps today" : "Connected to Health"
    }

    // MARK: - Hero step ring

    private var stepRing: some View {
        let goal = Double(stepGoal)
        let basePortion = max(totalSteps - activityPortion, 0)
        let baseFraction = min(Double(basePortion) / goal, 1.0)
        let activityEnd = min(Double(basePortion + activityPortion) / goal, 1.0)
        let progress = min(Double(totalSteps) / goal, 1.0)

        return VStack(spacing: 14) {
            ZStack {
                Circle()
                    .stroke(Theme.surfaceAlt, lineWidth: 18)

                // Base (Health / non-activity) steps.
                Circle()
                    .trim(from: 0, to: baseFraction)
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(colors: [AppTab.fitness.selectedColor, Theme.carb, AppTab.fitness.selectedColor]),
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 18, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut, value: baseFraction)

                // Steps sourced from logged activities, in a distinct color.
                Circle()
                    .trim(from: baseFraction, to: activityEnd)
                    .stroke(activityRingColor, style: StrokeStyle(lineWidth: 18, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut, value: activityEnd)

                VStack(spacing: 2) {
                    Image(systemName: "figure.walk")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(AppTab.fitness.selectedColor)
                    Text(totalSteps.formatted())
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.primaryText)
                        .contentTransition(.numericText())
                    Text("of \(stepGoal.formatted()) steps")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .frame(width: 200, height: 200)

            if activityPortion > 0 {
                HStack(spacing: 16) {
                    legendDot(color: AppTab.fitness.selectedColor, label: "\(basePortion.formatted()) steps")
                    legendDot(color: activityRingColor, label: "\(activityPortion.formatted()) from activity")
                }
            } else {
                Text(progress >= 1 ? "Goal reached — nice work! 🎉" : "\(Int(progress * 100))% of your daily goal")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .frame(maxWidth: .infinity)
        .card(padding: 22)
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 9, height: 9)
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.secondaryText)
        }
    }

    // MARK: - Log button & today's list

    private var logButton: some View {
        Button {
            showingLog = true
        } label: {
            Label("Log an activity", systemImage: "plus.circle.fill")
        }
        .buttonStyle(PrimaryButtonStyle())
    }

    @ViewBuilder
    private var todaysActivities: some View {
        if !activities.todayActivities.isEmpty {
            SectionBox(title: "Today's activities") {
                ForEach(Array(activities.todayActivities.enumerated()), id: \.element.id) { index, activity in
                    if index > 0 { RowDivider() }
                    ActivityRow(activity: activity) { activities.delete(activity); publish() }
                }
            }
        }
    }

    // MARK: - Supporting stats

    private var statsGrid: some View {
        HStack(spacing: 12) {
            StatTile(
                icon: "flame.fill",
                tint: Theme.carb,
                value: health.todayActiveEnergy.map { "\(Int($0))" } ?? "—",
                unit: "kcal",
                label: "Active"
            )
            StatTile(
                icon: "location.fill",
                tint: AppTab.pantry.selectedColor,
                value: distanceString,
                unit: "km",
                label: "Distance"
            )
            StatTile(
                icon: "timer",
                tint: Theme.accent,
                value: health.todayExerciseMinutes.map { "\($0)" } ?? "—",
                unit: "min",
                label: "Exercise"
            )
        }
    }

    private var distanceString: String {
        guard let meters = health.todayDistanceMeters else { return "—" }
        return String(format: "%.1f", meters / 1000)
    }

    // MARK: - Empty / gated states

    private var connectCard: some View {
        VStack(spacing: 16) {
            Image(systemName: "heart.text.square.fill")
                .font(.system(size: 44))
                .foregroundStyle(AppTab.fitness.selectedColor)
            Text("Connect to Apple Health")
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(Theme.primaryText)
            Text("Allow access to see your steps, distance, and activity right here in My Lifestyle.")
                .font(.system(size: 14))
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
            Button("Connect") {
                Task { await health.requestAuthorizationAndLoad() }
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .frame(maxWidth: .infinity)
        .card(padding: 28)
        .padding(.top, 40)
    }

    private var unavailableCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "heart.slash")
                .font(.system(size: 40))
                .foregroundStyle(Theme.secondaryText)
            Text("Health data isn't available on this device.")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .card(padding: 28)
        .padding(.top, 40)
    }
}

// MARK: - Stat tile

private struct StatTile: View {
    var icon: String
    var tint: Color
    var value: String
    var unit: String
    var label: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(tint)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.primaryText)
                Text(unit)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.secondaryText)
            }
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .card(padding: 16)
    }
}

// MARK: - Log activity sheet

private struct LogActivitySheet: View {
    var onSave: (LoggedActivity) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var type: ActivityType = .running
    @State private var stepsText = ""
    @State private var isAdditional = true
    @State private var date = Date()

    private let columns = [GridItem(.adaptive(minimum: 74), spacing: 10)]

    private var steps: Int { Int(stepsText) ?? 0 }
    private var canSave: Bool { steps > 0 }

    var body: some View {
        ZStack(alignment: .top) {
            Theme.background.ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        Text("Log activity")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.primaryText)
                        Spacer()
                        Button { dismiss() } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(Theme.secondaryText)
                                .frame(width: 36, height: 36)
                                .background(Circle().fill(Theme.surface))
                        }
                        .buttonStyle(.plain)
                    }

                    // Activity type picker
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Activity")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.secondaryText)
                        LazyVGrid(columns: columns, spacing: 10) {
                            ForEach(ActivityType.allCases) { option in
                                typeCell(option)
                            }
                        }
                    }

                    // Steps
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Steps from this activity")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.secondaryText)
                        TextField("e.g. 2500", text: $stepsText)
                            .keyboardType(.numberPad)
                            .textFieldStyle(RoundedFieldStyle())
                    }

                    // Additional vs part of total
                    VStack(alignment: .leading, spacing: 10) {
                        Text("How should these count?")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.secondaryText)
                        SegmentedSelector(
                            options: [(true, "Add to total"), (false, "Part of total")],
                            selection: $isAdditional
                        )
                        Text(isAdditional
                             ? "Added on top of the steps Health already tracked."
                             : "These are already included in your Health step count.")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.secondaryText)
                    }

                    // Date
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Date")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.secondaryText)
                        DatePicker("", selection: $date, in: ...Date(), displayedComponents: .date)
                            .labelsHidden()
                            .tint(Theme.accent)
                    }

                    Button("Save") {
                        onSave(LoggedActivity(
                            type: type,
                            steps: steps,
                            countsAsAdditional: isAdditional,
                            date: date
                        ))
                        dismiss()
                    }
                    .buttonStyle(PrimaryButtonStyle(isEnabled: canSave))
                    .disabled(!canSave)
                }
                .padding(20)
            }
        }
    }

    private func typeCell(_ option: ActivityType) -> some View {
        let selected = type == option
        return Button {
            type = option
        } label: {
            VStack(spacing: 6) {
                Image(systemName: option.icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(selected ? .white : option.color)
                Text(option.label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(selected ? .white : Theme.secondaryText)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(selected ? option.color : Theme.surfaceAlt)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    FitnessView()
}
