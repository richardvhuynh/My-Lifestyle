import SwiftUI
import PhotosUI
import Amplify

/// Community board where members share recipes they've made — with a photo and
/// caption — can like, comment on, and manage their own posts. Posts and comments
/// are stored in the cloud so the feed is shared across all users.
/// Identifies a member whose profile is being viewed, for `sheet(item:)`.
private struct MemberRef: Identifiable, Hashable {
    let name: String
    let userId: String?
    /// The member's avatar, supplied for the current user's own posts (profiles
    /// aren't synced across users, so this is only known for yourself).
    let imageData: Data?
    var id: String { userId ?? name }
}

struct CommunityView: View {
    @State private var posts: [CommunityPost] = []
    @State private var isLoading = true
    @State private var loadFailed = false
    @State private var showingComposer = false
    @State private var editingPost: CommunityPost?
    @State private var commentingPost: CommunityPost?
    @State private var postToDelete: CommunityPost?
    @State private var selectedMember: MemberRef?
    @State private var errorMessage: String?
    /// The signed-in (or guest) user's stable id + display name, resolved on appear
    /// so their own posts link to their real shared fitness profile.
    @State private var currentUserId: String?
    @State private var currentUsername = "You"

    // Local profile — used to show the user's current name and photo on their own
    // posts even if they changed it after posting. Stored on-device (AppStorage).
    @AppStorage("profileName") private var profileName = ""
    @AppStorage("profileImageData") private var profileImageData: Data?

