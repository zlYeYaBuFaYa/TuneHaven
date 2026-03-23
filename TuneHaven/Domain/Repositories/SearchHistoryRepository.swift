import Foundation

protocol SearchHistoryRepository: AnyObject {
    func fetchHistory(tab: LibraryTab, limit: Int) async -> [SearchHistoryItem]
    func saveHistory(keyword: String, tab: LibraryTab) async throws
    func deleteHistory(id: UUID) async throws
    func clearHistory() async throws
    func clearHistory(tab: LibraryTab) async throws
}
