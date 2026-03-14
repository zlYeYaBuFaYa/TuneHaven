import SwiftUI

struct CoverImageView: View {
    let path: String?
    let size: CGFloat
    var cornerRadius: CGFloat = 8

    @Environment(\.themePalette) private var palette

    var body: some View {
        Group {
            if let path, let image = ImageCacheManager.shared.image(forKey: path) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                PlaceholderCoverView(size: size)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

struct PlaceholderCoverView: View {
    let size: CGFloat
    @Environment(\.themePalette) private var palette

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(palette.surfaceSecondary)
            Image(systemName: "music.note")
                .font(.system(size: size * 0.35))
                .foregroundColor(palette.iconSecondary)
        }
        .frame(width: size, height: size)
    }
}
