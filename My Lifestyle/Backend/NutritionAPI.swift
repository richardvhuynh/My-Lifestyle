import Foundation

/// Computes recipe nutrition from the free USDA FoodData Central database. Each
/// ingredient is looked up by name to get its per-100g nutrition, then scaled
/// by the ingredient's weight (via `NutritionEstimator.grams`) and summed into
/// a whole-recipe total.
///
/// USDA's search relevance is weak for recipe ingredient names, so matches are
/// scored and only accepted when the food's description clearly matches the
/// ingredient's head word; anything unconfident falls back to
/// `NutritionEstimator`'s curated profile. Lookups are cached across a run.
/// Returns `nil` only when no ingredient resolved from USDA, so the client
/// shows a pure estimate.
enum NutritionAPI {
    static var isConfigured: Bool { !NutritionCredentials.usdaAPIKey.isEmpty }

    static func fetch(for recipe: Recipe) async -> NutritionInfo? {
        guard isConfigured, !recipe.ingredients.isEmpty else { return nil }

        var calories = 0.0, protein = 0.0, carbs = 0.0, fat = 0.0
        var usdaHits = 0

        for ingredient in recipe.ingredients {
            let profile: NutritionProfile
            if let usda = await profileFromUSDA(for: ingredient.name) {
                profile = usda
                usdaHits += 1
            } else {
                profile = NutritionEstimator.localProfile(for: ingredient.name)
            }
            let factor = NutritionEstimator.grams(for: ingredient) / 100
            calories += profile.calories * factor
            protein += profile.protein * factor
            carbs += profile.carbs * factor
            fat += profile.fat * factor
        }

        guard usdaHits > 0 else { return nil }

        func round1(_ v: Double) -> Double { (v * 10).rounded() / 10 }
        return NutritionInfo(
            calories: Int(calories.rounded()),
            protein: round1(protein),
            carbs: round1(carbs),
            fat: round1(fat)
        )
    }

    // MARK: - USDA lookup

    private static func profileFromUSDA(for name: String) async -> NutritionProfile? {
        let normalized = normalize(name)
        guard !normalized.head.isEmpty else { return nil }

        switch await USDACache.shared.lookup(normalized.query) {
        case .hit(let profile): return profile
        case .miss: return nil
        case .unknown: break
        }

        let profile = await queryUSDA(normalized)
        if let profile {
            await USDACache.shared.record(profile, for: normalized.query)
        } else {
            await USDACache.shared.recordMiss(for: normalized.query)
        }
        // Stay polite and under the hourly rate limit.
        try? await Task.sleep(nanoseconds: 250_000_000)
        return profile
    }

