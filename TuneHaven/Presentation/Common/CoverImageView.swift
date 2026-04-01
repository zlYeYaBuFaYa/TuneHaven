import Combine
import SwiftUI

struct CoverImageView: View {
    let path: String?
    let size: CGFloat
    var cornerRadius: CGFloat = 8

    @Environment(\.themePalette) private var palette
    @Environment(\.imageCache) private var imageCache
    @State private var cachedImage: UIImage?
    @State private var refreshToken = UUID()

    var body: some View {
        Group {
            if let cachedImage {
                Image(uiImage: cachedImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                PlaceholderCoverView(size: size, cornerRadius: cornerRadius)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .task(id: CoverLoadToken(path: path, refresh: refreshToken)) {
            guard let path else { cachedImage = nil; return }
            if let memImg = imageCache.memoryImage(forKey: path) {
                cachedImage = memImg
                return
            }
            let cache = imageCache
            let loaded = await Task.detached {
                await cache.imageAsync(forKey: path)
            }.value
            cachedImage = loaded
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .imageCacheDidUpdate)
                .compactMap { $0.userInfo?["key"] as? String }
                .filter { $0 == path }
        ) { _ in
            refreshToken = UUID()
        }
    }
}

private struct CoverLoadToken: Equatable {
    let path: String?
    let refresh: UUID
}

struct PlaceholderCoverView: View {
    let size: CGFloat
    var cornerRadius: CGFloat = 8
    @Environment(\.themePalette) private var palette

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(
                    LinearGradient(
                        colors: [palette.gradientStart.opacity(0.6), palette.gradientEnd.opacity(0.4)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Image(systemName: "music.note")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size * 0.35, height: size * 0.35)
                .foregroundColor(palette.iconSecondary)
        }
        .frame(width: size, height: size)
    }
}
