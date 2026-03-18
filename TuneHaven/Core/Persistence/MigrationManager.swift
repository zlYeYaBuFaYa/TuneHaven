import CoreData
import Foundation

/// CoreData 轻量级迁移管理（TDD Section 1.4）
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
        // v1.x → v2.0: 示例：迁移 has_completed_onboarding 默认值
        if oldVersion.isEmpty || oldVersion < "2.0" {
            if !UserDefaults.standard.bool(forKey: "has_completed_onboarding") {
                // 老用户已安装使用，标记 onboarding 已完成
                UserDefaults.standard.set(true, forKey: "has_completed_onboarding")
            }
        }
    }
}
