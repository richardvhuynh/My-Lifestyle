import SwiftUI

struct MacroProgressBar: View {
    var title: String
    var current: Double
    var goal: Double
    var color: Color

    private var progress: Double {
        guard goal > 0 else { return 0 }
        return min(current / goal, 1.0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
            Text("\(Int(current))/\(Int(goal)) g")
                .font(.subheadline).bold()
                .foregroundStyle(Theme.primaryText)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.surfaceAlt)
                    Capsule().fill(color)
                        .frame(width: geo.size.width * progress)
                }
            }
            .frame(height: 7)
        }
    }
}

#Preview {
    HStack(spacing: 20) {
        MacroProgressBar(title: "Carbs", current: 107, goal: 250, color: Theme.carb)
        MacroProgressBar(title: "Protein", current: 59, goal: 100, color: Theme.protein)
        MacroProgressBar(title: "Fat", current: 28, goal: 67, color: Theme.fat)
    }
    .padding()
}
