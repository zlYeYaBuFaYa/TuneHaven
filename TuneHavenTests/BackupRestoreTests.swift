import Foundation
import Testing
@testable import TuneHaven

// MARK: - ZIP

@Suite("备份包打包与解包")
struct BackupPackageTests {
    @Test("CRC32 与标准校验值一致")
    func testCRC32() {
        let data = Data("123456789".utf8)
        #expect(ZIPCRC32.checksum(data) == 0xCBF43926)
    }

    @Test("ZIP 往返保留中文文件名和内容")
    func testZipRoundTrip() throws {
        let root = try BackupTestFiles.makeRoot()
        defer { BackupTestFiles.remove(root) }
        let source = root.appendingPathComponent("src", isDirectory: true)
        try FileManager.default.createDirectory(at: source.appendingPathComponent("audio", isDirectory: true), withIntermediateDirectories: true)
        let payload = Data("你好，TuneHaven".utf8)
        try payload.write(to: source.appendingPathComponent("audio/歌曲.mp3"))
        let zip = root.appendingPathComponent("pack.tunehaven")
        try ZipStoreArchive.zipDirectory(at: source, to: zip)
        let extracted = root.appendingPathComponent("out", isDirectory: true)
        try ZipStoreArchive.unzip(zip, to: extracted)
        let restored = try Data(contentsOf: extracted.appendingPathComponent("audio/歌曲.mp3"))
        #expect(restored == payload)
    }

