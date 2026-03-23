import Foundation

protocol WebDAVClientProtocol: Sendable {
    func testConnection() async throws -> Bool
    func listDirectory(path: String) async throws -> [WebDAVFile]
    func downloadFile(
        remotePath: String,
        to destination: URL,
        progress: @escaping @Sendable (Int64, Int64) -> Void
    ) async throws -> URL
    func cancelDownload() async
}

protocol WebDAVClientFactory {
    func makeClient(baseURL: URL, username: String, password: String, trustSelfSignedCert: Bool) -> WebDAVClientProtocol
}
