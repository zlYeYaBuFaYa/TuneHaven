import Foundation

protocol LyricsAPIProviding {
    func get(
        trackName: String,
        artistName: String,
        albumName: String,
        duration: Int
    ) async throws -> LRCLibTrack?

    func search(
        trackName: String,
        artistName: String?
    ) async throws -> [LRCLibTrack]
}
