import Foundation

protocol WebDAVAccountStoring {
    func loadAccounts() -> [WebDAVAccount]
    func saveAccount(_ account: WebDAVAccount, password: String?) throws
    func deleteAccount(id: UUID) throws
    func password(for accountId: UUID) -> String?
    func updateLastConnected(accountId: UUID) throws
}
