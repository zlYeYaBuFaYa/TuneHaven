import Foundation

final class WebDAVAccountStore {
    static let shared = WebDAVAccountStore()
    private init() {}

    private let accountsKey = "webdav_accounts"
    private func passwordKey(for id: UUID) -> String { "webdav_pwd_\(id.uuidString)" }

    func loadAccounts() -> [WebDAVAccount] {
        guard let data = UserDefaults.standard.data(forKey: accountsKey),
              let accounts = try? JSONDecoder().decode([WebDAVAccount].self, from: data) else {
            return []
        }
        return accounts.sorted { ($0.lastConnectedAt ?? .distantPast) > ($1.lastConnectedAt ?? .distantPast) }
    }

    func saveAccount(_ account: WebDAVAccount, password: String?) throws {
        var accounts = loadAccounts()
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

    func deleteAccount(id: UUID) {
        var accounts = loadAccounts()
        accounts.removeAll { $0.id == id }
        if let data = try? JSONEncoder().encode(accounts) {
            UserDefaults.standard.set(data, forKey: accountsKey)
        }
        KeychainHelper.delete(forKey: passwordKey(for: id))
    }

    func password(for accountId: UUID) -> String? {
        KeychainHelper.loadString(forKey: passwordKey(for: accountId))
    }

    func updateLastConnected(accountId: UUID) {
        var accounts = loadAccounts()
        if let index = accounts.firstIndex(where: { $0.id == accountId }) {
            accounts[index].lastConnectedAt = Date()
            if let data = try? JSONEncoder().encode(accounts) {
                UserDefaults.standard.set(data, forKey: accountsKey)
            }
        }
    }
}
