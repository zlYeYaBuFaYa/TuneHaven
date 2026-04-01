import CoreData
import Foundation

final class CoreDataStack: @unchecked Sendable {
    static let shared = CoreDataStack()

    let container: NSPersistentContainer

    var viewContext: NSManagedObjectContext { container.viewContext }

    private var _backgroundContext: NSManagedObjectContext?

    private var backgroundContext: NSManagedObjectContext {
        guard let ctx = _backgroundContext else {
            fatalError("CoreDataStack.load() must be called before accessing backgroundContext")
        }
        return ctx
    }

    private init() {
        container = NSPersistentContainer(name: "MusicPlayer")
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    func load() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            container.loadPersistentStores { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
        let ctx = container.newBackgroundContext()
        ctx.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        ctx.automaticallyMergesChangesFromParent = true
        _backgroundContext = ctx
    }

    func performBackground<T: Sendable>(_ block: @Sendable @escaping (NSManagedObjectContext) throws -> T) async throws -> T {
        let ctx = backgroundContext
        return try await withCheckedThrowingContinuation { continuation in
            ctx.perform {
                do {
                    let result = try block(ctx)
                    if ctx.hasChanges {
                        try ctx.save()
                    }
                    continuation.resume(returning: result)
                } catch {
                    ctx.rollback()
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// 强制刷新 viewContext，确保能读取到 backgroundContext 的最新写入
    func refreshViewContext() async {
        let ctx = viewContext
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            ctx.perform {
                ctx.refreshAllObjects()
                continuation.resume()
            }
        }
    }
}
