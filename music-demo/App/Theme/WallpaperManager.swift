import SwiftUI
import PhotosUI

@MainActor
final class WallpaperManager: ObservableObject {
    static let shared = WallpaperManager()

    @Published var currentWallpaper: UIImage?
    @Published var useCustomWallpaper: Bool

    private let wallpaperFileName = "user_wallpaper.jpg"

    init() {
        useCustomWallpaper = UserDefaults.standard.bool(forKey: "use_custom_wallpaper")
        if useCustomWallpaper {
            currentWallpaper = loadFromDisk()
        }
    }

    func setWallpaper(_ image: UIImage) {
        currentWallpaper = image
        useCustomWallpaper = true
        UserDefaults.standard.set(true, forKey: "use_custom_wallpaper")
        saveToDisk(image)
    }

    func removeWallpaper() {
        currentWallpaper = nil
        useCustomWallpaper = false
        UserDefaults.standard.set(false, forKey: "use_custom_wallpaper")
        deleteFromDisk()
    }

    private var wallpaperURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent(wallpaperFileName)
    }

    private func saveToDisk(_ image: UIImage) {
        guard let data = image.jpegData(compressionQuality: 0.85) else { return }
        try? data.write(to: wallpaperURL)
    }

    private func loadFromDisk() -> UIImage? {
        guard let data = try? Data(contentsOf: wallpaperURL) else { return nil }
        return UIImage(data: data)
    }

    private func deleteFromDisk() {
        try? FileManager.default.removeItem(at: wallpaperURL)
    }
}
