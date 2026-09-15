import SwiftUI

/// A browse axis for the recipe explorer: group/filter by food category
/// ("Seafood", "Dessert"…) or by cuisine/area ("Italian", "Mexican"…).
enum RecipeBrowseAxis: String, CaseIterable, Identifiable {
    case category = "Category"
    case cuisine = "Cuisine"

    var id: String { rawValue }

    /// The axis value for a given recipe, if present.
    func value(of recipe: Recipe) -> String? {
        switch self {
        case .category: return recipe.category
        case .cuisine: return recipe.area
        }
    }
}

/// The shared recipe explorer. Recipes live in the cloud (`RecipeCloudService`)
/// so every user sees the same catalog; users browse them by food category or
/// cuisine and search by name.
struct RecipesView: View {
    /// Owned by `MainTabView` so tapping the tab bar can pop back to the grid.
    @Binding var path: NavigationPath
    @State private var searchText = ""
    @State private var recipes: [Recipe] = []
    @State private var browseAxis: RecipeBrowseAxis = .category
    @State private var selectedFilter: String?
    @State private var isLoading = false
    @State private var isImporting = false
    @State private var errorMessage: String?

    /// Distinct values for the active axis, sorted, used as filter chips.
    private var axisValues: [String] {
        let values = recipes.compactMap { browseAxis.value(of: $0) }
        return Array(Set(values)).sorted()
    }

    /// Recipes matching the search text and the selected axis filter.
    private var filtered: [Recipe] {
        recipes.filter { recipe in
            let matchesSearch = searchText.isEmpty
                || recipe.name.localizedCaseInsensitiveContains(searchText)
            let matchesFilter = selectedFilter == nil
                || browseAxis.value(of: recipe) == selectedFilter
            return matchesSearch && matchesFilter
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack(alignment: .top) {
                Theme.background.ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 16) {
                        AppHeader(
                            title: "Explore",
                            subtitle: subtitle,
                            trailingIcon: isImporting ? nil : "square.and.arrow.down",
                            trailingAction: { Task { await importRecipes() } }
                        )
                        .overlay(alignment: .trailing) {
                            if isImporting {
                                ProgressView().padding(.trailing, 16)
                            }
                        }

                        SearchField(text: $searchText, prompt: "Search recipes")
                            .padding(.horizontal, 16)

                        if !recipes.isEmpty {
                            axisPicker
                            filterChips
                        }

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.secondaryText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16)
                        }

                        if isLoading && recipes.isEmpty {
                            ProgressView("Loading recipes…")
                                .padding(.top, 40)
                        } else if recipes.isEmpty {
                            emptyState
                        } else {
                            LazyVGrid(columns: gridColumns, spacing: 16) {
                                ForEach(filtered) { recipe in
                                    NavigationLink(value: recipe) {
                                        RecipeCard(recipe: recipe)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                    .padding(.bottom, 120)
                }
                .refreshable { await load() }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Recipe.self) { recipe in
                RecipeDetailView(recipe: recipe) { updated in
                    // Reflect lazily-fetched nutrition back into the grid so it
                    // isn't looked up again this session.
                    if let index = recipes.firstIndex(where: { $0.id == updated.id }) {
                        recipes[index] = updated
                    }
                }
            }
            .task { await load() }
        }
    }

    /// Two flexible columns for the exploration grid.
    private var gridColumns: [GridItem] {
        [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]
    }

    private var subtitle: String {
        recipes.isEmpty ? "Discover recipes" : "\(recipes.count) recipes"
    }

    /// Segmented control switching between browsing by category and cuisine.
    private var axisPicker: some View {
        Picker("Browse by", selection: $browseAxis) {
            ForEach(RecipeBrowseAxis.allCases) { axis in
                Text(axis.rawValue).tag(axis)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .onChange(of: browseAxis) { _, _ in selectedFilter = nil }
    }

    /// Horizontally scrolling "All + values" chips for the active axis.
    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(title: "All", isSelected: selectedFilter == nil) {
                    selectedFilter = nil
                }
                ForEach(axisValues, id: \.self) { value in
                    FilterChip(title: value, isSelected: selectedFilter == value) {
                        selectedFilter = value
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "fork.knife")
                .font(.system(size: 40))
                .foregroundStyle(Theme.accentDark)
            Text("No recipes yet")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.primaryText)
            Text("Tap the import button to load the shared recipe catalog.")
                .font(.system(size: 14))
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
            Button("Import recipes") { Task { await importRecipes() } }
                .buttonStyle(PrimaryButtonStyle())
                .frame(maxWidth: 220)
                .disabled(isImporting)
        }
        .padding(.horizontal, 32)
        .padding(.top, 40)
    }

    /// Loads the shared catalog from the cloud. On the very first run the
    /// catalog is empty, so it seeds itself once from TheMealDB; afterwards
    /// recipes persist in the cloud and simply appear on launch — no manual
    /// import needed.
    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            var fetched = try await RecipeCloudService.list()
            if fetched.isEmpty {
                isImporting = true
                _ = try await RecipeCloudService.seedFromTheMealDB()
                fetched = try await RecipeCloudService.list()
                isImporting = false
            }
            recipes = fetched
            prefetchImages(for: fetched)
        } catch {
            errorMessage = "Couldn't load recipes. Pull to refresh to try again."
        }
        isImporting = false
        isLoading = false
    }

    /// Warms the image cache for the whole catalog so tiles show instantly
    /// instead of loading as they scroll into view.
    private func prefetchImages(for recipes: [Recipe]) {
        let urls = recipes.compactMap { recipe -> URL? in
            guard let name = recipe.imageName, name.hasPrefix("http") else { return nil }
            return URL(string: name)
        }
        Task { await ImageCache.shared.prefetch(urls) }
    }

    /// Seeds the shared cloud catalog from TheMealDB, then reloads so the new
    /// recipes are visible to this (and every) user.
    private func importRecipes() async {
        guard !isImporting else { return }
        isImporting = true
        errorMessage = nil
        do {
            _ = try await RecipeCloudService.seedFromTheMealDB()
            recipes = try await RecipeCloudService.list()
        } catch {
            errorMessage = "Import failed. Check your connection and try again."
        }
        isImporting = false
    }
}

