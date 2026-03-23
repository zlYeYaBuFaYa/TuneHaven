import AVFoundation
import Foundation

@MainActor
final class LyricsService: ObservableObject {
    private let log = AppLogger.shared
    private let repo: SongRepository
    private let api: LRCLibAPIClientProtocol

    private static let cooldownKey = "lyrics_match_cooldown"
    private static let cooldownDuration: TimeInterval = 7 * 24 * 3600

    init(repo: SongRepository,
         api: LRCLibAPIClientProtocol) {
        self.repo = repo
        self.api = api
    }

    // MARK: - Load Lyrics (fallthrough chain)

    func loadLyrics(for song: Song) async -> LyricsData? {
        log.debug("加载歌词: \(song.title)")

        // Step 1: DB-specified source
        var triedEmbedded = false
        if let source = song.lyricsSource {
            switch source {
            case .embedded:
                triedEmbedded = true
                if let data = await loadEmbedded(song: song) { return data }
            case .file, .manual:
                if let path = song.lyricsPath,
                   let data = loadFromFile(relativePath: path) { return data }
            }
        }

        // Step 2: Fallback — embedded (skip if already tried)
        if !triedEmbedded, let embedded = await loadEmbedded(song: song) { return embedded }

        // Step 3: Fallback — external LRC files
        let songIdFile = "\(song.id.uuidString).lrc"
        if let data = loadFromFile(relativePath: songIdFile) { return data }
        if let data = loadExternalLRC(songTitle: song.title) { return data }

        // Step 4: Online auto-match
        let autoMatch = UserDefaults.standard.object(forKey: AppStorageKey.autoMatchLyrics) as? Bool ?? true
        if autoMatch {
            if let data = await autoMatchOnline(for: song) { return data }
        }

        // Step 5: Nothing found
        log.debug("歌词未找到: \(song.title)")
        return nil
    }

    // MARK: - Online Auto Match (degraded search chain)

    func autoMatchOnline(for song: Song) async -> LyricsData? {
        guard !isCooldownActive(for: song.id) else { return nil }

        // Level 1: 精确匹配（歌名+艺术家+专辑+时长）
        if let data = try? await exactMatch(song: song) { return data }

        do {
            // Level 2: search API — 歌名 + 艺术家
            if let data = try await searchMatch(title: song.title, artist: song.artist, songId: song.id, songTitle: song.title) {
                return data
            }

            // Level 3: search API — 仅歌名（跳过已知艺术家为空的情况）
            if song.artist != SongDefaults.unknownArtist {
                if let data = try await searchMatch(title: song.title, artist: nil, songId: song.id, songTitle: song.title) {
                    return data
                }
            }

            // Level 4: search API — 简化歌名（去除括号、feat. 等）
            let simplified = simplifyTitle(song.title)
            if simplified != song.title && !simplified.isEmpty {
                if let data = try await searchMatch(title: simplified, artist: nil, songId: song.id, songTitle: song.title) {
                    return data
                }
            }
        } catch {
            log.debug("降级搜索网络错误: \(song.title) - \(error.localizedDescription)")
            return nil
        }

        markCooldown(for: song.id)
        return nil
    }

    private func exactMatch(song: Song) async throws -> LyricsData? {
        let track = try await api.get(
            trackName: song.title,
            artistName: song.artist,
            albumName: song.album,
            duration: Int(song.duration)
        )
        return try await processTrack(track, songId: song.id, songTitle: song.title)
    }

    private func searchMatch(title: String, artist: String?, songId: UUID, songTitle: String) async throws -> LyricsData? {
        let results = try await api.search(trackName: title, artistName: artist)
        let candidates = results.filter { !$0.instrumental && $0.hasAnyLyrics }
        let best = candidates.first(where: { $0.hasSyncedLyrics }) ?? candidates.first
        guard let best else { return nil }
        return try await processTrack(best, songId: songId, songTitle: songTitle)
    }

    private func processTrack(_ track: LRCLibTrack?, songId: UUID, songTitle: String) async throws -> LyricsData? {
        guard let track, !track.instrumental, let lyrics = track.bestLyrics else { return nil }
        cleanupOldLRC(songTitle: songTitle)
        try await saveLyricsFile(lyrics, for: songId)
        let lines = parseLRC(lyrics)
        if lines.isEmpty {
            return LyricsData(source: .file, lines: buildPlainLines(from: lyrics), rawText: lyrics)
        }
        return LyricsData(source: .file, lines: lines, rawText: lyrics)
    }

