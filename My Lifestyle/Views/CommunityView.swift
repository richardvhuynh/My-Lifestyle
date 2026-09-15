import SwiftUI
import PhotosUI

/// Community board where members share recipes they've made — with a photo and
/// caption — and can like each other's posts. Posts are in-memory sample data
/// for now; wire to the Amplify backend later alongside recipes.
struct CommunityView: View {
    @State private var posts: [CommunityPost] = CommunityView.samplePosts
    @State private var showingComposer = false

    var body: some View {
        ZStack(alignment: .top) {
            Theme.background.ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 16) {
                    AppHeader(
                        title: "Community",
                        subtitle: "\(posts.count) posts",
                        trailingIcon: "square.and.pencil",
                        trailingAction: { showingComposer = true }
                    )

                    LazyVStack(spacing: 16) {
                        ForEach($posts) { $post in
                            PostCard(post: $post)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 120)
            }
        }
        .sheet(isPresented: $showingComposer) {
            ComposePostView { newPost in
                withAnimation(.easeInOut(duration: 0.25)) {
                    posts.insert(newPost, at: 0)
                }
            }
        }
    }
}

// MARK: - Post card

private struct PostCard: View {
    @Binding var post: CommunityPost

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Author row
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

            // Like button
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    post.isLiked.toggle()
                    post.likeCount += post.isLiked ? 1 : -1
                }
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

// MARK: - Sample data

private extension CommunityView {
    static let samplePosts: [CommunityPost] = [
        CommunityPost(
            author: "Maya Chen",
            recipeName: "Chicken & Broccoli Bowl",
            caption: "First time hitting my protein goal and actually enjoying it. The feta makes it 🔥",
            likeCount: 42,
            date: Date().addingTimeInterval(-3600)
        ),
        CommunityPost(
            author: "Diego Ramos",
            recipeName: "Oatmeal with Berries",
            caption: "Sunday breakfast reset. Prepped a batch for the whole week.",
            likeCount: 18,
            date: Date().addingTimeInterval(-3600 * 6)
        ),
        CommunityPost(
            author: "Priya Patel",
            recipeName: "Overnight Chia Pudding",
            caption: "Cleared out the pantry temp items with this one. Zero waste week!",
            likeCount: 63,
            date: Date().addingTimeInterval(-3600 * 26)
        )
    ]
}

#Preview {
    CommunityView()
}
