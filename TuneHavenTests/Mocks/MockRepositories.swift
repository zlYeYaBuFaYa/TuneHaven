import Foundation
import UIKit
import Combine
@testable import TuneHaven

// MARK: - Mock Infrastructure

final class MockUserPreferences: UserPreferencesProviding {
    var playMode: PlayMode = .sequential
    var playbackSpeed: Float = 1.0
    var speedMemoryMode: SpeedMemoryMode = .global
    var autoMatchLyrics: Bool = true
    var recentPlayRange: Int = 7
    var lastPlayedSongId: String?
    var songDislikes: [String: Int] = [:]
    var perSongSpeeds: [String: Float] = [:]
    var lyricsCooldown: [String: Double] = [:]
}

final class MockImageCacheManaging: ImageCacheManaging {
    var cacheLimitMB: Int = 100
    var cacheCleared = false
    var mockCacheSize: Int64 = 0

    func setCacheLimit(_ megabytes: Int) { cacheLimitMB = megabytes }
    func clearAll() async { cacheCleared = true }
    func cacheSizeAsync() async -> Int64 { mockCacheSize }
    func memoryImage(forKey key: String) -> UIImage? { nil }
    func imageAsync(forKey key: String) async -> UIImage? { nil }
    func store(image: UIImage, forKey key: String) {}
}

final class MockCoverImageProcessing: CoverImageProcessing {
    var lastSongCoverData: Data?
    var songCoverResult: String? = "mock_cover.jpg"
    var playlistCoverResult: String = "mock_playlist.jpg"
    var gridCoverResult: String = "mock_grid.jpg"

    func processSongCover(data: Data, songId: UUID) async throws -> String? {
        lastSongCoverData = data
        return songCoverResult
    }
    func processPlaylistCover(imageData: Data, playlistId: UUID) async throws -> String {
        guard UIImage(data: imageData) != nil else {
            throw AppError.imageProcessingFailed("无效的图片数据")
        }
        return playlistCoverResult
    }
    func generatePlaylistGridCover(coverPaths: [String?], playlistId: UUID) async throws -> String {
        gridCoverResult
    }
}

final class MockFileStorageProviding: FileStorageProviding {
    var maxFileSizeBytes: Int64 = 500 * 1024 * 1024
    var supportedExtensions: Set<String> = ["mp3", "m4a", "flac"]
    var importTempURL: URL = URL(fileURLWithPath: NSTemporaryDirectory())
    var documentsURL: URL = URL(fileURLWithPath: NSTemporaryDirectory())
    var fileExistsResult = true

    func fileExists(relativePath: String) -> Bool { fileExistsResult }
    func sha256(of url: URL) throws -> String { "mockhash12345678" }
    func copyToMusic(from sourceURL: URL, fileHash: String, originalFileName: String) throws -> String {
        "\(fileHash.prefix(8))_\(originalFileName)"
    }
    func fileSize(at url: URL) -> Int64 { 1024 }
    func createDirectoryIfNeeded(at url: URL) throws {}
    func removeItem(at url: URL) throws {}
    func contentsOfDirectory(at url: URL) -> [URL] { [] }
    func musicFileURL(relativePath: String) -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(relativePath)
    }
    func lyricsFileURL(relativePath: String) -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(relativePath)
    }
    var lyricsDirectoryURL: URL {
        URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Lyrics")
    }
    func fileExists(at url: URL) -> Bool { fileExistsResult }
    func isReadableFile(at url: URL) -> Bool { fileExistsResult }
    func readStringContents(at url: URL) -> String? { nil }
}

final class MockAudioMetadataParsing: AudioMetadataParsing {
    var mockResult = ParsedMetadata(
        title: "Mock Title", artist: "Mock Artist", album: "Mock Album",
        duration: 180, format: "mp3", sampleRate: 44100, bitRate: 320,
        channels: 2, trackNumber: 1, year: 2024, genre: "Pop",
        encoder: nil, coverImageData: nil, isIncomplete: false
    )

    func parse(url: URL) async -> ParsedMetadata { mockResult }
}

