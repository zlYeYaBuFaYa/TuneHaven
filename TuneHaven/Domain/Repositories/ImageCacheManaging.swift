import UIKit

protocol ImageCacheManaging: AnyObject {
    func setCacheLimit(_ megabytes: Int)
    func clearAll() async
    func cacheSizeAsync() async -> Int64
    func memoryImage(forKey key: String) -> UIImage?
    func imageAsync(forKey key: String) async -> UIImage?
    func store(image: UIImage, forKey key: String)
}
