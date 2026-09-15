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
            let parsed = MealDBMeal.parseMeasure(measure)
            let resolved = IngredientClassifier.resolve(
                name: rawName, parsedAmount: parsed.amount, parsedUnit: parsed.unit
            )
            ingredients.append(RecipeIngredient(name: rawName.capitalized, amount: resolved.amount, unit: resolved.unit))
        }

        let steps = MealDBMeal.parseSteps(value("strInstructions") ?? "")

        return Recipe(
            name: name,
            imageName: value("strMealThumb"),
            category: value("strCategory"),
            area: value("strArea"),
            sourceId: value("idMeal"),
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

    /// Parses a free-text measure like "240g large", "1 tbsp", or "1 1/2 cups"
    /// into a numeric amount and an explicit `MeasurementUnit`. Either can be
    /// `nil`: no number found, and/or no explicit unit in the text (e.g.
    /// "Garnish", "1 chopped"). The caller fills gaps from the ingredient type.
    static func parseMeasure(_ measure: String) -> (amount: Double?, unit: MeasurementUnit?) {
        let trimmed = measure.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return (nil, nil) }

        // Peel the leading numeric portion (digits, dots, slashes, spaces, and
        // vulgar-fraction glyphs) off the front; the rest is the unit + notes.
        var index = trimmed.startIndex
        var numberPart = ""
        while index < trimmed.endIndex {
            let char = trimmed[index]
            if char.isNumber || char == "." || char == "/" || char == " " || vulgarFractions[char] != nil {
                numberPart.append(char)
                index = trimmed.index(after: index)
            } else {
                break
            }
        }

        return (parseQuantity(from: numberPart), detectUnit(after: trimmed[index...]))
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

    /// Determines the explicit unit from the text following the number. Reads
    /// the first word (splitting on spaces and slashes, e.g. "g/2oz" → "g") and
    /// matches known unit tokens. Returns `nil` when the text has no real unit
    /// ("large", "finely chopped", "Garnish"), so the ingredient type decides.
    private static func detectUnit(after rest: Substring) -> MeasurementUnit? {
        let word = rest
            .split(whereSeparator: { $0 == " " || $0 == "/" })
            .first
            .map { $0.lowercased() } ?? ""

        if word.isEmpty { return nil }
        if word.hasPrefix("kg") || word.hasPrefix("kilo") { return .kilograms }
        if word == "g" || word.hasPrefix("gram") || word.hasPrefix("gm") { return .grams }
        if word.hasPrefix("ml") || word.hasPrefix("millilit") { return .milliliters }
        if word == "l" || word.hasPrefix("litre") || word.hasPrefix("liter") { return .liters }
        if word.hasPrefix("tbsp") || word.hasPrefix("tbs") || word.hasPrefix("tbl") || word.hasPrefix("tablespoon") { return .tablespoons }
        if word.hasPrefix("tsp") || word.hasPrefix("teaspoon") { return .teaspoons }
        if word.hasPrefix("cup") { return .cups }
        if word.hasPrefix("fl") { return .fluidOunces }
        if word.hasPrefix("oz") || word.hasPrefix("ounce") { return .ounces }
        if word.hasPrefix("lb") || word.hasPrefix("pound") { return .pounds }
        return nil
    }

    /// Splits TheMealDB's instruction blob into ordered steps.
    ///
    /// The text is broken into lines, then each line is split into sentences so
    /// recipes that pack several actions into one paragraph (chop, heat, sauté…)
    /// become separate steps. Bare "STEP N" / "1." markers are dropped, and
    /// trailing non-cooking sections (Serving, Storage, Notes…) are folded into
    /// a single closing step rather than many fragments.
    private static func parseSteps(_ instructions: String) -> [RecipeStep] {
        let normalized = instructions
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{200b}", with: "") // zero-width spacers

        var steps: [String] = []
        var notes: [String] = []
        var inNotes = false

        for rawLine in normalized.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }

            // A short header line (Serving/Storage/etc.) begins the notes.
            if !inNotes, isNoteHeader(sentences(in: line).first ?? line) { inNotes = true }

            for sentence in sentences(in: line) {
                let text = cleanStepText(sentence)
                guard !text.isEmpty, !isPureMarker(text) else { continue }
                if inNotes {
                    notes.append(text)
                } else {
                    steps.append(text)
                }
            }
        }

        // Collapse all trailing note sentences into one closing step.
        if !notes.isEmpty {
            steps.append(notes.joined(separator: " "))
        }

        if steps.isEmpty {
            steps = [instructions.trimmingCharacters(in: .whitespacesAndNewlines)]
        }
        return steps.enumerated().map { RecipeStep(order: $0.offset + 1, instruction: $0.element) }
    }

    /// Splits a line into sentences on `.`/`!`/`?` boundaries (a period between
    /// digits like "1.5" is left intact since it isn't followed by a space).
    private static func sentences(in line: String) -> [String] {
        let sentinel = "\u{0001}"
        return line
            .replacingOccurrences(of: "([.!?])\\s+", with: "$1\(sentinel)", options: .regularExpression)
            .components(separatedBy: sentinel)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    // Ingredient unit/amount inference lives in `IngredientClassifier`.

    /// Joins a paragraph's lines into one string, collapses whitespace, and
    /// strips a leading "STEP N" / "N." / "N)" marker.
    private static func cleanStepText(_ chunk: String) -> String {
        var text = chunk
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)

        if let range = text.range(of: "^step\\s*\\d+\\s*[:.)-]?\\s*", options: [.regularExpression, .caseInsensitive]) {
            text = String(text[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        }
        if let range = text.range(of: "^\\d+\\s*[.)]\\s+", options: .regularExpression) {
            text = String(text[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        }
        return text
    }

    /// True when the text is only a step marker like "STEP 1", "1.", or "2)".
    private static func isPureMarker(_ text: String) -> Bool {
        text.range(of: "^(step\\s*)?\\d+\\s*[:.)-]?$", options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// True when a line looks like a non-cooking section header — a short title
    /// (≤ 5 words, no ending period) beginning with a storage/serving keyword.
    private static func isNoteHeader(_ line: String) -> Bool {
        let l = line.lowercased().trimmingCharacters(in: .whitespaces)
        guard !l.isEmpty, !l.hasSuffix("."), l.split(separator: " ").count <= 5 else { return false }
        let keywords = ["preserv", "serving", "to serve", "storage", "storing", "store",
                        "note", "tip", "make ahead", "freez", "reheat", "nutrition",
                        "variation", "leftover"]
        return keywords.contains { l.hasPrefix($0) }
    }
}
