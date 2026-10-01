import Foundation
import Amplify

/// Resolves the signed-in user's identity in the exact form Cognito/AppSync uses
/// for owner-based authorization (`sub::username`). Owner rules (`allow.owner()`,
/// `allow.ownersDefinedIn(...)`) compare against this claim, so the client builds
/// the same string whenever it needs to reference a user across records — the
/// author of a post, the two sides of a friendship, or a viewer on a fitness
/// profile. Centralized here so the format lives in exactly one place.
enum IdentityService {

    /// The current user's owner-identity string (`sub::username`), or nil when no
    /// user is signed in. This is the value stored as `FitnessProfile.userId`,
    /// `CommunityPost.authorId`, `Friendship.requesterId/recipientId`, and in a
    /// profile's `viewers` list.
    static func currentIdentity() async -> String? {
        guard let user = try? await Amplify.Auth.getCurrentUser() else { return nil }
        return "\(user.userId)::\(user.username)"
    }

    /// The current user's Cognito username (their email, given this pool's config).
    /// Used as the human-addressable handle when sending a friend request and as a
    /// display fallback.
    static func currentUsername() async -> String? {
        guard let user = try? await Amplify.Auth.getCurrentUser() else { return nil }
        return user.username
    }

    /// Extracts the username portion from an owner-identity string, i.e. the text
    /// after `::`. Falls back to the whole string if it isn't in `sub::username`
    /// form (e.g. legacy records).
    static func username(fromIdentity identity: String) -> String {
        guard let range = identity.range(of: "::") else { return identity }
        return String(identity[range.upperBound...])
    }
}
