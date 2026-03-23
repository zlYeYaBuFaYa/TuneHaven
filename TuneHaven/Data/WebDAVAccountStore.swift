import Foundation

final class WebDAVAccountStore: WebDAVAccountStoring {
    static let shared = WebDAVAccountStore()
    private init() {}

    private let queue = DispatchQueue(label: "com.tunehaven.webdav-account-store")
    private let accountsKey = "webdav_accounts"
    private func passwordKey(for id: UUID) -> String { "webdav_pwd_\(id.uuidString)" }

    func loadAccounts() -> [WebDAVAccount] {
        queue.sync { _loadAccounts() }
    }

    private func _loadAccounts() -> [WebDAVAccount] {
        guard let data = UserDefaults.standard.data(forKey: accountsKey),
              let accounts = try? JSONDecoder().decode([WebDAVAccount].self, from: data) else {
            return []
        }
        return accounts.sorted { ($0.lastConnectedAt ?? .distantPast) > ($1.lastConnectedAt ?? .distantPast) }
    }

    func saveAccount(_ account: WebDAVAccount, password: String?) throws {
        try queue.sync {
            var accounts = _loadAccounts()
            if let index = accounts.firstIndex(where: { $0.id == account.id }) {
                accounts[index] = account
            } else {
                accounts.append(account)
            }
            let data = try JSONEncoder().encode(accounts)
            UserDefaults.standard.set(data, forKey: accountsKey)

            if let password {
                try KeychainHelper.saveString(password, forKey: passwordKey(for: account.id))
            }
        }
    }

    func deleteAccount(id: UUID) {
        queue.async { [self] in
            var accounts = _loadAccounts()
            accounts.removeAll { $0.id == id }
            do {
                let data = try JSONEncoder().encode(accounts)
                UserDefaults.standard.set(data, forKey: accountsKey)
                KeychainHelper.delete(forKey: passwordKey(for: id))
            } catch {
                ErrorLogger.shared.log(.databaseError(error), context: "deleteAccount: 编码失败 id=\(id)")
            }
        }
    }

    func password(for accountId: UUID) -> String? {
        queue.sync {
            KeychainHelper.loadString(forKey: passwordKey(for: accountId))
        }
    }

    func updateLastConnected(accountId: UUID) {
        queue.async { [self] in
            var accounts = _loadAccounts()
            if let index = accounts.firstIndex(where: { $0.id == accountId }) {
                accounts[index].lastConnectedAt = Date()
                do {
                    let data = try JSONEncoder().encode(accounts)
                    UserDefaults.standard.set(data, forKey: accountsKey)
                } catch {
                    ErrorLogger.shared.log(.databaseError(error), context: "updateLastConnected: 编码失败 id=\(accountId)")
                }
            }
        }
    }
}
