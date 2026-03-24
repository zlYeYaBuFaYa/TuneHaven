import Foundation

protocol FileStorageProviding: AnyObject {
    var maxFileSizeBytes: Int64 { get }
    var supportedExtensions: Set<String> { get }
    var importTempURL: URL { get }
    var documentsURL: URL { get }
    func fileExists(relativePath: String) -> Bool
    func sha256(of url: URL) throws -> String
    func copyToMusic(from sourceURL: URL, fileHash: String, originalFileName: String) throws -> String
    func fileSize(at url: URL) -> Int64
    func createDirectoryIfNeeded(at url: URL) throws
    func removeItem(at url: URL) throws
    func contentsOfDirectory(at url: URL) -> [URL]

    func musicFileURL(relativePath: String) -> URL
    func lyricsFileURL(relativePath: String) -> URL
    var lyricsDirectoryURL: URL { get }
    func fileExists(at url: URL) -> Bool
    func isReadableFile(at url: URL) -> Bool
    func readStringContents(at url: URL) -> String?
}
