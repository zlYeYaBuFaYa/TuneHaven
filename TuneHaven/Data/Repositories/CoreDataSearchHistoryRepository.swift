import CoreData
import Foundation

final class CoreDataSearchHistoryRepository: SearchHistoryRepository {
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
                let results = (try? self.stack.viewContext.fetch(request)) ?? []
                let items = results.compactMap { entity -> SearchHistoryItem? in
                    guard let id = entity.id, let keyword = entity.keyword, let date = entity.searchedAt else { return nil }
                    return SearchHistoryItem(id: id, keyword: keyword, searchedAt: date)
                }
                continuation.resume(returning: items)
            }
        }
    }

    func saveHistory(keyword: String, tab: LibraryTab) async {
        let kw = keyword.trimmingCharacters(in: .whitespaces)
        guard !kw.isEmpty else { return }
        do {
            try await stack.performBackground { ctx in
                let request = SearchHistoryEntity.fetchRequest()
                request.predicate = NSPredicate(format: "keyword == %@ AND tabContext == %@", kw, tab.rawValue)
                request.fetchLimit = 1
                if let existing = try ctx.fetch(request).first {
                    existing.searchedAt = Date()
                } else {
                    let count = (try? ctx.count(for: {
                        let r = SearchHistoryEntity.fetchRequest()
                        r.predicate = NSPredicate(format: "tabContext == %@", tab.rawValue)
                        return r
                    }())) ?? 0
                    if count >= 10 {
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
        } catch {
            ErrorLogger.shared.log(.databaseError(error), context: "SearchHistory: saveHistory 持久化失败")
        }
    }

    func deleteHistory(id: UUID) async {
        do {
            try await stack.performBackground { ctx in
                let request = SearchHistoryEntity.fetchRequest()
                request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
                request.fetchLimit = 1
                if let entity = try ctx.fetch(request).first { ctx.delete(entity) }
            }
        } catch {
            ErrorLogger.shared.log(.databaseError(error), context: "SearchHistory: deleteHistory 持久化失败")
        }
    }

    func clearHistory() async {
        do {
            try await stack.performBackground { ctx in
                let request = SearchHistoryEntity.fetchRequest()
                let all = try ctx.fetch(request)
                all.forEach { ctx.delete($0) }
            }
        } catch {
            ErrorLogger.shared.log(.databaseError(error), context: "SearchHistory: clearHistory 持久化失败")
        }
    }

    func clearHistory(tab: LibraryTab) async {
        do {
            try await stack.performBackground { ctx in
                let request = SearchHistoryEntity.fetchRequest()
                request.predicate = NSPredicate(format: "tabContext == %@", tab.rawValue)
                let results = try ctx.fetch(request)
                results.forEach { ctx.delete($0) }
            }
        } catch {
            ErrorLogger.shared.log(.databaseError(error), context: "SearchHistory: clearHistory(tab:) 持久化失败")
        }
    }
}
