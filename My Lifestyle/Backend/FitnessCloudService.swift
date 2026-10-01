import Foundation
import Amplify

/// A member's shared fitness data, decoded from the cloud for display on their
/// profile. `weeklySteps` and `activities` are the same models the Fitness tab uses.
struct SharedFitness {
    var userId: String
    var displayName: String
    var weeklySteps: [DailySteps]
    var activities: [LoggedActivity]
    /// Owner-identity strings of the people allowed to read this profile (the
    /// owner's accepted friends). Managed by the friend-reconciliation path, not
    /// by fitness publishing.
    var viewers: [String]

    init(
        userId: String,
        displayName: String,
        weeklySteps: [DailySteps],
        activities: [LoggedActivity],
        viewers: [String] = []
    ) {
        self.userId = userId
        self.displayName = displayName
        self.weeklySteps = weeklySteps
        self.activities = activities
        self.viewers = viewers
    }
}

/// Read/write access to the `FitnessProfile` records through AppSync. The backend
/// authorizes with `allow.owner()` plus `allow.ownersDefinedIn('viewers')`, so a
/// member has full access to their own profile and can read a friend's only when
/// their identity is in that friend's `viewers` list (enforced server-side).
enum FitnessCloudService {

    /// Fetches a member's shared fitness profile, or nil if they haven't shared any
    /// (or the caller isn't authorized to read it — a non-friend gets nil/an error).
    static func fetch(userId: String) async throws -> SharedFitness? {
        let document = """
        query GetFitnessProfile($userId: String!) {
          getFitnessProfile(userId: $userId) {
            \(profileFields)
          }
        }
        """
        let request = GraphQLRequest<FitnessProfileRecord?>(
            document: document,
            variables: ["userId": userId],
            responseType: FitnessProfileRecord?.self,
            decodePath: "getFitnessProfile"
        )
        return try await run(request)?.toSharedFitness()
    }

    /// Creates or updates the current user's shared profile. Because `userId` is the
    /// primary key, we update when a record already exists and create otherwise.
    /// `viewers` is deliberately omitted from the write so routine fitness updates
    /// never clobber the friends-can-view list — that list is owned by `syncViewers`.
    static func publish(_ profile: SharedFitness) async throws {
        var input: [String: Any] = [
            "userId": profile.userId,
            "displayName": profile.displayName,
            "weeklySteps": encodeJSON(profile.weeklySteps) ?? "[]",
            "activities": encodeJSON(profile.activities) ?? "[]",
            "updatedAtEpoch": Date().timeIntervalSince1970
        ]
        let exists = (try? await fetch(userId: profile.userId)) != nil
        let mutation = exists ? "updateFitnessProfile" : "createFitnessProfile"
        let inputType = exists ? "UpdateFitnessProfileInput!" : "CreateFitnessProfileInput!"
        input["userId"] = profile.userId
        let document = """
        mutation Publish($input: \(inputType)) {
          \(mutation)(input: $input) {
            \(profileFields)
          }
        }
        """
        let request = GraphQLRequest<FitnessProfileRecord>(
            document: document,
            variables: ["input": input],
            responseType: FitnessProfileRecord.self,
            decodePath: mutation
        )
        _ = try await run(request, isMutation: true)
    }

    /// Ensures the current user's profile grants read access to every supplied
    /// friend identity. Called during friend reconciliation. Because a user can
    /// only edit their own profile, mutual visibility relies on both friends
    /// running this — each adds the other to their own `viewers`.
    static func syncViewers(_ friendIdentities: [String]) async throws {
        guard let myId = await IdentityService.currentIdentity() else { return }
        let existing = try? await fetch(userId: myId)
        let current = Set(existing?.viewers ?? [])
        let updated = current.union(friendIdentities)
        // Nothing new to grant and a profile already exists → no write needed.
        if existing != nil && updated == current { return }

        let exists = existing != nil
        let mutation = exists ? "updateFitnessProfile" : "createFitnessProfile"
        let inputType = exists ? "UpdateFitnessProfileInput!" : "CreateFitnessProfileInput!"
        var input: [String: Any] = [
            "userId": myId,
            "viewers": Array(updated)
        ]
        if !exists {
            // A shell profile so friends can be granted access before the member
            // has shared any steps/activities of their own.
            input["displayName"] = IdentityService.username(fromIdentity: myId)
            input["weeklySteps"] = "[]"
            input["activities"] = "[]"
            input["updatedAtEpoch"] = Date().timeIntervalSince1970
        }
        let document = """
        mutation SyncViewers($input: \(inputType)) {
          \(mutation)(input: $input) {
            \(profileFields)
          }
        }
        """
        let request = GraphQLRequest<FitnessProfileRecord>(
            document: document,
            variables: ["input": input],
            responseType: FitnessProfileRecord.self,
            decodePath: mutation
        )
        _ = try await run(request, isMutation: true)
    }

    /// The signed-in user's stable owner-identity (`sub::username`), used as the
    /// `FitnessProfile` key and as the author id stamped on Community posts. Returns
    /// nil when no user is signed in (the app is sign-in gated, so this is rare).
    static func currentUserId() async -> String? {
        await IdentityService.currentIdentity()
    }

    // MARK: - Private

    private static let profileFields = """
    userId
    displayName
    weeklySteps
    activities
    updatedAtEpoch
    viewers
    """

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

// MARK: - GraphQL payload

/// Mirrors the `FitnessProfile` model in `amplify/data/resource.ts`.
private struct FitnessProfileRecord: Decodable {
    let userId: String
    var displayName: String?
    var weeklySteps: String?
    var activities: String?
    var viewers: [String]?

    func toSharedFitness() -> SharedFitness {
        SharedFitness(
            userId: userId,
            displayName: displayName ?? "Member",
            weeklySteps: decodeJSON([DailySteps].self, from: weeklySteps) ?? [],
            activities: decodeJSON([LoggedActivity].self, from: activities) ?? [],
            viewers: viewers ?? []
        )
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
