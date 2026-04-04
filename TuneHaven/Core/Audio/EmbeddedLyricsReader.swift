import AVFoundation
import Foundation

final class EmbeddedLyricsReader: EmbeddedLyricsReading, Sendable {
    private static let lyricsIdentifiers: Set<AVMetadataIdentifier> = [
        .id3MetadataUnsynchronizedLyric,
        .iTunesMetadataLyrics
    ]

    func readEmbeddedLyrics(from fileURL: URL) async -> String? {
        let asset = AVURLAsset(url: fileURL)
        guard let metadata = try? await asset.load(.metadata) else { return nil }

        for item in metadata {
            guard let id = item.identifier, Self.lyricsIdentifiers.contains(id) else { continue }
            if let text = try? await item.load(.stringValue), !text.isEmpty {
                return text
            }
        }
        return nil
    }
}
