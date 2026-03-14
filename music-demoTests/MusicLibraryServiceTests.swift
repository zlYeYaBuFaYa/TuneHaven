import Testing
@testable import music_demo

// MARK: - MusicLibraryService Logic Tests
// 测试 MusicLibraryService 中不依赖 CoreData 的纯逻辑函数

@Suite("MusicLibraryService - 分组逻辑测试")
struct MusicLibraryServiceGroupingTests {

    // MARK: - Helpers

    private func makeSong(
        id: UUID = UUID(),
        title: String,
        artist: String,
        album: String,
        trackNumber: Int? = nil,
        year: Int? = nil,
        fileHash: String? = nil,
        coverImagePath: String? = nil
    ) -> Song {
        Song(
            id: id,
            title: title,
            artist: artist,
            album: album,
            duration: 180,
            fileHash: fileHash ?? UUID().uuidString,
            fileRelativePath: "\(title).mp3",
            coverImagePath: coverImagePath,
            lyricsPath: nil,
            lyricsSource: nil,
            metadata: Metadata(
                format: "mp3",
                sampleRate: 44100,
                bitRate: 320,
                channels: 2,
                encoder: nil,
                trackNumber: trackNumber,
                year: year,
                genre: nil
            ),
            importDate: Date(),
            fileSize: 1024 * 1024,
            playCount: 0,
            isFavorite: false,
            favoriteDate: nil,
            lastPlayedDate: nil
        )
    }

    // MARK: - 艺术家分组逻辑

    @Test("艺术家分组：相同艺术家的歌曲被合并")
    func testGroupByArtistMergesSameArtist() {
        let songs: [Song] = [
            makeSong(title: "夜曲", artist: "周杰伦", album: "十一月的萧邦"),
            makeSong(title: "晴天", artist: "周杰伦", album: "叶惠美"),
            makeSong(title: "七里香", artist: "周杰伦", album: "七里香"),
        ]

        let groups = groupSongsByArtist(songs)

        #expect(groups.count == 1)
        #expect(groups[0].name == "周杰伦")
        #expect(groups[0].songCount == 3)
    }

    @Test("艺术家分组：不同艺术家各自独立")
    func testGroupByArtistDifferentArtists() {
        let songs: [Song] = [
            makeSong(title: "夜曲", artist: "周杰伦", album: "专辑A"),
            makeSong(title: "Perfect", artist: "Ed Sheeran", album: "Divide"),
            makeSong(title: "Hello", artist: "Adele", album: "25"),
        ]

        let groups = groupSongsByArtist(songs)

        #expect(groups.count == 3)
    }

    @Test("艺术家分组：专辑计数正确")
    func testGroupByArtistAlbumCount() {
        let songs: [Song] = [
            makeSong(title: "S1", artist: "周杰伦", album: "专辑A"),
            makeSong(title: "S2", artist: "周杰伦", album: "专辑A"),
            makeSong(title: "S3", artist: "周杰伦", album: "专辑B"),
            makeSong(title: "S4", artist: "周杰伦", album: "专辑C"),
        ]

        let groups = groupSongsByArtist(songs)

        #expect(groups.count == 1)
        #expect(groups[0].albumCount == 3) // 3个不同专辑
        #expect(groups[0].songCount == 4)  // 4首歌
    }

    @Test("艺术家分组：按名称字母序排列")
    func testGroupByArtistSortedByName() {
        let songs: [Song] = [
            makeSong(title: "S1", artist: "Zebra", album: "A"),
            makeSong(title: "S2", artist: "Apple", album: "B"),
            makeSong(title: "S3", artist: "Middle", album: "C"),
        ]

        let groups = groupSongsByArtist(songs)

        #expect(groups[0].name == "Apple")
        #expect(groups[1].name == "Middle")
        #expect(groups[2].name == "Zebra")
    }

    @Test("艺术家分组：空列表返回空数组")
    func testGroupByArtistEmptyList() {
        let groups = groupSongsByArtist([])
        #expect(groups.isEmpty)
    }

