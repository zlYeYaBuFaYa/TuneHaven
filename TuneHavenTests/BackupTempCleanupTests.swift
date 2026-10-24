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
