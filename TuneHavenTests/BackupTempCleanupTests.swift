import Foundation
import Testing
@testable import TuneHaven

@MainActor
@Suite("备份临时目录清理")
struct BackupTempCleanupTests {
    @Test("冷启动只清空 export、incoming、extract")
    func testLaunchCleanupRemovesOnlyBackupTemps() throws {
        let fixture = try BackupTempFixture()
        defer { fixture.cleanup() }
        try fixture.write("old", at: fixture.directories.export.appendingPathComponent("old.tunehaven"))
        try fixture.write("in", at: fixture.directories.incoming.appendingPathComponent("in.tunehaven"))
        let unpacked = fixture.directories.extract.appendingPathComponent("session", isDirectory: true)
        try FileManager.default.createDirectory(at: unpacked, withIntermediateDirectories: true)
        try fixture.write("pkg", at: unpacked.appendingPathComponent("manifest.json"))
        let wifi = fixture.root.appendingPathComponent("wifi_upload", isDirectory: true)
        try FileManager.default.createDirectory(at: wifi, withIntermediateDirectories: true)
        try fixture.write("upload", at: wifi.appendingPathComponent("song.mp3"))
        let exportTemp = fixture.root.appendingPathComponent("export_temp", isDirectory: true)
        try FileManager.default.createDirectory(at: exportTemp, withIntermediateDirectories: true)
        try fixture.write("share", at: exportTemp.appendingPathComponent("note.txt"))

        let removed = BackupTempDirectory.cleanupOnLaunch(fixture.directories)
        #expect(removed == 3)
        #expect(fixture.names(in: fixture.directories.export).isEmpty)
        #expect(fixture.names(in: fixture.directories.incoming).isEmpty)
        #expect(fixture.names(in: fixture.directories.extract).isEmpty)
        #expect(FileManager.default.fileExists(atPath: fixture.directories.export.path))
        #expect(fixture.names(in: wifi) == ["song.mp3"])
        #expect(fixture.names(in: exportTemp) == ["note.txt"])
    }

    @Test("正式三个目录名与 SandboxPathManager 一致")
    func testLiveDirectoryNames() {
        let live = BackupTempDirectory.live
        #expect(live.export.lastPathComponent == "backup_export")
        #expect(live.incoming.lastPathComponent == "backup_incoming")
        #expect(live.extract.lastPathComponent == "backup_extract")
        #expect(live.export == SandboxPathManager.backupExportURL)
        #expect(live.incoming == SandboxPathManager.backupIncomingURL)
        #expect(live.extract == SandboxPathManager.backupExtractURL)
    }

    @Test("清理不会删除目录本身，也不把文件当成目录")
    func testRemoveContentsLeavesTheDirectoryAndSkipsFiles() throws {
        let fixture = try BackupTempFixture()
        defer { fixture.cleanup() }
        let file = fixture.root.appendingPathComponent("not-a-dir.tunehaven")
        try fixture.write("keep", at: file)
        #expect(BackupTempDirectory.removeContents(of: file) == 0)
        #expect(try Data(contentsOf: file) == Data("keep".utf8))

        let kept = fixture.directories.export.appendingPathComponent("keep.tunehaven")
        try fixture.write("new", at: kept)
        try fixture.write("old", at: fixture.directories.export.appendingPathComponent("old.tunehaven"))
        let removed = BackupTempDirectory.removeContents(of: fixture.directories.export, keeping: kept)
        #expect(removed == 1)
        #expect(fixture.names(in: fixture.directories.export) == ["keep.tunehaven"])
        #expect(FileManager.default.fileExists(atPath: fixture.directories.export.path))
    }

