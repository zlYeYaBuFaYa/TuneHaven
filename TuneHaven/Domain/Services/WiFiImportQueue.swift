import Foundation

/// WiFi 传输收到的文件逐个导入。导入闸门被备份等任务占用时等待，不判失败。
/// 处理 Task 持有队列直到排空，关闭传输页后已收到的文件仍会导入完。
@MainActor
final class WiFiImportQueue: ObservableObject {
    struct Item: Identifiable, Equatable {
        let id: UUID
        let fileName: String
        var status: Status
    }

    enum Status: Equatable {
        case waiting
        case importing
        case imported
        case duplicate
        case failed(String)
    }

    @Published private(set) var items: [Item] = []

    private struct Pending {
        let itemId: UUID
        let fileURL: URL
        let originalFilename: String
    }

    private let retryInterval: Duration
    private let removeFile: @MainActor (URL) -> Void
    private let log = AppLogger.shared
    private weak var importer: WiFiFileImporting?
    private var onImported: (@MainActor () async -> Void)?
    private var pending: [Pending] = []
    private var drainTask: Task<Void, Never>?

    init(
        retryInterval: Duration = .seconds(1),
        removeFile: @escaping @MainActor (URL) -> Void = { try? FileManager.default.removeItem(at: $0) }
    ) {
        self.retryInterval = retryInterval
        self.removeFile = removeFile
    }

    func configure(importer: WiFiFileImporting, onImported: @escaping @MainActor () async -> Void) {
        self.importer = importer
        self.onImported = onImported
    }

    func enqueue(fileURL: URL, originalFilename: String) {
        let id = UUID()
        items.append(Item(id: id, fileName: originalFilename, status: .waiting))
        pending.append(Pending(itemId: id, fileURL: fileURL, originalFilename: originalFilename))
        guard drainTask == nil else { return }
        drainTask = Task { await self.drain() }
    }

    private func drain() async {
        var importedSinceCallback = false
        while !pending.isEmpty {
            let next = pending.removeFirst()
            let status = await process(next)
            setStatus(status, for: next.itemId)
            removeFile(next.fileURL)
            if status == .imported { importedSinceCallback = true }

            if pending.isEmpty, importedSinceCallback {
                importedSinceCallback = false
                await onImported?()
            }
        }
        drainTask = nil
    }

    private func process(_ next: Pending) async -> Status {
        guard let importer else {
            return .failed("导入服务未就绪")
        }
        while importer.isImportBusy {
            try? await Task.sleep(for: retryInterval)
        }
        setStatus(.importing, for: next.itemId)
        // 同一 actor 上，检查闸门与 processWiFiFile 内部占用闸门之间没有挂起点
        let result = await importer.processWiFiFile(tempURL: next.fileURL, originalFilename: next.originalFilename)
        switch result.status {
        case .success, .successIncompleteMetadata:
            return .imported
        case .skippedDuplicate:
            return .duplicate
        case .skippedUnsupportedFormat, .skippedOversize, .failed:
            log.error("[WiFi] 导入失败: \(next.originalFilename) \(result.errorMessage ?? "")")
            return .failed(result.errorMessage ?? "导入失败")
        }
    }

    private func setStatus(_ status: Status, for id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].status = status
    }
}