    @Test("非法路径不会写到目标目录之外")
    func testZipSlipRejected() throws {
        let root = try BackupTestFiles.makeRoot()
        defer { BackupTestFiles.remove(root) }
        let zip = root.appendingPathComponent("bad.tunehaven")
        try ZipStoreArchive.writeDataEntries(
            [ZipStoreArchive.DataEntry(name: "../evil.txt", data: Data("no".utf8))],
            to: zip,
            validateNames: false
        )
        let destination = root.appendingPathComponent("safe", isDirectory: true)
        #expect(throws: AppError.self) {
            try ZipStoreArchive.unzip(zip, to: destination)
        }
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("evil.txt").path))
        #expect(!FileManager.default.fileExists(atPath: destination.appendingPathComponent("evil.txt").path))
    }

    @Test("损坏的包会被拒绝")
    func testCorruptZip() throws {
        let root = try BackupTestFiles.makeRoot()
        defer { BackupTestFiles.remove(root) }
        let zip = root.appendingPathComponent("ok.tunehaven")
        try ZipStoreArchive.writeDataEntries(
            [ZipStoreArchive.DataEntry(name: "manifest.json", data: Data("{}".utf8))],
            to: zip,
            validateNames: true
        )
        var bytes = try Data(contentsOf: zip)
        if let index = bytes.lastIndex(of: UInt8(ascii: "{")) {
            bytes[index] = UInt8(ascii: "x")
        }
        try bytes.write(to: zip)
        #expect(throws: AppError.self) {
            try ZipStoreArchive.unzip(zip, to: root.appendingPathComponent("bad-out", isDirectory: true))
        }
    }

    @Test("含音频的包更大，且 JSON 不含播放次数和密钥")
    func testExportRoundTripAndForbiddenKeys() throws {
        let root = try BackupTestFiles.makeRoot()
        defer { BackupTestFiles.remove(root) }
        let music = root.appendingPathComponent("Music", isDirectory: true)
        let lyrics = root.appendingPathComponent("Lyrics", isDirectory: true)
        let covers = root.appendingPathComponent("Covers", isDirectory: true)
        try FileManager.default.createDirectory(at: music, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: lyrics, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: covers, withIntermediateDirectories: true)
        let song = BackupTestFiles.song(title: "夜曲", favorite: true, relativePath: "night.mp3", fileSize: 4096)
        try Data(repeating: 7, count: 4096).write(to: music.appendingPathComponent("night.mp3"))
        let layout = BackupFileLayout(musicDirectory: music, lyricsDirectory: lyrics, coverDirectory: covers)
        let snapshot = BackupLibrarySnapshot(
            songs: [BackupLibrarySong(song: song)],
            playlists: [],
            groups: [],
            preferences: BackupPreferences(themeStyle: "azure_sky", playMode: 2, speedMemoryMode: 1, lyricsPreferSimplified: false)
        )
        let withAudio = BackupExporter.makePackage(
            snapshot: snapshot,
            includeAudio: true,
            appVersion: "9.9",
            exportedAt: Date(timeIntervalSince1970: 1_700_000_000),
            layout: layout
        )
        let metadataOnly = BackupExporter.makePackage(
            snapshot: snapshot,
            includeAudio: false,
            appVersion: "9.9",
            exportedAt: Date(timeIntervalSince1970: 1_700_000_000),
            layout: layout
        )
        let audioZip = root.appendingPathComponent("audio.tunehaven")
        let metaZip = root.appendingPathComponent("meta.tunehaven")
        try BackupPackageCodec.write(draft: withAudio, to: audioZip, stagingParent: root)
        try BackupPackageCodec.write(draft: metadataOnly, to: metaZip, stagingParent: root)
        let audioSize = BackupTestFiles.byteCount(audioZip)
        let metaSize = BackupTestFiles.byteCount(metaZip)
        #expect(audioSize > metaSize)

        let extracted = root.appendingPathComponent("pkg", isDirectory: true)
        let catalog = try BackupPackageCodec.extract(zipURL: audioZip, to: extracted)
        #expect(catalog.manifest.includesAudio)
        #expect(catalog.manifest.appVersion == "9.9")
        #expect(catalog.songs.count == 1)
        #expect(catalog.songs[0].isFavorite)
        #expect(catalog.songs[0].audioEntry != nil)
        #expect(catalog.preferences.themeStyle == "azure_sky")
        #expect(catalog.preferences.playMode == 2)

        let metaCatalog = try BackupPackageCodec.extract(zipURL: metaZip, to: root.appendingPathComponent("meta", isDirectory: true))
        #expect(metaCatalog.manifest.includesAudio == false)
        #expect(metaCatalog.songs[0].audioEntry == nil)

        let songsJSON = try String(contentsOf: extracted.appendingPathComponent("songs.json"), encoding: .utf8).lowercased()
        let prefsJSON = try String(contentsOf: extracted.appendingPathComponent("preferences.json"), encoding: .utf8).lowercased()
        for blob in [songsJSON, prefsJSON] {
            #expect(!blob.contains("playcount"))
            #expect(!blob.contains("subscription"))
            #expect(!blob.contains("keychain"))
            #expect(!blob.contains("webdav"))
            #expect(!blob.contains("password"))
            #expect(!blob.contains("app_first_launch"))
        }
    }

    @Test("不支持的包版本会被拒绝")
    func testUnsupportedVersion() throws {
        let root = try BackupTestFiles.makeRoot()
        defer { BackupTestFiles.remove(root) }
        var draft = BackupTestFiles.draft()
        draft.catalog.manifest.formatVersion = 99
        let zip = root.appendingPathComponent("old.tunehaven")
        try BackupPackageCodec.write(draft: draft, to: zip, stagingParent: root)
        #expect(throws: AppError.self) {
            try BackupPackageCodec.extract(zipURL: zip, to: root.appendingPathComponent("old-out", isDirectory: true))
        }
    }
}

// MARK: - 匹配与三模式

@Suite("备份恢复三模式")
struct BackupPlannerTests {
    @Test("主匹配优先于更小 UUID 的兜底候选")
    func testPrimaryMatchBeatsFallbackOrder() {
        let early = BackupTestFiles.song(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            title: "夜曲",
            album: "其他",
            duration: 180
        )
        let exact = BackupTestFiles.song(
            id: UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!,
            title: "夜曲",
            album: "十一月的萧邦",
            duration: 180
        )
        let matched = BackupSongMatcher.bestMatch(
            title: " 夜曲 ",
            artist: exact.artist,
            album: "十一月的萧邦",
            duration: 181.9,
            in: [early, exact]
        )
        #expect(matched?.id == exact.id)

        let fallback = BackupSongMatcher.bestMatch(
            title: "夜曲",
            artist: exact.artist,
            album: "完全不同",
            duration: 400,
            in: [exact, early]
        )
        #expect(fallback?.id == early.id)
    }

