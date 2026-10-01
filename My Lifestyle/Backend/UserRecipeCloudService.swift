import Foundation
import Amplify

/// Read/write access to a user's own private recipes (`UserRecipe`), authorized
/// with `allow.owner()` — list/create/delete only ever return or touch the signed-in
/// user's records, enforced server-side. Mirrors `RecipeCloudService`'s GraphQL
/// shape and reuses the app's `Recipe` model (minus the catalog-only `sourceId`).
enum UserRecipeCloudService {

    /// Fetches the signed-in user's own recipes (owner-filtered by AppSync).
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

    /// Persists a new private recipe and returns it with its cloud id filled in.
    @discardableResult
    static func create(_ recipe: Recipe) async throws -> Recipe {
        let document = """
        mutation CreateUserRecipe($input: CreateUserRecipeInput!) {
          createUserRecipe(input: $input) {
            \(recipeFields)
          }
        }
        """
        let request = GraphQLRequest<UserRecipeRecord>(
            document: document,
            variables: ["input": recipe.toUserRecipeInput()],
            responseType: UserRecipeRecord.self,
            decodePath: "createUserRecipe"
        )
        return try await run(request, isMutation: true).toRecipe() ?? recipe
    }

    /// Deletes one of the user's own recipes by its cloud id.
    static func delete(cloudId: String) async throws {
        let document = """
        mutation DeleteUserRecipe($input: DeleteUserRecipeInput!) {
          deleteUserRecipe(input: $input) {
            id
          }
        }
        """
        let request = GraphQLRequest<DeletePayload>(
            document: document,
            variables: ["input": ["id": cloudId]],
            responseType: DeletePayload.self,
            decodePath: "deleteUserRecipe"
        )
        _ = try await run(request, isMutation: true)
    }

    // MARK: - Private

    private static let recipeFields = """
    id
    name
    imageUrl
    category
    area
    servings
    calories
    protein
    carbs
    fat
    ingredients
    steps
    """

    private static func listPage(nextToken: String?) async throws -> UserRecipeConnection {
        let document = """
        query ListUserRecipes($nextToken: String) {
          listUserRecipes(nextToken: $nextToken) {
            items {
              \(recipeFields)
            }
            nextToken
          }
        }
        """
        var variables: [String: Any] = [:]
        if let nextToken { variables["nextToken"] = nextToken }
        let request = GraphQLRequest<UserRecipeConnection>(
            document: document,
            variables: variables.isEmpty ? nil : variables,
            responseType: UserRecipeConnection.self,
            decodePath: "listUserRecipes"
        )
        return try await run(request)
    }

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

private struct UserRecipeConnection: Decodable {
    let items: [UserRecipeRecord]
    let nextToken: String?
}

private struct DeletePayload: Decodable {
    let id: String
}

/// Mirrors the `UserRecipe` model in `amplify/data/resource.ts`.
private struct UserRecipeRecord: Decodable {
    let id: String
    var name: String?
    var imageUrl: String?
    var category: String?
    var area: String?
    var servings: Int?
    var calories: Int?
    var protein: Double?
    var carbs: Double?
    var fat: Double?
    var ingredients: String?
    var steps: String?

    func toRecipe() -> Recipe? {
        guard let name, !name.isEmpty else { return nil }
        return Recipe(
            cloudId: id,
            name: name,
            imageName: imageUrl,
            category: category,
            area: area,
            sourceId: nil,
            servings: max(1, servings ?? 1),
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
    /// Builds the `CreateUserRecipeInput` variable map, omitting nil fields and the
    /// catalog-only `sourceId`.
    func toUserRecipeInput() -> [String: Any] {
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
        input["servings"] = servings
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
