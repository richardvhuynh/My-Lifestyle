import SwiftUI
import PhotosUI

struct PantryView: View {
    @Environment(PantryStore.self) private var pantry
    private var pantryItems: [PantryItem] { pantry.items }

    // Draft state for the "add" form.
    @State private var draftKind: PantryItemKind = .consumable
    @State private var draftName = ""
    @State private var draftAmount = ""
    @State private var draftUnit: MeasurementUnit = .grams
    @State private var draftPhoto: PhotosPickerItem?
    @State private var draftImageData: Data?

    // Editing a consumable's amount via an alert.
    @State private var editingItem: PantryItem?
    @State private var editAmountText = ""
    @FocusState private var fieldFocused: Bool

    // Sample recipes to match against — replace with recipes fetched from your Amplify data API
    private let allRecipes: [Recipe] = [
        Recipe(name: "Chicken & Broccoli Bowl", ingredients: [
            RecipeIngredient(name: "Chicken breast", amount: 200, unit: .grams),
            RecipeIngredient(name: "Broccoli", amount: 150, unit: .grams),
            RecipeIngredient(name: "Feta cheese", amount: 1, unit: .ounces),
            RecipeIngredient(name: "Olive oil", amount: 1, unit: .tablespoons)
        ], steps: [], calories: 509, protein: 42, carbs: 20, fat: 24),
        Recipe(name: "Oatmeal with Berries", ingredients: [
            RecipeIngredient(name: "Oats", amount: 80, unit: .grams),
            RecipeIngredient(name: "Banana", amount: 1, unit: .whole),
            RecipeIngredient(name: "Blueberries", amount: 0.5, unit: .cups),
            RecipeIngredient(name: "Egg", amount: 1, unit: .whole)
        ], steps: [], calories: 434, protein: 18, carbs: 61, fat: 9)
    ]

    private var permanentItems: [PantryItem] {
        pantryItems.filter { $0.kind == .permanent }
    }

    private var consumableItems: [PantryItem] {
        pantryItems.filter { $0.kind == .consumable }
    }

    // Simple greedy overlap score for now — this is the seed of the "one shopping trip, several meals"
    // feature. A stronger version would look at combinations of recipes and score total ingredient
    // overlap across the set, not just each recipe individually against the pantry.
    private var matchedRecipes: [(recipe: Recipe, matchCount: Int)] {
        let have = Set(pantryItems.map { $0.name.lowercased() })
        return allRecipes
            .map { recipe -> (Recipe, Int) in
                let matches = recipe.ingredients.filter { have.contains($0.name.lowercased()) }.count
                return (recipe, matches)
            }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
    }