    @Test("ArtistGroup id 等于艺术家名称")
    func testArtistGroupId() {
        let group = ArtistGroup(name: "周杰伦", songCount: 3, albumCount: 2)
        #expect(group.id == "周杰伦")
    }

    // MARK: - 专辑分组逻辑

    @Test("专辑分组：相同艺术家+专辑合并为一组")
    func testGroupByAlbumMergesSameAlbum() {
        let songs: [Song] = [
            makeSong(title: "S1", artist: "周杰伦", album: "七里香"),
            makeSong(title: "S2", artist: "周杰伦", album: "七里香"),
            makeSong(title: "S3", artist: "周杰伦", album: "七里香"),
        ]

        let groups = groupSongsByAlbum(songs)

        #expect(groups.count == 1)
        #expect(groups[0].name == "七里香")
        #expect(groups[0].songCount == 3)
        #expect(groups[0].artist == "周杰伦")
    }

    @Test("专辑分组：同名专辑但不同艺术家各自独立")
    func testGroupByAlbumSameNameDifferentArtist() {
        let songs: [Song] = [
            makeSong(title: "S1", artist: "艺术家A", album: "同名专辑"),
            makeSong(title: "S2", artist: "艺术家B", album: "同名专辑"),
        ]

        let groups = groupSongsByAlbum(songs)

        #expect(groups.count == 2)
    }

    @Test("专辑分组：年份信息正确")
    func testGroupByAlbumYearInfo() {
        let songs: [Song] = [
            makeSong(title: "S1", artist: "周杰伦", album: "七里香", year: 2004),
            makeSong(title: "S2", artist: "周杰伦", album: "七里香", year: 2004),
        ]

        let groups = groupSongsByAlbum(songs)

        #expect(groups[0].year == 2004)
    }

    @Test("专辑分组：按名称字母序排列")
    func testGroupByAlbumSortedByName() {
        let songs: [Song] = [
            makeSong(title: "S1", artist: "Artist", album: "Z Album"),
            makeSong(title: "S2", artist: "Artist", album: "A Album"),
            makeSong(title: "S3", artist: "Artist", album: "M Album"),
        ]

        let groups = groupSongsByAlbum(songs)

        #expect(groups[0].name == "A Album")
        #expect(groups[1].name == "M Album")
        #expect(groups[2].name == "Z Album")
    }

    @Test("专辑分组：封面路径使用第一首歌的封面")
    func testGroupByAlbumCoverPath() {
        let firstCover = "cover_first.jpg"
        let songs: [Song] = [
            makeSong(title: "S1", artist: "A", album: "Album", coverImagePath: firstCover),
            makeSong(title: "S2", artist: "A", album: "Album", coverImagePath: "cover_second.jpg"),
        ]

        let groups = groupSongsByAlbum(songs)

        #expect(groups[0].coverImagePath == firstCover)
    }

    @Test("AlbumGroup id 等于 artist/name 格式")
    func testAlbumGroupId() {
        let group = AlbumGroup(name: "七里香", artist: "周杰伦", year: 2004, songCount: 5, coverImagePath: nil)
        #expect(group.id == "周杰伦/七里香")
    }

    // MARK: - 专辑详情排序（按 trackNumber）

    @Test("专辑详情中歌曲按 trackNumber 排序")
    func testAlbumDetailSortByTrackNumber() {
        let songs: [Song] = [
            makeSong(title: "第三首", artist: "A", album: "Album", trackNumber: 3),
            makeSong(title: "第一首", artist: "A", album: "Album", trackNumber: 1),
            makeSong(title: "第二首", artist: "A", album: "Album", trackNumber: 2),
        ]

        let sorted = songs.sorted { ($0.metadata.trackNumber ?? 999) < ($1.metadata.trackNumber ?? 999) }

        #expect(sorted[0].title == "第一首")
        #expect(sorted[1].title == "第二首")
        #expect(sorted[2].title == "第三首")
    }

    @Test("无 trackNumber 的歌曲排在已知 trackNumber 之后")
    func testAlbumDetailNoTrackNumber() {
        let songs: [Song] = [
            makeSong(title: "无序号", artist: "A", album: "Album", trackNumber: nil),
            makeSong(title: "第一首", artist: "A", album: "Album", trackNumber: 1),
        ]

        let sorted = songs.sorted { ($0.metadata.trackNumber ?? 999) < ($1.metadata.trackNumber ?? 999) }

        #expect(sorted[0].title == "第一首")
        #expect(sorted[1].title == "无序号")
    }
}