    @Test("合并：跳过、替换保留播放次数、另存副本")
    func testMergeSongChoices() {
        let playedAt = Date(timeIntervalSince1970: 1_600_000_000)
        let local = BackupTestFiles.song(title: "夜曲", playCount: 7, lastPlayed: playedAt, favorite: false)
        let packageSong = BackupTestFiles.record(id: UUID(), title: "夜曲", favorite: true, audio: "audio/a.mp3")
        let snapshot = BackupTestFiles.snapshot(songs: [local])

        let skip = BackupPlanner.plan(
            local: snapshot,
            package: BackupTestFiles.catalog(songs: [packageSong]),
            mode: .merge,
            resolution: BackupTestFiles.resolution(song: .skip)
        )
        #expect(skip.summary.songsSkipped == 1)
        #expect(skip.summary.songsAdded == 0)
        #expect(skip.copies.isEmpty)
        #expect(skip.snapshot.songs[0].song.playCount == 7)
        #expect(skip.snapshot.songs[0].song.isFavorite == false)

        let replaced = BackupPlanner.plan(
            local: snapshot,
            package: BackupTestFiles.catalog(songs: [packageSong]),
            mode: .merge,
            resolution: BackupTestFiles.resolution(song: .replace)
        )
        #expect(replaced.summary.songsReplaced == 1)
        #expect(replaced.snapshot.songs.count == 1)
        #expect(replaced.snapshot.songs[0].song.id == local.id)
        #expect(replaced.snapshot.songs[0].song.playCount == 7)
        #expect(replaced.snapshot.songs[0].song.lastPlayedDate == playedAt)
        #expect(replaced.snapshot.songs[0].song.isFavorite)
        #expect(replaced.copies.contains { if case .music = $0.destination { return true }; return false })

        let copied = BackupPlanner.plan(
            local: snapshot,
            package: BackupTestFiles.catalog(songs: [packageSong]),
            mode: .merge,
            resolution: BackupTestFiles.resolution(song: .saveCopy)
        )
        #expect(copied.summary.songsDuplicated == 1)
        #expect(copied.snapshot.songs.count == 2)
        #expect(copied.snapshot.songs.contains { $0.song.title.contains("副本") })
        #expect(copied.snapshot.songs.contains { $0.song.playCount == 7 })
    }

    @Test("精简包替换冲突时保留本地音频")
    func testMergeReplaceKeepsLocalAudioWhenPackageHasNone() {
        let local = BackupTestFiles.song(title: "夜曲", relativePath: "keep.mp3")
        let record = BackupTestFiles.record(id: UUID(), title: "夜曲", favorite: true, audio: nil)
        let plan = BackupPlanner.plan(
            local: BackupTestFiles.snapshot(songs: [local]),
            package: BackupTestFiles.catalog(songs: [record]),
            mode: .merge,
            resolution: BackupTestFiles.resolution(song: .replace)
        )
        #expect(plan.snapshot.songs[0].song.fileRelativePath == "keep.mp3")
        #expect(plan.snapshot.songs[0].song.isAudioMissing == false)
        #expect(plan.copies.contains { if case .music = $0.destination { return true }; return false } == false)
    }

    @Test("单条冲突覆盖优先于「应用到全部」关闭时的默认值")
    func testPerItemOverride() {
        let first = BackupTestFiles.song(title: "甲")
        let second = BackupTestFiles.song(title: "乙")
        let firstRecord = BackupTestFiles.record(id: UUID(), title: "甲", audio: nil)
        let secondRecord = BackupTestFiles.record(id: UUID(), title: "乙", audio: nil)
        var resolution = BackupTestFiles.resolution(song: .replace)
        resolution.applySongChoiceToAll = false
        resolution.songOverrides = [firstRecord.id: .skip]
        let plan = BackupPlanner.plan(
            local: BackupTestFiles.snapshot(songs: [first, second]),
            package: BackupTestFiles.catalog(songs: [firstRecord, secondRecord]),
            mode: .merge,
            resolution: resolution
        )
        #expect(plan.summary.songsSkipped == 1)
        #expect(plan.summary.songsReplaced == 1)
        #expect(plan.snapshot.songs.first { $0.id == first.id }?.song.playCount == first.playCount)
    }

