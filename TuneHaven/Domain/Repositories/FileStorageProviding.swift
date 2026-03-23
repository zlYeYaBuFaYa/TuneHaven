import Foundation

protocol FileStorageProviding: AnyObject {
    var maxFileSizeBytes: Int64 { get }
    var supportedExtensions: Set<String> { get }
    var importTempURL: URL { get }
    func fileExists(relativePath: String) -> Bool
    func sha256(of url: URL) throws -> String
    func copyToMusic(from sourceURL: URL, fileHash: String, originalFileName: String) throws -> String
    func fileSize(at url: URL) -> Int64
    func createDirectoryIfNeeded(at url: URL) throws
    func removeItem(at url: URL) throws
}
