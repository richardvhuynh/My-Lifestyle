import SwiftUI

/// A form for authoring a private recipe (stored in `UserRecipe`, visible only to
/// its creator). Produces a `Recipe` the caller persists. Macros are entered as
/// totals for the whole recipe, matching the catalog's convention.
struct RecipeComposeView: View {
    var onSave: (Recipe) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var servings = 1
    @State private var calories = ""
    @State private var protein = ""
    @State private var carbs = ""
    @State private var fat = ""

    @State private var ingredients: [RecipeIngredient] = []
    @State private var newIngredientName = ""
    @State private var newAmount = ""
    @State private var newUnit: MeasurementUnit = .grams

    @State private var steps: [String] = []
    @State private var newStep = ""

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        ZStack(alignment: .top) {
            Theme.background.ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    header

                    field("Recipe name", text: $name)

                    SectionBox(title: "Servings") {
                        Stepper("\(servings) serving\(servings == 1 ? "" : "s")", value: $servings, in: 1...50)
                    }

                    SectionBox(title: "Nutrition (whole recipe)") {
                        VStack(spacing: 10) {
                            numberField("Calories (kcal)", text: $calories)
                            numberField("Protein (g)", text: $protein)
                            numberField("Carbs (g)", text: $carbs)
                            numberField("Fat (g)", text: $fat)
                        }
                    }

                    ingredientsSection
                    stepsSection

                    Button("Save Recipe") { save() }
                        .buttonStyle(PrimaryButtonStyle(isEnabled: canSave))
                        .disabled(!canSave)
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private var header: some View {
        HStack {
            Text("New recipe")
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
    }

    private var ingredientsSection: some View {
        SectionBox(title: "Ingredients") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(ingredients) { ingredient in
                    HStack {
                        Text(ingredient.name)
                            .font(.system(size: 15))
                            .foregroundStyle(Theme.primaryText)
                        Spacer()
                        Text(ingredient.amountText)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.secondaryText)
                        Button {
                            ingredients.removeAll { $0.id == ingredient.id }
                        } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(Theme.danger)
                        }
                        .buttonStyle(.plain)
                    }
                    RowDivider()
                }

                HStack(spacing: 8) {
                    TextField("Name", text: $newIngredientName)
                        .textFieldStyle(RoundedFieldStyle())
                    TextField("Qty", text: $newAmount)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(RoundedFieldStyle())
                        .frame(width: 64)
                    Picker("Unit", selection: $newUnit) {
                        ForEach(MeasurementUnit.allCases) { unit in
                            Text(unit.label).tag(unit)
                        }
                    }
                    .labelsHidden()
                }
                Button("Add ingredient") { addIngredient() }
                    .buttonStyle(SecondaryButtonStyle(tint: Theme.accent))
                    .disabled(newIngredientName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private var stepsSection: some View {
        SectionBox(title: "Steps") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(index + 1)")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 24, height: 24)
                            .background(Circle().fill(Theme.accent))
                        Text(step)
                            .font(.system(size: 15))
                            .foregroundStyle(Theme.primaryText)
                        Spacer()
                        Button {
                            steps.remove(at: index)
                        } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(Theme.danger)
                        }
                        .buttonStyle(.plain)
                    }
                    RowDivider()
                }

                TextField("Describe a step…", text: $newStep, axis: .vertical)
                    .lineLimit(1...4)
                    .textFieldStyle(RoundedFieldStyle())
                Button("Add step") { addStep() }
                    .buttonStyle(SecondaryButtonStyle(tint: Theme.accent))
                    .disabled(newStep.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    // MARK: - Helpers

    private func field(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(RoundedFieldStyle())
    }

    private func numberField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .keyboardType(.decimalPad)
            .textFieldStyle(RoundedFieldStyle())
    }

    private func addIngredient() {
        let name = newIngredientName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let amount = Double(newAmount) ?? 0
        ingredients.append(RecipeIngredient(name: name, amount: amount, unit: newUnit))
        newIngredientName = ""
        newAmount = ""
    }

    private func addStep() {
        let text = newStep.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        steps.append(text)
        newStep = ""
    }

    private func save() {
        let recipeSteps = steps.enumerated().map { index, text in
            RecipeStep(order: index + 1, instruction: text)
        }
        let recipe = Recipe(
            name: name.trimmingCharacters(in: .whitespaces),
            category: "My Recipes",
            servings: servings,
            ingredients: ingredients,
            steps: recipeSteps,
            calories: Int(calories) ?? 0,
            protein: Double(protein) ?? 0,
            carbs: Double(carbs) ?? 0,
            fat: Double(fat) ?? 0
        )
        onSave(recipe)
        dismiss()
    }
}

#Preview {
    RecipeComposeView { _ in }
}
