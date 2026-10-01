import SwiftUI
import PhotosUI
import Amplify

/// Community board where members share recipes they've made — with a photo and
/// caption — and can like each other's posts. Posts are stored in the cloud
/// (`CommunityPost` in Amplify) so the feed is shared across all users.
/// Identifies a member whose profile is being viewed, for `sheet(item:)`.
private struct MemberRef: Identifiable, Hashable {
    let name: String
    let userId: String?
    var id: String { userId ?? name }
}

struct CommunityView: View {
    @State private var posts: [CommunityPost] = []
    @State private var isLoading = true
    @State private var loadFailed = false
    @State private var showingComposer = false
    @State private var selectedMember: MemberRef?
    @State private var errorMessage: String?
    /// The signed-in (or guest) user's stable id + display name, resolved on appear
    /// so their own posts link to their real shared fitness profile.
    @State private var currentUserId: String?
    @State private var currentDisplayName = "You"

    var body: some View {
        ZStack(alignment: .top) {
            Theme.background.ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 16) {
                    AppHeader(
                        title: "Community",
                        subtitle: subtitle,
                        trailingIcon: "square.and.pencil",
                        trailingAction: { showingComposer = true }
                    )

                    if isLoading {
                        ProgressView()
                            .padding(.top, 60)
                    } else if posts.isEmpty {
                        emptyState
                    } else {
                        LazyVStack(spacing: 16) {
                            ForEach($posts) { $post in
                                PostCard(post: $post, onOpenProfile: {
                                    selectedMember = MemberRef(name: post.author, userId: post.authorId)
                                }, onLikeChanged: { persistLike($0) })
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
                .padding(.bottom, 120)
            }
            .refreshable { await load() }
        }
        .task {
            currentUserId = await FitnessCloudService.currentUserId()
            if let user = try? await Amplify.Auth.getCurrentUser() {
                currentDisplayName = user.username
            }
            // Ensure each accepted friend can read our fitness profile (both sides
            // reconcile, so mutual visibility converges once both open the app).
            try? await FriendshipService.reconcileViewers()
            await load()
        }
        .sheet(isPresented: $showingComposer) {
            ComposePostView { newPost in
                var post = newPost
                post.author = currentDisplayName
                post.authorId = currentUserId
                submit(post)
            }
        }
        .sheet(item: $selectedMember) { member in
            UserProfileView(memberName: member.name, userId: member.userId)
        }
        .alert("Post failed", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var subtitle: String {
        isLoading ? "Loading…" : "\(posts.count) posts"
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: loadFailed ? "wifi.exclamationmark" : "square.on.square.dashed")
                .font(.system(size: 40))
                .foregroundStyle(Theme.secondaryText)
            Text(loadFailed ? "Couldn't load the feed." : "No posts yet — be the first to share a dish!")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
        .padding(.horizontal, 30)
    }

    // MARK: - Cloud actions

    private func load() async {
        loadFailed = false
        do {
            posts = try await CommunityCloudService.list()
        } catch {
            loadFailed = true
        }
        isLoading = false
    }

    /// Optimistically inserts the post, then creates it in the cloud and swaps in the
    /// saved copy (with its cloud id). If the save fails, removes it again and surfaces
    /// the reason rather than letting it vanish silently.
    private func submit(_ post: CommunityPost) {
        withAnimation(.easeInOut(duration: 0.25)) {
            posts.insert(post, at: 0)
        }
        Task {
            do {
                let saved = try await CommunityCloudService.create(post)
                if let index = posts.firstIndex(where: { $0.id == post.id }) {
                    posts[index] = saved
                }
            } catch {
                posts.removeAll { $0.id == post.id }
                errorMessage = "Couldn't post: \(error.localizedDescription)"
            }
        }
    }

    /// Reflects the user's like toggle into the cloud as a per-user like record,
    /// so liking never edits the post itself.
    private func persistLike(_ post: CommunityPost) {
        guard let cloudId = post.cloudId else { return }
        Task {
            if post.isLiked {
                try? await CommunityCloudService.like(postId: cloudId)
            } else {
                try? await CommunityCloudService.unlike(postId: cloudId)
            }
        }
    }
}

// MARK: - Post card

private struct PostCard: View {
    @Binding var post: CommunityPost
    var onOpenProfile: () -> Void
    var onLikeChanged: (CommunityPost) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Author row — tap to view the member's fitness profile.
            Button {
                onOpenProfile()
            } label: {
                HStack(spacing: 10) {
                    Circle()
                        .fill(Theme.accentSoft)
                        .frame(width: 40, height: 40)
                        .overlay(
                            Text(initials(for: post.author))
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(Theme.accentDark)
                        )
                    VStack(alignment: .leading, spacing: 1) {
                        Text(post.author)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.primaryText)
                        Text(post.date.formatted(.relative(presentation: .named)))
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.secondaryText)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.secondaryText.opacity(0.6))
                }
            }
            .buttonStyle(.plain)

            // Photo
            PostImage(imageData: post.imageData, seed: post.recipeName)
                .frame(height: 220)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(alignment: .bottomLeading) {
                    HStack(spacing: 6) {
                        Image(systemName: "fork.knife")
                            .font(.system(size: 11, weight: .bold))
                        Text(post.recipeName)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(.black.opacity(0.45)))
                    .padding(12)
                }

            if !post.caption.isEmpty {
                Text(post.caption)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Like button
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    post.isLiked.toggle()
                    post.likeCount += post.isLiked ? 1 : -1
                }
                onLikeChanged(post)
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: post.isLiked ? "heart.fill" : "heart")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(post.isLiked ? Theme.protein : Theme.secondaryText)
                        .scaleEffect(post.isLiked ? 1.1 : 1)
                    Text("\(post.likeCount)")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.secondaryText)
                        .contentTransition(.numericText())
                }
            }
            .buttonStyle(.plain)
        }
        .card(padding: 14)
    }

    private func initials(for name: String) -> String {
        let parts = name.split(separator: " ")
        let letters = parts.prefix(2).compactMap { $0.first }
        return String(letters).uppercased()
    }
}

