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
        let container = NSPersistentContainer(name: "MusicPlayer")
        #if DEBUG
        // UI 测试用：`TUNEHAVEN_FRESH_STORE=1` 时每次启动用 tmp 里新的 SQLite 文件，曲库为空、互不影响；
        // 设为其他值时按该名字取 tmp 里的库，同一用例重启后仍是同一个库。
        // 不用内存库：歌单数量的分组查询只有 SQLite 支持。
        if let store = ProcessInfo.processInfo.environment["TUNEHAVEN_FRESH_STORE"], !store.isEmpty {
            let name = store == "1" ? UUID().uuidString : store
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("uitest-\(name).sqlite")
            container.persistentStoreDescriptions = [NSPersistentStoreDescription(url: url)]
        }
        #endif
        self.init(container: container)
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
