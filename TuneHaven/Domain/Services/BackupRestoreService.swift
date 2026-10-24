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
    private let directories: BackupTempDirectory
    private let cancelFlag = BackupCancelFlag()
    private var preparedDirectory: URL?
    private var preparedSource: URL?
    private var preparedCatalog: BackupCatalog?
    private var extractInFlight = 0
    private var purgeIncomingWhenIdle = false
    /// 已复制、但恢复页还没弹出的 incoming 文件。关掉旧页面时不能把它删掉。
    private var pendingStagedURL: URL?

    var shouldReleaseExternalModal: Bool {
        pendingStagedURL == nil
    }

    var onLibraryWillChange: (@MainActor (BackupRestoreMode) async -> Void)?
    var onPreferencesApplied: (@MainActor (BackupPreferences) -> Void)?
    var onLibraryChanged: (@MainActor (BackupRestoreMode) async -> Void)?

    init(
        library: BackupLibraryApplying,
        activityGate: BackupActivityGate,
        layout: BackupFileLayout,
        directories: BackupTempDirectory = .live,
        onLibraryWillChange: (@MainActor (BackupRestoreMode) async -> Void)? = nil,
        onPreferencesApplied: (@MainActor (BackupPreferences) -> Void)? = nil,
        onLibraryChanged: (@MainActor (BackupRestoreMode) async -> Void)? = nil
    ) {
        self.library = library
        self.activityGate = activityGate
        self.layout = layout
        self.directories = directories
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
        if let url, let pendingStagedURL, BackupTempDirectory.sameFile(url, pendingStagedURL) {
            self.pendingStagedURL = nil
        }
        presentation = BackupPresentation(id: UUID(), kind: .restore, packageURL: url)
    }

    func cancel() {
        cancelFlag.cancel()
    }

    /// 恢复页被系统关掉时调用。忙或仍在解包时先标记，等工作结束后再删 incoming 副本。
    func handlePresentationChange(to newValue: BackupPresentation?) {
        if let newValue {
            presentation = newValue
            return
        }
        let wasRestore = presentation?.kind == .restore
        cancel()
        presentation = nil
        if wasRestore {
            purgeIncomingWhenIdle = true
        }
        if !isBusy && extractInFlight == 0 {
            discardPreparedPackage()
            if wasRestore {
                removeIncomingCopies()
                purgeIncomingWhenIdle = false
            }
        }
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
        if draft.catalog.manifest.payloadBytes > Int64(BackupPackageFormat.maxZipOffset) {
            throw AppError.backupInvalidPackage("备份超过 4GB，请关闭「包含音频」后重试")
        }
        // 确认这次导出会继续之后，再清掉旧包。isBusy 已挡住另一次导出。
        // 删除和打包都在后台，但 export() 返回前完成。只动 export。
        // 快照失败或超过 4GB 时保留上一份包。
        let exportDirectory = directories.export
        let destination = exportDirectory
            .appendingPathComponent("TuneHaven-\(Self.fileStamp()).\(BackupPackageFormat.fileExtension)")
        progress = BackupProgress(phase: "正在打包", completed: 0, total: max(draft.files.count, 1))
        let cancelled = cancelFlag
        try await runOffMain {
            BackupTempDirectory.removeContents(of: exportDirectory)
            try BackupPackageCodec.write(
                draft: draft,
                to: destination,
                stagingParent: exportDirectory,
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
        var committed = false
        do {
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
            committed = true
            onPreferencesApplied?(plan.snapshot.preferences)
            if mode != .preferencesOnly {
                await onLibraryChanged?(mode)
            }
            progress = BackupProgress(phase: "恢复完成", completed: 1, total: 1)
            removeIncomingCopies(preservingNewerThan: url)
            return summary
        } catch {
            if committed || (error as? AppError) == .backupCancelled {
                removeIncomingCopies(preservingNewerThan: url)
            }
            throw error
        }
    }

    /// 把外部备份复制到 incoming。不弹出页面。空闲时会先清掉目录里的旧副本。
    func stageExternalPackage(_ url: URL) -> URL? {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let directory = directories.incoming
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let destination = directory.appendingPathComponent("\(UUID().uuidString).\(BackupPackageFormat.fileExtension)")
            try FileManager.default.copyItem(at: url, to: destination)
            if !isBusy && extractInFlight == 0 {
                BackupTempDirectory.removeContents(of: directory, keeping: destination)
            }
            pendingStagedURL = destination
            return destination
        } catch {
            lastError = "无法读取备份包"
            ErrorLogger.shared.log(.backupInvalidPackage("无法复制外部备份包"), context: "BackupRestore.stage")
            return nil
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
        purgePendingIncomingIfIdle()
    }

    private func removeIncomingCopies() {
        BackupTempDirectory.removeContents(of: directories.incoming, keeping: pendingStagedURL)
    }

    /// 删掉 incoming 里的副本。还没弹出的新副本，或恢复页已经换成的另一份，留下。
    private func removeIncomingCopies(preservingNewerThan url: URL) {
        let keep = incomingFileToKeep(besides: url)
        BackupTempDirectory.removeContents(of: directories.incoming, keeping: keep)
    }

    private func incomingFileToKeep(besides url: URL) -> URL? {
        let candidates = [pendingStagedURL, presentation?.packageURL]
        for candidate in candidates {
            guard let candidate,
                  !BackupTempDirectory.sameFile(candidate, url),
                  BackupTempDirectory.containsFile(candidate, in: directories.incoming) else {
                continue
            }
            return candidate
        }
        return nil
    }

    private func purgePendingIncomingIfIdle() {
        guard purgeIncomingWhenIdle, !isBusy, extractInFlight == 0 else { return }
        purgeIncomingWhenIdle = false
        discardPreparedPackage()
        removeIncomingCopies()
    }

    private func catalog(for url: URL) async throws -> BackupCatalog {
        if preparedSource == url, let preparedCatalog {
            return preparedCatalog
        }
        discardPreparedPackage()
        extractInFlight += 1
        defer {
            extractInFlight -= 1
            purgePendingIncomingIfIdle()
        }
        let directory = directories.extract.appendingPathComponent(UUID().uuidString, isDirectory: true)
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
