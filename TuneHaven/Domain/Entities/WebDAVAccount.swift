import Foundation

struct WebDAVAccount: Identifiable, Codable, Hashable {
    let id: UUID
    var displayName: String
    var serverURL: String
    var username: String
    var trustSelfSignedCert: Bool
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