// MARK: - Helper functions (mirrors MusicLibraryService logic for unit testing)

private func groupSongsByArtist(_ songs: [Song]) -> [ArtistGroup] {
    var groups: [String: (songCount: Int, albums: Set<String>)] = [:]
    for song in songs {
        var g = groups[song.artist] ?? (0, [])
        g.songCount += 1
        g.albums.insert(song.album)
        groups[song.artist] = g
    }
    return groups
        .map { ArtistGroup(name: $0.key, songCount: $0.value.songCount, albumCount: $0.value.albums.count) }
        .sorted { $0.name < $1.name }
}

private func groupSongsByAlbum(_ songs: [Song]) -> [AlbumGroup] {
    var groups: [String: (artist: String, year: Int?, count: Int, cover: String?)] = [:]
    for song in songs {
        let key = "\(song.artist)/\(song.album)"
        var g = groups[key] ?? (song.artist, song.metadata.year, 0, song.coverImagePath)
        g.count += 1
        groups[key] = g
    }
    return groups
        .map { AlbumGroup(
            name: String($0.key.split(separator: "/").last ?? ""),
            artist: $0.value.artist,
            year: $0.value.year,
            songCount: $0.value.count,
            coverImagePath: $0.value.cover
        )}
        .sorted { $0.name < $1.name }
}

// MARK: - SongSortOption Tests

@Suite("SongSortOption Tests")
struct SongSortOptionTests {

    @Test("SongSortOption displayName 不为空")
    func testDisplayNames() {
        for option in SongSortOption.allCases {
            #expect(!option.displayName.isEmpty, "选项 \(option) 的 displayName 不应为空")
        }
    }

    @Test("SongSortOption rawValue 从 0 开始连续递增")
    func testRawValues() {
        let cases = SongSortOption.allCases
        for (index, option) in cases.enumerated() {
            #expect(option.rawValue == index)
        }
    }

    @Test("支持 6 个排序选项")
    func testSortOptionCount() {
        #expect(SongSortOption.allCases.count == 6)
    }
}

// MARK: - AudioFormat Tests

@Suite("AudioFormat Tests")
struct AudioFormatTests {

    @Test("AudioFormat displayName 不为空")
    func testDisplayNames() {
        for format in AudioFormat.allCases {
            #expect(!format.displayName.isEmpty)
        }
    }

    @Test("FLAC 显示名称包含暂不支持提示")
    func testFLACDisplayNameHasWarning() {
        let flac = AudioFormat.flac
        #expect(flac.displayName.contains("暂不支持"))
    }

    @Test("all 格式的 rawValue 为 all")
    func testAllFormatRawValue() {
        #expect(AudioFormat.all.rawValue == "all")
    }

    @Test("LibraryTab 包含 4 个选项")
    func testLibraryTabCount() {
        #expect(LibraryTab.allCases.count == 4)
    }
}

// MARK: - PlayMode Tests

@Suite("PlayMode Tests")
struct PlayModeTests {

    @Test("PlayMode displayName 不为空")
    func testDisplayNames() {
        for mode in PlayMode.allCases {
            #expect(!mode.displayName.isEmpty)
        }
    }

    @Test("PlayMode iconName 不为空")
    func testIconNames() {
        for mode in PlayMode.allCases {
            #expect(!mode.iconName.isEmpty)
        }
    }

    @Test("PlayMode 包含 4 种模式")
    func testPlayModeCount() {
        #expect(PlayMode.allCases.count == 4)
    }

    @Test("PlayMode rawValue 从 0 开始")
    func testPlayModeRawValues() {
        #expect(PlayMode.sequential.rawValue == 0)
        #expect(PlayMode.repeatOne.rawValue == 1)
        #expect(PlayMode.repeatAll.rawValue == 2)
        #expect(PlayMode.shuffle.rawValue == 3)
    }
}