    @Test("歌单合并追加新歌，系统歌单名不导入")
    func testPlaylistMergeAndReservedName() {
        let song = BackupTestFiles.song(title: "夜曲")
        let extra = BackupTestFiles.record(id: UUID(), title: "晴天", audio: nil)
        let existingRecord = BackupTestFiles.record(id: song.id, title: "夜曲", audio: nil)
        var playlist = BackupTestFiles.playlistRecord(name: "通勤", songIDs: [existingRecord.id, extra.id])
        playlist.groupName = "出行"
        let reserved = BackupTestFiles.playlistRecord(name: "我喜欢", songIDs: [existingRecord.id])
        let localPlaylist = BackupLibraryPlaylist(
            id: UUID(),
            name: "通勤",
            description: nil,
            isSystem: false,
            systemTypeRaw: SystemPlaylistType.normal.rawValue,
            groupId: nil,
            sortOrder: 0,
            createdAt: Date(timeIntervalSince1970: 1_500_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_500_000_000),
            songIds: [song.id]
        )
        let plan = BackupPlanner.plan(
            local: BackupLibrarySnapshot(
                songs: [BackupLibrarySong(song: song)],
                playlists: [localPlaylist],
                groups: [],
                preferences: BackupPreferences()
            ),
            package: BackupTestFiles.catalog(songs: [existingRecord, extra], playlists: [playlist, reserved]),
            mode: .merge,
            resolution: BackupTestFiles.resolution(song: .skip, playlist: .merge)
        )
        #expect(plan.summary.playlistsMerged == 1)
        #expect(plan.summary.playlistsSkipped == 1)
        #expect(plan.summary.songsAdded == 1)
        let merged = plan.snapshot.playlists.first { $0.name == "通勤" }
        #expect(merged?.songIds.count == 2)
        #expect(plan.snapshot.groups.contains { $0.name == "出行" })
        #expect(!plan.snapshot.playlists.contains { $0.name == "我喜欢" && !$0.isSystem })
    }

    @Test("替换曲库清空自建内容并恢复收藏，系统歌单还在")
    func testReplaceLibrary() {
        let old = BackupTestFiles.song(title: "旧歌", playCount: 4)
        let oldGroup = UUID()
        let system = BackupLibraryPlaylist(
            id: UUID(),
            name: "我喜欢",
            description: nil,
            isSystem: true,
            systemTypeRaw: SystemPlaylistType.favorites.rawValue,
            groupId: oldGroup,
            sortOrder: -2,
            createdAt: Date(),
            updatedAt: Date(),
            songIds: []
        )
        let user = BackupLibraryPlaylist(
            id: UUID(),
            name: "旧歌单",
            description: nil,
            isSystem: false,
            systemTypeRaw: 0,
            groupId: nil,
            sortOrder: 1,
            createdAt: Date(),
            updatedAt: Date(),
            songIds: [old.id]
        )
        let incoming = BackupTestFiles.record(id: UUID(), title: "新歌", favorite: true, audio: nil)
        let playlist = BackupTestFiles.playlistRecord(name: "新歌单", songIDs: [incoming.id])
        let plan = BackupPlanner.plan(
            local: BackupLibrarySnapshot(
                songs: [BackupLibrarySong(song: old)],
                playlists: [system, user],
                groups: [BackupLibraryGroup(id: oldGroup, name: "旧组", sortOrder: 0, createdAt: Date())],
                preferences: BackupPreferences(themeStyle: "cloud_white", playMode: 0, speedMemoryMode: 0, lyricsPreferSimplified: true)
            ),
            package: BackupTestFiles.catalog(
                songs: [incoming],
                playlists: [playlist],
                preferences: BackupPreferences(themeStyle: "azure_sky", playMode: 3, speedMemoryMode: 1, lyricsPreferSimplified: false)
            ),
            mode: .replaceLibrary,
            resolution: .recommended
        )
        #expect(plan.snapshot.songs.count == 1)
        #expect(plan.snapshot.songs[0].song.title == "新歌")
        #expect(plan.snapshot.songs[0].song.isFavorite)
        #expect(plan.snapshot.songs[0].song.isAudioMissing)
        #expect(plan.snapshot.songs[0].song.playCount == 0)
        #expect(plan.snapshot.playlists.contains { $0.id == system.id && $0.isSystem && $0.groupId == nil })
        #expect(!plan.snapshot.playlists.contains { $0.name == "旧歌单" })
        #expect(plan.snapshot.playlists.contains { $0.name == "新歌单" })
        #expect(!plan.snapshot.groups.contains { $0.name == "旧组" })
        #expect(plan.snapshot.preferences.themeStyle == "azure_sky")
        #expect(plan.snapshot.preferences.playMode == 3)
        #expect(plan.summary.songsMissingAudio == 1)
    }

