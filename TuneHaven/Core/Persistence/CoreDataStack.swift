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

    private convenience init() {
        self.init(container: NSPersistentContainer(name: "MusicPlayer"))
    }

    private init(container: NSPersistentContainer) {
        self.container = container
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    #if DEBUG
    /// 测试用内存库。复用单例的模型，避免同一进程加载两份模型导致实体类冲突。
    static func makeInMemory() async throws -> CoreDataStack {
        let model = CoreDataStack.shared.container.managedObjectModel
        let container = NSPersistentContainer(name: "MusicPlayer", managedObjectModel: model)
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        container.persistentStoreDescriptions = [description]
        let stack = CoreDataStack(container: container)
        try await stack.load()
        return stack
    }

    /// Integration tests for grouped SQLite fetches, which NSInMemoryStoreType cannot execute.
    static func makeSQLiteForTesting(at url: URL) async throws -> CoreDataStack {
        let container = NSPersistentContainer(name: "MusicPlayer", managedObjectModel: shared.container.managedObjectModel)
        let description = NSPersistentStoreDescription(url: url)
        description.type = NSSQLiteStoreType
        container.persistentStoreDescriptions = [description]
        let stack = CoreDataStack(container: container)
        try await stack.load()
        return stack
    }
    #endif

    /// 已加载过时直接返回：启动失败后重试会再次调用。
    func load() async throws {
        guard _backgroundContext == nil else { return }
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
