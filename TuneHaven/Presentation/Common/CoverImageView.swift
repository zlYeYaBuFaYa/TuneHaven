import SwiftUI

struct CoverImageView: View {
    let path: String?
    let size: CGFloat
    var cornerRadius: CGFloat = 8

    @Environment(\.themePalette) private var palette
    @State private var cachedImage: UIImage?

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
        .task(id: path) {
            guard let path else { cachedImage = nil; return }
            if let image = ImageCacheManager.shared.image(forKey: path) {
                cachedImage = image
            } else {
                let loaded = await Task.detached {
                    ImageCacheManager.shared.image(forKey: path)
                }.value
                cachedImage = loaded
            }
        }
    }
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
