import Foundation

/// A rolled-up nutrition total for a recipe.
struct NutritionInfo: Hashable {
    var calories: Int
    var protein: Double
    var carbs: Double
    var fat: Double
}

/// Estimates a recipe's nutrition from its ingredient list. TheMealDB (our
/// import source) ships no nutrition data, so we approximate: each ingredient's
/// amount is converted to grams and multiplied by a per-100g nutrition profile
/// looked up by keyword, with a generic fallback for unrecognized items.
///
/// These are rough estimates for exploration, not verified nutrition facts.
enum NutritionEstimator {

    /// Estimates how many servings a recipe yields from the total weight of its
    /// ingredients (~400 g of food per serving), clamped to 1…12. TheMealDB has
    /// no serving field, so this adapts to the dish size — a sandwich comes out
    /// as 1, a big stew as several — instead of a fixed guess.
    static func estimatedServings(for ingredients: [RecipeIngredient]) -> Int {
        let totalGrams = ingredients.reduce(0.0) { $0 + grams(for: $1) }
        let servings = (totalGrams / 400).rounded()
        return min(12, max(1, Int(servings)))
    }

    static func estimate(for ingredients: [RecipeIngredient]) -> NutritionInfo {
        var calories = 0.0, protein = 0.0, carbs = 0.0, fat = 0.0

        for ingredient in ingredients {
            let gramsAmount = grams(for: ingredient)
            let profile = localProfile(for: ingredient.name)
            let factor = gramsAmount / 100
            calories += profile.calories * factor
            protein += profile.protein * factor
            carbs += profile.carbs * factor
            fat += profile.fat * factor
        }

        return NutritionInfo(
            calories: Int(calories.rounded()),
            protein: (protein * 10).rounded() / 10,
            carbs: (carbs * 10).rounded() / 10,
            fat: (fat * 10).rounded() / 10
        )
    }

    /// Converts an ingredient's amount into grams. Mass converts directly,
    /// volume is treated as ~1 g/ml, and counts use a per-item weight. Shared
    /// with the USDA-backed `NutritionAPI` so both scale nutrients the same way.
    static func grams(for ingredient: RecipeIngredient) -> Double {
        let name = ingredient.name.lowercased()
        switch ingredient.unit.dimension {
        case .mass:
            return ingredient.amount * ingredient.unit.perBaseUnit
        case .volume:
            let grams = ingredient.amount * ingredient.unit.perBaseUnit
            // Deep-frying oil: only a little is absorbed, the rest is a cooking
            // medium that's discarded. Cap large oil/fat volumes so "2 cups
            // vegetable oil" doesn't add thousands of calories.
            if isFryingFat(name), grams > 45 { return 30 }
            return grams
        case .count:
            return ingredient.amount * perItemGrams(for: name)
        }
    }

    private static func isFryingFat(_ name: String) -> Bool {
        ["oil", "shortening", "lard", "ghee", "tallow"].contains { name.contains($0) }
    }

    // MARK: - Lookup tables

    /// Local, offline per-100g nutrition profile looked up by keyword, used as
    /// the fallback when a USDA lookup is unavailable.
    static func localProfile(for name: String) -> NutritionProfile {
        let n = name.lowercased()
        for (keywords, profile) in table {
            if keywords.contains(where: { n.contains($0) }) { return profile }
        }
        // Near-zero contributors: seasonings and water-like liquids.
        if ["salt", "pepper", "spice", "herb", "parsley", "basil", "cinnamon",
            "water", "stock", "broth", "vinegar", "baking"].contains(where: { n.contains($0) }) {
            return NutritionProfile(calories: 5, protein: 0.3, carbs: 0.6, fat: 0.1)
        }
        // Generic fallback so every recipe still gets a number.
        return NutritionProfile(calories: 120, protein: 4, carbs: 12, fat: 5)
    }

