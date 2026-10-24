import Foundation

struct BackupPresentation: Identifiable, Equatable {
    enum Kind: Equatable {
        case export
        case restore
    }

    let id: UUID
    var kind: Kind
    var packageURL: URL?
}

@MainActor
final class BackupRestoreService: ObservableObject {
    @Published var presentation: BackupPresentation?
    @Published private(set) var progress: BackupProgress?
    @Published private(set) var isBusy = false
    @Published var lastError: String?

    private let library: BackupLibraryApplying
    private let activityGate: BackupActivityGate
    private let layout: BackupFileLayout
    private let cancelFlag = BackupCancelFlag()
    private var preparedDirectory: URL?
    private var preparedSource: URL?
    private var preparedCatalog: BackupCatalog?

    var onLibraryWillChange: (@MainActor (BackupRestoreMode) async -> Void)?
    var onPreferencesApplied: (@MainActor (BackupPreferences) -> Void)?
    var onLibraryChanged: (@MainActor (BackupRestoreMode) async -> Void)?

    init(
        library: BackupLibraryApplying,
        activityGate: BackupActivityGate,
        layout: BackupFileLayout,
        onLibraryWillChange: (@MainActor (BackupRestoreMode) async -> Void)? = nil,
        onPreferencesApplied: (@MainActor (BackupPreferences) -> Void)? = nil,
        onLibraryChanged: (@MainActor (BackupRestoreMode) async -> Void)? = nil
    ) {
        self.library = library
        self.activityGate = activityGate
        self.layout = layout
        self.onLibraryWillChange = onLibraryWillChange
        self.onPreferencesApplied = onPreferencesApplied
        self.onLibraryChanged = onLibraryChanged
    }

    func presentExport() {
        lastError = nil
        presentation = BackupPresentation(id: UUID(), kind: .export, packageURL: nil)
    }

    func presentRestore(url: URL?) {
        lastError = nil
        presentation = BackupPresentation(id: UUID(), kind: .restore, packageURL: url)
    }

    func cancel() {
        cancelFlag.cancel()
    }

    func discardPreparedPackage() {
        if let preparedDirectory {
            try? FileManager.default.removeItem(at: preparedDirectory)
        }
        preparedDirectory = nil
        preparedSource = nil
        preparedCatalog = nil
    }

    func estimate(includeAudio: Bool) async -> Int64 {
        do {
            let snapshot = try await library.loadSnapshot()
            return BackupExporter.estimate(snapshot: snapshot, includeAudio: includeAudio, layout: layout)
        } catch {
            return 0
        }
    }

    func export(includeAudio: Bool) async throws -> URL {
        try beginWork()
        defer { endWork() }
        let snapshot = try await library.loadSnapshot()
        let draft = BackupExporter.makePackage(
            snapshot: snapshot,
            includeAudio: includeAudio,
            appVersion: Self.appVersion,
            exportedAt: Date(),
            layout: layout
        )
        let destination = SandboxPathManager.backupExportURL
            .appendingPathComponent("TuneHaven-\(Self.fileStamp()).\(BackupPackageFormat.fileExtension)")
        progress = BackupProgress(phase: "正在打包", completed: 0, total: max(draft.files.count, 1))
        let cancelled = cancelFlag
        try await runOffMain {
            try BackupPackageCodec.write(
                draft: draft,
                to: destination,
                stagingParent: SandboxPathManager.backupExportURL,
                isCancelled: { cancelled.isCancelled() }
            )
        }
        progress = BackupProgress(phase: "打包完成", completed: 1, total: 1)
        return destination
    }

    func inspect(url: URL) async throws -> BackupPreview {
        let catalog = try await withSecurityScope(url) {
            try await self.catalog(for: url)
        }
        let local = try await library.loadSnapshot()
        return BackupPlanner.preview(local: local, package: catalog)
    }

    func restore(
        url: URL,
        mode: BackupRestoreMode,
        resolution: BackupConflictResolution
    ) async throws -> BackupRestoreSummary {
        try beginWork()
        defer { endWork() }
        let catalog = try await withSecurityScope(url) {
            try await self.catalog(for: url)
        }
        guard let root = preparedDirectory else {
            throw AppError.backupInvalidPackage("临时目录不存在")
        }
        let original = try await library.loadSnapshot()
        let plan = BackupPlanner.plan(
            local: original,
            package: catalog,
            mode: mode,
            resolution: resolution
        )
        progress = BackupProgress(phase: "正在恢复", completed: 0, total: max(plan.copies.count, 1))
        if mode != .preferencesOnly {
            await onLibraryWillChange?(mode)
        }
        let summary = try await BackupCommitter.commit(
            original: original,
            plan: plan,
            packageRoot: root,
            layout: layout,
            library: library,
            isCancelled: { [cancelFlag] in cancelFlag.isCancelled() }
        )
        onPreferencesApplied?(plan.snapshot.preferences)
        if mode != .preferencesOnly {
            await onLibraryChanged?(mode)
        }
        progress = BackupProgress(phase: "恢复完成", completed: 1, total: 1)
        return summary
    }

    @discardableResult
    func receiveExternalPackage(_ url: URL) -> Bool {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let directory = SandboxPathManager.backupIncomingURL
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let destination = directory.appendingPathComponent("\(UUID().uuidString).\(BackupPackageFormat.fileExtension)")
            try FileManager.default.copyItem(at: url, to: destination)
            presentRestore(url: destination)
            return true
        } catch {
            lastError = "无法读取备份包"
            ErrorLogger.shared.log(.backupInvalidPackage("无法复制外部备份包"), context: "BackupRestore.receive")
            return false
        }
    }

    // MARK: - Private

    private func beginWork() throws {
        guard !isBusy else { throw AppError.fileSystemError("已有导入或备份任务正在进行") }
        try activityGate.beginBackup()
        isBusy = true
        lastError = nil
        cancelFlag.reset()
    }

    private func endWork() {
        isBusy = false
        progress = nil
        activityGate.endBackup()
        if presentation == nil {
            discardPreparedPackage()
        }
    }

    private func catalog(for url: URL) async throws -> BackupCatalog {
        if preparedSource == url, let preparedCatalog {
            return preparedCatalog
        }
        discardPreparedPackage()
        let directory = SandboxPathManager.backupExtractURL.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let cancelled = cancelFlag
        let catalog = try await runOffMain {
            if cancelled.isCancelled() { throw AppError.backupCancelled }
            return try BackupPackageCodec.extract(zipURL: url, to: directory)
        }
        preparedDirectory = directory
        preparedSource = url
        preparedCatalog = catalog
        return catalog
    }

    private func withSecurityScope<T>(_ url: URL, _ body: () async throws -> T) async throws -> T {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        return try await body()
    }

    private func runOffMain<T: Sendable>(_ work: @Sendable @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    continuation.resume(returning: try work())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    private static func fileStamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }
}

private final class BackupCancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    func reset() {
        lock.lock()
        cancelled = false
        lock.unlock()
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    func isCancelled() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }
}
