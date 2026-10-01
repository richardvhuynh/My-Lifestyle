import SwiftUI

/// Manage friends: add someone by email, respond to incoming requests, and see
/// current friends. Friendship is what unlocks viewing another member's fitness
/// (enforced server-side via each profile's `viewers` list).
struct FriendsView: View {
    @State private var incoming: [FriendSummary] = []
    @State private var friends: [FriendSummary] = []
    @State private var addEmail = ""
    @State private var isLoading = true
    @State private var isWorking = false
    @State private var message: String?

    var body: some View {
        ZStack(alignment: .top) {
            Theme.background.ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 20) {
                    addSection

                    if isLoading {
                        ProgressView().padding(.top, 20)
                    } else {
                        if !incoming.isEmpty { requestsSection }
                        friendsSection
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .refreshable { await load() }
        }
        .navigationTitle("Friends")
        .task { await load() }
    }

    // MARK: - Sections

    private var addSection: some View {
        SectionBox(title: "Add a friend") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    TextField("Friend's email", text: $addEmail)
                        .textFieldStyle(RoundedFieldStyle())
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()
                    Button("Add") { add() }
                        .buttonStyle(PrimaryButtonStyle(isEnabled: canAdd))
                        .disabled(!canAdd || isWorking)
                        .frame(width: 80)
                }
                if let message {
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.secondaryText)
                }
            }
        }
    }

    private var requestsSection: some View {
        SectionBox(title: "Requests") {
            VStack(spacing: 0) {
                ForEach(Array(incoming.enumerated()), id: \.element.id) { index, request in
                    if index > 0 { RowDivider() }
                    HStack(spacing: 12) {
                        avatar(for: request.name)
                        Text(request.name)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Theme.primaryText)
                            .lineLimit(1)
                        Spacer()
                        Button("Accept") { accept(request) }
                            .buttonStyle(PrimaryButtonStyle(isEnabled: !isWorking))
                            .fixedSize()
                            .disabled(isWorking)
                        Button {
                            decline(request)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Theme.secondaryText)
                                .frame(width: 32, height: 32)
                                .background(Circle().fill(Theme.surfaceAlt))
                        }
                        .buttonStyle(.plain)
                        .disabled(isWorking)
                    }
                    .padding(.vertical, 8)
                }
            }
        }
    }

    private var friendsSection: some View {
        SectionBox(title: "Friends") {
            if friends.isEmpty {
                Text("No friends yet. Add someone by email, or open a member from the Community feed.")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(friends.enumerated()), id: \.element.id) { index, friend in
                        if index > 0 { RowDivider() }
                        HStack(spacing: 12) {
                            avatar(for: friend.name)
                            Text(friend.name)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(Theme.primaryText)
                                .lineLimit(1)
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Theme.accent)
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
        }
    }

    private func avatar(for name: String) -> some View {
        Circle()
            .fill(Theme.accentSoft)
            .frame(width: 38, height: 38)
            .overlay(
                Text(initials(for: name))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.accentDark)
            )
    }

    // MARK: - Actions

    private var canAdd: Bool {
        addEmail.contains("@") && addEmail.contains(".")
    }

    private func add() {
        let email = addEmail
        isWorking = true
        message = nil
        Task {
            try? await FriendshipService.addFriend(username: email, toId: nil)
            addEmail = ""
            message = "Request sent to \(email)."
            await load()
            isWorking = false
        }
    }

    private func accept(_ request: FriendSummary) {
        isWorking = true
        Task {
            try? await FriendshipService.addFriend(username: request.name, toId: request.identity)
            await load()
            isWorking = false
        }
    }

    private func decline(_ request: FriendSummary) {
        isWorking = true
        Task {
            try? await FriendshipService.decline(username: request.name)
            await load()
            isWorking = false
        }
    }

    private func load() async {
        isLoading = true
        try? await FriendshipService.reconcileViewers()
        incoming = (try? await FriendshipService.incomingRequests()) ?? []
        friends = (try? await FriendshipService.friends()) ?? []
        isLoading = false
    }

    private func initials(for name: String) -> String {
        let base = name.split(separator: "@").first.map(String.init) ?? name
        let parts = base.split(whereSeparator: { "._ ".contains($0) })
        let letters = parts.prefix(2).compactMap { $0.first }
        return String(letters).uppercased()
    }
}

#Preview {
    NavigationStack { FriendsView() }
}