    private static func queryUSDA(_ term: SearchTerm) async -> NutritionProfile? {
        var components = URLComponents(string: "https://api.nal.usda.gov/fdc/v1/foods/search")!
        components.queryItems = [
            URLQueryItem(name: "api_key", value: NutritionCredentials.usdaAPIKey),
            URLQueryItem(name: "query", value: term.query),
            URLQueryItem(name: "pageSize", value: "25"),
            // Generic whole-food datasets, not branded products.
            URLQueryItem(name: "dataType", value: "Foundation,SR Legacy")
        ]
        guard let url = components.url else { return nil }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            let foods = try JSONDecoder().decode(USDASearchResponse.self, from: data).foods ?? []
            return bestMatch(from: foods, term: term)?.profile()
        } catch {
            return nil
        }
    }

    /// Picks the best-scoring food whose description actually contains the
    /// ingredient's head word, preferring Foundation data, more matched words,
    /// "raw" forms, and concise descriptions. Returns nil when nothing matches.
    private static func bestMatch(from foods: [USDAFood], term: SearchTerm) -> USDAFood? {
        var best: (food: USDAFood, score: Double)?
        for food in foods {
            let desc = (food.description ?? "").lowercased()
            // Require every significant word (so "olive oil" doesn't match
            // "coconut oil", and "chicken breast" needs both words).
            guard term.words.allSatisfy({ desc.contains($0) }) else { continue }
            guard (food.profile()?.calories ?? 0) > 0 else { continue }

            var score = 0.0
            if food.dataType == "Foundation" { score += 5 }
            else if food.dataType == "SR Legacy" { score += 3 }
            if desc.hasPrefix(term.head) { score += 2 }
            if desc.contains("raw") { score += 1 }
            // Push down processed/derivative forms ("rice crackers", "salmon
            // nuggets, breaded") in favor of the plain ingredient.
            if processedKeywords.contains(where: { desc.contains($0) }) { score -= 6 }
            score -= Double(desc.split(separator: " ").count) * 0.15

            if best == nil || score > best!.score {
                best = (food, score)
            }
        }
        return best?.food
    }

    // MARK: - Ingredient name normalization

    struct SearchTerm {
        let query: String       // cleaned query sent to USDA
        let words: [String]     // significant words for scoring
        let head: String        // primary food word that must appear in a match
    }

    /// Processed/derivative descriptors that indicate a food isn't the plain
    /// ingredient we want.
    private static let processedKeywords: Set<String> = [
        "nugget", "breaded", "cracker", "chips", "snack", "cake", "candy",
        "bar", "sauce", "soup", "powder", "drink", "fried", "juice", "flavored",
        "dried", "dehydrated", "concentrate", "roasted", "canned"
    ]

    /// A few common recipe→USDA vocabulary differences.
    private static let synonyms: [String: String] = [
        "prawn": "shrimp", "prawns": "shrimp", "aubergine": "eggplant",
        "courgette": "zucchini", "coriander": "cilantro", "rocket": "arugula",
        "beetroot": "beets", "sultanas": "raisins", "mince": "ground beef",
        "prawn's": "shrimp"
    ]

    /// Words that describe rather than identify a food; dropped from the query.
    private static let descriptors: Set<String> = [
        "fresh", "large", "small", "medium", "ground", "chopped", "sliced",
        "diced", "minced", "grated", "whole", "boneless", "skinless", "cooked",
        "ripe", "king", "baby", "plain", "self", "raising", "extra", "virgin",
        "free", "range", "of", "the", "and", "a", "an", "to", "for", "into",
        "finely", "roughly", "hot", "cold", "dried", "frozen", "canned",
        "peeled", "beaten", "softened", "melted", "warm", "thinly", "packet"
    ]

    private static func normalize(_ name: String) -> SearchTerm {
        var words = name
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .map { synonyms[$0] ?? $0 }
            .flatMap { $0.split(separator: " ").map(String.init) }

        let significant = words.filter { !descriptors.contains($0) }
        if !significant.isEmpty { words = significant }

        return SearchTerm(
            query: words.joined(separator: " "),
            words: words,
            head: words.last ?? ""
        )
    }
}

/// Caches USDA lookups (hits and misses) for the duration of a seeding run so
/// repeated ingredients like salt, oil, or garlic aren't re-fetched.
private actor USDACache {
    static let shared = USDACache()

    enum Result { case hit(NutritionProfile), miss, unknown }

    private var hits: [String: NutritionProfile] = [:]
    private var misses: Set<String> = []

    func lookup(_ key: String) -> Result {
        if let profile = hits[key] { return .hit(profile) }
        if misses.contains(key) { return .miss }
        return .unknown
    }

    func record(_ profile: NutritionProfile, for key: String) { hits[key] = profile }
    func recordMiss(for key: String) { misses.insert(key) }
}

// MARK: - USDA payload

private struct USDASearchResponse: Decodable {
    let foods: [USDAFood]?
}

private struct USDAFood: Decodable {
    let description: String?
    let dataType: String?
    let foodNutrients: [USDANutrient]?

    /// Builds a per-100g profile from the food's nutrients (USDA reports search
    /// results per 100g). Nutrient numbers: 208 energy(kcal), 203 protein,
    /// 205 carbs, 204 fat.
    func profile() -> NutritionProfile? {
        guard let foodNutrients else { return nil }
        func value(_ number: String) -> Double {
            foodNutrients.first { $0.nutrientNumber == number }?.value ?? 0
        }
        let calories = value("208")
        guard calories > 0 else { return nil }
        return NutritionProfile(
            calories: calories,
            protein: value("203"),
            carbs: value("205"),
            fat: value("204")
        )
    }
}

private struct USDANutrient: Decodable {
    let nutrientNumber: String?
    let value: Double?
}
