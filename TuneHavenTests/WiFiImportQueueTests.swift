import Testing
import Foundation
@testable import TuneHaven

// MARK: - Mock

@MainActor
private final class MockWiFiImporter: WiFiFileImporting {
    var isImportBusy = false
    var statuses: [String: ImportFileStatus] = [:]
    var errorMessages: [String: String] = [:]
    private(set) var processed: [String] = []
    private(set) var inFlight = 0
    private(set) var maxInFlight = 0

    func processWiFiFile(tempURL: URL, originalFilename: String) async -> SingleImportResult {
        inFlight += 1
        maxInFlight = max(maxInFlight, inFlight)
        // 让出执行权，若队列不是串行，其他导入会在这里插进来
        try? await Task.sleep(for: .milliseconds(5))
        processed.append(originalFilename)
        inFlight -= 1
        return SingleImportResult(
            fileName: originalFilename,
            status: statuses[originalFilename] ?? .success,
            song: nil,
            errorMessage: errorMessages[originalFilename]
        )
    }
}

@MainActor
private final class Recorder {
    var removed: [URL] = []
    var importedCallbacks = 0
}

@MainActor
private func waitUntil(timeout: Duration = .seconds(2), _ condition: () -> Bool) async {
    let deadline = ContinuousClock.now + timeout
    while !condition() && ContinuousClock.now < deadline {
        try? await Task.sleep(for: .milliseconds(5))
    }
}

private func url(_ name: String) -> URL {
    URL(fileURLWithPath: "/tmp/wifi_upload/\(UUID().uuidString)-\(name)")
}

// MARK: - Tests

@Suite("WiFiImportQueue Tests")
@MainActor
struct WiFiImportQueueTests {

    private func makeQueue(_ importer: MockWiFiImporter, _ recorder: Recorder) -> WiFiImportQueue {
        let queue = WiFiImportQueue(retryInterval: .milliseconds(5)) { recorder.removed.append($0) }
        queue.configure(importer: importer) { recorder.importedCallbacks += 1 }
        return queue
    }

    private func isFinished(_ queue: WiFiImportQueue) -> Bool {
        queue.items.allSatisfy { $0.status != .waiting && $0.status != .importing }
    }

    @Test("连续入队的文件按顺序逐个导入，同一时刻最多一个")
    func testSerialInOrder() async {
        let importer = MockWiFiImporter()
        let recorder = Recorder()
        let queue = makeQueue(importer, recorder)

        for name in ["a.mp3", "b.mp3", "c.mp3"] {
            queue.enqueue(fileURL: url(name), originalFilename: name)
        }
        await waitUntil { importer.processed.count == 3 && isFinished(queue) }

        #expect(importer.processed == ["a.mp3", "b.mp3", "c.mp3"])
        #expect(importer.maxInFlight == 1)
        #expect(queue.items.map(\.status) == [.imported, .imported, .imported])
    }

    @Test("导入结果映射为对应状态，失败带原因")
    func testStatusMapping() async {
        let importer = MockWiFiImporter()
        importer.statuses = [
            "ok.mp3": .success,
            "partial.mp3": .successIncompleteMetadata,
            "dup.mp3": .skippedDuplicate,
            "bad.mp3": .failed,
            "huge.mp3": .skippedOversize
        ]
        importer.errorMessages = ["bad.mp3": "文件读取失败"]
        let recorder = Recorder()
        let queue = makeQueue(importer, recorder)
        let names = ["ok.mp3", "partial.mp3", "dup.mp3", "bad.mp3", "huge.mp3"]

        for name in names { queue.enqueue(fileURL: url(name), originalFilename: name) }
        await waitUntil { importer.processed.count == names.count && isFinished(queue) }

        #expect(queue.items.map(\.status) == [
            .imported, .imported, .duplicate, .failed("文件读取失败"), .failed("导入失败")
        ])
    }

    @Test("每个文件处理后都删除上传临时文件，包括失败和重复")
    func testRemovesEveryTempFile() async {
        let importer = MockWiFiImporter()
        importer.statuses = ["dup.mp3": .skippedDuplicate, "bad.mp3": .failed]
        let recorder = Recorder()
        let queue = makeQueue(importer, recorder)
        let urls = [url("ok.mp3"), url("dup.mp3"), url("bad.mp3")]

        for (u, name) in zip(urls, ["ok.mp3", "dup.mp3", "bad.mp3"]) {
            queue.enqueue(fileURL: u, originalFilename: name)
        }
        await waitUntil { recorder.removed.count == 3 }

        #expect(recorder.removed == urls)
    }

    @Test("闸门被占用时等待，解除后继续导入，不判失败")
    func testWaitsWhileBusy() async {
        let importer = MockWiFiImporter()
        importer.isImportBusy = true
        let recorder = Recorder()
        let queue = makeQueue(importer, recorder)

        queue.enqueue(fileURL: url("a.mp3"), originalFilename: "a.mp3")
        try? await Task.sleep(for: .milliseconds(50))
        #expect(importer.processed.isEmpty)
        #expect(queue.items.first?.status == .waiting)

        importer.isImportBusy = false
        await waitUntil { isFinished(queue) }

        #expect(importer.processed == ["a.mp3"])
        #expect(queue.items.first?.status == .imported)
    }

    @Test("排空后只回调一次；全部重复或失败时不回调")
    func testImportedCallback() async {
        let importer = MockWiFiImporter()
        let recorder = Recorder()
        let queue = makeQueue(importer, recorder)

        queue.enqueue(fileURL: url("a.mp3"), originalFilename: "a.mp3")
        queue.enqueue(fileURL: url("b.mp3"), originalFilename: "b.mp3")
        await waitUntil { isFinished(queue) && recorder.importedCallbacks > 0 }
        try? await Task.sleep(for: .milliseconds(20))
        #expect(recorder.importedCallbacks == 1)

        importer.statuses = ["c.mp3": .skippedDuplicate, "d.mp3": .failed]
        queue.enqueue(fileURL: url("c.mp3"), originalFilename: "c.mp3")
        queue.enqueue(fileURL: url("d.mp3"), originalFilename: "d.mp3")
        await waitUntil { importer.processed.count == 4 && isFinished(queue) }
        try? await Task.sleep(for: .milliseconds(20))
        #expect(recorder.importedCallbacks == 1)
    }

    @Test("未配置导入服务时条目失败，并删除临时文件")
    func testUnconfigured() async {
        let recorder = Recorder()
        let queue = WiFiImportQueue(retryInterval: .milliseconds(5)) { recorder.removed.append($0) }
        let file = url("a.mp3")

        queue.enqueue(fileURL: file, originalFilename: "a.mp3")
        await waitUntil { isFinished(queue) }

        #expect(queue.items.first?.status == .failed("导入服务未就绪"))
        #expect(recorder.removed == [file])
    }
}
