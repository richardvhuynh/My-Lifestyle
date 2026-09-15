import Foundation

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
