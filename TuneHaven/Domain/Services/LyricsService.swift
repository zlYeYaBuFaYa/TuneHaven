import AVFoundation
import Foundation

final class LyricsService {
    static let shared = LyricsService()
    private let log = AppLogger.shared
    private init() {}

    func loadLyrics(for song: Song) async -> LyricsData? {
        log.debug("加载歌词: \(song.title)")
        if let source = song.lyricsSource {
            switch source {
            case .embedded:
                return await loadEmbedded(song: song)
            case .file, .manual:
                if let path = song.lyricsPath {
                    return loadFromFile(relativePath: path)
                }
                return nil
            }
        }
        if let embedded = await loadEmbedded(song: song) { return embedded }
        if let file = loadExternalLRC(songTitle: song.title) { return file }
        log.debug("歌词未找到: \(song.title)")
        return nil
    }

    func parseLRC(_ content: String) -> [LyricsLine] {
        var lines: [LyricsLine] = []
        let rawLines = content.components(separatedBy: "\n")
        for line in rawLines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("[") else { continue }
            let pattern = #"\[(\d{2}):(\d{2})\.(\d{2,3})\](.*)"#
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) else { continue }

            func group(_ i: Int) -> String {
                guard let r = Range(match.range(at: i), in: trimmed) else { return "" }
                return String(trimmed[r])
            }

            let minutes = Double(group(1)) ?? 0
            let seconds = Double(group(2)) ?? 0
            let centiseconds = Double(group(3)) ?? 0
            let divisor: Double = group(3).count == 3 ? 1000 : 100
            let timestamp = minutes * 60 + seconds + centiseconds / divisor
            let text = group(4).trimmingCharacters(in: .whitespaces)
            if !text.isEmpty {
                lines.append(LyricsLine(timestamp: timestamp, text: text))
            }
        }
        return lines.sorted { $0.timestamp < $1.timestamp }
    }

    private func loadEmbedded(song: Song) async -> LyricsData? {
        let url = SandboxPathManager.musicFileURL(relativePath: song.fileRelativePath)
        let asset = AVURLAsset(url: url)
        guard let metadata = try? await asset.load(.metadata) else { return nil }

        for item in metadata {
            guard let id = item.identifier else { continue }
            if id == .id3MetadataUnsynchronizedLyric {
                if let text = try? await item.load(.stringValue), !text.isEmpty {
                    let lines = parseLRC(text)
                    if lines.isEmpty {
                        let plainLines = text.components(separatedBy: "\n").enumerated().map { (i, t) in
                            LyricsLine(timestamp: Double(i) * 3, text: t)
                        }
                        return LyricsData(source: .embedded, lines: plainLines, rawText: text)
                    }
                    return LyricsData(source: .embedded, lines: lines, rawText: text)
                }
            }
        }
        return nil
    }

    private func loadFromFile(relativePath: String) -> LyricsData? {
        let url = SandboxPathManager.lyricsFileURL(relativePath: relativePath)
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let lines = parseLRC(content)
        return LyricsData(source: .file, lines: lines, rawText: content)
    }

    private func loadExternalLRC(songTitle: String) -> LyricsData? {
        let candidates = ["\(songTitle).lrc"]
        for name in candidates {
            let url = SandboxPathManager.lyricsURL.appendingPathComponent(name)
            if let content = try? String(contentsOf: url, encoding: .utf8) {
                let lines = parseLRC(content)
                return LyricsData(source: .file, lines: lines, rawText: content)
            }
        }
        return nil
    }
}
