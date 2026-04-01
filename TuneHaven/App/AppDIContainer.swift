import SwiftUI

// MARK: - ImageCache EnvironmentKey

struct ImageCacheKey: EnvironmentKey {
    static let defaultValue: ImageCacheManaging = ImageCacheManager.shared
}

extension EnvironmentValues {
    var imageCache: ImageCacheManaging {
        get { self[ImageCacheKey.self] }
        set { self[ImageCacheKey.self] = newValue }
    }
}

@MainActor
final class AppDIContainer: ObservableObject {
    // MARK: - UI State
    let themeManager: ThemeManager
    let router: AppRouter
    let snackbar: SnackbarState

    // MARK: - Infrastructure
    let audioEngine: AudioEngine
    let audioSessionManager: AudioSessionManager
    let preferences: UserPreferencesProviding
    let coverProcessor: CoverImageProcessing

    // MARK: - Services (首屏必须同步创建)
    let libraryService: MusicLibraryService
    let playlistService: PlaylistService
    let groupService: PlaylistGroupService
    let playbackService: PlaybackService
    let searchService: SearchService

    // MARK: - Services (非首屏，延迟创建)
    lazy var importService: ImportService = {
        ImportService(
            songRepo: songRepo,
            fileService: FileStorageService.shared,
            coverProcessor: coverProcessor,
            metadataParser: AudioMetadataParser.shared
        )
    }()
    lazy var webDAVService: WebDAVService = {
        WebDAVService(
            accountStore: WebDAVAccountStore.shared,
            clientFactory: DefaultWebDAVClientFactory(),
            importService: self.importService,
            fileStorage: FileStorageService.shared
        )
    }()
    lazy var lyricsService: LyricsService = {
        LyricsService(
            repo: songRepo,
            api: LRCLibAPIClient.shared,
            preferences: preferences,
            fileStorage: FileStorageService.shared,
            embeddedReader: EmbeddedLyricsReader()
        )
    }()
    lazy var shareService: ShareService = {
        ShareService(
            songRepo: songRepo,
            playlistService: playlistService,
            groupService: groupService,
            importService: importService,
            fileStorage: FileStorageService.shared,
            backgroundTask: BackgroundTaskProvider(),
            serverFactory: { ShareServer() },
            clientFactory: { ShareClient() }
        )
    }()
    // MARK: - Shared Repositories
    private let songRepo: SongRepository

    /// App 启动时的基础设施初始化（迁移、数据库加载、沙盒目录、临时文件清理）
    func bootstrap() async throws {
        MigrationManager.shared.runVersionUpgradeTasks()
        try await CoreDataStack.shared.load()
        await MigrationManager.shared.runPostLoadMigrations()
        SandboxPathManager.createAllDirectories()
        WiFiTransferServer.cleanupTempFiles()
        OpenInImportHandler.cleanupInbox(fileStorage: FileStorageService.shared)
    }

    init() {
        let audioSession = AudioSessionManager.shared
        self.audioEngine = AudioEngine.shared
        self.audioSessionManager = audioSession

        self.themeManager = ThemeManager()
        self.router = AppRouter()
        self.snackbar = SnackbarState()

        let preferences: UserPreferencesProviding = UserPreferencesStore()
        self.preferences = preferences

        let coverProcessor: CoverImageProcessing = CoverImageProcessor()
        self.coverProcessor = coverProcessor

        let songRepo: SongRepository = CoreDataSongRepository()
        let playlistRepo: PlaylistRepository = CoreDataPlaylistRepository()
        let groupRepo: PlaylistGroupRepository = CoreDataPlaylistGroupRepository()
        let searchHistoryRepo: SearchHistoryRepository = CoreDataSearchHistoryRepository()

        self.songRepo = songRepo

        let libraryService = MusicLibraryService(songRepo: songRepo, imageCache: ImageCacheManager.shared)
        self.libraryService = libraryService
        self.playlistService = PlaylistService(repo: playlistRepo, songRepo: songRepo, coverProcessor: coverProcessor)
        self.groupService = PlaylistGroupService(repo: groupRepo)
        self.searchService = SearchService(historyRepo: searchHistoryRepo)
        self.playbackService = PlaybackService(
            playlistRepo: playlistRepo,
            songRepo: songRepo,
            queueService: PlayQueueService(),
            libraryService: libraryService,
            engine: AudioEngine.shared,
            audioSession: audioSession,
            nowPlaying: NowPlayingManager.shared,
            fileStorage: FileStorageService.shared,
            preferences: preferences,
            sleepTimer: SleepTimerService()
        )
    }
}
