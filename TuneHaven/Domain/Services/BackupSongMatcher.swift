import Foundation

enum BackupSongMatcher {
    static func normalize(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func normalizeAlbum(_ raw: String) -> String {
        let value = normalize(raw)
        if value.isEmpty || value == normalize(SongDefaults.unknownAlbum) {
            return ""
        }
        return value
    }

    static func isReservedPlaylistName(_ name: String) -> Bool {
        let normalized = normalize(name)
        return normalized == normalize(SystemPlaylistName.favorites)
            || normalized == normalize(SystemPlaylistName.recentlyPlayed)
    }

    /// 主匹配：标题 + 艺人 + 专辑 + 时长。未命中时兜底标题 + 艺人。
    static func bestMatch(
        title: String,
        artist: String,
        album: String,
        duration: TimeInterval,
        in songs: [Song]
    ) -> Song? {
        let titleKey = normalize(title)
        let artistKey = normalize(artist)
        let pool = songs
            .filter { normalize($0.title) == titleKey && normalize($0.artist) == artistKey }
            .sorted { $0.id.uuidString < $1.id.uuidString }
        guard !pool.isEmpty else { return nil }
        let albumKey = normalizeAlbum(album)
        if let exact = pool.first(where: {
            normalizeAlbum($0.album) == albumKey
                && abs($0.duration - duration) < BackupPackageFormat.durationMatchTolerance
        }) {
            return exact
        }
        return pool[0]
    }

    static func uniqueName(_ name: String, existing: Set<String>) -> String {
        if !existing.contains(normalize(name)) { return name }
        let copy = name + " 副本"
        if !existing.contains(normalize(copy)) { return copy }
        var index = 2
        while existing.contains(normalize("\(copy) \(index)")) {
            index += 1
            if index > 10_000 { return "\(copy) \(UUID().uuidString.prefix(8))" }
        }
        return "\(copy) \(index)"
    }
}
