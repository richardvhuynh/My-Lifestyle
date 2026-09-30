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

    /// Herbs and seasonings should read as spoons, not a "whole" count.
    private static let seasonings = ["salt", "pepper", "parsley", "thyme", "cilantro",
        "coriander", "basil", "oregano", "rosemary", "mint", "dill", "chive",
        "sage", "tarragon", "marjoram"]

    /// Produce peppers (bell/chili/etc.) are counted vegetables, not the
    /// "pepper" seasoning — keep them as-is.
    private static let producePeppers = ["bell pepper", "red pepper", "green pepper",
        "yellow pepper", "orange pepper", "sweet pepper", "jalapeno", "capsicum",
        "poblano", "serrano", "habanero"]

    static func normalizeSeasoningUnit(name: String, unit: MeasurementUnit) -> MeasurementUnit {
        let n = name.lowercased()
        if producePeppers.contains(where: { n.contains($0) }) { return unit }
        guard unit == .whole else { return unit }
        return seasonings.contains { n.contains($0) } ? .tablespoons : unit
    }

    /// Imperative verbs that open a cooking instruction. Spoonacular's
    /// ingredient parser sometimes mistakes a step sentence for an ingredient
    /// (e.g. "Add the peppers", "Reduce the heat a little"); such entries begin
    /// with one of these and are dropped by `isPlausibleIngredientName`.
    private static let instructionVerbs: Set<String> = [
        "add", "heat", "reduce", "cook", "stir", "season", "serve", "mix",
        "place", "remove", "bring", "simmer", "saute", "sauté", "bake", "pour",
        "combine", "whisk", "beat", "fold", "drain", "cut", "chop", "slice",
        "dice", "mince", "preheat", "transfer", "cover", "let", "set", "spread",
        "sprinkle", "garnish", "roll", "knead", "boil", "roast", "grill", "fry",
        "blend", "mash", "peel", "grate", "melt", "arrange", "divide", "repeat",
        "continue", "allow", "discard", "reserve", "rinse", "wash", "soak",
        "marinate", "whip", "turn", "flip", "top", "layer", "drizzle", "brush",
        "dust", "taste", "adjust", "refrigerate", "chill", "freeze", "warm",
        "reheat", "can", "make", "prepare", "wipe"
    ]

    /// True when a parsed name reads like a real ingredient rather than a stray
    /// instruction fragment. Real ingredient names are short noun phrases with
    /// no sentence punctuation and don't open with an imperative cooking verb.
    static func isPlausibleIngredientName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        if trimmed.contains(".") || trimmed.contains("!") { return false }
        let words = trimmed.split(separator: " ")
        if words.count > 5 { return false }
        if let first = words.first, instructionVerbs.contains(first.lowercased()) {
            return false
        }
        return true
    }

    /// Strips HTML tags/entities (e.g. "&nbsp;") that Spoonacular leaves in text
    /// and collapses whitespace.
    static func clean(_ s: String) -> String {
        var t = s.replacingOccurrences(of: "&nbsp;", with: " ", options: .caseInsensitive)
        t = t.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        let entities = ["&amp;": "&", "&lt;": "<", "&gt;": ">", "&#39;": "'",
                        "&rsquo;": "'", "&apos;": "'", "&quot;": "\"",
                        "&ldquo;": "\"", "&rdquo;": "\"", "&deg;": "°"]
        for (key, value) in entities {
            t = t.replacingOccurrences(of: key, with: value, options: .caseInsensitive)
        }
        t = t.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
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
        let title = SpoonacularService.clean(title)
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
                let text = SpoonacularService.clean(step.step ?? "")
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
        let raw = SpoonacularService.clean(nameClean ?? name ?? "")
        guard !raw.isEmpty, SpoonacularService.isPlausibleIngredientName(raw) else { return nil }
        let quantity = (amount ?? 0) > 0 ? amount! : 1
        let unit = SpoonacularService.normalizeSeasoningUnit(
            name: raw, unit: SpoonacularService.mapUnit(unit ?? "")
        )
        return RecipeIngredient(name: raw.capitalized, amount: quantity, unit: unit)
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
