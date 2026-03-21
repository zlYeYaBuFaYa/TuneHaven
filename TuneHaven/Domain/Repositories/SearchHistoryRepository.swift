import Foundation

protocol SearchHistoryRepository: AnyObject {
    func fetchHistory(tab: LibraryTab, limit: Int) async -> [SearchHistoryItem]
    func saveHistory(keyword: String, tab: LibraryTab) async
    func deleteHistory(id: UUID) async
    func clearHistory() async
    func clearHistory(tab: LibraryTab) async
}
