import CoreData
import Foundation

/// CoreData 轻量级迁移管理
/// 当 xcdatamodel 版本变更时负责自动迁移
final class MigrationManager {
    static let shared = MigrationManager()
    private init() {}

    /// 检查是否需要迁移，并执行轻量级自动迁移
    func migrateStoreIfNeeded(at storeURL: URL, model: NSManagedObjectModel) throws {
        guard FileManager.default.fileExists(atPath: storeURL.path) else { return }

        let metadata: [String: Any]
        do {
            metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(
                ofType: NSSQLiteStoreType, at: storeURL, options: nil
            )
        } catch {
            ErrorLogger.shared.log(.databaseError(error), context: "MigrationManager.metadataCheck")
            throw error
        }

        guard !model.isConfiguration(withName: nil, compatibleWithStoreMetadata: metadata) else {
            return // 已兼容，无需迁移
        }

        let options: [String: Any] = [
            NSMigratePersistentStoresAutomaticallyOption: true,
            NSInferMappingModelAutomaticallyOption: true
        ]

        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        do {
            try coordinator.addPersistentStore(
                ofType: NSSQLiteStoreType,
                configurationName: nil,
                at: storeURL,
                options: options
            )
            // migration succeeded
        } catch {
            ErrorLogger.shared.log(.databaseError(error), context: "MigrationManager.migrate")
            throw error
        }
    }

    // MARK: - App 版本升级处理（非 CoreData 迁移）

    private static let lastVersionKey = "last_app_version"

    /// 应用版本升级后执行一次性数据修复
    func runVersionUpgradeTasks() {
        let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let last = UserDefaults.standard.string(forKey: Self.lastVersionKey) ?? ""

        guard current != last else { return }

        performUpgrade(from: last, to: current)
        UserDefaults.standard.set(current, forKey: Self.lastVersionKey)
    }

    private func performUpgrade(from oldVersion: String, to newVersion: String) {
        let oldNumeric = numericVersion(oldVersion)
        if oldNumeric == (0, 0, 0) || oldNumeric < (2, 0, 0) {
            let onboardingKey = "has_completed_onboarding"
            if !UserDefaults.standard.bool(forKey: onboardingKey) {
                UserDefaults.standard.set(true, forKey: onboardingKey)
            }
        }
    }

    private func numericVersion(_ version: String) -> (Int, Int, Int) {
        let parts = version.split(separator: ".").compactMap { Int($0) }
        return (parts.count > 0 ? parts[0] : 0,
                parts.count > 1 ? parts[1] : 0,
                parts.count > 2 ? parts[2] : 0)
    }

    // MARK: - CoreData 数据修复（需在 CoreDataStack.load() 之后调用）

    private static let lyricsSourceMigratedKey = "lyrics_source_sentinel_migrated"

    func runPostLoadMigrations() async {
        await migrateLyricsSourceSentinel()
    }

    /// lyricsSource 哨兵值从 0 改为 -1：将旧记录中 lyricsSource=0 且无歌词文件的记录修正为 -1（nil）
    private func migrateLyricsSourceSentinel() async {
        guard !UserDefaults.standard.bool(forKey: Self.lyricsSourceMigratedKey) else { return }
        do {
            try await CoreDataStack.shared.performBackground { ctx in
                let request = SongEntity.fetchRequest()
                request.predicate = NSPredicate(format: "lyricsSource == 0 AND lyricsPath == nil")
                let entities = try ctx.fetch(request)
                for entity in entities {
                    entity.lyricsSource = Int16.min
                }
            }
            UserDefaults.standard.set(true, forKey: Self.lyricsSourceMigratedKey)
            AppLogger.shared.info("lyricsSource 哨兵值迁移完成")
        } catch {
            ErrorLogger.shared.log(.databaseError(error), context: "MigrationManager.migrateLyricsSourceSentinel")
        }
    }
}
