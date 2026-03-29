import CoreData
import Foundation

final class CoreDataSyncRepository: SyncRepository {
    private let stack: CoreDataStack
    private let log = AppLogger.shared

    init(stack: CoreDataStack = .shared) {
        self.stack = stack
    }

    func fetchAllMissingReferences() async -> [MissingSongReference] {
        await withCheckedContinuation { continuation in
            stack.viewContext.perform {
                let request = MissingSongReferenceEntity.fetchRequest()
                request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
                do {
                    let results = try self.stack.viewContext.fetch(request)
                    let refs = results.compactMap { MissingSongReferenceMapper.toDomain($0) }
                    continuation.resume(returning: refs)
                } catch {
                    ErrorLogger.shared.log(.databaseError(error), context: "SyncRepo.fetchAll")
                    self.log.error(error, context: "MissingSongReference.fetchAll 查询失败")
                    continuation.resume(returning: [])
                }
            }
        }
    }

    func fetchMissingReferences(forPlaylist playlistId: UUID) async -> [MissingSongReference] {
        await withCheckedContinuation { continuation in
            stack.viewContext.perform {
                let request = MissingSongReferenceEntity.fetchRequest()
                request.predicate = NSPredicate(format: "playlistId == %@", playlistId as CVarArg)
                request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
                do {
                    let results = try self.stack.viewContext.fetch(request)
                    let refs = results.compactMap { MissingSongReferenceMapper.toDomain($0) }
                    continuation.resume(returning: refs)
                } catch {
                    ErrorLogger.shared.log(.databaseError(error), context: "SyncRepo.fetchForPlaylist")
                    self.log.error(error, context: "MissingSongReference.fetchForPlaylist 查询失败")
                    continuation.resume(returning: [])
                }
            }
        }
    }

    func insertMissingReference(_ reference: MissingSongReference) async throws {
        try await stack.performBackground { context in
            let entity = MissingSongReferenceEntity(context: context)
            entity.id = reference.id
            entity.title = reference.title
            entity.artist = reference.artist
            entity.album = reference.album
            entity.duration = reference.duration
            entity.playlistId = reference.playlistId
            entity.createdAt = Date()
        }
    }

    func insertMissingReferences(_ references: [MissingSongReference]) async throws {
        guard !references.isEmpty else { return }
        try await stack.performBackground { context in
            for ref in references {
                let entity = MissingSongReferenceEntity(context: context)
                entity.id = ref.id
                entity.title = ref.title
                entity.artist = ref.artist
                entity.album = ref.album
                entity.duration = ref.duration
                entity.playlistId = ref.playlistId
                entity.createdAt = Date()
            }
        }
    }

    func deleteMissingReference(id: UUID) async throws {
        try await stack.performBackground { context in
            let request = MissingSongReferenceEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            let results = try context.fetch(request)
            for entity in results {
                context.delete(entity)
            }
        }
    }

    func deleteMissingReferences(ids: [UUID]) async throws {
        guard !ids.isEmpty else { return }
        try await stack.performBackground { context in
            let request = MissingSongReferenceEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id IN %@", ids)
            let results = try context.fetch(request)
            for entity in results {
                context.delete(entity)
            }
        }
    }

    func deleteMissingReferences(forPlaylist playlistId: UUID) async throws {
        try await stack.performBackground { context in
            let request = MissingSongReferenceEntity.fetchRequest()
            request.predicate = NSPredicate(format: "playlistId == %@", playlistId as CVarArg)
            let results = try context.fetch(request)
            for entity in results {
                context.delete(entity)
            }
        }
    }
}