    private var canAdd: Bool {
        !draftName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        ZStack(alignment: .top) {
            Theme.background.ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 20) {
                    AppHeader(title: "Pantry", subtitle: "\(pantryItems.count) items")

                    addSection

                    goodsSection(
                        title: "Permanent goods",
                        subtitle: "Always stocked — never used up",
                        items: permanentItems,
                        emptyText: "No permanent goods yet"
                    )

                    goodsSection(
                        title: "Consumable goods",
                        subtitle: "Tracked and drawn down as you cook",
                        items: consumableItems,
                        emptyText: "No consumable goods yet"
                    )

                    matchesSection
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 120)
                // Tapping empty space dismisses the keyboard so you're never
                // stuck with it open.
                .contentShape(Rectangle())
                .onTapGesture { fieldFocused = false }
            }
            .scrollDismissesKeyboard(.immediately)
        }
        .alert("Update amount", isPresented: editAmountAlertPresented) {
            TextField("Amount", text: $editAmountText)
                .keyboardType(.decimalPad)
            Button("Cancel", role: .cancel) { editingItem = nil }
            Button("Save") { saveEditedAmount() }
        } message: {
            if let editingItem {
                Text("New amount for \(editingItem.name) (\(editingItem.unit.label))")
            }
        }
    }

    private var editAmountAlertPresented: Binding<Bool> {
        Binding(get: { editingItem != nil }, set: { if !$0 { editingItem = nil } })
    }

    // MARK: - Add form

    private var addSection: some View {
        SectionBox(title: "Add to pantry") {
            VStack(spacing: 12) {
                SegmentedSelector(
                    options: PantryItemKind.allCases.map { ($0, $0.rawValue) },
                    selection: $draftKind
                )

                HStack(spacing: 10) {
                    photoPickerButton

                    TextField("e.g. Chicken breast", text: $draftName)
                        .textFieldStyle(RoundedFieldStyle())
                        .focused($fieldFocused)
                        .onSubmit(addItem)
                }

                // Consumables carry a measured amount that recipes decrement.
                // Permanent goods do not, so the amount row is hidden for them.
                if draftKind == .consumable {
                    HStack(spacing: 10) {
                        TextField("Amount", text: $draftAmount)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(RoundedFieldStyle())
                            .focused($fieldFocused)

                        unitPicker
                    }
                }

                Button("Add item", action: addItem)
                    .buttonStyle(PrimaryButtonStyle(isEnabled: canAdd))
                    .disabled(!canAdd)
            }
        }
    }

    private var photoPickerButton: some View {
        PhotosPicker(selection: $draftPhoto, matching: .images) {
            Group {
                if let draftImageData, let uiImage = UIImage(data: draftImageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.accent)
                }
            }
            .frame(width: 46, height: 46)
            .background(
                RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous)
                    .fill(Theme.surfaceAlt)
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .onChange(of: draftPhoto) { _, newValue in
            Task {
                draftImageData = try? await newValue?.loadTransferable(type: Data.self)
            }
        }
    }

    private var unitPicker: some View {
        Menu {
            ForEach(MeasurementUnit.allCases) { unit in
                Button(unit.label) { draftUnit = unit }
            }
        } label: {
            HStack(spacing: 6) {
                Text(draftUnit.label)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.primaryText)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.secondaryText)
            }
            .frame(minWidth: 70)
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background(
                RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous)
                    .fill(Theme.surfaceAlt)
            )
        }
    }

    // MARK: - Goods list

    private func goodsSection(title: String, subtitle: String, items: [PantryItem], emptyText: String) -> some View {
        SectionBox(title: title) {
            VStack(alignment: .leading, spacing: 10) {
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondaryText)

                if items.isEmpty {
                    Text(emptyText)
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            if index > 0 { RowDivider() }
                            itemRow(item)
                        }
                    }
                }
            }
        }
    }

    private func itemRow(_ item: PantryItem) -> some View {
        HStack(spacing: 12) {
            itemThumbnail(item)

            Text(item.name)
                .font(.system(size: 15))
                .foregroundStyle(Theme.primaryText)

            Spacer()

            if item.kind == .consumable {
                Button {
                    beginEditing(item)
                } label: {
                    HStack(spacing: 4) {
                        Text(item.amountText)
                        Image(systemName: "pencil").font(.system(size: 10))
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.accentDark)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Theme.accentSoft))
                }
                .buttonStyle(.plain)
            }

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

    private func itemThumbnail(_ item: PantryItem) -> some View {
        Group {
            if let data = item.imageData, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "leaf.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.accent)
            }
        }
        .frame(width: 34, height: 34)
        .background(Circle().fill(Theme.accentSoft))
        .clipShape(Circle())
    }

    // MARK: - Matches

    private var matchesSection: some View {
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

    // MARK: - Actions

    private func addItem() {
        let trimmed = draftName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        let amount = Double(draftAmount.trimmingCharacters(in: .whitespaces)) ?? 0
        let item = PantryItem(
            name: trimmed,
            kind: draftKind,
            amount: draftKind == .consumable ? amount : 0,
            unit: draftUnit,
            imageData: draftImageData
        )

        withAnimation(.easeInOut(duration: 0.2)) {
            pantry.add(item)
        }
        resetDraft()
    }

    private func resetDraft() {
        draftName = ""
        draftAmount = ""
        draftPhoto = nil
        draftImageData = nil
    }

    private func remove(_ item: PantryItem) {
        withAnimation(.easeInOut(duration: 0.2)) {
            pantry.remove(item)
        }
    }

    private func beginEditing(_ item: PantryItem) {
        fieldFocused = false
        editingItem = item
        editAmountText = item.amount == item.amount.rounded()
            ? String(Int(item.amount))
            : String(item.amount)
    }

    private func saveEditedAmount() {
        guard let item = editingItem,
              let amount = Double(editAmountText.trimmingCharacters(in: .whitespaces)) else {
            editingItem = nil
            return
        }
        pantry.updateAmount(item, to: max(0, amount))
        editingItem = nil
    }
}

#Preview {
    PantryView()
        .environment(PantryStore())
}