    private func simplifyTitle(_ title: String) -> String {
        var result = title
        let patterns = [#"\(.*?\)"#, #"（.*?）"#, #"\[.*?\]"#]
        for pattern in patterns {
            result = result.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        let lower = result.lowercased()
        let suffixes = ["feat.", "ft.", "remix", "live", "acoustic", "version", "remastered"]
        for suffix in suffixes {
            if let range = lower.range(of: suffix) {
                result = String(result[result.startIndex..<range.lowerBound])
            }
        }
        return result.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Online Search (manual)

    func searchOnline(title: String, artist: String?) async throws -> [LRCLibTrack] {
        try await api.search(trackName: title, artistName: artist)
    }

    // MARK: - Save Lyrics

    func saveLyrics(_ lrcContent: String, for song: Song) async throws {
        cleanupOldLRC(songTitle: song.title)
        try await saveLyricsFile(lrcContent, for: song.id)
        clearCooldown(for: song.id)
    }

    // MARK: - Import Lyrics File

    func importLyricsFile(url: URL, for song: Song) async throws {
        let didAccess = url.startAccessingSecurityScopedResource()
        if !didAccess {
            log.error("startAccessingSecurityScopedResource 返回 false: \(url.lastPathComponent)，尝试直接读取")
            guard FileManager.default.isReadableFile(atPath: url.path) else {
                throw AppError.lyricsImportFailed("无法访问文件（安全范围授权失败）")
            }
        }
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }

        let content: String
        do {
            content = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw AppError.lyricsImportFailed(error.localizedDescription)
        }

        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AppError.lyricsImportFailed("文件内容为空")
        }

        cleanupOldLRC(songTitle: song.title)
        try await saveLyricsFile(content, for: song.id)
        clearCooldown(for: song.id)
    }

    // MARK: - Delete Lyrics

    func deleteLyrics(for song: Song) async throws {
        let fm = FileManager.default
        let songIdFile = "\(song.id.uuidString).lrc"
        let fileURL = SandboxPathManager.lyricsFileURL(relativePath: songIdFile)
        if fm.fileExists(atPath: fileURL.path) {
            do {
                try fm.removeItem(at: fileURL)
            } catch {
                throw AppError.lyricsDeleteFailed(error.localizedDescription)
            }
        }
        if let path = song.lyricsPath, path != songIdFile {
            let oldURL = SandboxPathManager.lyricsFileURL(relativePath: path)
            try? fm.removeItem(at: oldURL)
        }

        do {
            try await repo.updateLyrics(songId: song.id, lyricsPath: nil, lyricsSource: nil)
        } catch {
            throw AppError.lyricsDeleteFailed(error.localizedDescription)
        }
    }

    // MARK: - LRC Parsing

    private static let lrcRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: #"\[(\d{1,3}):(\d{2})\.(\d{2,3})\](.*)"#)
    }()

    nonisolated func parseLRC(_ content: String) -> [LyricsLine] {
        guard let regex = Self.lrcRegex else { return [] }
        var lines: [LyricsLine] = []
        let rawLines = content.components(separatedBy: "\n")
        for line in rawLines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("[") else { continue }
            guard let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) else { continue }

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

    // MARK: - Private: Load Methods

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
                        let plainLines = buildPlainLines(from: text)
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
        if lines.isEmpty && !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let plainLines = buildPlainLines(from: content)
            return LyricsData(source: .file, lines: plainLines, rawText: content)
        }
        return LyricsData(source: .file, lines: lines, rawText: content)
    }

    private func loadExternalLRC(songTitle: String) -> LyricsData? {
        let candidates = ["\(songTitle).lrc"]
        for name in candidates {
            let url = SandboxPathManager.lyricsURL.appendingPathComponent(name)
            if let content = try? String(contentsOf: url, encoding: .utf8) {
                let lines = parseLRC(content)
                if lines.isEmpty && !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let plainLines = buildPlainLines(from: content)
                    return LyricsData(source: .file, lines: plainLines, rawText: content)
                }
                return LyricsData(source: .file, lines: lines, rawText: content)
            }
        }
        return nil
    }

    // MARK: - Private: File Operations

    private func saveLyricsFile(_ content: String, for songId: UUID) async throws {
        let relativePath = "\(songId.uuidString).lrc"
        let fileURL = SandboxPathManager.lyricsFileURL(relativePath: relativePath)

        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            throw AppError.lyricsSaveFailed(error.localizedDescription)
        }

        do {
            try await repo.updateLyrics(songId: songId, lyricsPath: relativePath, lyricsSource: .file)
        } catch {
            throw AppError.lyricsSaveFailed(error.localizedDescription)
        }
    }

    private func cleanupOldLRC(songTitle: String) {
        let oldURL = SandboxPathManager.lyricsURL.appendingPathComponent("\(songTitle).lrc")
        try? FileManager.default.removeItem(at: oldURL)
    }

    private func buildPlainLines(from text: String) -> [LyricsLine] {
        text.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .enumerated()
            .map { LyricsLine(timestamp: Double($0.offset) * 3, text: $0.element) }
    }

    // MARK: - Private: Cooldown

    private func isCooldownActive(for songId: UUID) -> Bool {
        let dict = UserDefaults.standard.dictionary(forKey: Self.cooldownKey) as? [String: Double] ?? [:]
        guard let timestamp = dict[songId.uuidString] else { return false }
        return Date().timeIntervalSince1970 - timestamp < Self.cooldownDuration
    }

    private func markCooldown(for songId: UUID) {
        var dict = UserDefaults.standard.dictionary(forKey: Self.cooldownKey) as? [String: Double] ?? [:]
        let now = Date().timeIntervalSince1970
        dict[songId.uuidString] = now
        dict = dict.filter { now - $0.value < Self.cooldownDuration }
        UserDefaults.standard.set(dict, forKey: Self.cooldownKey)
    }

    private func clearCooldown(for songId: UUID) {
        var dict = UserDefaults.standard.dictionary(forKey: Self.cooldownKey) as? [String: Double] ?? [:]
        dict.removeValue(forKey: songId.uuidString)
        UserDefaults.standard.set(dict, forKey: Self.cooldownKey)
    }
}
