import Foundation

@MainActor
final class LyricsService: ObservableObject {
    private let log = AppLogger.shared
    private let repo: SongRepository
    private let api: any LyricsAPIProviding
    private let preferences: UserPreferencesProviding
    private let fileStorage: FileStorageProviding
    private let embeddedReader: EmbeddedLyricsReading
    private let subscriptionService: SubscriptionService

    private static let cooldownDuration: TimeInterval = 7 * 24 * 3600

    init(repo: SongRepository,
         api: any LyricsAPIProviding,
         preferences: UserPreferencesProviding,
         fileStorage: FileStorageProviding,
         embeddedReader: EmbeddedLyricsReading,
         subscriptionService: SubscriptionService) {
        self.repo = repo
        self.api = api
        self.preferences = preferences
        self.fileStorage = fileStorage
        self.embeddedReader = embeddedReader
        self.subscriptionService = subscriptionService
    }

    // MARK: - Load Lyrics (fallthrough chain)

    func loadLyrics(for song: Song) async -> LyricsData? {
        log.debug("加载歌词: \(song.title)")

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

        if !triedEmbedded, let embedded = await loadEmbedded(song: song) { return embedded }

        let songIdFile = "\(song.id.uuidString).lrc"
        if let data = loadFromFile(relativePath: songIdFile) { return data }
        if let data = loadExternalLRC(songTitle: song.title) { return data }

        if preferences.autoMatchLyrics {
            if let data = await autoMatchOnline(for: song) { return data }
        }

        log.debug("歌词未找到: \(song.title)")
        return nil
    }

    // MARK: - Online Auto Match (degraded search chain)

    func autoMatchOnline(for song: Song) async -> LyricsData? {
        guard subscriptionService.canAccess(.onlineLyricsSearch) else {
            log.debug("Free 用户，跳过在线歌词匹配")
            return nil
        }
        guard !isCooldownActive(for: song.id) else { return nil }

        if let data = try? await exactMatch(song: song) { return data }

        do {
            if let data = try await searchMatch(title: song.title, artist: song.artist, songId: song.id, songTitle: song.title) {
                return data
            }

            if song.artist != SongDefaults.unknownArtist {
                if let data = try await searchMatch(title: song.title, artist: nil, songId: song.id, songTitle: song.title) {
                    return data
                }
            }

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
        return buildLyricsData(from: lyrics, source: .file)
    }

    private func simplifyTitle(_ title: String) -> String {
        var result = title
        let patterns = [#"\(.*?\)"#, #"（.*?）"#, #"\[.*?\]"#]
        for pattern in patterns {
            result = result.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        let suffixes = ["feat.", "ft.", "remix", "live", "acoustic", "version", "remastered"]
        for suffix in suffixes {
            if let range = result.range(of: suffix, options: .caseInsensitive) {
                result = String(result[result.startIndex..<range.lowerBound])
            }
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Online Search (manual)

    func searchOnline(title: String, artist: String?) async throws -> [LRCLibTrack] {
        guard subscriptionService.canAccess(.onlineLyricsSearch) else {
            throw AppError.featureRequiresPremium(PremiumFeature.onlineLyricsSearch.rawValue)
        }
        return try await api.search(trackName: title, artistName: artist)
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
            guard fileStorage.isReadableFile(at: url) else {
                throw AppError.lyricsImportFailed("无法访问文件（安全范围授权失败）")
            }
        }
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }

        guard let content = fileStorage.readStringContents(at: url) else {
            throw AppError.lyricsImportFailed("文件读取失败")
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
        let songIdFile = "\(song.id.uuidString).lrc"
        let fileURL = fileStorage.lyricsFileURL(relativePath: songIdFile)
        if fileStorage.fileExists(at: fileURL) {
            do {
                try fileStorage.removeItem(at: fileURL)
            } catch {
                throw AppError.lyricsDeleteFailed(error.localizedDescription)
            }
        }
        if let path = song.lyricsPath, path != songIdFile {
            let oldURL = fileStorage.lyricsFileURL(relativePath: path)
            try? fileStorage.removeItem(at: oldURL)
        }

        do {
            try await repo.updateLyrics(songId: song.id, lyricsPath: nil, lyricsSource: nil)
        } catch {
            throw AppError.lyricsDeleteFailed(error.localizedDescription)
        }
    }

    // MARK: - Query

    nonisolated func hasExternalLyrics(for songId: UUID) -> Bool {
        let fileURL = fileStorage.lyricsFileURL(relativePath: "\(songId.uuidString).lrc")
        return fileStorage.fileExists(at: fileURL)
    }

    // MARK: - LRC Parsing

    private nonisolated static let lrcRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: #"\[(\d{1,3}):(\d{2})\.(\d{2,3})\](.*)"#)
    }()

    nonisolated func parseLRC(_ content: String) -> [LyricsLine] {
        guard let regex = Self.lrcRegex else { return [] }
        var lines: [LyricsLine] = []
        let rawLines = content.components(separatedBy: "\n")
        for line in rawLines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
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
            let text = group(4).trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                lines.append(LyricsLine(timestamp: timestamp, text: text))
            }
        }
        return lines.sorted { $0.timestamp < $1.timestamp }
    }

    // MARK: - Private: Load Methods

    private func loadEmbedded(song: Song) async -> LyricsData? {
        let url = fileStorage.musicFileURL(relativePath: song.fileRelativePath)
        guard let text = await embeddedReader.readEmbeddedLyrics(from: url), !text.isEmpty else { return nil }
        return buildLyricsData(from: text, source: .embedded)
    }

    private func loadFromFile(relativePath: String) -> LyricsData? {
        let url = fileStorage.lyricsFileURL(relativePath: relativePath)
        guard let content = fileStorage.readStringContents(at: url) else { return nil }
        return buildLyricsData(from: content, source: .file)
    }

    private func loadExternalLRC(songTitle: String) -> LyricsData? {
        let safeName = songTitle
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "..", with: "_")
        let candidates = ["\(safeName).lrc"]
        for name in candidates {
            let url = fileStorage.lyricsDirectoryURL.appendingPathComponent(name)
            guard let content = fileStorage.readStringContents(at: url) else { continue }
            if let data = buildLyricsData(from: content, source: .file) { return data }
        }
        return nil
    }