    @Test("仅恢复偏好不改曲目")
    func testPreferencesOnly() {
        let song = BackupTestFiles.song(title: "夜曲", relativePath: "keep.mp3")
        let plan = BackupPlanner.plan(
            local: BackupTestFiles.snapshot(songs: [song], theme: "cloud_white"),
            package: BackupTestFiles.catalog(
                songs: [BackupTestFiles.record(id: UUID(), title: "别的歌", audio: "audio/x.mp3")],
                preferences: BackupPreferences(themeStyle: "azure_sky", playMode: 1, speedMemoryMode: 1, lyricsPreferSimplified: false)
            ),
            mode: .preferencesOnly,
            resolution: .recommended
        )
        #expect(plan.copies.isEmpty)
        #expect(plan.snapshot.songs.map(\.song.title) == ["夜曲"])
        #expect(plan.snapshot.songs[0].song.fileRelativePath == "keep.mp3")
        #expect(plan.snapshot.preferences.themeStyle == "azure_sky")
        #expect(plan.snapshot.preferences.lyricsPreferSimplified == false)
        #expect(plan.summary.preferencesRestored)
        #expect(plan.summary.songsAdded == 0)
    }

    @Test("偏好写入不碰无关键")
    func testPreferenceAllowList() {
        let name = "backup-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        defaults.set("secret", forKey: "webdav_password")
        defaults.set("premium", forKey: "subscription_tier")
        BackupPreferenceStore.write(
            BackupPreferences(themeStyle: "azure_sky", playMode: 2, speedMemoryMode: 1, lyricsPreferSimplified: false),
            to: defaults
        )
        #expect(defaults.string(forKey: "webdav_password") == "secret")
        #expect(defaults.string(forKey: "subscription_tier") == "premium")
        #expect(defaults.string(forKey: AppStorageKey.themeStyle) == "azure_sky")
        #expect(defaults.integer(forKey: AppStorageKey.playMode) == 2)
        #expect(defaults.integer(forKey: AppStorageKey.speedMemoryMode) == 1)
        #expect(defaults.object(forKey: AppStorageKey.lyricsPreferSimplified) as? Bool == false)
        defaults.removePersistentDomain(forName: name)
    }
}

// MARK: - 提交与回滚

@Suite("备份提交与失败回滚")
struct BackupCommitTests {
    @Test("提交成功后音频进入曲库")
    func testCommitWritesAudio() async throws {
        let fixture = try BackupCommitFixture()
        defer { fixture.cleanup() }
        let library = InMemoryBackupLibrary(snapshot: BackupTestFiles.snapshot(songs: []))
        let summary = try await BackupCommitter.commit(
            original: library.snapshot,
            plan: fixture.plan,
            packageRoot: fixture.packageRoot,
            layout: fixture.layout,
            library: library,
            isCancelled: { false }
        )
        #expect(summary.songsAdded == 1)
        #expect(library.snapshot.songs.count == 1)
        #expect(library.snapshot.songs[0].song.isAudioMissing == false)
        let relative = library.snapshot.songs[0].song.fileRelativePath
        #expect(relative.hasPrefix("backup-"))
        #expect(!relative.contains("/"))
        let stored = try Data(contentsOf: fixture.layout.url(for: .music(relativePath: relative)))
        #expect(stored == fixture.audioBytes)
        #expect(FileManager.default.fileExists(atPath: fixture.keepURL.path))
    }

