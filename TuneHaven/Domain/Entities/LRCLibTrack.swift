import Foundation

struct LRCLibTrack: Codable, Identifiable {
    let id: Int
    let trackName: String
    let artistName: String
    let albumName: String
    let duration: Double
    let instrumental: Bool
    let plainLyrics: String?
    let syncedLyrics: String?
}

extension LRCLibTrack {
    var hasSyncedLyrics: Bool {
        guard let s = syncedLyrics else { return false }
        return !s.isEmpty
    }

    var hasAnyLyrics: Bool {
        hasSyncedLyrics || {
            guard let p = plainLyrics else { return false }
            return !p.isEmpty
        }()
    }

    var bestLyrics: String? {
        if hasSyncedLyrics { return syncedLyrics }
        if let p = plainLyrics, !p.isEmpty { return p }
        return nil
    }

    var durationText: String {
        DurationFormatter.format(duration)
    }
}
