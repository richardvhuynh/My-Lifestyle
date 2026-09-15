import Foundation

struct Recipe: Identifiable, Hashable {
    let id: UUID
    /// The cloud record id (AppSync/DynamoDB). `nil` for local seed recipes
    /// that haven't been persisted yet.
    var cloudId: String?
    var name: String
    var imageName: String?
    /// TheMealDB food category (e.g. "Seafood"), used as a browse axis.
    var category: String?
    /// TheMealDB cuisine/area (e.g. "Italian"), used as a browse axis.
    var area: String?
    /// TheMealDB meal id this recipe was imported from, used to de-duplicate
    /// imports. `nil` for hand-authored recipes.
    var sourceId: String?
    var ingredients: [RecipeIngredient]
    var steps: [RecipeStep]
    var calories: Int
    var protein: Double
    var carbs: Double
    var fat: Double

    init(id: UUID = UUID(), cloudId: String? = nil, name: String, imageName: String? = nil, category: String? = nil, area: String? = nil, sourceId: String? = nil, ingredients: [RecipeIngredient], steps: [RecipeStep], calories: Int, protein: Double, carbs: Double, fat: Double) {
        self.id = id
        self.cloudId = cloudId
        self.name = name
        self.imageName = imageName
        self.category = category
        self.area = area
        self.sourceId = sourceId
        self.ingredients = ingredients
        self.steps = steps
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
    }
}

/// One ingredient line in a recipe: what it is and how much of it the recipe
/// needs. The amount + unit is what the pantry decrements on completion.
struct RecipeIngredient: Identifiable, Hashable, Codable {
    let id: UUID
    var name: String
    var amount: Double
    var unit: MeasurementUnit

    init(id: UUID = UUID(), name: String, amount: Double, unit: MeasurementUnit) {
        self.id = id
        self.name = name
        self.amount = amount
        self.unit = unit
    }

    /// Display string for the required amount, e.g. "2 whole" or "100 g".
    var amountText: String { unit.formatted(amount) }
}

struct RecipeStep: Identifiable, Hashable, Codable {
    let id: UUID
    var order: Int
    var instruction: String
    var videoURL: String?

    init(id: UUID = UUID(), order: Int, instruction: String, videoURL: String? = nil) {
        self.id = id
        self.order = order
        self.instruction = instruction
        self.videoURL = videoURL
    }
}

// MARK: - Pantry

/// The physical dimension a unit measures. Conversions are only valid between
/// units that share a dimension (you can turn grams into ounces, but not into
/// milliliters).
enum UnitDimension {
    case mass
    case volume
    case count
}

/// A measurement unit for a pantry amount. Each unit knows its dimension and a
/// factor that converts it to that dimension's base unit (grams for mass,
/// milliliters for volume, pieces for count), which is all we need to convert
/// any two units of the same dimension.
enum MeasurementUnit: String, CaseIterable, Identifiable, Codable {
    // Mass
    case grams = "g"
    case kilograms = "kg"
    case ounces = "oz"
    case pounds = "lb"
    // Volume
    case milliliters = "ml"
    case liters = "L"
    case teaspoons = "tsp"
    case tablespoons = "tbsp"
    case cups = "cup"
    case fluidOunces = "fl oz"
    // Count
    case whole = "whole"
    case pieces = "pc"

    var id: String { rawValue }

    /// Human-readable label shown in the UI.
    var label: String { rawValue }

    var dimension: UnitDimension {
        switch self {
        case .grams, .kilograms, .ounces, .pounds:
            return .mass
        case .milliliters, .liters, .teaspoons, .tablespoons, .cups, .fluidOunces:
            return .volume
        case .whole, .pieces:
            return .count
        }
    }

    /// How many base units one of this unit represents.
    var perBaseUnit: Double {
        switch self {
        // Mass → grams
        case .grams: return 1
        case .kilograms: return 1000
        case .ounces: return 28.349523125
        case .pounds: return 453.59237
        // Volume → milliliters
        case .milliliters: return 1
        case .liters: return 1000
        case .teaspoons: return 4.92892159375
        case .tablespoons: return 14.78676478125
        case .cups: return 236.5882365
        case .fluidOunces: return 29.5735295625
        // Count → pieces (both "whole" and "pc" are one item)
        case .whole, .pieces: return 1
        }
    }

