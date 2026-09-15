import SwiftUI

/// In-memory store of decoded images so cells recycled by `LazyVGrid` show
/// instantly instead of re-fetching (which caused the flicker when scrolling
/// back). Backed further by `URLCache` on disk for instant loads across
/// launches. `NSCache` is thread-safe.
final class ImageCache {
    static let shared = ImageCache()
    private let cache = NSCache<NSURL, UIImage>()

    func image(for url: URL) -> UIImage? { cache.object(forKey: url as NSURL) }
    func insert(_ image: UIImage, for url: URL) { cache.setObject(image, forKey: url as NSURL) }
}

/// A drop-in async image that fills its frame, caching results in memory and on
/// disk so a given URL only ever downloads once. Shows `placeholder` until the
/// image is ready.
struct CachedImage<Placeholder: View>: View {
    let url: URL?
    @ViewBuilder var placeholder: () -> Placeholder

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder()
            }
        }
        .task(id: url) { await load() }
    }

    private func load() async {
        guard let url else { return }
        if let cached = ImageCache.shared.image(for: url) {
            image = cached
            return
        }
        var request = URLRequest(url: url)
        request.cachePolicy = .returnCacheDataElseLoad
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let loaded = UIImage(data: data) else { return }
        ImageCache.shared.insert(loaded, for: url)
        image = loaded
    }
}