/// A pill-shaped selectable filter chip used by the recipe explorer.
private struct FilterChip: View {
    var title: String
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isSelected ? .white : Theme.primaryText)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(
                    Capsule().fill(isSelected ? Theme.accent : Theme.surface)
                )
                .overlay(
                    Capsule().stroke(Color.black.opacity(0.05), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
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

/// Shows a recipe's photo. `imageName` may be a remote URL (imported recipes),
/// a bundled asset name, or `nil` — falling back to a themed placeholder icon.
private struct RecipeThumbnail: View {
    var imageName: String?
    var cornerRadius: CGFloat
    var iconSize: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Theme.accentSoft)
            .overlay {
                if let imageName, imageName.hasPrefix("http") {
                    CachedImage(url: URL(string: imageName)) { placeholder }
                } else if let imageName, UIImage(named: imageName) != nil {
                    Image(imageName).resizable().scaledToFill()
                } else {
                    placeholder
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private var placeholder: some View {
        Image(systemName: "photo")
            .font(.system(size: iconSize))
            .foregroundStyle(Theme.accentDark)
    }
}

/// A grid tile for the explorer: the recipe photo with its name beneath.
private struct RecipeCard: View {
    var recipe: Recipe

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RecipeThumbnail(imageName: recipe.imageName, cornerRadius: 16, iconSize: 28)
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: .infinity)

            Text(recipe.name)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.primaryText)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let tag = recipe.category ?? recipe.area {
                Text(tag)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
            }
        }
    }
}

struct RecipeDetailView: View {
    @State private var recipe: Recipe
    /// Called when nutrition is lazily fetched, so the grid can update its copy.
    private let onUpdate: (Recipe) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var isCooking = false
    /// TheMealDB gives no yield, so we estimate it from the recipe's total
    /// ingredient weight (see `NutritionEstimator.estimatedServings`). The user
    /// can still adjust to scale ingredients.
    private let baseServings: Int
    @State private var servings: Int

    init(recipe: Recipe, onUpdate: @escaping (Recipe) -> Void = { _ in }) {
        _recipe = State(initialValue: recipe)
        self.onUpdate = onUpdate
        let estimated = NutritionEstimator.estimatedServings(for: recipe.ingredients)
        self.baseServings = estimated
        _servings = State(initialValue: estimated)
    }

    /// Nutrition for a single serving (stored total ÷ base servings).
    private var perServing: NutritionInfo {
        let total = recipe.nutrition
        let d = Double(baseServings)
        func r1(_ v: Double) -> Double { (v / d * 10).rounded() / 10 }
        return NutritionInfo(
            calories: Int((Double(total.calories) / d).rounded()),
            protein: r1(total.protein),
            carbs: r1(total.carbs),
            fat: r1(total.fat)
        )
    }

    /// Multiplier applied to ingredient amounts for the chosen servings.
    private var scale: Double { Double(servings) / Double(baseServings) }

