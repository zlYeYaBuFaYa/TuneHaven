import UIKit

enum ThumbnailSize: String {
    case small = "small"
    case medium = "medium"
    case large = "large"
    case original = "original"

    var suffix: String { rawValue }

    var dimension: CGFloat {
        switch self {
        case .small: return 100
        case .medium: return 200
        case .large: return 400
        case .original: return 1024
        }
    }
}

final class ThumbnailGenerator {
    static func resize(_ image: UIImage, to size: ThumbnailSize) -> UIImage {
        let dim = size.dimension
        let targetSize = CGSize(width: dim, height: dim)
        if image.size.width <= dim && image.size.height <= dim { return image }
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            let scale = max(dim / image.size.width, dim / image.size.height)
            let scaledW = image.size.width * scale
            let scaledH = image.size.height * scale
            let drawRect = CGRect(x: (dim - scaledW) / 2, y: (dim - scaledH) / 2, width: scaledW, height: scaledH)
            image.draw(in: drawRect)
        }
    }

    static func generateGridCover(images: [UIImage?], size: CGFloat = 400) -> UIImage {
        let cellSize = size / 2
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        return renderer.image { ctx in
            let placeholderColor = UIColor.systemGray5
            for i in 0..<4 {
                let col = CGFloat(i % 2)
                let row = CGFloat(i / 2)
                let rect = CGRect(x: col * cellSize, y: row * cellSize, width: cellSize, height: cellSize)
                if let img = images.count > i ? images[i] : nil {
                    img.draw(in: rect)
                } else {
                    placeholderColor.setFill()
                    ctx.fill(rect)
                    let noteImage = UIImage(systemName: "music.note")?.withTintColor(.systemGray3)
                    let noteSize: CGFloat = cellSize * 0.4
                    let noteRect = CGRect(x: rect.midX - noteSize / 2,
                                         y: rect.midY - noteSize / 2,
                                         width: noteSize,
                                         height: noteSize)
                    noteImage?.draw(in: noteRect)
                }
            }
        }
    }
}
