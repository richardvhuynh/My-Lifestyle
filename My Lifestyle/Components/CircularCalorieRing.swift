import SwiftUI

struct CircularCalorieRing: View {
    var eaten: Int
    var goal: Int
    var burned: Int = 0

    private var remaining: Int { max(goal - eaten + burned, 0) }
    private var progress: Double {
        guard goal > 0 else { return 0 }
        return min(Double(eaten) / Double(goal), 1.0)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.surfaceAlt, lineWidth: 16)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [Theme.accent, Theme.carb, Theme.protein, Theme.accent]),
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 16, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut, value: progress)

            VStack(spacing: 2) {
                Text("\(remaining)")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.primaryText)
                Text("kcal left")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .frame(width: 180, height: 180)
    }
}

#Preview {
    CircularCalorieRing(eaten: 943, goal: 2000, burned: 282)
        .padding()
        .background(Theme.background)
}