    var body: some View {
        ZStack(alignment: .top) {
            Theme.background.ignoresSafeArea()

            // Fixed back bar kept outside the ScrollView so it stays reachable
            // below the status bar and always pops back to the list.
            VStack(spacing: 0) {
                topBar
                // GeometryReader pins the content to exactly the viewport width
                // so it's vertical-scroll only — no horizontal drift.
                GeometryReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        content
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                            .padding(.bottom, 40)
                            .frame(width: proxy.size.width, alignment: .topLeading)
                    }
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .fullScreenCover(isPresented: $isCooking) {
            RecipeCookingView(recipe: recipe)
        }
        .task { await loadNutritionIfNeeded() }
    }

    /// The first time a recipe with no stored nutrition is opened, look it up
    /// from USDA, show it, and persist it to the cloud so it's permanent.
    private func loadNutritionIfNeeded() async {
        guard !recipe.hasStoredNutrition,
              !recipe.ingredients.isEmpty,
              let cloudId = recipe.cloudId,
              let info = await NutritionAPI.fetch(for: recipe) else { return }

        recipe.calories = info.calories
        recipe.protein = info.protein
        recipe.carbs = info.carbs
        recipe.fat = info.fat
        onUpdate(recipe)
        try? await RecipeCloudService.updateNutrition(cloudId: cloudId, info)
    }

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                    Text("Recipes")
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.accentDark)
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    /// Stepper that scales the recipe up or down by number of servings.
    private var servingsControl: some View {
        HStack {
            Text("Servings")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.primaryText)
            Spacer()
            HStack(spacing: 18) {
                Button { if servings > 1 { servings -= 1 } } label: {
                    Image(systemName: "minus.circle.fill")
                }
                .buttonStyle(.plain)
                .disabled(servings <= 1)

                Text("\(servings)")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Theme.primaryText)
                    .frame(minWidth: 22)

                Button { if servings < 20 { servings += 1 } } label: {
                    Image(systemName: "plus.circle.fill")
                }
                .buttonStyle(.plain)
                .disabled(servings >= 20)
            }
            .font(.system(size: 22))
            .foregroundStyle(Theme.accent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface)
        )
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 18) {
            RecipeThumbnail(imageName: recipe.imageName, cornerRadius: 18, iconSize: 40)
                .frame(height: 160)

            VStack(alignment: .leading, spacing: 4) {
                Text(recipe.name)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.primaryText)
                Text("\(perServing.calories) kcal per serving" + (recipe.isNutritionEstimated ? " · estimated" : ""))
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.secondaryText)
            }

            HStack(spacing: 10) {
                macroChip("Protein", "\(Int(perServing.protein))g", Theme.protein)
                macroChip("Carbs", "\(Int(perServing.carbs))g", Theme.carb)
                macroChip("Fat", "\(Int(perServing.fat))g", Theme.fat)
            }

            servingsControl

            Button { isCooking = true } label: {
                Label("Start Recipe", systemImage: "play.fill")
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(recipe.steps.isEmpty && recipe.ingredients.isEmpty)

            SectionBox(title: "Ingredients") {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(recipe.ingredients) { ingredient in
                                HStack(spacing: 10) {
                                    Circle().fill(Theme.accent).frame(width: 6, height: 6)
                                    Text(ingredient.name)
                                        .font(.system(size: 15))
                                        .foregroundStyle(Theme.primaryText)
                                    Spacer()
                                    Text(ingredient.unit.formatted(ingredient.amount * scale))
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(Theme.secondaryText)
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

/// A guided, one-step-at-a-time cooking flow. Advance with Next; on the final
/// step, Complete marks the recipe done and decrements matching pantry stock.
struct RecipeCookingView: View {
    let recipe: Recipe
    @Environment(PantryStore.self) private var pantry
    @Environment(\.dismiss) private var dismiss
    @State private var stepIndex = 0
    @State private var isFinished = false
    @State private var consumedItems: [String] = []

    private var steps: [RecipeStep] {
        recipe.steps.sorted { $0.order < $1.order }
    }

    private var isLastStep: Bool {
        stepIndex >= steps.count - 1
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            if isFinished {
                completionView
            } else {
                cookingView
            }
        }
    }

    // MARK: Cooking

    private var cookingView: some View {
        VStack(spacing: 20) {
            HStack {
                Text(steps.isEmpty ? recipe.name : "Step \(stepIndex + 1) of \(steps.count)")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.secondaryText)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.secondaryText)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(Theme.surface))
                }
                .buttonStyle(.plain)
            }

            if steps.count > 1 {
                ProgressView(value: Double(stepIndex + 1), total: Double(steps.count))
                    .tint(Theme.accent)
            }

            ScrollView(.vertical, showsIndicators: false) {
                Text(steps.isEmpty
                     ? "No steps were provided for this recipe. Tap Complete when you're done cooking."
                     : steps[stepIndex].instruction)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Theme.primaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Theme.surface)
                    )
            }

            HStack(spacing: 12) {
                if stepIndex > 0 {
                    Button("Back") {
                        withAnimation { stepIndex -= 1 }
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
                Button(isLastStep ? "Complete" : "Next") {
                    if isLastStep {
                        complete()
                    } else {
                        withAnimation { stepIndex += 1 }
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(20)
    }

    // MARK: Completion

    private var completionView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(Theme.accent)
            Text("Recipe complete!")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.primaryText)
            Text(consumedItems.isEmpty
                 ? "No matching pantry items to update."
                 : "Pantry updated: \(consumedItems.joined(separator: ", "))")
                .font(.system(size: 15))
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
            Button("Done") { dismiss() }
                .buttonStyle(PrimaryButtonStyle())
                .frame(maxWidth: 220)
                .padding(.top, 8)
        }
        .padding(32)
    }

    private func complete() {
        consumedItems = pantry.completeRecipe(recipe)
        withAnimation { isFinished = true }
    }
}

#Preview {
    RecipesView(path: .constant(NavigationPath()))
        .environment(PantryStore())
}
