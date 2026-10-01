import Foundation
import UIKit
import Amplify

/// Read/write access to the shared `CommunityPost` feed through AppSync. Every
/// signed-in user reads the whole feed and can create a post; only a post's author
/// can edit or delete it. Likes are separate `CommunityLike` records owned by the
/// liker, so anyone can like any post without being able to modify it.
enum CommunityCloudService {

    /// Fetches the whole feed, newest first, with each post's like count and whether
    /// the current user has liked it (derived from `CommunityLike` records).
    static func list() async throws -> [CommunityPost] {
        var posts: [CommunityPost] = []
        var nextToken: String?
        repeat {
            let page = try await listPage(nextToken: nextToken)
            posts.append(contentsOf: page.items.map { $0.toPost() })
            nextToken = page.nextToken
        } while nextToken != nil

        let myId = await IdentityService.currentIdentity()
        let likes = (try? await listLikes()) ?? []
        let comments = (try? await listAllComments()) ?? []
        for index in posts.indices {
            guard let cloudId = posts[index].cloudId else { continue }
            let postLikes = likes.filter { $0.postId == cloudId }
            posts[index].likeCount = postLikes.count
            posts[index].isLiked = myId != nil && postLikes.contains { $0.liker == myId }
            posts[index].commentCount = comments.filter { $0.postId == cloudId }.count
        }
        return posts.sorted { $0.date > $1.date }
    }

    /// Persists a new post (compressing any attached photo) and returns it with its
    /// cloud id filled in.
    static func create(_ post: CommunityPost) async throws -> CommunityPost {
        var input: [String: Any] = [
            "author": post.author,
            "recipeName": post.recipeName,
            "caption": post.caption,
            "createdAtEpoch": post.date.timeIntervalSince1970
        ]
        input["authorId"] = post.authorId
        if let imageData = post.imageData {
            input["imageBase64"] = compressedBase64(from: imageData)
        }
        let document = """
        mutation CreateCommunityPost($input: CreateCommunityPostInput!) {
          createCommunityPost(input: $input) {
            \(postFields)
          }
        }
        """
        let request = GraphQLRequest<CommunityPostRecord>(
            document: document,
            variables: ["input": input],
            responseType: CommunityPostRecord.self,
            decodePath: "createCommunityPost"
        )
        return try await run(request, isMutation: true).toPost()
    }

    /// Updates an existing post's recipe name, caption, and (if a new photo was
    /// chosen) its image. Server-side owner auth ensures only the author succeeds.
    static func update(_ post: CommunityPost) async throws -> CommunityPost {
        guard let cloudId = post.cloudId else { throw ServiceError.missingCloudId }
        var input: [String: Any] = [
            "id": cloudId,
            "recipeName": post.recipeName,
            "caption": post.caption
        ]
        if let imageData = post.imageData {
            input["imageBase64"] = compressedBase64(from: imageData)
        }
        let document = """
        mutation UpdateCommunityPost($input: UpdateCommunityPostInput!) {
          updateCommunityPost(input: $input) {
            \(postFields)
          }
        }
        """
        let request = GraphQLRequest<CommunityPostRecord>(
            document: document,
            variables: ["input": input],
            responseType: CommunityPostRecord.self,
            decodePath: "updateCommunityPost"
        )
        return try await run(request, isMutation: true).toPost()
    }

    /// Deletes a post. Server-side owner auth ensures only the author succeeds.
    static func delete(postId cloudId: String) async throws {
        let document = """
        mutation DeleteCommunityPost($input: DeleteCommunityPostInput!) {
          deleteCommunityPost(input: $input) {
            id
          }
        }
        """
        let request = GraphQLRequest<LikeIdPayload>(
            document: document,
            variables: ["input": ["id": cloudId]],
            responseType: LikeIdPayload.self,
            decodePath: "deleteCommunityPost"
        )
        _ = try await run(request, isMutation: true)
    }

    // MARK: - Comments

    /// All comments on a single post, oldest first.
    static func listComments(postId: String) async throws -> [CommunityComment] {
        var comments: [CommunityComment] = []
        var nextToken: String?
        repeat {
            let page = try await listCommentsPage(postId: postId, nextToken: nextToken)
            comments.append(contentsOf: page.items.map { $0.toComment() })
            nextToken = page.nextToken
        } while nextToken != nil
        return comments.sorted { $0.date < $1.date }
    }