    @Test("缺失目录的冷启动清理是空操作")
    func testLaunchCleanupMissingDirectories() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("backup-missing-\(UUID().uuidString)", isDirectory: true)
        let locations = BackupTempDirectory(
            export: root.appendingPathComponent("backup_export"),
            incoming: root.appendingPathComponent("backup_incoming"),
            extract: root.appendingPathComponent("backup_extract")
        )
        #expect(BackupTempDirectory.cleanupOnLaunch(locations) == 0)
    }

    @Test("导出前删掉旧包，且不碰 incoming 和 extract")
    func testExportDropsPreviousPackages() async throws {
        let fixture = try BackupTempFixture()
        defer { fixture.cleanup() }
        try fixture.write("old", at: fixture.directories.export.appendingPathComponent("old.tunehaven"))
        let stale = fixture.directories.export.appendingPathComponent("stage-stale", isDirectory: true)
        try FileManager.default.createDirectory(at: stale, withIntermediateDirectories: true)
        try fixture.write("blob", at: stale.appendingPathComponent("blob.bin"))
        try fixture.write("in", at: fixture.directories.incoming.appendingPathComponent("keep.tunehaven"))
        try fixture.write("ex", at: fixture.directories.extract.appendingPathComponent("session.txt"))

        let first = try await fixture.service.export(includeAudio: false)
        #expect(first.lastPathComponent.hasSuffix(".tunehaven"))
        #expect(!FileManager.default.fileExists(atPath: fixture.directories.export.appendingPathComponent("old.tunehaven").path))
        #expect(!FileManager.default.fileExists(atPath: stale.path))
        #expect(fixture.names(in: fixture.directories.export).count == 1)
        #expect(fixture.names(in: fixture.directories.incoming) == ["keep.tunehaven"])
        #expect(fixture.names(in: fixture.directories.extract) == ["session.txt"])

        let second = try await fixture.service.export(includeAudio: false)
        let names = fixture.names(in: fixture.directories.export)
        #expect(names.count == 1)
        #expect(names == [second.lastPathComponent])
        #expect(FileManager.default.fileExists(atPath: second.path))
        if first.path != second.path {
            #expect(!FileManager.default.fileExists(atPath: first.path))
        }
    }

    @Test("外部副本只认 incoming 目录内部")
    func testContainsFileStaysInsideIncoming() throws {
        let fixture = try BackupTempFixture()
        defer { fixture.cleanup() }
        let inside = fixture.directories.incoming.appendingPathComponent("a.tunehaven")
        let outside = fixture.root.appendingPathComponent("a.tunehaven")
        #expect(BackupTempDirectory.containsFile(inside, in: fixture.directories.incoming))
        #expect(!BackupTempDirectory.containsFile(outside, in: fixture.directories.incoming))
        #expect(!BackupTempDirectory.containsFile(fixture.directories.incoming, in: fixture.directories.incoming))
    }

    @Test("连续从外部打开只保留最新副本")
    func testStagingReplacesPreviousIncomingCopy() throws {
        let fixture = try BackupTempFixture()
        defer { fixture.cleanup() }
        let firstSource = try fixture.makePackage()
        let secondSource = try fixture.makePackage()
        let first = fixture.service.stageExternalPackage(firstSource)
        let second = fixture.service.stageExternalPackage(secondSource)
        #expect(first != nil)
        #expect(second != nil)
        #expect(fixture.names(in: fixture.directories.incoming) == [second!.lastPathComponent])
        #expect(FileManager.default.fileExists(atPath: firstSource.path))
        #expect(FileManager.default.fileExists(atPath: secondSource.path))
    }

    @Test("复制失败时保留已有 incoming 副本")
    func testFailedStageKeepsExistingCopy() throws {
        let fixture = try BackupTempFixture()
        defer { fixture.cleanup() }
        let existing = fixture.directories.incoming.appendingPathComponent("keep.tunehaven")
        try fixture.write("keep", at: existing)
        let missing = fixture.root.appendingPathComponent("missing.tunehaven")
        #expect(fixture.service.stageExternalPackage(missing) == nil)
        #expect(FileManager.default.fileExists(atPath: existing.path))
    }

    @Test("恢复成功后删除 incoming 副本，原文件和再次恢复不受影响")
    func testRestoreSuccessDeletesIncomingCopy() async throws {
        let fixture = try BackupTempFixture()
        defer { fixture.cleanup() }
        let source = try fixture.makePackage()
        let staged = try #require(fixture.service.stageExternalPackage(source))
        fixture.service.presentRestore(url: staged)
        let summary = try await fixture.service.restore(
            url: staged,
            mode: .preferencesOnly,
            resolution: .recommended
        )
        #expect(summary.preferencesRestored)
        #expect(fixture.names(in: fixture.directories.incoming).isEmpty)
        #expect(FileManager.default.fileExists(atPath: source.path))
        let again = try await fixture.service.restore(
            url: staged,
            mode: .preferencesOnly,
            resolution: .recommended
        )
        #expect(again.preferencesRestored)
        #expect(fixture.names(in: fixture.directories.incoming).isEmpty)
    }

    @Test("取消恢复后删除 incoming 副本，解包缓存仍可重试")
    func testCancelDeletesIncomingCopy() async throws {
        let fixture = try BackupTempFixture()
        defer { fixture.cleanup() }
        var cancelOnce = true
        fixture.service.onLibraryWillChange = { _ in
            if cancelOnce {
                cancelOnce = false
                fixture.service.cancel()
            }
        }
        let source = try fixture.makePackage()
        let staged = try #require(fixture.service.stageExternalPackage(source))
        fixture.service.presentRestore(url: staged)
        await #expect(throws: AppError.backupCancelled) {
            try await fixture.service.restore(url: staged, mode: .merge, resolution: .recommended)
        }
        #expect(fixture.names(in: fixture.directories.incoming).isEmpty)
        #expect(FileManager.default.fileExists(atPath: source.path))
        let summary = try await fixture.service.restore(url: staged, mode: .merge, resolution: .recommended)
        #expect(summary.preferencesRestored)
    }

    @Test("无效包在关闭恢复页之前保留副本")
    func testInvalidPackageKeptUntilDismiss() async throws {
        let fixture = try BackupTempFixture()
        defer { fixture.cleanup() }
        let source = fixture.root.appendingPathComponent("bad.tunehaven")
        try fixture.write("nope", at: source)
        let staged = try #require(fixture.service.stageExternalPackage(source))
        fixture.service.presentRestore(url: staged)
        await #expect(throws: AppError.self) {
            try await fixture.service.restore(url: staged, mode: .preferencesOnly, resolution: .recommended)
        }
        #expect(FileManager.default.fileExists(atPath: staged.path))
        fixture.service.handlePresentationChange(to: nil)
        #expect(!FileManager.default.fileExists(atPath: staged.path))
        #expect(FileManager.default.fileExists(atPath: source.path))
        #expect(fixture.service.presentation == nil)
    }

    @Test("关闭恢复页会删掉 incoming 副本和解包目录")
    func testDismissRestoreDeletesIncomingAndExtract() async throws {
        let fixture = try BackupTempFixture()
        defer { fixture.cleanup() }
        let source = try fixture.makePackage()
        let staged = try #require(fixture.service.stageExternalPackage(source))
        fixture.service.presentRestore(url: staged)
        _ = try await fixture.service.inspect(url: staged)
        #expect(!fixture.names(in: fixture.directories.extract).isEmpty)
        fixture.service.handlePresentationChange(to: nil)
        #expect(fixture.names(in: fixture.directories.incoming).isEmpty)
        #expect(fixture.names(in: fixture.directories.extract).isEmpty)
        #expect(FileManager.default.fileExists(atPath: source.path))
    }

    @Test("旧恢复页先关掉时，保留还没弹出的新副本")
    func testDismissKeepsPendingStagedPackage() throws {
        let fixture = try BackupTempFixture()
        defer { fixture.cleanup() }
        let firstSource = try fixture.makePackage()
        let secondSource = try fixture.makePackage()
        let first = try #require(fixture.service.stageExternalPackage(firstSource))
        fixture.service.presentRestore(url: first)
        #expect(fixture.service.shouldReleaseExternalModal)
        let second = try #require(fixture.service.stageExternalPackage(secondSource))
        #expect(fixture.service.shouldReleaseExternalModal == false)
        fixture.service.handlePresentationChange(to: nil)
        #expect(FileManager.default.fileExists(atPath: second.path))
        #expect(!FileManager.default.fileExists(atPath: first.path))
        fixture.service.presentRestore(url: second)
        #expect(fixture.service.shouldReleaseExternalModal)
        fixture.service.handlePresentationChange(to: nil)
        #expect(!FileManager.default.fileExists(atPath: second.path))
    }

    @Test("关闭导出页不会删除 incoming 副本")
    func testDismissExportKeepsIncoming() throws {
        let fixture = try BackupTempFixture()
        defer { fixture.cleanup() }
        let kept = fixture.directories.incoming.appendingPathComponent("keep.tunehaven")
        try fixture.write("keep", at: kept)
        fixture.service.presentExport()
        fixture.service.handlePresentationChange(to: nil)
        #expect(FileManager.default.fileExists(atPath: kept.path))
    }

    @Test("恢复进行中关闭页面，结束后再删除 incoming 副本")
    func testDismissDuringRestoreDeletesIncomingWhenIdle() async throws {
        let fixture = try BackupTempFixture()
        defer { fixture.cleanup() }
        let source = try fixture.makePackage()
        let staged = try #require(fixture.service.stageExternalPackage(source))
        fixture.service.presentRestore(url: staged)
        fixture.service.onLibraryWillChange = { _ in
            #expect(fixture.service.isBusy)
            fixture.service.handlePresentationChange(to: nil)
            #expect(FileManager.default.fileExists(atPath: staged.path))
        }
        await #expect(throws: AppError.backupCancelled) {
            try await fixture.service.restore(url: staged, mode: .merge, resolution: .recommended)
        }
        #expect(fixture.names(in: fixture.directories.incoming).isEmpty)
        #expect(fixture.service.presentation == nil)
    }
}

