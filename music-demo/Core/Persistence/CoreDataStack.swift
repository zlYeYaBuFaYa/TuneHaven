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

    func save(context: NSManagedObjectContext) {
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            ErrorLogger.shared.log(.databaseError(error), context: "CoreDataStack.save")
        }
    }

    func performBackground<T>(_ block: @escaping (NSManagedObjectContext) throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            backgroundContext.perform {
                do {
                    let result = try block(self.backgroundContext)
                    if self.backgroundContext.hasChanges {
                        var notification: Notification?
                        let token = NotificationCenter.default.addObserver(
                            forName: .NSManagedObjectContextDidSave,
                            object: self.backgroundContext,
                            queue: nil
                        ) { notification = $0 }

                        try self.backgroundContext.save()
                        NotificationCenter.default.removeObserver(token)

                        if let notification {
                            self.viewContext.performAndWait {
                                self.viewContext.mergeChanges(fromContextDidSave: notification)
                            }
                        }
                    }
                    self.viewContext.perform {
                        continuation.resume(returning: result)
                    }
                } catch {
                    self.backgroundContext.rollback()
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
