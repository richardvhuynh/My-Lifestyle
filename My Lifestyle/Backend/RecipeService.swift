import Foundation

/// Fetches recipes from [TheMealDB](https://www.themealdb.com/api.php), a free
/// public recipe database that requires no API key. It returns meal names,
/// photos, ingredient lists with measures, and step instructions.
///
/// Note: TheMealDB's free tier does not provide nutrition data, so imported
/// recipes come in with zeroed calories/macros. Swap in a nutrition API
/// (Edamam, Spoonacular, etc.) later if real macros are needed.
enum RecipeService {
    private static let base = "https://www.themealdb.com/api/json/v1/1/"

    /// Fetches a batch of recipes. The free tier has no "list everything"
    /// endpoint, so we search by a spread of first letters and flatten the
    /// results into a single de-duplicated list.
    static func fetchRecipes(letters: [Character] = ["b", "c", "s", "p", "e", "l"]) async -> [Recipe] {
        var recipes: [Recipe] = []
        var seenNames = Set<String>()

        for letter in letters {
            for meal in await fetchMeals(startingWith: letter) {
                let recipe = meal.toRecipe()
                let key = recipe.name.lowercased()
                guard !key.isEmpty, seenNames.insert(key).inserted else { continue }
                recipes.append(recipe)
            }
        }
        return recipes
    }

    /// Fetches every meal whose name starts with `letter`.
    private static func fetchMeals(startingWith letter: Character) async -> [MealDBMeal] {
        guard let url = URL(string: base + "search.php?f=\(letter)") else { return [] }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(MealDBResponse.self, from: data)
            return response.meals ?? []
        } catch {
            // A single failed page shouldn't abort the whole import.
            return []
        }
    }
}

// MARK: - TheMealDB payload

private struct MealDBResponse: Decodable {
    let meals: [MealDBMeal]?
}

/// A single meal from TheMealDB. The API returns a flat JSON object with
/// dynamic keys (`strIngredient1`…`strIngredient20`, `strMeasure1`…), so we
/// decode into a `[String: String]` bag and read fields by name.
private struct MealDBMeal: Decodable {
    let fields: [String: String]

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        // Values are either strings or null; drop the nulls.
        fields = try container.decode([String: String?].self).compactMapValues { $0 }
    }

    func toRecipe() -> Recipe {
        let name = value("strMeal") ?? "Untitled Recipe"

        var ingredients: [RecipeIngredient] = []
        for index in 1...20 {
            guard let rawName = value("strIngredient\(index)"),
                  !rawName.isEmpty else { continue }
            let measure = value("strMeasure\(index)") ?? ""
            let (amount, unit) = MealDBMeal.parseMeasure(measure)
            ingredients.append(RecipeIngredient(name: rawName.capitalized, amount: amount, unit: unit))
        }

        let steps = MealDBMeal.parseSteps(value("strInstructions") ?? "")

        return Recipe(
            name: name,
            imageName: value("strMealThumb"),
            ingredients: ingredients,
            steps: steps,
            // TheMealDB provides no nutrition data on the free tier.
            calories: 0, protein: 0, carbs: 0, fat: 0
        )
    }

    private func value(_ key: String) -> String? {
        guard let raw = fields[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return nil }
        return raw
    }

    // MARK: Parsing helpers

    /// Turns a free-text measure like "200g", "1 tbsp", or "1 1/2 cups" into a
    /// numeric amount and a `MeasurementUnit`, best-effort. Unrecognized or
    /// empty measures fall back to a single piece.
    static func parseMeasure(_ measure: String) -> (Double, MeasurementUnit) {
        let trimmed = measure.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return (1, .pieces) }

        // Peel off the leading numeric portion (digits, dots, slashes, spaces,
        // and vulgar-fraction glyphs) from the trailing unit text.
        var numberPart = ""
        var inNumber = true
        for char in trimmed {
            if inNumber, char.isNumber || char == "." || char == "/" || char == " " || vulgarFractions[char] != nil {
                numberPart.append(char)
            } else {
                inNumber = false
            }
        }

        let amount = parseQuantity(from: numberPart) ?? 1
        return (amount, detectUnit(in: trimmed))
    }

    private static let vulgarFractions: [Character: Double] = [
        "½": 0.5, "¼": 0.25, "¾": 0.75, "⅓": 1.0 / 3, "⅔": 2.0 / 3, "⅛": 0.125
    ]

    /// Sums a numeric string that may contain a whole number, a fraction, or a
    /// mixed number ("1 1/2"), plus single vulgar-fraction glyphs.
    private static func parseQuantity(from text: String) -> Double? {
        var total = 0.0
        var matched = false

        for token in text.split(separator: " ") {
            let piece = String(token)
            if piece.count == 1, let fraction = vulgarFractions[piece.first!] {
                total += fraction
                matched = true
            } else if piece.contains("/") {
                let parts = piece.split(separator: "/")
                if parts.count == 2, let num = Double(parts[0]), let den = Double(parts[1]), den != 0 {
                    total += num / den
                    matched = true
                }
            } else if let number = Double(piece) {
                total += number
                matched = true
            }
        }
        return matched ? total : nil
    }

    /// Matches unit keywords, checking the more specific tokens first so that,
    /// e.g., "fl oz" isn't swallowed by "oz" and "kg" isn't swallowed by "g".
    private static func detectUnit(in measure: String) -> MeasurementUnit {
        let m = measure.lowercased()
        if m.contains("fl oz") || m.contains("fluid ounce") { return .fluidOunces }
        if m.contains("tbsp") || m.contains("tbs") || m.contains("tablespoon") { return .tablespoons }
        if m.contains("tsp") || m.contains("teaspoon") { return .teaspoons }
        if m.contains("kg") || m.contains("kilo") { return .kilograms }
        if m.contains("ml") || m.contains("millilit") { return .milliliters }
        if m.contains("cup") { return .cups }
        if m.contains("oz") || m.contains("ounce") { return .ounces }
        if m.contains("lb") || m.contains("pound") { return .pounds }
        if m.contains("litre") || m.contains("liter") { return .liters }
        if m.contains("gram") || m.hasSuffix("g") { return .grams }
        return .pieces
    }

    /// Splits TheMealDB's instruction blob into ordered steps, one per non-empty
    /// line.
    private static func parseSteps(_ instructions: String) -> [RecipeStep] {
        let lines = instructions
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let source = lines.isEmpty ? [instructions] : lines
        return source.enumerated().map { RecipeStep(order: $0.offset + 1, instruction: $0.element) }
    }
}
