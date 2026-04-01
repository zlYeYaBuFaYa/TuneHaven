import UIKit

// TODO: 🟢20 — import UIKit 因 UIImage 深度嵌入协议接口，去除需大规模重构，列入后续迭代
protocol ImageCacheManaging: AnyObject {
    func setCacheLimit(_ megabytes: Int)
    func clearAll() async
    func cacheSizeAsync() async -> Int64
    func memoryImage(forKey key: String) -> UIImage?
    func imageAsync(forKey key: String) async -> UIImage?
    func store(image: UIImage, forKey key: String)
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
