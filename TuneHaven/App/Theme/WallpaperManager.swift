import SwiftUI
import PhotosUI

@MainActor
final class WallpaperManager: ObservableObject {

    @Published var currentWallpaper: UIImage?
    @Published var useCustomWallpaper: Bool {
        didSet { UserDefaults.standard.set(useCustomWallpaper, forKey: AppStorageKey.useCustomWallpaper) }
    }

    private static let maxWallpaperDimension: CGFloat = 2048

    private let wallpaperFileName = "user_wallpaper.jpg"

    init() {
        useCustomWallpaper = UserDefaults.standard.bool(forKey: AppStorageKey.useCustomWallpaper)
        if useCustomWallpaper {
            currentWallpaper = loadFromDisk()
        }
    }

    @discardableResult
    func setWallpaper(_ image: UIImage) -> Bool {
        do {
            let resized = Self.constrainSize(image, maxDimension: Self.maxWallpaperDimension)
            try saveToDisk(resized)
            currentWallpaper = resized
            useCustomWallpaper = true
            return true
        } catch {
            ErrorLogger.shared.logGeneric(error, context: "壁纸保存失败")
            return false
        }
    }

    func removeWallpaper() {
        currentWallpaper = nil
        useCustomWallpaper = false
        deleteFromDisk()
    }

    // MARK: - Private

    private var wallpaperURL: URL {
        SandboxPathManager.documentsURL.appendingPathComponent(wallpaperFileName)
    }

    private func saveToDisk(_ image: UIImage) throws {
        guard let data = image.jpegData(compressionQuality: 0.85) else {
            throw AppError.fileSystemError("无法生成 JPEG 数据")
        }
        try data.write(to: wallpaperURL)
    }

    private func loadFromDisk() -> UIImage? {
        guard let data = try? Data(contentsOf: wallpaperURL) else { return nil }
        return UIImage(data: data)
    }

    private func deleteFromDisk() {
        try? FileManager.default.removeItem(at: wallpaperURL)
    }

    private static func constrainSize(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        guard size.width > maxDimension || size.height > maxDimension else { return image }

        let scale = maxDimension / max(size.width, size.height)
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)

        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