    @Test("数据库提交失败时回滚新文件且保留旧曲目")
    func testApplyFailureRollsBack() async throws {
        let fixture = try BackupCommitFixture(existingSong: true)
        defer { fixture.cleanup() }
        let library = InMemoryBackupLibrary(snapshot: fixture.original)
        library.failApply = true
        await #expect(throws: AppError.self) {
            try await BackupCommitter.commit(
                original: fixture.original,
                plan: fixture.plan,
                packageRoot: fixture.packageRoot,
                layout: fixture.layout,
                library: library,
                isCancelled: { false }
            )
        }
        #expect(library.applyCount == 1)
        #expect(library.snapshot.songs.map(\.song.title) == ["旧歌"])
        #expect(FileManager.default.fileExists(atPath: fixture.keepURL.path))
        let names = (try? FileManager.default.contentsOfDirectory(atPath: fixture.layout.musicDirectory.path)) ?? []
        #expect(Set(names) == ["keep.mp3"])
    }

    @Test("包内封面文件缺失时保留本地封面")
    func testMissingCoverKeepsLocalCover() async throws {
        let root = try BackupTestFiles.makeRoot()
        defer { BackupTestFiles.remove(root) }
        let music = root.appendingPathComponent("Music", isDirectory: true)
        let covers = root.appendingPathComponent("Covers", isDirectory: true)
        try FileManager.default.createDirectory(at: music, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: covers, withIntermediateDirectories: true)
        let coverURL = covers.appendingPathComponent("old.jpg")
        try Data("cover".utf8).write(to: coverURL)
        try Data("keep".utf8).write(to: music.appendingPathComponent("keep.mp3"))
        var song = BackupTestFiles.song(title: "夜曲", relativePath: "keep.mp3")
        song.coverImagePath = "old.jpg"
        var record = BackupTestFiles.record(id: UUID(), title: "夜曲", favorite: true, audio: nil)
        record.coverEntry = "covers/missing.jpg"
        let original = BackupTestFiles.snapshot(songs: [song])
        let plan = BackupPlanner.plan(
            local: original,
            package: BackupTestFiles.catalog(songs: [record]),
            mode: .merge,
            resolution: BackupTestFiles.resolution(song: .replace)
        )
        let library = InMemoryBackupLibrary(snapshot: original)
        _ = try await BackupCommitter.commit(
            original: original,
            plan: plan,
            packageRoot: root.appendingPathComponent("package", isDirectory: true),
            layout: BackupFileLayout(
                musicDirectory: music,
                lyricsDirectory: root.appendingPathComponent("Lyrics"),
                coverDirectory: covers
            ),
            library: library,
            isCancelled: { false }
        )
        #expect(library.snapshot.songs[0].song.coverImagePath == "old.jpg")
        #expect(library.snapshot.songs[0].song.fileRelativePath == "keep.mp3")
        #expect(FileManager.default.fileExists(atPath: coverURL.path))
    }

    @Test("取消发生在提交前，曲库和旧文件都不动")
    func testCancelBeforeApply() async throws {
        let fixture = try BackupCommitFixture(existingSong: true)
        defer { fixture.cleanup() }
        let library = InMemoryBackupLibrary(snapshot: fixture.original)
        await #expect(throws: AppError.self) {
            try await BackupCommitter.commit(
                original: fixture.original,
                plan: fixture.plan,
                packageRoot: fixture.packageRoot,
                layout: fixture.layout,
                library: library,
                isCancelled: { true }
            )
        }
        #expect(library.applyCount == 0)
        #expect(library.snapshot.songs.map(\.song.title) == ["旧歌"])
        #expect(FileManager.default.fileExists(atPath: fixture.keepURL.path))
    }

    @Test("仅偏好提交不改音频文件")
    func testPreferencesCommitDoesNotTouchAudio() async throws {
        let root = try BackupTestFiles.makeRoot()
        defer { BackupTestFiles.remove(root) }
        let music = root.appendingPathComponent("Music", isDirectory: true)
        try FileManager.default.createDirectory(at: music, withIntermediateDirectories: true)
        let keep = music.appendingPathComponent("keep.mp3")
        try Data("keep".utf8).write(to: keep)
        let song = BackupTestFiles.song(title: "夜曲", relativePath: "keep.mp3")
        let original = BackupTestFiles.snapshot(songs: [song], theme: "cloud_white")
        let plan = BackupPlanner.plan(
            local: original,
            package: BackupTestFiles.catalog(
                songs: [],
                preferences: BackupPreferences(themeStyle: "azure_sky", playMode: 2, speedMemoryMode: 0, lyricsPreferSimplified: true)
            ),
            mode: .preferencesOnly,
            resolution: .recommended
        )
        let library = InMemoryBackupLibrary(snapshot: original)
        _ = try await BackupCommitter.commit(
            original: original,
            plan: plan,
            packageRoot: root,
            layout: BackupFileLayout(
                musicDirectory: music,
                lyricsDirectory: root.appendingPathComponent("Lyrics"),
                coverDirectory: root.appendingPathComponent("Covers")
            ),
            library: library,
            isCancelled: { false }
        )
        #expect(try Data(contentsOf: keep) == Data("keep".utf8))
        #expect(library.snapshot.songs[0].song.fileRelativePath == "keep.mp3")
        #expect(library.snapshot.preferences.themeStyle == "azure_sky")
    }
}

