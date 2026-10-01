import Foundation
import Amplify

/// One directional friend edge (I added them). A friendship is mutual only when
/// edges exist in both directions and neither is declined.
struct FriendEdge: Identifiable {
    let id: String
    /// Owner-identity of the edge's author.
    let fromId: String
    let fromName: String
    /// Email/username the edge points at.
    let toUsername: String
    /// Owner-identity of the target, when known.
    let toId: String?
    /// "active" or "declined".
    let status: String
}

/// A member surfaced in the Friends UI, resolved from the raw edges.
struct FriendSummary: Identifiable {
    /// The other member's owner-identity (when known) or username.
    let id: String
    let name: String
    /// Their owner-identity, needed to grant fitness access. Nil until they've
    /// created an edge back toward us.
    let identity: String?
}

/// Read/write access to `Friendship` edges. Everything a user writes they own
/// (`fromId`), so there are no cross-user updates. Sending a request and accepting
/// one are the same operation — creating an edge toward the other person; the link
/// becomes mutual once both edges exist.
enum FriendshipService {

    // MARK: - Reads

    /// People who added me but whom I haven't added back yet (pending incoming).
    static func incomingRequests() async throws -> [FriendSummary] {
        guard let myId = await IdentityService.currentIdentity(),
              let myName = await IdentityService.currentUsername() else { return [] }
        let edges = try await listAll()
        // People I've already added back (so they're no longer "pending incoming").
        let myOutgoingTargets = Set(
            edges.filter { $0.fromId == myId }.map { $0.toUsername.lowercased() }
        )
        return edges
            .filter { $0.toUsername.lowercased() == myName.lowercased() && $0.status == "active" }
            .filter { !myOutgoingTargets.contains($0.fromName.lowercased()) }
            .map { FriendSummary(id: $0.fromId, name: $0.fromName, identity: $0.fromId) }
    }

    /// My accepted (mutual) friends.
    static func friends() async throws -> [FriendSummary] {
        guard let myId = await IdentityService.currentIdentity(),
              let myName = await IdentityService.currentUsername() else { return [] }
        let edges = try await listAll()
        let myActiveOut = edges.filter { $0.fromId == myId && $0.status == "active" }
        var result: [FriendSummary] = []
        for out in myActiveOut {
            // Is there an active edge back toward me?
            let back = edges.first {
                $0.status == "active"
                    && $0.toUsername.lowercased() == myName.lowercased()
                    && $0.fromName.lowercased() == out.toUsername.lowercased()
            }
            if let back {
                result.append(FriendSummary(id: back.fromId, name: back.fromName, identity: back.fromId))
            }
        }
        return result
    }

    /// Owner-identities of my mutual friends, for granting fitness read access.
    static func acceptedFriendIdentities() async throws -> [String] {
        try await friends().compactMap { $0.identity }
    }

    /// Relationship between me and a member identified by username, for UI state.
    enum Relation { case none, outgoing, incoming, friends, selfUser }

    static func relation(withUsername username: String) async throws -> Relation {
        guard let myId = await IdentityService.currentIdentity(),
              let myName = await IdentityService.currentUsername() else { return .none }
        let target = username.lowercased()
        if target == myName.lowercased() { return .selfUser }
        let edges = try await listAll()
        let iAdded = edges.contains {
            $0.fromId == myId && $0.toUsername.lowercased() == target && $0.status == "active"
        }
        let theyAdded = edges.contains {
            $0.fromName.lowercased() == target
                && $0.toUsername.lowercased() == myName.lowercased()
                && $0.status == "active"
        }
        switch (iAdded, theyAdded) {
        case (true, true): return .friends
        case (true, false): return .outgoing
        case (false, true): return .incoming
        case (false, false): return .none
        }
    }

    // MARK: - Writes

    /// Creates an edge toward `username` (used both to request and to accept).
    static func addFriend(username: String, toId: String? = nil) async throws {
        guard let myId = await IdentityService.currentIdentity(),
              let myName = await IdentityService.currentUsername() else { return }
        let target = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !target.isEmpty, target != myName.lowercased() else { return }

        // Don't create a duplicate active edge toward the same person.
        let existing = try await listAll()
        if existing.contains(where: {
            $0.fromId == myId && $0.toUsername.lowercased() == target && $0.status == "active"
        }) { return }

        var input: [String: Any] = [
            "fromId": myId,
            "fromName": myName,
            "toUsername": target,
            "status": "active"
        ]
        if let toId { input["toId"] = toId }
        try await mutate(name: "createFriendship", inputType: "CreateFriendshipInput!", input: input)
        // Grant them read access to my fitness profile straight away.
        if let toId { try? await FitnessCloudService.syncViewers([toId]) }
    }

    /// Records a declined edge so the request stops showing as incoming and never
    /// becomes mutual.
    static func decline(username: String) async throws {
        guard let myId = await IdentityService.currentIdentity(),
              let myName = await IdentityService.currentUsername() else { return }
        let input: [String: Any] = [
            "fromId": myId,
            "fromName": myName,
            "toUsername": username.lowercased(),
            "status": "declined"
        ]
        try await mutate(name: "createFriendship", inputType: "CreateFriendshipInput!", input: input)
    }

    /// Reconciles my fitness `viewers` with my mutual friends. Call on launch / when
    /// social surfaces appear so both sides of each friendship eventually grant each
    /// other read access.
    static func reconcileViewers() async throws {
        let ids = try await acceptedFriendIdentities()
        if !ids.isEmpty { try await FitnessCloudService.syncViewers(ids) }
    }

    // MARK: - Private

    private static let edgeFields = """
    id
    fromId
    fromName
    toUsername
    toId
    status
    """

    private static func listAll() async throws -> [FriendEdge] {
        var edges: [FriendEdge] = []
        var nextToken: String?
        repeat {
            let page = try await listPage(nextToken: nextToken)
            edges.append(contentsOf: page.items.map { $0.toEdge() })
            nextToken = page.nextToken
        } while nextToken != nil
        return edges
    }

    private static func listPage(nextToken: String?) async throws -> FriendshipConnection {
        let document = """
        query ListFriendships($nextToken: String) {
          listFriendships(nextToken: $nextToken) {
            items {
              \(edgeFields)
            }
            nextToken
          }
        }
        """
        var variables: [String: Any] = [:]
        if let nextToken { variables["nextToken"] = nextToken }
        let request = GraphQLRequest<FriendshipConnection>(
            document: document,
            variables: variables.isEmpty ? nil : variables,
            responseType: FriendshipConnection.self,
            decodePath: "listFriendships"
        )
        return try await run(request)
    }

    private static func mutate(name: String, inputType: String, input: [String: Any]) async throws {
        let document = """
        mutation Friendship($input: \(inputType)) {
          \(name)(input: $input) {
            \(edgeFields)
          }
        }
        """
        let request = GraphQLRequest<FriendshipRecord>(
            document: document,
            variables: ["input": input],
            responseType: FriendshipRecord.self,
            decodePath: name
        )
        _ = try await run(request, isMutation: true)
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

private struct FriendshipConnection: Decodable {
    let items: [FriendshipRecord]
    let nextToken: String?
}

private struct FriendshipRecord: Decodable {
    let id: String
    var fromId: String?
    var fromName: String?
    var toUsername: String?
    var toId: String?
    var status: String?

    func toEdge() -> FriendEdge {
        FriendEdge(
            id: id,
            fromId: fromId ?? "",
            fromName: fromName ?? "",
            toUsername: toUsername ?? "",
            toId: toId,
            status: status ?? "active"
        )
    }
}