@MainActor
final class BackupTempFixture {
    let root: URL
    let directories: BackupTempDirectory
    let service: BackupRestoreService
    let library: InMemoryBackupLibrary

    init(snapshot: BackupLibrarySnapshot = BackupTestFiles.snapshot(songs: [])) throws {
        root = try BackupTestFiles.makeRoot()
        let export = root.appendingPathComponent("backup_export", isDirectory: true)
        let incoming = root.appendingPathComponent("backup_incoming", isDirectory: true)
        let extract = root.appendingPathComponent("backup_extract", isDirectory: true)
        let music = root.appendingPathComponent("Music", isDirectory: true)
        let lyrics = root.appendingPathComponent("Lyrics", isDirectory: true)
        let covers = root.appendingPathComponent("Covers", isDirectory: true)
        for directory in [export, incoming, extract, music, lyrics, covers] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        directories = BackupTempDirectory(export: export, incoming: incoming, extract: extract)
        library = InMemoryBackupLibrary(snapshot: snapshot)
        service = BackupRestoreService(
            library: library,
            activityGate: BackupActivityGate(),
            layout: BackupFileLayout(musicDirectory: music, lyricsDirectory: lyrics, coverDirectory: covers),
            directories: directories
        )
    }

    func cleanup() {
        BackupTestFiles.remove(root)
    }

    func write(_ text: String, at url: URL) throws {
        try Data(text.utf8).write(to: url)
    }

    func names(in url: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []).sorted()
    }

    func makePackage() throws -> URL {
        let url = root.appendingPathComponent("outside-\(UUID().uuidString).tunehaven")
        try BackupPackageCodec.write(draft: BackupTestFiles.draft(), to: url, stagingParent: root)
        return url
    }
}
