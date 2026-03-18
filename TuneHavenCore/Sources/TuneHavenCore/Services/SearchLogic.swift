import Foundation

/// 搜索逻辑（纯 Foundation 实现，提取自 SearchService）
public enum SearchLogic {

    /// 全局搜索
    /// - Parameters:
    ///   - query: 搜索关键词（前缀匹配，大小写不敏感）
    ///   - songs: 歌曲列表
    /// - Returns: 搜索结果（含歌曲、艺术家分组、专辑分组）
    public static func search(query: String, in songs: [Song]) -> SearchResult {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else {
            return SearchResult(songs: [], artists: [], albums: [], totalSongCount: 0, totalArtistCount: 0, totalAlbumCount: 0)
        }

        let matched = songs.filter {
            $0.title.lowercased().hasPrefix(q) ||
            $0.artist.lowercased().hasPrefix(q) ||
            $0.album.lowercased().hasPrefix(q)
        }

        var artistCounts: [String: (songs: Int, albums: Set<String>)] = [:]
        for song in matched {
            var g = artistCounts[song.artist] ?? (0, [])
            g.songs += 1
            g.albums.insert(song.album)
            artistCounts[song.artist] = g
        }
        let artists = artistCounts
            .map { ArtistGroup(name: $0.key, songCount: $0.value.songs, albumCount: $0.value.albums.count) }
            .sorted { $0.name < $1.name }

        var albumData: [String: (artist: String, year: Int?, count: Int, cover: String?)] = [:]
        for song in matched {
            let key = "\(song.artist)/\(song.album)"
            var g = albumData[key] ?? (song.artist, song.metadata.year, 0, song.coverImagePath)
            g.count += 1
            albumData[key] = g
        }
        let albums = albumData
            .map { AlbumGroup(
                name: String($0.key.split(separator: "/").last ?? ""),
                artist: $0.value.artist,
                year: $0.value.year,
                songCount: $0.value.count,
                coverImagePath: $0.value.cover
            )}
            .sorted { $0.name < $1.name }

        return SearchResult(
            songs: matched,
            artists: artists,
            albums: albums,
            totalSongCount: matched.count,
            totalArtistCount: artists.count,
            totalAlbumCount: albums.count
        )
    }
}
