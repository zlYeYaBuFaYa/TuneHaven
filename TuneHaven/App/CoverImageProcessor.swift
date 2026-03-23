import UIKit

final class CoverImageProcessor: CoverImageProcessing {
    private let imageCache: ImageCacheManager

    init(imageCache: ImageCacheManager = .shared) {
        self.imageCache = imageCache
    }

    func processSongCover(data: Data, songId: UUID) async throws -> String? {
        guard let image = UIImage(data: data) else { return nil }
        let thumb = ThumbnailGenerator.resize(image, to: .medium)
        let cacheURL = SandboxPathManager.coverImageURL(songId: songId, size: .medium)
        guard let jpegData = thumb.jpegData(compressionQuality: 0.85) else {
            throw AppError.imageProcessingFailed("无法压缩封面图片")
        }
        try jpegData.write(to: cacheURL)
        let key = "\(songId.uuidString)_medium.jpg"
        await MainActor.run { imageCache.store(image: thumb, forKey: key) }
        return key
    }

    func processPlaylistCover(imageData: Data, playlistId: UUID) async throws -> String {
        guard let image = UIImage(data: imageData) else {
            throw AppError.imageProcessingFailed("无效的图片数据")
        }
        let thumb = ThumbnailGenerator.resize(image, to: .large)
        let url = SandboxPathManager.playlistCoverURL(playlistId: playlistId)
        guard let jpegData = thumb.jpegData(compressionQuality: 0.9) else {
            throw AppError.imageProcessingFailed("无法压缩图片")
        }
        try jpegData.write(to: url)
        return url.lastPathComponent
    }

    func generatePlaylistGridCover(coverPaths: [String?], playlistId: UUID) async throws -> String {
        let images: [UIImage?] = (0..<4).map { i -> UIImage? in
            guard i < coverPaths.count, let path = coverPaths[i] else { return nil }
            return imageCache.image(forKey: path)
        }
        let gridImage = ThumbnailGenerator.generateGridCover(images: images)
        let url = SandboxPathManager.playlistCoverURL(playlistId: playlistId)
        guard let data = gridImage.jpegData(compressionQuality: 0.85) else {
            throw AppError.imageProcessingFailed("无法生成拼接封面")
        }
        try data.write(to: url)
        await MainActor.run { imageCache.store(image: gridImage, forKey: url.lastPathComponent) }
        return url.lastPathComponent
    }
}