    /// Converts `amount` of this unit into `target`, or `nil` when the units
    /// measure different dimensions (e.g. mass → volume).
    func convert(_ amount: Double, to target: MeasurementUnit) -> Double? {
        guard dimension == target.dimension else { return nil }
        return amount * perBaseUnit / target.perBaseUnit
    }

    /// Formats an amount in this unit for display, trimming trailing ".0",
    /// e.g. `formatted(2)` → "2 whole", `formatted(1.5)` → "1.5 cup".
    func formatted(_ amount: Double) -> String {
        let rounded = (amount * 100).rounded() / 100
        let number = rounded == rounded.rounded()
            ? String(Int(rounded))
            : String(rounded)
        return "\(number) \(label)"
    }
}

/// How the pantry treats an item when a recipe using it is completed.
enum PantryItemKind: String, CaseIterable, Identifiable {
    /// Staples the user is assumed to always have (salt, oil, spices). The app
    /// never decrements these on recipe completion.
    case permanent = "Permanent"
    /// Tracked stock with a measured amount that is decremented as it is used.
    case consumable = "Consumable"

    var id: String { rawValue }
}

/// An item in the user's pantry: a name, an image, and — for consumables — a
/// measured amount that recipes draw down.
struct PantryItem: Identifiable, Hashable {
    let id: UUID
    var name: String
    var kind: PantryItemKind
    /// Remaining amount, expressed in `unit`. Ignored for permanent goods.
    var amount: Double
    var unit: MeasurementUnit
    /// A photo of the item, if the user supplied one.
    var imageData: Data?

    init(
        id: UUID = UUID(),
        name: String,
        kind: PantryItemKind = .consumable,
        amount: Double = 0,
        unit: MeasurementUnit = .grams,
        imageData: Data? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.amount = amount
        self.unit = unit
        self.imageData = imageData
    }

    /// A short display string for the amount, e.g. "100 g". Empty for
    /// permanent goods, which are not measured.
    var amountText: String {
        guard kind == .consumable else { return "" }
        return unit.formatted(amount)
    }

    /// Consumes `usedAmount` of `usedUnit` from this item, converting into the
    /// item's own unit. Permanent goods and mismatched dimensions are left
    /// untouched. The amount never drops below zero.
    mutating func consume(_ usedAmount: Double, unit usedUnit: MeasurementUnit) {
        guard kind == .consumable else { return }
        guard let inOwnUnit = usedUnit.convert(usedAmount, to: unit) else { return }
        amount = max(0, amount - inOwnUnit)
    }
}

enum MealType: String, CaseIterable, Identifiable {
    case breakfast = "Breakfast"
    case lunch = "Lunch"
    case dinner = "Dinner"
    case snack = "Snack"
    var id: String { rawValue }
}

struct DiaryEntry: Identifiable, Hashable {
    let id: UUID
    var mealType: MealType
    var title: String
    var calories: Int
    var date: Date

    init(id: UUID = UUID(), mealType: MealType, title: String, calories: Int, date: Date = Date()) {
        self.id = id
        self.mealType = mealType
        self.title = title
        self.calories = calories
        self.date = date
    }
}

/// A post on the Community board: a member sharing a recipe they made, with an
/// optional photo, that others can like.
struct CommunityPost: Identifiable, Hashable {
    let id: UUID
    var author: String
    var recipeName: String
    var caption: String
    /// Photo the poster attached (JPEG data). When `nil`, the card shows a
    /// generated gradient placeholder.
    var imageData: Data?
    var likeCount: Int
    var isLiked: Bool
    var date: Date

    init(
        id: UUID = UUID(),
        author: String,
        recipeName: String,
        caption: String,
        imageData: Data? = nil,
        likeCount: Int = 0,
        isLiked: Bool = false,
        date: Date = Date()
    ) {
        self.id = id
        self.author = author
        self.recipeName = recipeName
        self.caption = caption
        self.imageData = imageData
        self.likeCount = likeCount
        self.isLiked = isLiked
        self.date = date
    }
}