@MainActor
@Suite("缺失音频挂回")
struct BackupReattachTests {
    @Test("导入同曲时挂回未找到条目")
    func testReattachMissingSong() async {
        let id = UUID()
        let missing = BackupTestFiles.song(
            id: id,
            title: "Mock Title",
            artist: "Mock Artist",
            album: "Mock Album",
            duration: 180,
            relativePath: Song.missingAudioPath(for: id),
            favorite: true,
            playCount: 3
        )
        let repo = MockSongRepository()
        repo.songs = [missing]
        let service = ImportService(
            songRepo: repo,
            fileService: MockFileStorageProviding(),
            coverProcessor: MockCoverImageProcessing(),
            metadataParser: MockAudioMetadataParsing()
        )
        let result = await service.importFromFiles(urls: [URL(fileURLWithPath: "/tmp/a.mp3")]) { _ in }
        #expect(result.successCount == 1)
        #expect(repo.songs.count == 1)
        #expect(repo.songs[0].id == id)
        #expect(repo.songs[0].isAudioMissing == false)
        #expect(repo.songs[0].isFavorite)
        #expect(repo.songs[0].playCount == 3)
    }
}

@Suite("备份与导入互斥")
struct BackupActivityGateTests {
    @Test("备份进行中不能再开始导入")
    func testGateRejectsOverlap() throws {
        let gate = BackupActivityGate()
        try gate.beginBackup()
        #expect(throws: AppError.self) {
            try gate.beginImport()
        }
        gate.endBackup()
        try gate.beginImport()
        gate.endImport()
    }
}

// MARK: - Fixtures

final class InMemoryBackupLibrary: BackupLibraryApplying, @unchecked Sendable {
    var snapshot: BackupLibrarySnapshot
    var failApply = false
    private(set) var applyCount = 0

    init(snapshot: BackupLibrarySnapshot) {
        self.snapshot = snapshot
    }

    func loadSnapshot() async throws -> BackupLibrarySnapshot { snapshot }

    func apply(_ snapshot: BackupLibrarySnapshot) async throws {
        applyCount += 1
        if failApply {
            throw AppError.backupCommitRolledBack("模拟失败")
        }
        self.snapshot = snapshot
    }
}

private struct BackupCommitFixture {
    let root: URL
    let packageRoot: URL
    let layout: BackupFileLayout
    let keepURL: URL
    let audioBytes: Data
    let original: BackupLibrarySnapshot
    let plan: BackupCommitPlan

    init(existingSong: Bool = false) throws {
        root = try BackupTestFiles.makeRoot()
        packageRoot = root.appendingPathComponent("package", isDirectory: true)
        let music = root.appendingPathComponent("Music", isDirectory: true)
        try FileManager.default.createDirectory(at: music, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: packageRoot.appendingPathComponent("audio", isDirectory: true), withIntermediateDirectories: true)
        keepURL = music.appendingPathComponent("keep.mp3")
        try Data("keep".utf8).write(to: keepURL)
        audioBytes = Data("new-audio".utf8)
        let incomingID = UUID()
        let entry = "audio/\(incomingID.uuidString).mp3"
        try audioBytes.write(to: packageRoot.appendingPathComponent(entry))
        layout = BackupFileLayout(
            musicDirectory: music,
            lyricsDirectory: root.appendingPathComponent("Lyrics"),
            coverDirectory: root.appendingPathComponent("Covers")
        )
        let old = BackupTestFiles.song(title: "旧歌", relativePath: "keep.mp3")
        original = BackupTestFiles.snapshot(songs: existingSong ? [old] : [])
        let record = BackupTestFiles.record(id: incomingID, title: "新歌", favorite: true, audio: entry)
        plan = BackupPlanner.plan(
            local: original,
            package: BackupTestFiles.catalog(songs: [record]),
            mode: .replaceLibrary,
            resolution: .recommended
        )
    }

    func cleanup() {
        BackupTestFiles.remove(root)
    }
}

