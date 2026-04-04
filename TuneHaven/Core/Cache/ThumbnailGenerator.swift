import UIKit

enum ThumbnailSize: Int {
    case small = 100
    case medium = 200
    case large = 400
    case original = 1024

    var suffix: String { String(describing: self) }
    var dimension: CGFloat { CGFloat(rawValue) }
}

enum ThumbnailGenerator {
    static func resize(_ image: UIImage, to size: ThumbnailSize) -> UIImage {
        let dim = size.dimension
        guard image.size.width > 0, image.size.height > 0 else { return image }
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
                if let img = i < images.count ? images[i] : nil {
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
