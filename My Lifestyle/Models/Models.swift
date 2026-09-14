import Foundation

struct Recipe: Identifiable, Hashable {
    let id: UUID
    var name: String
    var imageName: String?
    var ingredients: [String]
    var steps: [RecipeStep]
    var calories: Int
    var protein: Double
    var carbs: Double
    var fat: Double

    init(id: UUID = UUID(), name: String, imageName: String? = nil, ingredients: [String], steps: [RecipeStep], calories: Int, protein: Double, carbs: Double, fat: Double) {
        self.id = id
        self.name = name
        self.imageName = imageName
        self.ingredients = ingredients
        self.steps = steps
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
    }
}

struct RecipeStep: Identifiable, Hashable {
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

struct PantryItem: Identifiable, Hashable {
    let id: UUID
    var name: String
    var quantity: String?

    init(id: UUID = UUID(), name: String, quantity: String? = nil) {
        self.id = id
        self.name = name
        self.quantity = quantity
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
