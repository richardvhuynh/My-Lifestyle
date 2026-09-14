import SwiftUI

struct PantryView: View {
    @State private var pantryItems: [PantryItem] = []
    @State private var newItemName = ""

    // Sample recipes to match against — replace with recipes fetched from your Amplify data API
    private let allRecipes: [Recipe] = [
        Recipe(name: "Chicken & Broccoli Bowl", ingredients: ["Chicken breast", "Broccoli", "Feta cheese", "Olive oil"], steps: [], calories: 509, protein: 42, carbs: 20, fat: 24),
        Recipe(name: "Oatmeal with Berries", ingredients: ["Oats", "Banana", "Blueberries", "Egg"], steps: [], calories: 434, protein: 18, carbs: 61, fat: 9)
    ]

    // Simple greedy overlap score for now — this is the seed of the "one shopping trip, several meals"
    // feature. A stronger version would look at combinations of recipes and score total ingredient
    // overlap across the set, not just each recipe individually against the pantry.
    private var matchedRecipes: [(recipe: Recipe, matchCount: Int)] {
        let have = Set(pantryItems.map { $0.name.lowercased() })
        return allRecipes
            .map { recipe -> (Recipe, Int) in
                let matches = recipe.ingredients.filter { have.contains($0.lowercased()) }.count
                return (recipe, matches)
            }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
    }

    private var canAdd: Bool {
        !newItemName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        ZStack(alignment: .top) {
            Theme.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    AppHeader(title: "Pantry", subtitle: "\(pantryItems.count) items")

                    // Add to pantry
                    SectionBox(title: "Add to pantry") {
                        HStack(spacing: 10) {
                            TextField("e.g. Chicken breast", text: $newItemName)
                                .textFieldStyle(RoundedFieldStyle())
                                .onSubmit(addItem)
                            Button(action: addItem) {
                                Image(systemName: "plus")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 46, height: 46)
                                    .background(
                                        RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous)
                                            .fill(Theme.accent)
                                            .opacity(canAdd ? 1 : 0.4)
                                    )
                            }
                            .buttonStyle(.plain)
                            .disabled(!canAdd)
                        }
                    }

                    // Your pantry
                    SectionBox(title: "Your pantry") {
                        if pantryItems.isEmpty {
                            Text("No items yet")
                                .font(.system(size: 15))
                                .foregroundStyle(Theme.secondaryText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(Array(pantryItems.enumerated()), id: \.element.id) { index, item in
                                    if index > 0 { RowDivider() }
                                    HStack {
                                        Image(systemName: "leaf.fill")
                                            .font(.system(size: 13))
                                            .foregroundStyle(Theme.accent)
                                        Text(item.name)
                                            .font(.system(size: 15))
                                            .foregroundStyle(Theme.primaryText)
                                        Spacer()
                                        Button {
                                            remove(item)
                                        } label: {
                                            Image(systemName: "trash")
                                                .font(.system(size: 14))
                                                .foregroundStyle(Theme.danger)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(.vertical, 6)
                                }
                            }
                        }
                    }

                    // Matches
                    SectionBox(title: "You could make") {
                        if matchedRecipes.isEmpty {
                            Text("Add pantry items to see matches")
                                .font(.system(size: 15))
                                .foregroundStyle(Theme.secondaryText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(Array(matchedRecipes.enumerated()), id: \.element.recipe.id) { index, match in
                                    if index > 0 { RowDivider() }
                                    HStack {
                                        Text(match.recipe.name)
                                            .font(.system(size: 15))
                                            .foregroundStyle(Theme.primaryText)
                                        Spacer()
                                        Text("\(match.matchCount)/\(match.recipe.ingredients.count)")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(Theme.accentDark)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 5)
                                            .background(Capsule().fill(Theme.accentSoft))
                                    }
                                    .padding(.vertical, 6)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 120)
            }
        }
    }

    private func addItem() {
        let trimmed = newItemName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            pantryItems.append(PantryItem(name: trimmed))
        }
        newItemName = ""
    }

    private func remove(_ item: PantryItem) {
        withAnimation(.easeInOut(duration: 0.2)) {
            pantryItems.removeAll { $0.id == item.id }
        }
    }
}

#Preview {
    PantryView()
}
