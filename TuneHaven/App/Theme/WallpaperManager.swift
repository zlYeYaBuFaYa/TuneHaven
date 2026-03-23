import SwiftUI
import PhotosUI

@MainActor
final class WallpaperManager: ObservableObject {

    @Published var currentWallpaper: UIImage?
    @Published var useCustomWallpaper: Bool

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
            try saveToDisk(image)
            currentWallpaper = image
            useCustomWallpaper = true
            UserDefaults.standard.set(true, forKey: AppStorageKey.useCustomWallpaper)
            return true
        } catch {
            ErrorLogger.log(error)
            return false
        }
    }

    func removeWallpaper() {
        currentWallpaper = nil
        useCustomWallpaper = false
        UserDefaults.standard.set(false, forKey: AppStorageKey.useCustomWallpaper)
        deleteFromDisk()
    }

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
}
