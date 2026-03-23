import Foundation

protocol ImageCacheManaging: AnyObject {
    func setCacheLimit(_ megabytes: Int)
    func clearAll() async
    func cacheSizeAsync() async -> Int64
}
