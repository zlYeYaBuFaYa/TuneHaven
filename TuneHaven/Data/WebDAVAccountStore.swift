import Foundation

// 账户元数据（URL、用户名）存 UserDefaults，密码存 Keychain 加密保护
final class WebDAVAccountStore: WebDAVAccountStoring {
    static let shared = WebDAVAccountStore()
    private init() {}

    private let queue = DispatchQueue(label: "com.tunehaven.webdav-account-store")
    private let accountsKey = "webdav_accounts"
    private var cachedAccounts: [WebDAVAccount]?
    private func passwordKey(for id: UUID) -> String { "webdav_pwd_\(id.uuidString)" }

    func loadAccounts() -> [WebDAVAccount] {
        queue.sync { _loadAccounts() }
    }

    private func _loadAccounts() -> [WebDAVAccount] {
        if let cached = cachedAccounts { return cached }
        guard let data = UserDefaults.standard.data(forKey: accountsKey) else {
            cachedAccounts = []
            return []
        }
        do {
            let accounts = try JSONDecoder().decode([WebDAVAccount].self, from: data)
                .sorted { ($0.lastConnectedAt ?? .distantPast) > ($1.lastConnectedAt ?? .distantPast) }
            cachedAccounts = accounts
            return accounts
        } catch {
            ErrorLogger.shared.logGeneric(error, context: "_loadAccounts: 解码失败，账户数据可能损坏")
            cachedAccounts = []
            return []
        }
    }

    private func _persist(_ accounts: [WebDAVAccount]) throws {
        let data = try JSONEncoder().encode(accounts)
        UserDefaults.standard.set(data, forKey: accountsKey)
        cachedAccounts = accounts
    }

    func saveAccount(_ account: WebDAVAccount, password: String?) throws {
        try queue.sync {
            var accounts = _loadAccounts()
            if let index = accounts.firstIndex(where: { $0.id == account.id }) {
                accounts[index] = account
            } else {
                accounts.append(account)
            }
            try _persist(accounts)
            if let password {
                try KeychainHelper.saveString(password, forKey: passwordKey(for: account.id))
            }
        }
    }

    func deleteAccount(id: UUID) {
        queue.sync {
            KeychainHelper.delete(forKey: passwordKey(for: id))
            var accounts = _loadAccounts()
            accounts.removeAll { $0.id == id }
            do {
                try _persist(accounts)
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
        queue.sync {
            var accounts = _loadAccounts()
            if let index = accounts.firstIndex(where: { $0.id == accountId }) {
                accounts[index].lastConnectedAt = Date()
                do {
                    try _persist(accounts)
                } catch {
                    ErrorLogger.shared.log(.databaseError(error), context: "updateLastConnected: 编码失败 id=\(accountId)")
                }
            }
        }
    }
}
