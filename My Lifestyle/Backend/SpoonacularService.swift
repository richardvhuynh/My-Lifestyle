import Foundation

/// Fetches fully-structured recipes from Spoonacular: real ingredient amounts
/// and units, discrete steps, serving counts, and per-serving nutrition — all
/// in a single `complexSearch` request.
///
/// Spoonacular's free tier is limited (~150 points/day), so this is only used
/// to seed the shared cloud catalog once (via `RecipeCloudService.seedCatalog`).
/// End users read the catalog from the cloud and never call Spoonacular.
enum SpoonacularService {

    /// Fetches a batch of complete recipes. `number` costs roughly one point per
    /// returned recipe with nutrition included.
    static func fetchRecipes(number: Int = 100) async -> [Recipe] {
        guard !NutritionCredentials.spoonacularAPIKey.isEmpty else { return [] }

        var components = URLComponents(string: "https://api.spoonacular.com/recipes/complexSearch")!
        components.queryItems = [
            URLQueryItem(name: "apiKey", value: NutritionCredentials.spoonacularAPIKey),
            URLQueryItem(name: "number", value: String(number)),
            URLQueryItem(name: "addRecipeInformation", value: "true"),
            URLQueryItem(name: "addRecipeNutrition", value: "true"),
            URLQueryItem(name: "fillIngredients", value: "true"),
            URLQueryItem(name: "instructionsRequired", value: "true"),
            URLQueryItem(name: "sort", value: "random")
        ]
        guard let url = components.url else { return [] }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return [] }
            return try JSONDecoder().decode(SpoonSearchResponse.self, from: data).results.compactMap { $0.toRecipe() }
        } catch {
            return []
        }
    }

    /// Maps a Spoonacular unit string to the app's `MeasurementUnit`. Unknown or
    /// count-like units ("clove", "slice", "large", "") become a whole count.
    static func mapUnit(_ raw: String) -> MeasurementUnit {
        var u = raw.lowercased().trimmingCharacters(in: .whitespaces)
        if u.hasSuffix("s") { u = String(u.dropLast()) } // plural → singular

        switch u {
        case "g", "gram", "gr": return .grams
        case "kg", "kilogram": return .kilograms
        case "oz", "ounce": return .ounces
        case "lb", "pound": return .pounds
        case "ml", "milliliter", "millilitre": return .milliliters
        case "l", "liter", "litre": return .liters
        case "cup": return .cups
        case "tablespoon", "tbsp", "tbs", "tbl": return .tablespoons
        case "teaspoon", "tsp": return .teaspoons
        case "fl oz", "fluid ounce": return .fluidOunces
        default: return .whole
        }
    }
}

// MARK: - Spoonacular payload

private struct SpoonSearchResponse: Decodable {
    let results: [SpoonRecipe]
}

private struct SpoonRecipe: Decodable {
    let id: Int
    let title: String
    let image: String?
    let servings: Int?
    let dishTypes: [String]?
    let cuisines: [String]?
    let extendedIngredients: [SpoonIngredient]?
    let analyzedInstructions: [SpoonInstruction]?
    let nutrition: SpoonNutrition?

    func toRecipe() -> Recipe? {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        let servingCount = max(1, servings ?? 1)
        let factor = Double(servingCount)

        // Spoonacular reports nutrition per serving; store the recipe total.
        func perServing(_ name: String) -> Double {
            nutrition?.nutrients?.first { $0.name == name }?.amount ?? 0
        }
        func round1(_ v: Double) -> Double { (v * 10).rounded() / 10 }

        let ingredients = (extendedIngredients ?? []).compactMap { $0.toIngredient() }

        var steps: [RecipeStep] = []
        for group in analyzedInstructions ?? [] {
            for step in group.steps ?? [] {
                let text = (step.step ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                steps.append(RecipeStep(order: steps.count + 1, instruction: text))
            }
        }

        return Recipe(
            name: title,
            imageName: image,
            category: dishTypes?.first.map { $0.capitalized },
            area: cuisines?.first,
            sourceId: "spoonacular-\(id)",
            servings: servingCount,
            ingredients: ingredients,
            steps: steps,
            calories: Int((perServing("Calories") * factor).rounded()),
            protein: round1(perServing("Protein") * factor),
            carbs: round1(perServing("Carbohydrates") * factor),
            fat: round1(perServing("Fat") * factor)
        )
    }
}

private struct SpoonIngredient: Decodable {
    let name: String?
    let nameClean: String?
    let amount: Double?
    let unit: String?

    func toIngredient() -> RecipeIngredient? {
        let raw = (nameClean ?? name)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !raw.isEmpty else { return nil }
        let quantity = (amount ?? 0) > 0 ? amount! : 1
        return RecipeIngredient(name: raw.capitalized, amount: quantity, unit: SpoonacularService.mapUnit(unit ?? ""))
    }
}

private struct SpoonInstruction: Decodable {
    let steps: [SpoonStep]?
}

private struct SpoonStep: Decodable {
    let number: Int?
    let step: String?
}

private struct SpoonNutrition: Decodable {
    let nutrients: [SpoonNutrient]?
}

private struct SpoonNutrient: Decodable {
    let name: String?
    let amount: Double?
    let unit: String?
}
