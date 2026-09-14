import Foundation

/// Mirrors the `Todo` model defined in `amplify/data/resource.ts`.
/// Decoded from the AppSync GraphQL responses.
struct Todo: Codable, Identifiable, Hashable {
    let id: String
    var content: String?
}

/// Wrapper for the `listTodos` connection payload (`{ items: [...] }`).
struct TodoList: Codable {
    let items: [Todo]
}
