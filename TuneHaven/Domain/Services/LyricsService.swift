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

    private var revisions: [UUID: Int] = [:]

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
        await loadLyricsResult(for: song).data
    }

    func loadLyricsResult(for original: Song, onMatching: (() -> Void)? = nil) async -> LyricsLoadResult {
        // The player may hold a pre-edit value. Read the persisted lyrics choice again.
        let song = await repo.fetchSong(id: original.id) ?? original
        if song.lyricsSource == .instrumental { return LyricsLoadResult(state: .instrumental) }
        var triedEmbedded = false
        if let source = song.lyricsSource {
            switch source {
            case .embedded:
                triedEmbedded = true
                if let data = await loadEmbedded(song: song) { return LyricsLoadResult(state: .loaded, data: data) }
            case .file, .manual:
                if let path = song.lyricsPath, let data = loadFromFile(relativePath: path) {
                    return LyricsLoadResult(state: .loaded, data: data)
                }
            case .instrumental: break
            }
        }
        if !triedEmbedded, let data = await loadEmbedded(song: song) { return LyricsLoadResult(state: .loaded, data: data) }
        if let data = loadFromFile(relativePath: "\(song.id.uuidString).lrc") ?? loadExternalLRC(songTitle: song.title) {
            return LyricsLoadResult(state: .loaded, data: data)
        }
        guard !Task.isCancelled, preferences.autoMatchLyrics,
              subscriptionService.canAccess(.onlineLyricsSearch) else { return LyricsLoadResult(state: .unavailable) }
        if isCooldownActive(for: song.id) { return LyricsLoadResult(state: .notFound) }
        onMatching?()
        return await matchOnline(for: song)
    }

    // MARK: - Online Auto Match (degraded search chain)

    func autoMatchOnline(for song: Song) async -> LyricsData? {
        guard subscriptionService.canAccess(.onlineLyricsSearch), !isCooldownActive(for: song.id) else { return nil }
        return await matchOnline(for: song).data
    }

    private func matchOnline(for song: Song) async -> LyricsLoadResult {
        let revision = revisions[song.id, default: 0]
        func checkCurrent() throws {
            try Task.checkCancellation()
            guard revisions[song.id, default: 0] == revision else { throw CancellationError() }
        }
        var hadNetworkError = false
        do {
            let track: LRCLibTrack?
            do {
                track = try await api.get(trackName: song.title, artistName: song.artist,
                                          albumName: song.album, duration: Int(song.duration))
            } catch {
                try Task.checkCancellation()
                hadNetworkError = true
                track = nil
            }
            try checkCurrent()
            // Only an exact match may automatically classify a song as instrumental.
            if let track, track.instrumental {
                try await markInstrumental(for: song)
                return LyricsLoadResult(state: .instrumental)
            }
            if let data = try await processTrack(track, song: song) { return LyricsLoadResult(state: .loaded, data: data) }

            var queries: [(String, String?)] = [(song.title, song.artist)]
            if song.artist != SongDefaults.unknownArtist { queries.append((song.title, nil)) }
            let simplified = simplifyTitle(song.title)
            if simplified != song.title && !simplified.isEmpty { queries.append((simplified, nil)) }
            for (title, artist) in queries {
                let results = try await api.search(trackName: title, artistName: artist)
                try checkCurrent()
                let candidates = results.filter { !$0.instrumental && $0.hasAnyLyrics }
                let best = candidates.first(where: { $0.hasSyncedLyrics }) ?? candidates.first
                if let data = try await processTrack(best, song: song) { return LyricsLoadResult(state: .loaded, data: data) }
            }
        } catch is CancellationError {
            return LyricsLoadResult(state: .unavailable)
        } catch AppError.lyricsSaveFailed {
            return LyricsLoadResult(state: .saveError)
        } catch {
            return LyricsLoadResult(state: .networkError)
        }
        // A failed exact request must not create a seven-day no-results cache.
        guard !hadNetworkError else { return LyricsLoadResult(state: .networkError) }
        markCooldown(for: song.id)
        return LyricsLoadResult(state: .notFound)
    }

    private func processTrack(_ track: LRCLibTrack?, song: Song) async throws -> LyricsData? {
        guard let track, !track.instrumental, let lyrics = track.bestLyrics else { return nil }
        try Task.checkCancellation()
        try await saveLyrics(lyrics, for: song)
        return buildLyricsData(from: lyrics, source: .file)
    }

    func markInstrumental(for song: Song) async throws {
        try Task.checkCancellation()
        revisions[song.id, default: 0] += 1
        let revision = revisions[song.id, default: 0]
        do {
            try await repo.updateLyrics(songId: song.id, lyricsPath: nil, lyricsSource: .instrumental)
        } catch { throw AppError.lyricsSaveFailed(error.localizedDescription) }
        // A manual import may have completed while the repository save was suspended.
        guard revisions[song.id, default: 0] == revision else { return }
        // Remove only this song's saved lyrics, so a later lyric import can replace the mark.
        let url = fileStorage.lyricsFileURL(relativePath: "\(song.id.uuidString).lrc")
        try? fileStorage.removeItem(at: url)
        clearCooldown(for: song.id)
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
        revisions[song.id, default: 0] += 1
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

        revisions[song.id, default: 0] += 1
        cleanupOldLRC(songTitle: song.title)
        try await saveLyricsFile(content, for: song.id)
        clearCooldown(for: song.id)
    }

    // MARK: - Delete Lyrics

    func deleteLyrics(for song: Song) async throws {
        revisions[song.id, default: 0] += 1
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

    /// 时间标签：`mm:ss`、`mm:ss.x`～`mm:ss.xxx`，部分歌词用冒号分隔小数（`mm:ss:xx`）。
    private nonisolated static let timeTagRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: #"^(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?$"#)
    }()

    /// 解析 LRC：一行可带多个行首时间标签（同一句在多个时间出现），
    /// `[offset:±毫秒]` 为正时歌词整体提前，结果按时间升序、同时间保持原顺序。
    nonisolated func parseLRC(_ content: String) -> [LyricsLine] {
        guard let regex = Self.timeTagRegex else { return [] }
        var entries: [(timestamp: Double, text: String)] = []
        var offsetMilliseconds: Double = 0

        for line in content.components(separatedBy: .newlines) {
            var rest = Substring(line.trimmingCharacters(in: .whitespaces))
            var timestamps: [Double] = []
            while rest.hasPrefix("["), let close = rest.firstIndex(of: "]") {
                let tag = String(rest[rest.index(after: rest.startIndex)..<close]).trimmingCharacters(in: .whitespaces)
                rest = rest[rest.index(after: close)...]
                if let timestamp = Self.parseTimeTag(tag, regex: regex) {
                    timestamps.append(timestamp)
                } else if tag.lowercased().hasPrefix("offset:"),
                          let value = Double(tag.dropFirst("offset:".count).trimmingCharacters(in: .whitespaces)) {
                    offsetMilliseconds = value
                }
            }
            let text = rest.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            for timestamp in timestamps {
                entries.append((timestamp, text))
            }
        }

        let shift = offsetMilliseconds / 1000
        return entries.enumerated()
            .sorted { lhs, rhs in
                lhs.element.timestamp == rhs.element.timestamp
                    ? lhs.offset < rhs.offset
                    : lhs.element.timestamp < rhs.element.timestamp
            }
            .map { LyricsLine(timestamp: max(0, $0.element.timestamp - shift), text: $0.element.text) }
    }

    private nonisolated static func parseTimeTag(_ tag: String, regex: NSRegularExpression) -> Double? {
        guard let match = regex.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag)) else { return nil }
        func group(_ i: Int) -> String? {
            guard let r = Range(match.range(at: i), in: tag) else { return nil }
            return String(tag[r])
        }
        guard let minutes = group(1).flatMap(Double.init),
              let seconds = group(2).flatMap(Double.init) else { return nil }
        var fraction: Double = 0
        if let digits = group(3), let value = Double(digits) {
            fraction = value / pow(10, Double(digits.count))
        }
        return minutes * 60 + seconds + fraction
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

    private func externalLyricsURL(songTitle: String) -> URL? {
        let directory = fileStorage.lyricsDirectoryURL.standardizedFileURL
        let url = directory.appendingPathComponent("\(songTitle).lrc").standardizedFileURL
        guard url.deletingLastPathComponent() == directory else { return nil }
        return url
    }

    private func loadExternalLRC(songTitle: String) -> LyricsData? {
        guard let url = externalLyricsURL(songTitle: songTitle),
              let content = fileStorage.readStringContents(at: url) else { return nil }
        return buildLyricsData(from: content, source: .file)
    }

    // MARK: - Private: Shared Parsing

    private func buildLyricsData(from content: String, source: LyricsSource) -> LyricsData? {
        let lines = parseLRC(content)
        if lines.isEmpty && !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return LyricsData(source: source, lines: [], rawText: content)
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
        guard let oldURL = externalLyricsURL(songTitle: songTitle) else { return }
        try? fileStorage.removeItem(at: oldURL)
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