    /// Adds a comment to a post and returns it with its cloud id filled in.
    static func addComment(postId: String, author: String, authorId: String?, text: String) async throws -> CommunityComment {
        var input: [String: Any] = [
            "postId": postId,
            "author": author,
            "text": text,
            "createdAtEpoch": Date().timeIntervalSince1970
        ]
        input["authorId"] = authorId
        let document = """
        mutation CreateCommunityComment($input: CreateCommunityCommentInput!) {
          createCommunityComment(input: $input) {
            \(commentFields)
          }
        }
        """
        let request = GraphQLRequest<CommunityCommentRecord>(
            document: document,
            variables: ["input": input],
            responseType: CommunityCommentRecord.self,
            decodePath: "createCommunityComment"
        )
        return try await run(request, isMutation: true).toComment()
    }

    /// Deletes a comment. Server-side owner auth ensures only its author succeeds.
    static func deleteComment(id: String) async throws {
        let document = """
        mutation DeleteCommunityComment($input: DeleteCommunityCommentInput!) {
          deleteCommunityComment(input: $input) {
            id
          }
        }
        """
        let request = GraphQLRequest<LikeIdPayload>(
            document: document,
            variables: ["input": ["id": id]],
            responseType: LikeIdPayload.self,
            decodePath: "deleteCommunityComment"
        )
        _ = try await run(request, isMutation: true)
    }

    /// Likes a post by creating a `CommunityLike` owned by the current user. No-op
    /// if the user already likes it (avoids duplicate records).
    static func like(postId: String) async throws {
        let mine = try await myLikes(forPost: postId)
        guard mine.isEmpty else { return }
        var input: [String: Any] = ["postId": postId]
        input["userId"] = await IdentityService.currentIdentity()
        let document = """
        mutation CreateCommunityLike($input: CreateCommunityLikeInput!) {
          createCommunityLike(input: $input) {
            id
          }
        }
        """
        let request = GraphQLRequest<LikeIdPayload>(
            document: document,
            variables: ["input": input],
            responseType: LikeIdPayload.self,
            decodePath: "createCommunityLike"
        )
        _ = try await run(request, isMutation: true)
    }

    /// Removes the current user's like from a post by deleting their like record(s).
    static func unlike(postId: String) async throws {
        for like in try await myLikes(forPost: postId) {
            let document = """
            mutation DeleteCommunityLike($input: DeleteCommunityLikeInput!) {
              deleteCommunityLike(input: $input) {
                id
              }
            }
            """
            let request = GraphQLRequest<LikeIdPayload>(
                document: document,
                variables: ["input": ["id": like.id]],
                responseType: LikeIdPayload.self,
                decodePath: "deleteCommunityLike"
            )
            _ = try await run(request, isMutation: true)
        }
    }

    // MARK: - Private

    private enum ServiceError: Error { case missingCloudId }

    private static let postFields = """
    id
    author
    authorId
    recipeName
    caption
    imageBase64
    createdAtEpoch
    """

    private static let likeFields = """
    id
    postId
    userId
    owner
    """

    private static let commentFields = """
    id
    postId
    author
    authorId
    text
    createdAtEpoch
    """

    private static func listPage(nextToken: String?) async throws -> CommunityConnection {
        let document = """
        query ListCommunityPosts($nextToken: String) {
          listCommunityPosts(nextToken: $nextToken) {
            items {
              \(postFields)
            }
            nextToken
          }
        }
        """
        var variables: [String: Any] = [:]
        if let nextToken { variables["nextToken"] = nextToken }
        let request = GraphQLRequest<CommunityConnection>(
            document: document,
            variables: variables.isEmpty ? nil : variables,
            responseType: CommunityConnection.self,
            decodePath: "listCommunityPosts"
        )
        return try await run(request)
    }

    /// Fetches every like record (authenticated users may read all likes, which is
    /// how the feed totals counts and marks the current user's likes).
    private static func listLikes() async throws -> [CommunityLikeRecord] {
        var likes: [CommunityLikeRecord] = []
        var nextToken: String?
        repeat {
            let page = try await listLikesPage(nextToken: nextToken)
            likes.append(contentsOf: page.items)
            nextToken = page.nextToken
        } while nextToken != nil
        return likes
    }

    private static func listLikesPage(nextToken: String?) async throws -> CommunityLikeConnection {
        let document = """
        query ListCommunityLikes($nextToken: String) {
          listCommunityLikes(nextToken: $nextToken) {
            items {
              \(likeFields)
            }
            nextToken
          }
        }
        """
        var variables: [String: Any] = [:]
        if let nextToken { variables["nextToken"] = nextToken }
        let request = GraphQLRequest<CommunityLikeConnection>(
            document: document,
            variables: variables.isEmpty ? nil : variables,
            responseType: CommunityLikeConnection.self,
            decodePath: "listCommunityLikes"
        )
        return try await run(request)
    }

