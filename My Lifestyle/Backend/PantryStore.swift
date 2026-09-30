import Foundation

/// How much of a recipe ingredient the user's pantry already covers, used to
/// highlight what they have (and by how much) on the recipe screen.
enum IngredientAvailability: Equatable {
    /// No matching pantry item — the user still needs to get this.
    case missing
    /// A permanent staple (salt, oil, spices) the user always has on hand.
    case staple
    /// A tracked consumable with enough on hand to cover the recipe.
    case sufficient(have: Double, unit: MeasurementUnit)
    /// A tracked consumable, but short — carries both the amount on hand and
    /// the amount the recipe needs (in the pantry item's unit) so the UI can
    /// show "have X / need Y".
    case insufficient(have: Double, need: Double, unit: MeasurementUnit)

    /// Whether the pantry already fully covers this ingredient.
    var isSatisfied: Bool {
        switch self {
        case .staple, .sufficient: return true
        case .missing, .insufficient: return false
        }
    }
}

/// Shared, app-wide source of truth for the user's pantry. Injected into the
/// SwiftUI environment so the Pantry tab and the recipe cooking flow read and
/// mutate the same items — completing a recipe decrements the pantry here and
/// the change is reflected everywhere at once.
@MainActor
@Observable
final class PantryStore {
    var items: [PantryItem] = []

    func add(_ item: PantryItem) {
        items.append(item)
    }

    func remove(_ item: PantryItem) {
        items.removeAll { $0.id == item.id }
    }

    /// Sets a consumable item's remaining amount to an exact value.
    func updateAmount(_ item: PantryItem, to amount: Double) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].amount = amount
    }

    /// Reports how much of a recipe ingredient the pantry already covers, so
    /// the recipe screen can highlight what the user has and flag shortfalls.
    /// Matching mirrors `completeRecipe` (case-insensitive name match) so the
    /// highlight reflects exactly what completing the recipe would draw down.
    func availability(for ingredient: RecipeIngredient) -> IngredientAvailability {
        guard let item = items.first(where: {
            $0.name.lowercased() == ingredient.name.lowercased()
        }) else { return .missing }

        // Permanent staples aren't measured — the user is assumed to have them.
        guard item.kind == .consumable else { return .staple }

        // Express the required amount in the pantry item's own unit so the two
        // are directly comparable. If the units measure different dimensions
        // (e.g. the recipe asks for a volume but the pantry tracks mass) we
        // can't compare quantities, so just report that the user has it.
        guard let need = ingredient.unit.convert(ingredient.amount, to: item.unit) else {
            return .sufficient(have: item.amount, unit: item.unit)
        }

        if item.amount + 1e-9 >= need {
            return .sufficient(have: item.amount, unit: item.unit)
        }
        return .insufficient(have: item.amount, need: need, unit: item.unit)
    }

    /// Applies a completed recipe to the pantry: each ingredient decrements the
    /// matching consumable good by the recipe's required amount (converting
    /// units as needed). Permanent goods and unmatched ingredients are left
    /// untouched. Returns the names of the pantry items that were drawn down.
    @discardableResult
    func completeRecipe(_ recipe: Recipe) -> [String] {
        var updated: [String] = []
        for ingredient in recipe.ingredients {
            guard let index = items.firstIndex(where: {
                $0.name.lowercased() == ingredient.name.lowercased()
            }) else { continue }
            guard items[index].kind == .consumable else { continue }
            items[index].consume(ingredient.amount, unit: ingredient.unit)
            updated.append(items[index].name)
        }
        return updated
    }
}
