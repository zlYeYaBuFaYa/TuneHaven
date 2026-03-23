import UIKit
import Foundation

extension Notification.Name {
    static let imageCacheDidUpdate = Notification.Name("imageCacheDidUpdate")
}

final class ImageCacheManager {
    static let shared = ImageCacheManager()

    private let memoryCache = NSCache<NSString, UIImage>()
    private let fileManager = FileManager.default
    private var cacheLimitMB: Int = 100
    private let log = AppLogger.shared
    private var trackedCacheSize: Int64 = -1
    private let fileQueue = DispatchQueue(label: "com.tunehaven.imagecache.file", qos: .utility)

    private init() {
        memoryCache.totalCostLimit = 50 * 1024 * 1024
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.memoryCache.removeAllObjects()
        }
    }

    func setCacheLimit(_ megabytes: Int) {
        let clamped = max(10, min(megabytes, 300))
        fileQueue.async { [weak self] in self?.cacheLimitMB = clamped }
    }

    func memoryImage(forKey key: String) -> UIImage? {
        memoryCache.object(forKey: key as NSString)
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

    func imageAsync(forKey key: String) async -> UIImage? {
        if let cached = memoryCache.object(forKey: key as NSString) {
            return cached
        }
        let url = cacheFileURL(key: key)
        return await withCheckedContinuation { continuation in
            fileQueue.async { [weak self] in
                guard let self,
                      self.fileManager.fileExists(atPath: url.path),
                      let data = try? Data(contentsOf: url),
                      let image = UIImage(data: data) else {
                    continuation.resume(returning: nil)
                    return
                }
                DispatchQueue.main.async {
                    self.memoryCache.setObject(image, forKey: key as NSString, cost: data.count)
                    continuation.resume(returning: image)
                }
            }
        }
    }

    func store(image: UIImage, forKey key: String) {
        guard let data = image.jpegData(compressionQuality: 0.85) else { return }
        memoryCache.setObject(image, forKey: key as NSString, cost: data.count)
        let url = cacheFileURL(key: key)
        fileQueue.async { [weak self] in
            try? data.write(to: url)
            if let self, self.trackedCacheSize >= 0 {
                self.trackedCacheSize += Int64(data.count)
            }
            self?.evictIfNeeded()
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .imageCacheDidUpdate, object: nil, userInfo: ["key": key])
            }
        }
    }

    func removeImage(forKey key: String) {
        memoryCache.removeObject(forKey: key as NSString)
        let url = cacheFileURL(key: key)
        fileQueue.async { [weak self] in
            try? self?.fileManager.removeItem(at: url)
        }
    }

    func clearAll() async {
        log.info("清理图片缓存")
        memoryCache.removeAllObjects()
        let fm = fileManager
        let coverURL = SandboxPathManager.coverImagesURL
        let plURL = SandboxPathManager.playlistCoversURL
        await withCheckedContinuation { continuation in
            fileQueue.async { [weak self] in
                for dir in [coverURL, plURL] {
                    if let files = try? fm.contentsOfDirectory(atPath: dir.path) {
                        for file in files {
                            try? fm.removeItem(at: dir.appendingPathComponent(file))
                        }
                    }
                }
                self?.trackedCacheSize = 0
                continuation.resume()
            }
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

    func cacheSizeAsync() async -> Int64 {
        await withCheckedContinuation { continuation in
            fileQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(returning: 0)
                    return
                }
                let size = self.cacheSize()
                continuation.resume(returning: size)
            }
        }
    }

    private func cacheFileURL(key: String) -> URL {
        let sanitized = key
            .replacingOccurrences(of: "..", with: "")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "\\", with: "_")
        return SandboxPathManager.coverImagesURL.appendingPathComponent(sanitized)
    }

    private func evictIfNeeded() {
        let limitBytes = Int64(cacheLimitMB) * 1024 * 1024
        let currentSize = trackedCacheSize >= 0 ? trackedCacheSize : cacheSize()
        if trackedCacheSize < 0 { trackedCacheSize = currentSize }
        guard currentSize > limitBytes else { return }

        let dirs = [SandboxPathManager.coverImagesURL, SandboxPathManager.playlistCoversURL]
        var allFiles: [(url: URL, date: Date, size: Int64)] = []
        for dir in dirs {
            guard let files = try? fileManager.contentsOfDirectory(atPath: dir.path) else { continue }
            for file in files {
                let fileURL = dir.appendingPathComponent(file)
                let attrs = try? fileManager.attributesOfItem(atPath: fileURL.path)
                let date = attrs?[.modificationDate] as? Date ?? Date.distantPast
                let size = attrs?[.size] as? Int64 ?? 0
                allFiles.append((url: fileURL, date: date, size: size))
            }
        }
        allFiles.sort { $0.date < $1.date }

        var freed: Int64 = 0
        let target = currentSize - limitBytes + limitBytes / 10
        for file in allFiles {
            guard freed < target else { break }
            try? fileManager.removeItem(at: file.url)
            freed += file.size
        }
        trackedCacheSize = max(0, currentSize - freed)
    }

    func formattedCacheSize() -> String {
        let bytes = cacheSize()
        let mb = Double(bytes) / 1024 / 1024
        return mb < 1
            ? String(format: "%.0f KB", Double(bytes) / 1024)
            : String(format: "%.1f MB", mb)
    }
}

extension ImageCacheManager: ImageCacheManaging {}
