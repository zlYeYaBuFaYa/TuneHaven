import CoreData
import Foundation

final class CoreDataStack {
    static let shared = CoreDataStack()

    let container: NSPersistentContainer

    var viewContext: NSManagedObjectContext { container.viewContext }

    private let backgroundContext: NSManagedObjectContext

    private init() {
        container = NSPersistentContainer(name: "MusicPlayer")
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        let ctx = container.newBackgroundContext()
        ctx.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        ctx.automaticallyMergesChangesFromParent = true
        backgroundContext = ctx
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
    }

    func performBackground<T: Sendable>(_ block: @Sendable @escaping (NSManagedObjectContext) throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            backgroundContext.perform {
                do {
                    let result = try block(self.backgroundContext)
                    if self.backgroundContext.hasChanges {
                        try self.backgroundContext.save()
                    }
                    continuation.resume(returning: result)
                } catch {
                    self.backgroundContext.rollback()
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