@MainActor
final class MockAudioSessionManaging: AudioSessionManaging {
    var ensureActiveCalled = false
    @discardableResult func ensureActive() -> Bool {
        ensureActiveCalled = true
        return true
    }
}

@MainActor
final class MockNowPlayingManaging: NowPlayingManaging {
    var lastUpdatedSong: Song?
    var lastCoverPath: String?
    var setupCalled = false

    func update(song: Song, currentTime: TimeInterval, duration: TimeInterval, speed: Float, coverPath: String?) {
        lastUpdatedSong = song
        lastCoverPath = coverPath
    }
    func updateElapsedTime(currentTime: TimeInterval, duration: TimeInterval, speed: Float) {}
    func clear() {}
    func setupRemoteCommands(
        onPlay: @escaping @Sendable () -> Void,
        onPause: @escaping @Sendable () -> Void,
        onTogglePlayPause: @escaping @Sendable () -> Void,
        onNext: @escaping @Sendable () -> Void,
        onPrevious: @escaping @Sendable () -> Void,
        onSeek: @escaping @Sendable (TimeInterval) -> Void
    ) {
        setupCalled = true
    }
}

// MARK: - Mock Audio Engine

@MainActor
final class MockAudioEngine: AudioEngineProtocol {
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 180
    var state: PlaybackState = .idle

    var statePublisher: AnyPublisher<PlaybackState, Never> { stateSubject.eraseToAnyPublisher() }
    var playbackEndedPublisher: AnyPublisher<Void, Never> { playbackEndedSubject.eraseToAnyPublisher() }
    var timeUpdatePublisher: AnyPublisher<(currentTime: TimeInterval, duration: TimeInterval), Never> { timeUpdateSubject.eraseToAnyPublisher() }

    let stateSubject = PassthroughSubject<PlaybackState, Never>()
    let playbackEndedSubject = PassthroughSubject<Void, Never>()
    let timeUpdateSubject = PassthroughSubject<(currentTime: TimeInterval, duration: TimeInterval), Never>()

    var loadCalled = false
    var playCalled = false
    var pauseCalled = false
    var stopCalled = false

    func load(url: URL) async { loadCalled = true; state = .paused }
    func play() { playCalled = true; state = .playing }
    func pause() { pauseCalled = true; state = .paused }
    func stop() { stopCalled = true; state = .idle }
    func seek(to time: TimeInterval) { currentTime = time }
    func skip(by seconds: TimeInterval) { currentTime += seconds }
    func setSpeed(_ speed: Float) {}
    func togglePlayPause() {
        if case .playing = state { pause() } else { play() }
    }
}

// MARK: - Mock API Clients

final class MockLRCLibAPIClient: LyricsAPIProviding {
    var getResult: LRCLibTrack?
    var searchResults: [LRCLibTrack] = []

    func get(trackName: String, artistName: String, albumName: String, duration: Int) async throws -> LRCLibTrack? {
        getResult
    }
    func search(trackName: String, artistName: String?) async throws -> [LRCLibTrack] {
        searchResults
    }
}

// MARK: - Mock Embedded Lyrics Reader

final class MockEmbeddedLyricsReader: EmbeddedLyricsReading {
    var result: String?
    func readEmbeddedLyrics(from fileURL: URL) async -> String? { result }
}

// MARK: - Mock Subscription

final class MockSubscriptionProvider: SubscriptionProviding {
    var products: [SubscriptionProduct] = []
    var purchaseResult: PurchaseResult = .success
    var entitlementState = EntitlementState(hasLifetime: false, hasActiveSubscription: false, subscriptionExpirationDate: nil)
    var originalPurchaseDate: Date?

    func fetchProducts() async throws -> [SubscriptionProduct] { products }
    func purchase(_ productID: String) async throws -> PurchaseResult { purchaseResult }
    func restorePurchases() async throws {}
    func resolveEntitlements() async -> EntitlementState { entitlementState }
    func appOriginalPurchaseDate() async -> Date? { originalPurchaseDate }
    func transactionUpdates() -> AsyncStream<TransactionUpdate> {
        AsyncStream { $0.finish() }
    }
}

// MARK: - Mock Repositories

final class MockSearchHistoryRepository: SearchHistoryRepository {
    private var tabHistory: [LibraryTab: [SearchHistoryItem]] = [:]

