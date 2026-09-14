import SwiftUI

struct RecipesView: View {
    @State private var searchText = ""

    // Sample data — replace with recipes fetched from your Amplify data API
    @State private var recipes: [Recipe] = [
        Recipe(
            name: "Chicken & Broccoli Bowl",
            ingredients: ["Chicken breast", "Broccoli", "Feta cheese", "Olive oil"],
            steps: [
                RecipeStep(order: 1, instruction: "Season and pan-sear the chicken breast until cooked through."),
                RecipeStep(order: 2, instruction: "Steam the broccoli until tender-crisp."),
                RecipeStep(order: 3, instruction: "Plate together, top with crumbled feta and a drizzle of olive oil.")
            ],
            calories: 509, protein: 42, carbs: 20, fat: 24
        ),
        Recipe(
            name: "Oatmeal with Berries",
            ingredients: ["Oats", "Banana", "Blueberries", "Egg"],
            steps: [
                RecipeStep(order: 1, instruction: "Cook oats with water or milk until creamy."),
                RecipeStep(order: 2, instruction: "Top with sliced banana and blueberries."),
                RecipeStep(order: 3, instruction: "Serve with a boiled or fried egg on the side.")
            ],
            calories: 434, protein: 18, carbs: 61, fat: 9
        )
    ]

    private var filtered: [Recipe] {
        searchText.isEmpty ? recipes : recipes.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Theme.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        AppHeader(title: "Recipes", subtitle: "\(recipes.count) saved")

                        SearchField(text: $searchText, prompt: "Search recipes")
                            .padding(.horizontal, 16)

                        LazyVStack(spacing: 12) {
                            ForEach(filtered) { recipe in
                                NavigationLink(value: recipe) {
                                    RecipeRow(recipe: recipe)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    .padding(.bottom, 120)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Recipe.self) { recipe in
                RecipeDetailView(recipe: recipe)
            }
        }
    }
}

/// Hand-built search field replacing `.searchable`.
struct SearchField: View {
    @Binding var text: String
    var prompt: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.secondaryText)
            TextField(prompt, text: $text)
                .font(.system(size: 16))
                .foregroundStyle(Theme.primaryText)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.secondaryText)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous)
                .fill(Theme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous)
                        .stroke(Color.black.opacity(0.05), lineWidth: 1)
                )
        )
    }
}

private struct RecipeRow: View {
    var recipe: Recipe
    var body: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.accentSoft)
                .frame(width: 56, height: 56)
                .overlay(
                    Image(systemName: "photo")
                        .font(.system(size: 20))
                        .foregroundStyle(Theme.accentDark)
                )
            VStack(alignment: .leading, spacing: 3) {
                Text(recipe.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.primaryText)
                Text("\(recipe.calories) kcal · \(recipe.ingredients.count) ingredients")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondaryText)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.secondaryText)
        }
        .card(padding: 14)
    }
}

struct RecipeDetailView: View {
    var recipe: Recipe
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .top) {
            Theme.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // Custom back button
                    Button { dismiss() } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left")
                            Text("Recipes")
                        }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.accentDark)
                    }
                    .buttonStyle(.plain)

                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Theme.accentSoft)
                        .frame(height: 160)
                        .overlay(
                            Image(systemName: "photo")
                                .font(.system(size: 40))
                                .foregroundStyle(Theme.accentDark)
                        )

                    VStack(alignment: .leading, spacing: 4) {
                        Text(recipe.name)
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.primaryText)
                        Text("\(recipe.calories) kcal")
                            .font(.system(size: 15))
                            .foregroundStyle(Theme.secondaryText)
                    }

                    // Macro chips
                    HStack(spacing: 10) {
                        macroChip("Protein", "\(Int(recipe.protein))g", Theme.protein)
                        macroChip("Carbs", "\(Int(recipe.carbs))g", Theme.carb)
                        macroChip("Fat", "\(Int(recipe.fat))g", Theme.fat)
                    }

                    SectionBox(title: "Ingredients") {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(recipe.ingredients, id: \.self) { ingredient in
                                HStack(spacing: 10) {
                                    Circle().fill(Theme.accent).frame(width: 6, height: 6)
                                    Text(ingredient)
                                        .font(.system(size: 15))
                                        .foregroundStyle(Theme.primaryText)
                                }
                            }
                        }
                    }

                    SectionBox(title: "Steps") {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(recipe.steps.sorted(by: { $0.order < $1.order }).enumerated()), id: \.element.id) { index, step in
                                if index > 0 { RowDivider() }
                                HStack(alignment: .top, spacing: 12) {
                                    Text("\(step.order)")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(.white)
                                        .frame(width: 26, height: 26)
                                        .background(Circle().fill(Theme.accent))
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(step.instruction)
                                            .font(.system(size: 15))
                                            .foregroundStyle(Theme.primaryText)
                                        if step.videoURL != nil {
                                            // Swap in a VideoPlayer here once step videos are hosted in S3
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .fill(Theme.surfaceAlt)
                                                .frame(height: 160)
                                                .overlay(
                                                    Image(systemName: "play.circle.fill")
                                                        .font(.largeTitle)
                                                        .foregroundStyle(Theme.accent)
                                                )
                                        }
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private func macroChip(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(color.opacity(0.12))
        )
    }
}

#Preview {
    RecipesView()
}
