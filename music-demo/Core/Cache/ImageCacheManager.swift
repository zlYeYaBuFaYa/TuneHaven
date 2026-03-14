import UIKit
import Foundation

final class ImageCacheManager {
    static let shared = ImageCacheManager()

    private let memoryCache = NSCache<NSString, UIImage>()
    private let fileManager = FileManager.default
    private var cacheLimitMB: Int = 100

    private init() {
        memoryCache.totalCostLimit = 50 * 1024 * 1024
        NotificationCenter.default.addObserver(self,
            selector: #selector(didReceiveMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil)
    }

    func setCacheLimit(_ megabytes: Int) {
        cacheLimitMB = min(megabytes, 300)
    }

    func image(forKey key: String) -> UIImage? {
        if let cached = memoryCache.object(forKey: key as NSString) {
            return cached
        }
        let url = cacheFileURL(key: key)
        guard fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let image = UIImage(data: data) else { return nil }
        memoryCache.setObject(image, forKey: key as NSString, cost: data.count)
        return image
    }

    func store(image: UIImage, forKey key: String) {
        memoryCache.setObject(image, forKey: key as NSString)
        if let data = image.jpegData(compressionQuality: 0.85) {
            try? data.write(to: cacheFileURL(key: key))
        }
        evictIfNeeded()
    }

    func removeImage(forKey key: String) {
        memoryCache.removeObject(forKey: key as NSString)
        try? fileManager.removeItem(at: cacheFileURL(key: key))
    }

    func clearAll() async {
        memoryCache.removeAllObjects()
        let url = SandboxPathManager.coverImagesURL
        guard let files = try? fileManager.contentsOfDirectory(atPath: url.path) else { return }
        for file in files {
            try? fileManager.removeItem(at: url.appendingPathComponent(file))
        }
        let plUrl = SandboxPathManager.playlistCoversURL
        guard let plFiles = try? fileManager.contentsOfDirectory(atPath: plUrl.path) else { return }
        for file in plFiles {
            try? fileManager.removeItem(at: plUrl.appendingPathComponent(file))
        }
    }

    func cacheSize() -> Int64 {
        var size: Int64 = 0
        let dirs = [SandboxPathManager.coverImagesURL, SandboxPathManager.playlistCoversURL]
        for dir in dirs {
            guard let files = try? fileManager.contentsOfDirectory(atPath: dir.path) else { continue }
            for file in files {
                let url = dir.appendingPathComponent(file)
                size += (try? fileManager.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
            }
        }
        return size
    }

    private func cacheFileURL(key: String) -> URL {
        SandboxPathManager.coverImagesURL.appendingPathComponent(key)
    }

    private func evictIfNeeded() {
        let limitBytes = Int64(cacheLimitMB) * 1024 * 1024
        guard cacheSize() > limitBytes else { return }
        let url = SandboxPathManager.coverImagesURL
        guard var files = try? fileManager.contentsOfDirectory(atPath: url.path) else { return }
        files.sort {
            let d1 = (try? fileManager.attributesOfItem(atPath: url.appendingPathComponent($0).path)[.modificationDate] as? Date) ?? Date.distantPast
            let d2 = (try? fileManager.attributesOfItem(atPath: url.appendingPathComponent($1).path)[.modificationDate] as? Date) ?? Date.distantPast
            return d1 < d2
        }
        let toRemove = files.prefix(max(1, files.count / 5))
        for file in toRemove {
            try? fileManager.removeItem(at: url.appendingPathComponent(file))
        }
    }

    @objc private func didReceiveMemoryWarning() {
        memoryCache.removeAllObjects()
    }
}
