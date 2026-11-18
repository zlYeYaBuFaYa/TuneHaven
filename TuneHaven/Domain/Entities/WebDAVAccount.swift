import Foundation

struct WebDAVAccount: Identifiable, Codable, Hashable {
    let id: UUID
    var displayName: String
    var serverURL: String
    var username: String
    var trustSelfSignedCert: Bool
    /// 信任自签证书时，首次连接记住的证书 SHA-256 指纹；重新保存账户时清空
    var pinnedCertificateSHA256: String?
    var createdAt: Date
    var lastConnectedAt: Date?

    var host: String { URL(string: serverURL)?.host ?? serverURL }

    init(id: UUID = UUID(), displayName: String = "", serverURL: String = "",
         username: String = "", trustSelfSignedCert: Bool = false,
         createdAt: Date = Date(), lastConnectedAt: Date? = nil) {
        self.id = id
        self.displayName = displayName
        self.serverURL = serverURL
        self.username = username
        self.trustSelfSignedCert = trustSelfSignedCert
        self.createdAt = createdAt
        self.lastConnectedAt = lastConnectedAt
    }

    var effectiveDisplayName: String {
        displayName.isEmpty ? host : displayName
    }
}
