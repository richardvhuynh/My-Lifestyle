import Foundation
import Amplify

/// Read/write access to the shared `Recipe` catalog through the AppSync
/// GraphQL API. Like `TodoService`, the backend authorizes `Recipe` with
/// `allow.guest()` over the Cognito identity pool (AWS IAM), so every user —
/// signed in or not — reads and seeds the same global catalog.
enum RecipeCloudService {

    /// Fetches the entire shared catalog, following pagination to the end.
    static func list() async throws -> [Recipe] {
        var recipes: [Recipe] = []
        var nextToken: String?
        repeat {
            let page = try await listPage(nextToken: nextToken)
            recipes.append(contentsOf: page.items.compactMap { $0.toRecipe() })
            nextToken = page.nextToken
        } while nextToken != nil
        return recipes
    }

    /// Imports recipes from TheMealDB into the shared catalog, skipping any
    /// already present (matched by `sourceId`, then by name). Returns the count
    /// of newly added recipes.
    @discardableResult
    static func seedFromTheMealDB() async throws -> Int {
        let existing = try await list()
        let existingSourceIds = Set(existing.compactMap { $0.sourceId })
        let existingNames = Set(existing.map { $0.name.lowercased() })

        let fetched = await RecipeService.fetchRecipes()
        let newRecipes = fetched.filter { recipe in
            if let sourceId = recipe.sourceId, existingSourceIds.contains(sourceId) { return false }
            return !existingNames.contains(recipe.name.lowercased())
        }

        for recipe in newRecipes {
            try await create(recipe)
        }
        return newRecipes.count
    }

    /// Persists a single recipe via the generated `createRecipe` mutation.
    @discardableResult
    static func create(_ recipe: Recipe) async throws -> Recipe {
        let document = """
        mutation CreateRecipe($input: CreateRecipeInput!) {
          createRecipe(input: $input) {
            \(recipeFields)
          }
        }
        """
        let request = GraphQLRequest<RecipeRecord>(
            document: document,
            variables: ["input": recipe.toCreateInput()],
            responseType: RecipeRecord.self,
            decodePath: "createRecipe"
        )
        return try await run(request, isMutation: true).toRecipe() ?? recipe
    }

    // MARK: - Private

    /// Selection set shared by the list query and create mutation.
    private static let recipeFields = """
    id
    name
    imageUrl
    category
    area
    calories
    protein
    carbs
    fat
    ingredients
    steps
    sourceId
    """

    private static func listPage(nextToken: String?) async throws -> RecipeConnection {
        let document = """
        query ListRecipes($nextToken: String) {
          listRecipes(nextToken: $nextToken) {
            items {
              \(recipeFields)
            }
            nextToken
          }
        }
        """
        var variables: [String: Any] = [:]
        if let nextToken { variables["nextToken"] = nextToken }
        let request = GraphQLRequest<RecipeConnection>(
            document: document,
            variables: variables.isEmpty ? nil : variables,
            responseType: RecipeConnection.self,
            decodePath: "listRecipes"
        )
        return try await run(request)
    }

    /// Executes a request and unwraps the `GraphQLResult`, surfacing any
    /// GraphQL-level errors as a thrown error.
    private static func run<R: Decodable>(
        _ request: GraphQLRequest<R>,
        isMutation: Bool = false
    ) async throws -> R {
        let result = isMutation
            ? try await Amplify.API.mutate(request: request)
            : try await Amplify.API.query(request: request)
        switch result {
        case .success(let value):
            return value
        case .failure(let errors):
            throw errors
        }
    }
}

// MARK: - GraphQL payloads

/// Wrapper for the `listRecipes` connection payload.
private struct RecipeConnection: Decodable {
    let items: [RecipeRecord]
    let nextToken: String?
}

/// Mirrors the `Recipe` model in `amplify/data/resource.ts`. `ingredients` and
/// `steps` arrive as JSON-encoded strings and are decoded into the app's
/// structured models.
private struct RecipeRecord: Decodable {
    let id: String
    var name: String?
    var imageUrl: String?
    var category: String?
    var area: String?
    var calories: Int?
    var protein: Double?
    var carbs: Double?
    var fat: Double?
    var ingredients: String?
    var steps: String?
    var sourceId: String?

    func toRecipe() -> Recipe? {
        guard let name, !name.isEmpty else { return nil }
        return Recipe(
            cloudId: id,
            name: name,
            imageName: imageUrl,
            category: category,
            area: area,
            sourceId: sourceId,
            ingredients: decodeJSON([RecipeIngredient].self, from: ingredients) ?? [],
            steps: decodeJSON([RecipeStep].self, from: steps) ?? [],
            calories: calories ?? 0,
            protein: protein ?? 0,
            carbs: carbs ?? 0,
            fat: fat ?? 0
        )
    }
}

private extension Recipe {
    /// Builds the `CreateRecipeInput` variable map, omitting nil fields.
    func toCreateInput() -> [String: Any] {
        var input: [String: Any] = [
            "name": name,
            "calories": calories,
            "protein": protein,
            "carbs": carbs,
            "fat": fat
        ]
        input["imageUrl"] = imageName
        input["category"] = category
        input["area"] = area
        input["sourceId"] = sourceId
        input["ingredients"] = encodeJSON(ingredients)
        input["steps"] = encodeJSON(steps)
        return input
    }
}

// MARK: - JSON helpers

private func encodeJSON<T: Encodable>(_ value: T) -> String? {
    guard let data = try? JSONEncoder().encode(value) else { return nil }
    return String(data: data, encoding: .utf8)
}

private func decodeJSON<T: Decodable>(_ type: T.Type, from string: String?) -> T? {
    guard let string, let data = string.data(using: .utf8) else { return nil }
    return try? JSONDecoder().decode(type, from: data)
}
