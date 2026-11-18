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

/// 自签证书的信任方式：首次连接记住证书指纹，之后只接受同一张证书（TOFU）。
/// 系统本身信任的证书（CA 签发）不受影响，续期后照常连接。
struct WebDAVTrustPolicy: Sendable {
    var trustSelfSigned: Bool
    var pinnedFingerprint: String?
    /// 首次信任某张自签证书时回调其指纹，用于持久化
    var onPinned: (@Sendable (String) -> Void)?

    init(trustSelfSigned: Bool, pinnedFingerprint: String? = nil, onPinned: (@Sendable (String) -> Void)? = nil) {
        self.trustSelfSigned = trustSelfSigned
        self.pinnedFingerprint = pinnedFingerprint
        self.onPinned = onPinned
    }

    enum Decision: Equatable {
        case defaultHandling
        case accept
        case acceptAndPin(String)
        case rejectChanged
    }

    /// `systemTrusted`：系统按默认规则校验是否通过；`presented`：服务器证书指纹。
    func decide(systemTrusted: Bool, presented: String?) -> Decision {
        guard trustSelfSigned, !systemTrusted, let presented else { return .defaultHandling }
        guard let pinnedFingerprint else { return .acceptAndPin(presented) }
        return pinnedFingerprint == presented ? .accept : .rejectChanged
    }
}

protocol WebDAVClientFactory {
    func makeClient(baseURL: URL, username: String, password: String, trust: WebDAVTrustPolicy) -> WebDAVClientProtocol
}
