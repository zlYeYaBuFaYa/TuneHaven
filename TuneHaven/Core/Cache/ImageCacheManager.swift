import UIKit
import Foundation

extension Notification.Name {
    static let imageCacheDidUpdate = Notification.Name("imageCacheDidUpdate")
}

/// 封面的内存缓存。磁盘上的封面是唯一存储，由 `CoverImageProcessor` 写入，这里只读不删。
final class ImageCacheManager: @unchecked Sendable {
    static let shared = ImageCacheManager(
        coverDirectory: SandboxPathManager.coverImagesURL,
        playlistCoverDirectory: SandboxPathManager.playlistCoversURL
    )

    private let memoryCache = NSCache<NSString, UIImage>()
    private let fileManager = FileManager.default
    private let coverDirectory: URL
    private let playlistCoverDirectory: URL
    private let fileQueue = DispatchQueue(label: "com.tunehaven.imagecache.file", qos: .utility)

    init(coverDirectory: URL, playlistCoverDirectory: URL) {
        self.coverDirectory = coverDirectory
        self.playlistCoverDirectory = playlistCoverDirectory
        memoryCache.totalCostLimit = 50 * 1024 * 1024
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.memoryCache.removeAllObjects()
        }
    }

    func memoryImage(forKey key: String) -> UIImage? {
        memoryCache.object(forKey: key as NSString)
    }

    func imageAsync(forKey key: String) async -> UIImage? {
        if let cached = memoryCache.object(forKey: key as NSString) {
            return cached
        }
        return await withCheckedContinuation { continuation in
            fileQueue.async { [weak self] in
                guard let self,
                      let url = self.fileURL(forKey: key),
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

    /// 更新内存中的图片并通知界面刷新。调用方负责先把文件写到正式目录。
    func store(image: UIImage, forKey key: String) {
        memoryCache.setObject(image, forKey: key as NSString, cost: Self.memoryCost(of: image))
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .imageCacheDidUpdate, object: nil, userInfo: ["key": key])
        }
    }

    func cacheSizeAsync() async -> Int64 {
        await withCheckedContinuation { continuation in
            fileQueue.async { [weak self] in
                continuation.resume(returning: self?.calculateStorageSize() ?? 0)
            }
        }
    }

    private func calculateStorageSize() -> Int64 {
        var size: Int64 = 0
        for dir in [coverDirectory, playlistCoverDirectory] {
            guard let files = try? fileManager.contentsOfDirectory(atPath: dir.path) else { continue }
            for file in files {
                let url = dir.appendingPathComponent(file)
                size += (try? fileManager.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
            }
        }
        return size
    }

    /// 歌单封面名为 `{playlistId}.jpg`，歌曲封面名为 `{songId}_medium.jpg`，两者不会重名。
    private func fileURL(forKey key: String) -> URL? {
        let sanitized = key
            .replacingOccurrences(of: "..", with: "")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "\\", with: "_")
        guard !sanitized.isEmpty else { return nil }
        for dir in [playlistCoverDirectory, coverDirectory] {
            let url = dir.appendingPathComponent(sanitized)
            if fileManager.fileExists(atPath: url.path) { return url }
        }
        return nil
    }

    private static func memoryCost(of image: UIImage) -> Int {
        let pixels = image.size.width * image.scale * image.size.height * image.scale
        return Int(pixels) * 4
    }
}

extension ImageCacheManager: ImageCacheManaging {}
