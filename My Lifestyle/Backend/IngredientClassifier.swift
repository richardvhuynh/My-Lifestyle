import Foundation

/// Decides an ingredient's unit and amount.
///
/// TheMealDB's measure text is messy and often has no real unit ("Garnish",
/// "1 chopped", "To serve"). When the parser finds an explicit unit we honor it;
/// otherwise we infer a sensible unit **from the ingredient itself** so items
/// read naturally and convert to grams correctly for nutrition:
/// sauces/condiments → tbsp, spices/seeds → tsp, oils → tbsp (cups when stated),
/// liquids → ml, cheese/deli/meat/fish → grams, produce → whole.
enum IngredientClassifier {

    static func resolve(
        name: String,
        parsedAmount: Double?,
        parsedUnit: MeasurementUnit?
    ) -> (amount: Double, unit: MeasurementUnit) {
        // A real unit from the recipe text always wins (e.g. "240g", "2 cups").
        if let unit = parsedUnit {
            return (parsedAmount ?? 1, unit)
        }
        let (unit, fallbackAmount) = category(for: name)
        // For an inferred weight item, a bare number is a piece count ("4 bacon"
        // = 4 rashers, not 4 g) that can't be converted reliably — use a
        // standard portion instead. Counts and spoons keep the parsed number.
        if unit.dimension == .mass {
            return (fallbackAmount, unit)
        }
        return (parsedAmount ?? fallbackAmount, unit)
    }

    /// Maps an ingredient name to a (unit, default amount) when the recipe text
    /// gave no unit. Ordered so distinctive categories win (oils before spices
    /// so "sesame oil" ≠ "sesame seed"; sauces/pastes before produce so "tomato
    /// paste" ≠ "tomato").
    private static func category(for rawName: String) -> (MeasurementUnit, Double) {
        let n = rawName.lowercased().trimmingCharacters(in: .whitespaces)
        func has(_ keywords: [String]) -> Bool { keywords.contains { n.contains($0) } }

        // Oils & fats → tablespoons (explicit "cups" is honored upstream).
        if has(["oil", "ghee"]) { return (.tablespoons, 2) }

        // Spices, seeds & leavening → teaspoons.
        if n == "pepper" || has([
            "salt", "peppercorn", "black pepper", "white pepper", "ground pepper",
            "cayenne", "sesame", "seed", "spice", "cinnamon", "cumin", "paprika",
            "nutmeg", "oregano", "thyme", "turmeric", "vanilla", "cardamom",
            "curry powder", "chilli powder", "chili powder", "chilli flake",
            "chili flake", "baking powder", "baking soda"
        ]) { return (.teaspoons, 1) }

        // Condiments, sauces & pastes → tablespoons.
        if has([
            "sauce", "ketchup", "mustard", "mayo", "dressing", "soy", "sriracha",
            "salsa", "gravy", "pesto", "hoisin", "worcester", "honey", "syrup",
            "jam", "marmalade", "paste", "vinegar", "tahini", "harissa", "oyster",
            "ketjap"
        ]) { return (.tablespoons, 2) }

        // Liquids → millilitres.
        if has([
            "water", "milk", "cream", "stock", "broth", "juice", "wine", "beer",
            "buttermilk", "coconut milk", "passata", "coffee", "espresso"
        ]) { return (.milliliters, 100) }

        // Cheese & deli meats → grams.
        if has([
            "cheese", "mozzarella", "feta", "parmesan", "cheddar", "ricotta",
            "halloumi", "paneer", "ham", "bacon", "prosciutto", "salami",
            "pepperoni", "chorizo", "butter"
        ]) { return (.grams, 60) }

        // Meat & fish → grams.
        if has([
            "chicken", "beef", "pork", "lamb", "turkey", "duck", "veal",
            "sausage", "mince", "steak", "salmon", "tuna", "cod", "haddock",
            "tilapia", "fish", "shrimp", "prawn", "mackerel", "anchovy"
        ]) { return (.grams, 200) }

        // Dry goods & grains → grams.
        if has([
            "flour", "sugar", "rice", "oat", "cornstarch", "cornflour", "cocoa",
            "breadcrumb", "semolina", "polenta", "couscous", "lentil", "chickpea",
            "pasta", "noodle", "spaghetti", "macaroni", "bean"
        ]) { return (.grams, 100) }

        // Countable produce → whole.
        if has([
            "bell pepper", "red pepper", "green pepper", "yellow pepper",
            "capsicum", "chilli", "chili pepper", "jalapeno", "onion", "garlic",
            "egg", "apple", "banana", "lemon", "lime", "orange", "tomato",
            "potato", "carrot", "shallot", "avocado", "pear", "scallion",
            "spring onion", "cucumber", "courgette", "zucchini", "aubergine",
            "eggplant", "leek", "celery", "mushroom", "broccoli", "cauliflower",
            "cabbage", "lettuce", "plantain"
        ]) { return (.whole, 1) }

        // Unknown: a small amount in grams beats a misleading "1 whole".
        return (.grams, 30)
    }
}
