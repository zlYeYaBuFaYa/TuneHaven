import CoreData
import Foundation

final class CoreDataSearchHistoryRepository: SearchHistoryRepository, @unchecked Sendable {
    private static let maxHistoryCount = 10
    private let stack: CoreDataStack

    init(stack: CoreDataStack = .shared) {
        self.stack = stack
    }

    func fetchHistory(tab: LibraryTab, limit: Int) async -> [SearchHistoryItem] {
        await withCheckedContinuation { continuation in
            stack.viewContext.perform {
                let request = SearchHistoryEntity.fetchRequest()
                request.predicate = NSPredicate(format: "tabContext == %@", tab.rawValue)
                request.sortDescriptors = [NSSortDescriptor(key: "searchedAt", ascending: false)]
                request.fetchLimit = limit
                do {
                    let results = try self.stack.viewContext.fetch(request)
                    let items = results.compactMap { entity -> SearchHistoryItem? in
                        guard let id = entity.id, let keyword = entity.keyword, let date = entity.searchedAt else { return nil }
                        return SearchHistoryItem(id: id, keyword: keyword, searchedAt: date)
                    }
                    continuation.resume(returning: items)
                } catch {
                    ErrorLogger.shared.log(.databaseError(error), context: "fetchHistory")
                    AppLogger.shared.error(error, context: "fetchHistory 查询失败")
                    continuation.resume(returning: [])
                }
            }
        }
    }

    func saveHistory(keyword: String, tab: LibraryTab) async throws {
        let kw = keyword.trimmingCharacters(in: .whitespaces)
        guard !kw.isEmpty else { return }
        try await stack.performBackground { ctx in
            let request = SearchHistoryEntity.fetchRequest()
            request.predicate = NSPredicate(format: "keyword == %@ AND tabContext == %@", kw, tab.rawValue)
            request.fetchLimit = 1
            if let existing = try ctx.fetch(request).first {
                existing.searchedAt = Date()
            } else {
                let countReq = SearchHistoryEntity.fetchRequest()
                countReq.predicate = NSPredicate(format: "tabContext == %@", tab.rawValue)
                let count = (try? ctx.count(for: countReq)) ?? 0
                if count >= Self.maxHistoryCount {
                    let oldReq = SearchHistoryEntity.fetchRequest()
                    oldReq.predicate = NSPredicate(format: "tabContext == %@", tab.rawValue)
                    oldReq.sortDescriptors = [NSSortDescriptor(key: "searchedAt", ascending: true)]
                    oldReq.fetchLimit = 1
                    if let oldest = try ctx.fetch(oldReq).first { ctx.delete(oldest) }
                }
                let entity = SearchHistoryEntity(context: ctx)
                entity.id = UUID()
                entity.keyword = kw
                entity.tabContext = tab.rawValue
                entity.searchedAt = Date()
            }
        }
    }

    func deleteHistory(id: UUID) async throws {
        try await stack.performBackground { ctx in
            let request = SearchHistoryEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            request.fetchLimit = 1
            if let entity = try ctx.fetch(request).first { ctx.delete(entity) }
        }
    }

    func clearHistory() async throws {
        try await stack.performBackground { ctx in
            let request = SearchHistoryEntity.fetchRequest()
            let all = try ctx.fetch(request)
            all.forEach { ctx.delete($0) }
        }
    }

    func clearHistory(tab: LibraryTab) async throws {
        try await stack.performBackground { ctx in
            let request = SearchHistoryEntity.fetchRequest()
            request.predicate = NSPredicate(format: "tabContext == %@", tab.rawValue)
            let results = try ctx.fetch(request)
            results.forEach { ctx.delete($0) }
        }
    }
}
