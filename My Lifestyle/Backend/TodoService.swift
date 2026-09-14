import Foundation
import Amplify

/// Read/write access to the `Todo` model through the AppSync GraphQL API.
///
/// The backend authorizes `Todo` with `allow.guest()` over the Cognito
/// identity pool (AWS IAM), so these calls work with unauthenticated
/// (guest) credentials — no sign-in required.
enum TodoService {

    /// Fetches all todos via the generated `listTodos` query.
    static func list() async throws -> [Todo] {
        let document = """
        query ListTodos {
          listTodos {
            items {
              id
              content
            }
          }
        }
        """
        let request = GraphQLRequest<TodoList>(
            document: document,
            responseType: TodoList.self,
            decodePath: "listTodos"
        )
        return try await run(request).items
    }

    /// Creates a new todo via the generated `createTodo` mutation.
    @discardableResult
    static func create(content: String) async throws -> Todo {
        let document = """
        mutation CreateTodo($input: CreateTodoInput!) {
          createTodo(input: $input) {
            id
            content
          }
        }
        """
        let request = GraphQLRequest<Todo>(
            document: document,
            variables: ["input": ["content": content]],
            responseType: Todo.self,
            decodePath: "createTodo"
        )
        return try await run(request, isMutation: true)
    }

    /// Deletes a todo via the generated `deleteTodo` mutation.
    @discardableResult
    static func delete(id: String) async throws -> Todo {
        let document = """
        mutation DeleteTodo($input: DeleteTodoInput!) {
          deleteTodo(input: $input) {
            id
            content
          }
        }
        """
        let request = GraphQLRequest<Todo>(
            document: document,
            variables: ["input": ["id": id]],
            responseType: Todo.self,
            decodePath: "deleteTodo"
        )
        return try await run(request, isMutation: true)
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