    /// The name shown for the current user: their chosen profile name, else their
    /// account username.
    private var myDisplayName: String {
        let trimmed = profileName.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? currentUsername : trimmed
    }

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
                                let isOwn = post.authorId != nil && post.authorId == currentUserId
                                PostCard(
                                    post: $post,
                                    isOwn: isOwn,
                                    overrideName: isOwn ? myDisplayName : nil,
                                    overrideImageData: isOwn ? profileImageData : nil,
                                    onOpenProfile: {
                                        if isOwn {
                                            selectedMember = MemberRef(name: myDisplayName, userId: post.authorId, imageData: profileImageData)
                                        } else {
                                            selectedMember = MemberRef(name: post.author, userId: post.authorId, imageData: nil)
                                        }
                                    },
                                    onLikeChanged: { persistLike($0) },
                                    onOpenComments: { commentingPost = post },
                                    onEdit: { editingPost = post },
                                    onDelete: { postToDelete = post }
                                )
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
                currentUsername = user.username
            }
            // Ensure each accepted friend can read our fitness profile (both sides
            // reconcile, so mutual visibility converges once both open the app).
            try? await FriendshipService.reconcileViewers()
            await load()
        }
        .sheet(isPresented: $showingComposer) {
            ComposePostView { newPost in
                submit(newPost)
            }
        }
        .sheet(item: $editingPost) { post in
            ComposePostView(existing: post) { updated in
                updatePost(updated)
            }
        }
        .sheet(item: $commentingPost) { post in
            CommentsView(
                post: post,
                currentUserId: currentUserId,
                myName: myDisplayName,
                onCountChanged: { count in
                    if let index = posts.firstIndex(where: { $0.id == post.id }) {
                        posts[index].commentCount = count
                    }
                }
            )
        }
        .sheet(item: $selectedMember) { member in
            UserProfileView(memberName: member.name, userId: member.userId, avatarImageData: member.imageData)
        }
        .alert("Delete post?", isPresented: Binding(
            get: { postToDelete != nil },
            set: { if !$0 { postToDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) { postToDelete = nil }
            Button("Delete", role: .destructive) {
                if let post = postToDelete { deletePost(post) }
                postToDelete = nil
            }
        } message: {
            Text("This permanently removes your post.")
        }
        .alert("Something went wrong", isPresented: Binding(
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
    private func submit(_ newPost: CommunityPost) {
        var post = newPost
        post.author = myDisplayName
        post.authorId = currentUserId
        withAnimation(.easeInOut(duration: 0.25)) {
            posts.insert(post, at: 0)
        }
        Task {
            do {
                // Guarantee the post is stamped with the author's identity so it can
                // be recognized as "mine" (edit/delete, profile override) on reload.
                if post.authorId == nil {
                    post.authorId = await FitnessCloudService.currentUserId()
                    currentUserId = post.authorId
                    if let index = posts.firstIndex(where: { $0.id == post.id }) {
                        posts[index].authorId = post.authorId
                    }
                }
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

    /// Optimistically applies an edit, then persists it. Preserves like/comment
    /// counts since the update response doesn't carry them.
    private func updatePost(_ post: CommunityPost) {
        if let index = posts.firstIndex(where: { $0.id == post.id }) {
            posts[index] = post
        }
        Task {
            do {
                var saved = try await CommunityCloudService.update(post)
                saved.likeCount = post.likeCount
                saved.isLiked = post.isLiked
                saved.commentCount = post.commentCount
                if let index = posts.firstIndex(where: { $0.id == post.id }) {
                    posts[index] = saved
                }
            } catch {
                errorMessage = "Couldn't update: \(error.localizedDescription)"
                await load()
            }
        }
    }

    /// Optimistically removes the post, restoring it if the delete fails.
    private func deletePost(_ post: CommunityPost) {
        guard let cloudId = post.cloudId else {
            posts.removeAll { $0.id == post.id }
            return
        }
        let backup = posts
        withAnimation(.easeInOut(duration: 0.25)) {
            posts.removeAll { $0.id == post.id }
        }
        Task {
            do {
                try await CommunityCloudService.delete(postId: cloudId)
            } catch {
                posts = backup
                errorMessage = "Couldn't delete: \(error.localizedDescription)"
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

/// Two-letter initials for an author name, used in avatar placeholders.
private func authorInitials(_ name: String) -> String {
    let parts = name.split(separator: " ")
    let letters = parts.prefix(2).compactMap { $0.first }
    return String(letters).uppercased()
}

/// Circular avatar: the member's photo when available, else their initials.
private struct AuthorAvatar: View {
    var name: String
    var imageData: Data?
    var size: CGFloat = 40

    var body: some View {
        if let imageData, let uiImage = UIImage(data: imageData) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
        } else {
            Circle()
                .fill(Theme.accentSoft)
                .frame(width: size, height: size)
                .overlay(
                    Text(authorInitials(name))
                        .font(.system(size: size * 0.37, weight: .bold))
                        .foregroundStyle(Theme.accentDark)
                )
        }
    }
}

// MARK: - Post card

private struct PostCard: View {
    @Binding var post: CommunityPost
    var isOwn: Bool
    /// When set (own posts), overrides the stored author name/photo with the user's
    /// current profile values.
    var overrideName: String?
    var overrideImageData: Data?
    var onOpenProfile: () -> Void
    var onLikeChanged: (CommunityPost) -> Void
    var onOpenComments: () -> Void
    var onEdit: () -> Void
    var onDelete: () -> Void

    private var displayedName: String { overrideName ?? post.author }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Author row — tap to view the member's fitness profile.
            HStack(spacing: 10) {
                Button {
                    onOpenProfile()
                } label: {
                    HStack(spacing: 10) {
                        AuthorAvatar(name: displayedName, imageData: overrideImageData)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(displayedName)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Theme.primaryText)
                            Text(post.date.formatted(.relative(presentation: .named)))
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.secondaryText)
                        }
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                if isOwn {
                    Menu {
                        Button {
                            onEdit()
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            onDelete()
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.secondaryText)
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                } else {
                    Button {
                        onOpenProfile()
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.secondaryText.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                }
            }

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

            // Like + comment actions
            HStack(spacing: 22) {
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

                Button {
                    onOpenComments()
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "bubble.right")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.secondaryText)
                        Text("\(post.commentCount)")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Theme.secondaryText)
                            .contentTransition(.numericText())
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .card(padding: 14)
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

// MARK: - Comments

private struct CommentsView: View {
    let post: CommunityPost
    let currentUserId: String?
    let myName: String
    var onCountChanged: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var comments: [CommunityComment] = []
    @State private var isLoading = true
    @State private var draft = ""
    @State private var isSending = false
    @FocusState private var fieldFocused: Bool

    var body: some View {
        ZStack(alignment: .top) {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Text("Comments")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
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
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 12)

                if isLoading {
                    Spacer()
                    ProgressView()
                    Spacer()
                } else if comments.isEmpty {
                    Spacer()
                    VStack(spacing: 10) {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(.system(size: 36))
                            .foregroundStyle(Theme.secondaryText)
                        Text("No comments yet — start the conversation.")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Theme.secondaryText)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 40)
                    Spacer()
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 14) {
                            ForEach(comments) { comment in
                                commentRow(comment)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                }

                inputBar
            }
        }
        .task {
            await loadComments()
        }
    }

    private func commentRow(_ comment: CommunityComment) -> some View {
        let isOwn = comment.authorId != nil && comment.authorId == currentUserId
        return HStack(alignment: .top, spacing: 10) {
            AuthorAvatar(name: comment.author, imageData: nil, size: 34)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(comment.author)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.primaryText)
                    Text(comment.date.formatted(.relative(presentation: .named)))
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.secondaryText)
                    Spacer(minLength: 0)
                    if isOwn {
                        Button(role: .destructive) {
                            delete(comment)
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Theme.danger)
                        }
                        .buttonStyle(.plain)
                    }
                }
                Text(comment.text)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 12)
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Add a comment…", text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(RoundedFieldStyle())
                .focused($fieldFocused)

            Button {
                send()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(canSend ? Theme.accent : Theme.secondaryText.opacity(0.5))
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Theme.surface.ignoresSafeArea(edges: .bottom))
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespaces).isEmpty && !isSending
    }

    private func loadComments() async {
        guard let cloudId = post.cloudId else {
            isLoading = false
            return
        }
        comments = (try? await CommunityCloudService.listComments(postId: cloudId)) ?? []
        onCountChanged(comments.count)
        isLoading = false
    }

    private func send() {
        guard let cloudId = post.cloudId else { return }
        let text = draft.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        isSending = true
        fieldFocused = false
        Task {
            do {
                let saved = try await CommunityCloudService.addComment(
                    postId: cloudId,
                    author: myName,
                    authorId: currentUserId,
                    text: text
                )
                withAnimation(.easeInOut(duration: 0.2)) {
                    comments.append(saved)
                }
                draft = ""
                onCountChanged(comments.count)
            } catch {
                // Keep the draft so the user can retry.
            }
            isSending = false
        }
    }

    private func delete(_ comment: CommunityComment) {
        withAnimation(.easeInOut(duration: 0.2)) {
            comments.removeAll { $0.id == comment.id }
        }
        onCountChanged(comments.count)
        Task { try? await CommunityCloudService.deleteComment(id: comment.id) }
    }
}

// MARK: - Composer

private struct ComposePostView: View {
    /// When editing, the post being changed; `nil` for a brand-new post.
    var existing: CommunityPost?
    var onSubmit: (CommunityPost) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var recipeName: String
    @State private var caption: String
    @State private var pickerItem: PhotosPickerItem?
    @State private var imageData: Data?

    init(existing: CommunityPost? = nil, onSubmit: @escaping (CommunityPost) -> Void) {
        self.existing = existing
        self.onSubmit = onSubmit
        _recipeName = State(initialValue: existing?.recipeName ?? "")
        _caption = State(initialValue: existing?.caption ?? "")
        _imageData = State(initialValue: existing?.imageData)
    }

    private var isEditing: Bool { existing != nil }

    private var canPost: Bool {
        !recipeName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        ZStack(alignment: .top) {
            Theme.background.ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Text(isEditing ? "Edit post" : "Share a dish")
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

                    Button(isEditing ? "Save changes" : "Post") {
                        submit()
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

    private func submit() {
        let name = recipeName.trimmingCharacters(in: .whitespaces)
        let text = caption.trimmingCharacters(in: .whitespaces)
        if var post = existing {
            post.recipeName = name
            post.caption = text
            post.imageData = imageData
            onSubmit(post)
        } else {
            onSubmit(CommunityPost(
                author: "You",
                recipeName: name,
                caption: text,
                imageData: imageData
            ))
        }
    }
}

#Preview {
    CommunityView()
}