    /// Every comment across all posts, used to total per-post comment counts on
    /// the feed (mirrors how likes are totaled).
    private static func listAllComments() async throws -> [CommunityCommentRecord] {
        var comments: [CommunityCommentRecord] = []
        var nextToken: String?
        repeat {
            let page = try await listCommentsPage(postId: nil, nextToken: nextToken)
            comments.append(contentsOf: page.items)
            nextToken = page.nextToken
        } while nextToken != nil
        return comments
    }

    /// One page of comments, optionally filtered to a single post.
    private static func listCommentsPage(postId: String?, nextToken: String?) async throws -> CommunityCommentConnection {
        let document = """
        query ListCommunityComments($filter: ModelCommunityCommentFilterInput, $nextToken: String) {
          listCommunityComments(filter: $filter, nextToken: $nextToken) {
            items {
              \(commentFields)
            }
            nextToken
          }
        }
        """
        var variables: [String: Any] = [:]
        if let postId { variables["filter"] = ["postId": ["eq": postId]] }
        if let nextToken { variables["nextToken"] = nextToken }
        let request = GraphQLRequest<CommunityCommentConnection>(
            document: document,
            variables: variables.isEmpty ? nil : variables,
            responseType: CommunityCommentConnection.self,
            decodePath: "listCommunityComments"
        )
        return try await run(request)
    }

    /// The current user's like record(s) for a given post.
    private static func myLikes(forPost postId: String) async throws -> [CommunityLikeRecord] {
        guard let myId = await IdentityService.currentIdentity() else { return [] }
        return try await listLikes().filter { $0.postId == postId && $0.liker == myId }
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

    /// Downscales and JPEG-encodes a photo, then base64s it, iterating on dimension
    /// and quality until the JPEG is under `maxBytes` so the record stays well within
    /// the DynamoDB 400KB item limit (base64 inflates size ~33%). Returns nil if the
    /// photo can't be made small enough — the caller then posts without an image
    /// rather than failing the whole post.
    private static func compressedBase64(from data: Data) -> String? {
        guard let image = UIImage(data: data) else { return nil }
        let maxBytes = 260_000
        var dimension: CGFloat = 900
        while dimension >= 300 {
            let longEdge = max(image.size.width, image.size.height)
            let scale = min(1, dimension / longEdge)
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let renderer = UIGraphicsImageRenderer(size: size)
            let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
            for quality in [0.5, 0.4, 0.3] as [CGFloat] {
                if let jpeg = resized.jpegData(compressionQuality: quality), jpeg.count <= maxBytes {
                    return jpeg.base64EncodedString()
                }
            }
            dimension -= 200
        }
        return nil
    }
}

// MARK: - GraphQL payloads

private struct CommunityConnection: Decodable {
    let items: [CommunityPostRecord]
    let nextToken: String?
}

private struct CommunityLikeConnection: Decodable {
    let items: [CommunityLikeRecord]
    let nextToken: String?
}

private struct CommunityCommentConnection: Decodable {
    let items: [CommunityCommentRecord]
    let nextToken: String?
}

private struct CommunityCommentRecord: Decodable {
    let id: String
    var postId: String?
    var author: String?
    var authorId: String?
    var text: String?
    var createdAtEpoch: Double?

    func toComment() -> CommunityComment {
        CommunityComment(
            id: id,
            postId: postId ?? "",
            author: author ?? "Member",
            authorId: authorId,
            text: text ?? "",
            date: createdAtEpoch.map { Date(timeIntervalSince1970: $0) } ?? Date()
        )
    }
}

private struct CommunityLikeRecord: Decodable {
    let id: String
    let postId: String
    let userId: String?
    let owner: String?

    /// The liker's identity, preferring the explicit `userId` and falling back to
    /// the implicit `owner` for likes created before `userId` existed.
    var liker: String? { userId ?? owner }
}

private struct LikeIdPayload: Decodable {
    let id: String
}

/// Mirrors the `CommunityPost` model in `amplify/data/resource.ts`. `likeCount` and
/// `isLiked` are derived from `CommunityLike` records, not stored on the post.
private struct CommunityPostRecord: Decodable {
    let id: String
    var author: String?
    var authorId: String?
    var recipeName: String?
    var caption: String?
    var imageBase64: String?
    var createdAtEpoch: Double?

    func toPost() -> CommunityPost {
        CommunityPost(
            cloudId: id,
            author: author ?? "Member",
            authorId: authorId,
            recipeName: recipeName ?? "",
            caption: caption ?? "",
            imageData: imageBase64.flatMap { Data(base64Encoded: $0) },
            likeCount: 0,
            date: createdAtEpoch.map { Date(timeIntervalSince1970: $0) } ?? Date()
        )
    }
}