    var history: [SearchHistoryItem] {
        tabHistory.values.flatMap { $0 }
    }

    func fetchHistory(tab: LibraryTab, limit: Int) async -> [SearchHistoryItem] {
        Array((tabHistory[tab] ?? []).prefix(limit))
    }
    func saveHistory(keyword: String, tab: LibraryTab) async throws {
        let item = SearchHistoryItem(id: UUID(), keyword: keyword, searchedAt: Date())
        tabHistory[tab, default: []].append(item)
    }
    func deleteHistory(id: UUID) async throws {
        for tab in tabHistory.keys {
            tabHistory[tab]?.removeAll { $0.id == id }
        }
    }
    func clearHistory() async throws { tabHistory.removeAll() }
    func clearHistory(tab: LibraryTab) async throws {
        tabHistory[tab] = nil
    }
}

final class MockSongRepository: SongRepository {
    var songs: [Song] = []

    func fetchAll(sortBy: SongSortOption, ascending: Bool) async -> [Song] { songs }
    func fetchSong(id: UUID) async -> Song? { songs.first { $0.id == id } }
    func fetchByHash(_ hash: String) async -> Song? { songs.first { $0.fileHash == hash } }
    func fetchSongs(byIds ids: [UUID]) async -> [Song] { songs.filter { ids.contains($0.id) } }
    func fetchSongs(byArtist artist: String, sortBy: SongSortOption, ascending: Bool) async -> [Song] {
        songs.filter { $0.artist == artist }
    }
    func fetchSongs(byAlbum album: String, artist: String, sortBy: SongSortOption, ascending: Bool) async -> [Song] {
        songs.filter { $0.album == album && $0.artist == artist }
    }
    func insert(song: Song) async throws { songs.append(song) }
    func softDelete(ids: [UUID]) async throws -> UndoToken {
        UndoToken(songIds: ids, movedFiles: [], expiresAt: Date().addingTimeInterval(30))
    }
    func undoDelete(token: UndoToken) async throws {}
    func commitDelete(token: UndoToken) async throws {}
    func toggleFavorite(id: UUID) async throws {}
    func recordPlay(id: UUID) async throws {}
    func updateLyrics(songId: UUID, lyricsPath: String?, lyricsSource: LyricsSource?) async throws {}
    func updateSongInfo(id: UUID, title: String, artist: String, album: String) async throws {}
    func countReferences(toFileHash hash: String) async -> Int { 0 }
    func cleanupPendingDeletes() async {}
    func fetchRecentlyPlayed(days: Int, page: Int, pageSize: Int) async -> PagedResult<Song> {
        PagedResult(items: [], totalCount: 0, hasMore: false)
    }
    func fetchArtistGroups() async -> [ArtistGroup] { [] }
    func fetchAlbumGroups() async -> [AlbumGroup] { [] }
}

final class MockPlaylistRepository: PlaylistRepository {
    func fetchAll() async -> [Playlist] { [] }
    func fetchPlaylistDetail(id: UUID) async -> PlaylistDetail? { nil }
    func create(name: String, description: String?) async throws -> Playlist {
        Playlist(id: UUID(), name: name, description: description,
                 coverImagePath: nil, autoCoverHash: nil,
                 isSystem: false, systemType: .normal, songCount: 0,
                 groupId: nil, sortOrder: 0,
                 createdAt: Date(), updatedAt: Date())
    }
    func update(id: UUID, name: String?, description: String?) async throws {}
    func delete(id: UUID) async throws {}
    func addSongs(_ songIds: [UUID], to playlistId: UUID) async throws {}
    func removeSongs(_ songIds: [UUID], from playlistId: UUID) async throws {}
    func reorder(orderedIds: [UUID]) async throws {}
    func reorderSongs(in playlistId: UUID, orderedSongIds: [UUID]) async throws {}
    func createSystemPlaylists() async throws {}
    func fetchFavoritesSongIds() async -> [UUID] { [] }
    func updateAutoCover(playlistId: UUID, path: String, hash: String) async throws {}
    func setCustomCover(playlistId: UUID, imagePath: String) async throws {}
}