/// Shows the poster's photo, or a deterministic gradient placeholder derived from
/// the recipe name when no photo was attached.
private struct PostImage: View {
    var imageData: Data?
    var seed: String

    var body: some View {
        if let imageData, let uiImage = UIImage(data: imageData) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
        } else {
            LinearGradient(
                colors: gradientColors(for: seed),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .overlay(
                Image(systemName: "photo")
                    .font(.system(size: 34))
                    .foregroundStyle(.white.opacity(0.7))
            )
        }
    }

    private func gradientColors(for seed: String) -> [Color] {
        let palettes: [[Color]] = [
            [Theme.accent, Theme.accentDark],
            [Theme.carb, Theme.protein],
            [Theme.fat, Theme.accent],
            [Color(red: 0.28, green: 0.52, blue: 1.0), Color(red: 0.9, green: 0.3, blue: 0.72)]
        ]
        let index = abs(seed.hashValue) % palettes.count
        return palettes[index]
    }
}

// MARK: - Composer

private struct ComposePostView: View {
    var onPost: (CommunityPost) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var recipeName = ""
    @State private var caption = ""
    @State private var pickerItem: PhotosPickerItem?
    @State private var imageData: Data?

    private var canPost: Bool {
        !recipeName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        ZStack(alignment: .top) {
            Theme.background.ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Text("Share a dish")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.primaryText)
                        Spacer()
                        Button { dismiss() } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(Theme.secondaryText)
                                .frame(width: 36, height: 36)
                                .background(Circle().fill(Theme.surface))
                        }
                        .buttonStyle(.plain)
                    }

                    // Photo picker
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        ZStack {
                            if let imageData, let uiImage = UIImage(data: imageData) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFill()
                            } else {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(Theme.surfaceAlt)
                                    .overlay(
                                        VStack(spacing: 8) {
                                            Image(systemName: "camera.fill")
                                                .font(.system(size: 26))
                                            Text("Add a photo")
                                                .font(.system(size: 14, weight: .medium))
                                        }
                                        .foregroundStyle(Theme.secondaryText)
                                    )
                            }
                        }
                        .frame(height: 200)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Recipe")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.secondaryText)
                        TextField("What did you make?", text: $recipeName)
                            .textFieldStyle(RoundedFieldStyle())
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Caption")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.secondaryText)
                        TextField("Say something about it…", text: $caption, axis: .vertical)
                            .lineLimit(3...6)
                            .textFieldStyle(RoundedFieldStyle())
                    }

                    Button("Post") {
                        let post = CommunityPost(
                            author: "You",
                            recipeName: recipeName.trimmingCharacters(in: .whitespaces),
                            caption: caption.trimmingCharacters(in: .whitespaces),
                            imageData: imageData
                        )
                        onPost(post)
                        dismiss()
                    }
                    .buttonStyle(PrimaryButtonStyle(isEnabled: canPost))
                    .disabled(!canPost)
                }
                .padding(20)
            }
        }
        .task(id: pickerItem) {
            if let pickerItem,
               let data = try? await pickerItem.loadTransferable(type: Data.self) {
                imageData = data
            }
        }
    }
}

#Preview {
    CommunityView()
}
