import UIKit

final class ThumbnailGenerator {
    static func resize(_ image: UIImage, to size: ThumbnailSize) -> UIImage {
        let dim = size.dimension
        let targetSize = CGSize(width: dim, height: dim)
        if image.size.width <= dim && image.size.height <= dim { return image }
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
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