    // MARK: - Private: Shared Parsing

    private func buildLyricsData(from content: String, source: LyricsSource) -> LyricsData? {
        let lines = parseLRC(content)
        if lines.isEmpty && !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return LyricsData(source: source, lines: buildPlainLines(from: content), rawText: content)
        }
        if lines.isEmpty { return nil }
        return LyricsData(source: source, lines: lines, rawText: content)
    }

    // MARK: - Private: File Operations

    private func saveLyricsFile(_ content: String, for songId: UUID) async throws {
        let relativePath = "\(songId.uuidString).lrc"
        let fileURL = fileStorage.lyricsFileURL(relativePath: relativePath)

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
        let safeName = songTitle
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "..", with: "_")
        let oldURL = fileStorage.lyricsDirectoryURL.appendingPathComponent("\(safeName).lrc")
        try? fileStorage.removeItem(at: oldURL)
    }

    private func buildPlainLines(from text: String) -> [LyricsLine] {
        text.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .enumerated()
            .map { LyricsLine(timestamp: Double($0.offset) * 3, text: $0.element) }
    }

    // MARK: - Private: Cooldown

    private func isCooldownActive(for songId: UUID) -> Bool {
        let dict = preferences.lyricsCooldown
        guard let timestamp = dict[songId.uuidString] else { return false }
        return Date().timeIntervalSince1970 - timestamp < Self.cooldownDuration
    }

    private func markCooldown(for songId: UUID) {
        var dict = preferences.lyricsCooldown
        let now = Date().timeIntervalSince1970
        dict[songId.uuidString] = now
        dict = dict.filter { now - $0.value < Self.cooldownDuration }
        preferences.lyricsCooldown = dict
    }

    private func clearCooldown(for songId: UUID) {
        var dict = preferences.lyricsCooldown
        dict.removeValue(forKey: songId.uuidString)
        preferences.lyricsCooldown = dict
    }
}
