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
}
