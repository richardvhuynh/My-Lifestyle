import SwiftUI

struct DiaryView: View {
    /// Switches the app to the Profile tab (wired from `MainTabView`).
    var onOpenProfile: () -> Void = {}

    // Sample data — replace with entries fetched from your Amplify data API
    @State private var entries: [DiaryEntry] = [
        DiaryEntry(mealType: .breakfast, title: "Egg, Banana, Blueberries, Oatmeal", calories: 434),
        DiaryEntry(mealType: .lunch, title: "Broccoli, Feta Cheese, Chicken, Extra Virgin Olive Oil", calories: 509)
    ]

    // Placeholder daily goals — later pulled from the user's profile
    private let calorieGoal = 2000
    private let proteinGoal = 100.0
    private let carbGoal = 250.0
    private let fatGoal = 67.0

    private var eaten: Int { entries.reduce(0) { $0 + $1.calories } }

    var body: some View {
        ZStack(alignment: .top) {
            Theme.background.ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 20) {
                    AppHeader(
                        title: "My Lifestyle",
                        subtitle: Date().formatted(.dateTime.weekday(.wide).day().month(.wide)),
                        trailingIcon: "person.crop.circle.fill",
                        trailingAction: onOpenProfile
                    )

                    // Calorie ring + eaten/left summary
                    VStack(spacing: 18) {
                        CircularCalorieRing(eaten: eaten, goal: calorieGoal)
                            .padding(.top, 4)

                        HStack {
                            summaryStat(value: "\(eaten)", label: "EATEN")
                            Spacer()
                            summaryStat(value: "\(max(calorieGoal - eaten, 0))", label: "LEFT")
                        }
                        .padding(.horizontal, 30)
                    }
                    .frame(maxWidth: .infinity)
                    .card(padding: 20)
                    .padding(.horizontal, 16)

                    // Macros
                    HStack(spacing: 20) {
                        MacroProgressBar(title: "Carbs", current: 107, goal: carbGoal, color: Theme.carb)
                        MacroProgressBar(title: "Protein", current: 59, goal: proteinGoal, color: Theme.protein)
                        MacroProgressBar(title: "Fat", current: 28, goal: fatGoal, color: Theme.fat)
                    }
                    .card(padding: 18)
                    .padding(.horizontal, 16)

                    // Meals
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Today's Meals")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(Theme.primaryText)
                            .padding(.horizontal, 22)

                        ForEach(MealType.allCases) { meal in
                            MealSectionView(
                                mealType: meal,
                                entries: entries.filter { $0.mealType == meal },
                                onAdd: { /* hook up "add food" flow once recipes/logging are wired to the backend */ }
                            )
                            .padding(.horizontal, 16)
                        }
                    }
                }
                .padding(.bottom, 120) // clears the floating custom tab bar
            }
        }
    }

    private func summaryStat(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.primaryText)
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(Theme.secondaryText)
        }
    }
}

private struct MealSectionView: View {
    var mealType: MealType
    var entries: [DiaryEntry]
    var onAdd: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(mealType.rawValue)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.primaryText)
                Spacer()
                Text("\(entries.reduce(0) { $0 + $1.calories }) kcal")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.secondaryText)
            }

            if entries.isEmpty {
                HStack {
                    Text("No foods logged")
                        .foregroundStyle(Theme.secondaryText)
                        .font(.system(size: 14))
                    Spacer()
                    IconButton(systemName: "plus", action: onAdd)
                }
            } else {
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    if index > 0 { RowDivider() }
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Theme.accentSoft)
                            .frame(width: 44, height: 44)
                            .overlay(
                                Image(systemName: "fork.knife")
                                    .foregroundStyle(Theme.accentDark)
                            )
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.title)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Theme.primaryText)
                                .lineLimit(1)
                            Text("\(entry.calories) kcal")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.secondaryText)
                        }
                        Spacer()
                        IconButton(systemName: "plus", action: onAdd)
                    }
                }
            }
        }
        .card(padding: 16)
    }
}

#Preview {
    DiaryView()
}