enum BackupTestFiles {
    static func makeRoot() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("backup-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    static func byteCount(_ url: URL) -> Int64 {
        guard let raw = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] else { return 0 }
        if let number = raw as? NSNumber { return number.int64Value }
        return raw as? Int64 ?? 0
    }

    static func song(
        id: UUID = UUID(),
        title: String,
        artist: String = "周杰伦",
        album: String = "十一月的萧邦",
        duration: TimeInterval = 180,
        relativePath: String = "song.mp3",
        favorite: Bool = false,
        playCount: Int = 0,
        lastPlayed: Date? = nil,
        fileSize: Int64 = 128
    ) -> Song {
        Song(
            id: id,
            title: title,
            artist: artist,
            album: album,
            duration: duration,
            fileHash: "hash-\(id.uuidString)",
            fileRelativePath: relativePath,
            coverImagePath: nil,
            lyricsPath: nil,
            lyricsSource: nil,
            metadata: Metadata(format: "mp3", sampleRate: 44100, bitRate: 320, channels: 2, encoder: nil, trackNumber: 1, year: 2005, genre: nil),
            importDate: Date(timeIntervalSince1970: 1_700_000_000),
            fileSize: fileSize,
            playCount: playCount,
            isFavorite: favorite,
            favoriteDate: favorite ? Date(timeIntervalSince1970: 1_700_000_100) : nil,
            lastPlayedDate: lastPlayed
        )
    }

    static func snapshot(songs: [Song], theme: String? = "cloud_white") -> BackupLibrarySnapshot {
        BackupLibrarySnapshot(
            songs: songs.map { BackupLibrarySong(song: $0) },
            playlists: [],
            groups: [],
            preferences: BackupPreferences(themeStyle: theme, playMode: 0, speedMemoryMode: 0, lyricsPreferSimplified: true)
        )
    }

    static func record(id: UUID, title: String, favorite: Bool = false, audio: String?) -> BackupSongRecord {
        BackupSongRecord(
            id: id,
            title: title,
            artist: "周杰伦",
            album: "十一月的萧邦",
            duration: 180,
            fileHash: "pkg-\(id.uuidString)",
            fileSize: 128,
            format: "mp3",
            sampleRate: 44100,
            bitRate: 320,
            channels: 2,
            encoder: nil,
            trackNumber: 1,
            year: 2005,
            genre: nil,
            audioEntry: audio,
            coverEntry: nil,
            lyricsEntry: nil,
            lyricsSource: nil,
            isFavorite: favorite,
            favoriteDate: favorite ? Date(timeIntervalSince1970: 1_700_000_100) : nil,
            importDate: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    static func playlistRecord(name: String, songIDs: [UUID]) -> BackupPlaylistRecord {
        BackupPlaylistRecord(id: UUID(), name: name, description: nil, groupName: nil, sortOrder: 0, songIds: songIDs)
    }

    static func catalog(
        songs: [BackupSongRecord],
        playlists: [BackupPlaylistRecord] = [],
        preferences: BackupPreferences = BackupPreferences(themeStyle: "cloud_white", playMode: 0, speedMemoryMode: 0, lyricsPreferSimplified: true)
    ) -> BackupCatalog {
        BackupCatalog(
            manifest: BackupManifest(
                formatVersion: 1,
                appVersion: "1.0",
                exportedAt: Date(timeIntervalSince1970: 1_700_000_000),
                includesAudio: songs.contains { $0.audioEntry != nil },
                songCount: songs.count,
                playlistCount: playlists.count,
                groupCount: 0,
                payloadBytes: 0
            ),
            preferences: preferences,
            groups: [],
            playlists: playlists,
            songs: songs
        )
    }

    static func resolution(
        song: BackupSongConflictChoice,
        playlist: BackupPlaylistConflictChoice = .merge
    ) -> BackupConflictResolution {
        BackupConflictResolution(
            songChoice: song,
            playlistChoice: playlist,
            applySongChoiceToAll: true,
            applyPlaylistChoiceToAll: true,
            songOverrides: [:],
            playlistOverrides: [:]
        )
    }

    static func draft() -> BackupExportDraft {
        let record = record(id: UUID(), title: "空", favorite: false, audio: nil)
        return BackupExportDraft(
            catalog: catalog(songs: [record]),
            files: []
        )
    }
}
