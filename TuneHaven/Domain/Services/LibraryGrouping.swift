import Foundation

enum LibraryGrouping {
    static func artistGroups(from songs: [Song]) -> [ArtistGroup] {
        var groups: [String: (songCount: Int, albums: Set<String>)] = [:]
        for song in songs {
            var g = groups[song.artist] ?? (0, [])
            g.songCount += 1
            g.albums.insert(song.album)
            groups[song.artist] = g
        }
        return groups
            .map { ArtistGroup(name: $0.key, songCount: $0.value.songCount, albumCount: $0.value.albums.count) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func albumGroups(from songs: [Song]) -> [AlbumGroup] {
        var groups: [AlbumKey: (year: Int?, count: Int, cover: String?)] = [:]
        for song in songs {
            let key = AlbumKey(artist: song.artist, album: song.album)
            var g = groups[key] ?? (song.metadata.year, 0, song.coverImagePath)
            g.count += 1
            groups[key] = g
        }
        return groups
            .map { AlbumGroup(name: $0.key.album, artist: $0.key.artist,
                              year: $0.value.year, songCount: $0.value.count,
                              coverImagePath: $0.value.cover) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// 「最近添加」专辑：按专辑内最新导入的歌曲时间倒序（交互设计文档 §4.1）。
    /// 封面取最新导入且有封面的那首；没有「专辑收藏」概念。
    static func recentlyAddedAlbums(from songs: [Song], limit: Int) -> [AlbumGroup] {
        guard limit > 0 else { return [] }
        var groups: [AlbumKey: (latest: Date, year: Int?, count: Int, cover: String?, coverDate: Date)] = [:]
        for song in songs {
            let key = AlbumKey(artist: song.artist, album: song.album)
            var g = groups[key] ?? (song.importDate, song.metadata.year, 0, nil, .distantPast)
            g.count += 1
            g.latest = max(g.latest, song.importDate)
            if let cover = song.coverImagePath, song.importDate >= g.coverDate {
                g.cover = cover
                g.coverDate = song.importDate
            }
            groups[key] = g
        }
        return groups
            .sorted {
                if $0.value.latest != $1.value.latest { return $0.value.latest > $1.value.latest }
                return $0.key.album.localizedCaseInsensitiveCompare($1.key.album) == .orderedAscending
            }
            .prefix(limit)
            .map { AlbumGroup(name: $0.key.album, artist: $0.key.artist,
                              year: $0.value.year, songCount: $0.value.count,
                              coverImagePath: $0.value.cover) }
    }
}
