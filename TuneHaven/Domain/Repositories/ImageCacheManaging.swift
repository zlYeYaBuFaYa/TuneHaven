import Foundation

protocol ImageCacheManaging: AnyObject {
    func setCacheLimit(_ megabytes: Int)
    func clearAll() async
    func cacheSizeAsync() async -> Int64
    func memoryImageData(forKey key: String) -> Data?
    func imageDataAsync(forKey key: String) async -> Data?
    func storeImageData(_ data: Data, forKey key: String)
}

extension ImageCacheManaging {
    func formattedCacheSize() async -> String {
        let bytes = await cacheSizeAsync()
        let mb = Double(bytes) / 1024 / 1024
        return mb < 1
            ? String(format: "%.0f KB", Double(bytes) / 1024)
            : String(format: "%.1f MB", mb)
    }
}
