import SwiftUI

/// Minimal end-to-end demo of the AppSync `Todo` model: list, create, delete.
/// Works with guest credentials thanks to the `allow.guest()` rule.
struct TodoDemoView: View {
    @State private var todos: [Todo] = []
    @State private var newContent = ""
    @State private var errorMessage: String?
    @State private var isLoading = false

    var body: some View {
        List {
            Section {
                HStack {
                    TextField("New todo", text: $newContent)
                    Button("Add") {
                        Task { await add() }
                    }
                    .disabled(newContent.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section("Todos") {
                if todos.isEmpty && !isLoading {
                    Text("No todos yet — add one above.")
                        .foregroundStyle(.secondary)
                }
                ForEach(todos) { todo in
                    Text(todo.content ?? "(empty)")
                }
                .onDelete { indexSet in
                    Task { await delete(at: indexSet) }
                }
            }
        }
        .navigationTitle("Cloud Todos")
        .overlay {
            if isLoading { ProgressView() }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            todos = try await TodoService.list()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func add() async {
        let content = newContent.trimmingCharacters(in: .whitespaces)
        guard !content.isEmpty else { return }
        do {
            let todo = try await TodoService.create(content: content)
            todos.append(todo)
            newContent = ""
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete(at offsets: IndexSet) async {
        let toDelete = offsets.map { todos[$0] }
        for todo in toDelete {
            do {
                try await TodoService.delete(id: todo.id)
                todos.removeAll { $0.id == todo.id }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