    private static let table: [(keywords: [String], profile: NutritionProfile)] = [
        (["chicken", "turkey"], .init(calories: 165, protein: 31, carbs: 0, fat: 3.6)),
        (["bacon"], .init(calories: 541, protein: 37, carbs: 1.4, fat: 42)),
        (["beef", "steak", "mince"], .init(calories: 250, protein: 26, carbs: 0, fat: 15)),
        (["pork", "sausage", "ham"], .init(calories: 242, protein: 27, carbs: 0, fat: 14)),
        (["lamb"], .init(calories: 294, protein: 25, carbs: 0, fat: 21)),
        (["salmon"], .init(calories: 208, protein: 20, carbs: 0, fat: 13)),
        (["tuna"], .init(calories: 132, protein: 28, carbs: 0, fat: 1)),
        (["shrimp", "prawn"], .init(calories: 99, protein: 24, carbs: 0.2, fat: 0.3)),
        (["fish", "cod", "haddock", "tilapia"], .init(calories: 105, protein: 23, carbs: 0, fat: 1)),
        (["egg"], .init(calories: 155, protein: 13, carbs: 1.1, fat: 11)),
        (["butter"], .init(calories: 717, protein: 0.9, carbs: 0.1, fat: 81)),
        (["oil"], .init(calories: 884, protein: 0, carbs: 0, fat: 100)),
        (["cream"], .init(calories: 340, protein: 2, carbs: 3, fat: 36)),
        (["cheese", "feta", "parmesan", "mozzarella", "cheddar"], .init(calories: 350, protein: 25, carbs: 2, fat: 28)),
        (["yogurt", "yoghurt"], .init(calories: 59, protein: 10, carbs: 3.6, fat: 0.4)),
        (["milk"], .init(calories: 42, protein: 3.4, carbs: 5, fat: 1)),
        (["rice"], .init(calories: 130, protein: 2.7, carbs: 28, fat: 0.3)),
        (["pasta", "spaghetti", "noodle", "macaroni"], .init(calories: 158, protein: 6, carbs: 31, fat: 1)),
        (["oat"], .init(calories: 389, protein: 17, carbs: 66, fat: 7)),
        (["bread", "flour", "breadcrumb"], .init(calories: 265, protein: 9, carbs: 49, fat: 3.2)),
        (["potato"], .init(calories: 77, protein: 2, carbs: 17, fat: 0.1)),
        (["sugar"], .init(calories: 387, protein: 0, carbs: 100, fat: 0)),
        (["honey", "syrup"], .init(calories: 304, protein: 0.3, carbs: 82, fat: 0)),
        (["banana"], .init(calories: 89, protein: 1.1, carbs: 23, fat: 0.3)),
        (["apple"], .init(calories: 52, protein: 0.3, carbs: 14, fat: 0.2)),
        (["berry", "berries"], .init(calories: 57, protein: 0.7, carbs: 14, fat: 0.3)),
        (["tomato"], .init(calories: 18, protein: 0.9, carbs: 3.9, fat: 0.2)),
        (["onion"], .init(calories: 40, protein: 1.1, carbs: 9, fat: 0.1)),
        (["garlic"], .init(calories: 149, protein: 6, carbs: 33, fat: 0.5)),
        (["broccoli"], .init(calories: 34, protein: 2.8, carbs: 7, fat: 0.4)),
        (["carrot"], .init(calories: 41, protein: 0.9, carbs: 10, fat: 0.2)),
        (["spinach", "kale", "lettuce"], .init(calories: 23, protein: 2.9, carbs: 3.6, fat: 0.4)),
        (["pepper", "capsicum"], .init(calories: 20, protein: 0.9, carbs: 4.6, fat: 0.2)),
        (["mushroom"], .init(calories: 22, protein: 3.1, carbs: 3.3, fat: 0.3)),
        (["bean", "lentil", "chickpea"], .init(calories: 127, protein: 9, carbs: 22, fat: 0.5)),
        (["nut", "almond", "cashew", "peanut"], .init(calories: 579, protein: 21, carbs: 22, fat: 50)),
        (["chocolate", "cocoa"], .init(calories: 546, protein: 5, carbs: 61, fat: 31)),
        (["avocado"], .init(calories: 160, protein: 2, carbs: 9, fat: 15)),
        (["coconut"], .init(calories: 354, protein: 3.3, carbs: 15, fat: 33)),
        (["wine", "beer"], .init(calories: 83, protein: 0.1, carbs: 2.6, fat: 0))
    ]

    /// Approximate weight of one whole item, by keyword. Expects `name` already
    /// lowercased.
    private static func perItemGrams(for name: String) -> Double {
        // Seeds, spices, and garnishes — frequently listed with no real
        // quantity (e.g. "Garnish", "To serve"), so keep their weight tiny.
        let small = ["sesame", "seed", "salt", "peppercorn", "spice", "powder",
                     "cinnamon", "cumin", "paprika", "nutmeg", "oregano",
                     "thyme", "herb", "garnish", "zest"]
        if small.contains(where: { name.contains($0) }) { return 5 }

        let weights: [(String, Double)] = [
            ("garlic", 5), ("clove", 5), ("egg", 50), ("banana", 120),
            ("apple", 180), ("shallot", 40), ("onion", 110), ("potato", 170),
            ("tomato", 120), ("carrot", 60), ("lemon", 60), ("lime", 60),
            ("scallion", 15), ("spring onion", 15), ("chicken", 170), ("slice", 25)
        ]
        for (keyword, grams) in weights where name.contains(keyword) { return grams }
        if name.contains("bell pepper") || name.contains("capsicum") { return 120 }
        // Unknown countable: assume a modest amount, not a full 100 g.
        return 25
    }
}

/// Per-100g nutrition: kcal, protein g, carbs g, fat g.
struct NutritionProfile {
    var calories: Double
    var protein: Double
    var carbs: Double
    var fat: Double
}

// MARK: - Recipe nutrition

extension Recipe {
    /// True when the recipe carries real, stored nutrition values.
    var hasStoredNutrition: Bool {
        calories > 0 || protein > 0 || carbs > 0 || fat > 0
    }

    /// Nutrition to display: stored values when present, otherwise an estimate
    /// derived from the ingredients.
    var nutrition: NutritionInfo {
        if hasStoredNutrition {
            return NutritionInfo(calories: calories, protein: protein, carbs: carbs, fat: fat)
        }
        return NutritionEstimator.estimate(for: ingredients)
    }

    /// True when `nutrition` is an approximation rather than stored data.
    var isNutritionEstimated: Bool {
        !hasStoredNutrition && !ingredients.isEmpty
    }
}
