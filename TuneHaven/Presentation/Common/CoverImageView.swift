import SwiftUI

struct CoverImageView: View {
    let path: String?
    let size: CGFloat
    var cornerRadius: CGFloat = 8

    @Environment(\.themePalette) private var palette
    @State private var cachedImage: UIImage?
    @State private var refreshToken = UUID()

    init(path: String?, size: CGFloat, cornerRadius: CGFloat = 8) {
        self.path = path
        self.size = size
        self.cornerRadius = cornerRadius
        _cachedImage = State(initialValue: path.flatMap { ImageCacheManager.shared.memoryImage(forKey: $0) })
    }

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
            if let memImg = ImageCacheManager.shared.memoryImage(forKey: path) {
                cachedImage = memImg
                return
            }
            let loaded = await Task.detached {
                await ImageCacheManager.shared.imageAsync(forKey: path)
            }.value
            cachedImage = loaded
        }
        .onReceive(NotificationCenter.default.publisher(for: .imageCacheDidUpdate)) { note in
            guard let updatedKey = note.userInfo?["key"] as? String,
                  updatedKey == path else { return }
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
