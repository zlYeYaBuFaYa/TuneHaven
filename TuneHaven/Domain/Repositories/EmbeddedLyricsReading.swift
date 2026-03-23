import Foundation

protocol EmbeddedLyricsReading {
    func readEmbeddedLyrics(from fileURL: URL) async -> String?
}
