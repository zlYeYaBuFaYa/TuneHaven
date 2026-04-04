import Testing
import Foundation
import Combine
@testable import TuneHaven

@Suite("PlaybackService Tests")
@MainActor
struct PlaybackServiceTests {
    let mockEngine = MockAudioEngine()
    let mockSongRepo = MockSongRepository()
    let mockPlaylistRepo = MockPlaylistRepository()
    let mockAudioSession = MockAudioSessionManaging()
    let mockNowPlaying = MockNowPlayingManaging()
    let mockFileStorage = MockFileStorageProviding()
    let mockPreferences = MockUserPreferences()
    let mockImageCache = MockImageCacheManaging()
    let mockSubscriptionProvider = MockSubscriptionProvider()

    func makeService() -> PlaybackService {
        let libraryService = MusicLibraryService(songRepo: mockSongRepo, imageCache: mockImageCache)
        let queueService = PlayQueueService()
        let sleepTimer = SleepTimerService()
        let subscriptionService = SubscriptionService(provider: mockSubscriptionProvider)
        return PlaybackService(
            playlistRepo: mockPlaylistRepo,
            songRepo: mockSongRepo,
            queueService: queueService,
            libraryService: libraryService,
            engine: mockEngine,
            audioSession: mockAudioSession,
            nowPlaying: mockNowPlaying,
            fileStorage: mockFileStorage,
            preferences: mockPreferences,
            sleepTimer: sleepTimer,
            subscriptionService: subscriptionService
        )
    }

    // MARK: - play(song:in:)

    @Test("play 加载并播放歌曲，isPlaying 变为 true")
    func testPlaySongSetsPlaying() async {
        let svc = makeService()
        let song = makeSong(title: "A")
        mockSongRepo.songs = [song]
        await svc.play(song: song, in: .queue)

        #expect(svc.isPlaying == true)
        #expect(svc.currentSong?.id == song.id)
        #expect(mockEngine.loadCalled)
        #expect(mockEngine.playCalled)
    }

    @Test("play 同一首歌曲已播放时不重复加载")
    func testPlaySameSongNoReload() async {
        let svc = makeService()
        let song = makeSong(title: "A")
        mockSongRepo.songs = [song]
        await svc.play(song: song, in: .queue)
        mockEngine.loadCalled = false
        mockEngine.playCalled = false

        await svc.play(song: song, in: .queue)
        #expect(!mockEngine.loadCalled)
    }

    @Test("play 暂停后再 play 恢复播放而不重新加载")
    func testPlayResumeFromPause() async {
        let svc = makeService()
        let song = makeSong(title: "A")
        mockSongRepo.songs = [song]
        await svc.play(song: song, in: .queue)

        mockEngine.pause()
        mockEngine.loadCalled = false

        await svc.play(song: song, in: .queue)
        #expect(mockEngine.playCalled)
        #expect(!mockEngine.loadCalled)
    }

    // MARK: - togglePlayPause

    @Test("togglePlayPause 在播放时暂停")
    func testTogglePlayPauseDuringPlayback() async {
        let svc = makeService()
        let song = makeSong(title: "A")
        mockSongRepo.songs = [song]
        await svc.play(song: song, in: .queue)

        svc.togglePlayPause()
        #expect(mockEngine.pauseCalled)
    }

    @Test("togglePlayPause 在暂停时恢复播放")
    func testTogglePlayPauseDuringPause() async {
        let svc = makeService()
        let song = makeSong(title: "A")
        mockSongRepo.songs = [song]
        await svc.play(song: song, in: .queue)

        mockEngine.pause()
        mockEngine.playCalled = false
        svc.togglePlayPause()
        #expect(mockEngine.playCalled)
    }

    // MARK: - stop

    @Test("stop 停止播放并设置 isPlaying 为 false")
    func testStopSetsNotPlaying() async {
        let svc = makeService()
        let song = makeSong(title: "A")
        mockSongRepo.songs = [song]
        await svc.play(song: song, in: .queue)

        svc.stop()
        #expect(svc.isPlaying == false)
        #expect(mockEngine.stopCalled)
    }

    // MARK: - seek

    @Test("seek 边界值被钳制到 [0, duration]")
    func testSeekClamping() async {
        let svc = makeService()
        let song = makeSong(title: "A")
        mockSongRepo.songs = [song]
        await svc.play(song: song, in: .queue)

        svc.seek(to: -10)
        #expect(mockEngine.currentTime == 0)

        mockEngine.duration = 200
        svc.seek(to: 999)
        #expect(mockEngine.currentTime == 200)
    }

    // MARK: - playMode

    @Test("cyclePlayMode 在各模式间循环")
    func testCyclePlayMode() async {
        let svc = makeService()
        let initial = svc.playMode
        svc.cyclePlayMode()
        #expect(svc.playMode != initial)
    }

    @Test("setPlayMode 设置指定模式并持久化")
    func testSetPlayMode() async {
        let svc = makeService()
        svc.setPlayMode(.shuffle)
        #expect(svc.playMode == .shuffle)
        #expect(mockPreferences.playMode == .shuffle)
    }

    // MARK: - speed

    @Test("setSpeed 更新速度")
    func testSetSpeed() async {
        let svc = makeService()
        svc.setSpeed(1.5)
        #expect(svc.playbackSpeed == 1.5)
    }

    // MARK: - lossless blocking

    @Test("Free 用户播放无损歌曲被阻止")
    func testLosslessBlocked() async {
        let svc = makeService()
        let losslessSong = makeSong(title: "Lossless")
        let losslessMetadata = Metadata(
            format: "flac", sampleRate: 96000, bitRate: 1411,
            channels: 2, encoder: nil, trackNumber: nil, year: nil, genre: nil
        )
        let song = Song(
            id: losslessSong.id, title: "Lossless", artist: "A", album: "B",
            duration: 180, fileHash: "hash", fileRelativePath: "hash.flac",
            coverImagePath: nil, lyricsPath: nil, lyricsSource: nil,
            metadata: losslessMetadata, importDate: Date(), fileSize: 1024,
            playCount: 0, isFavorite: false, favoriteDate: nil, lastPlayedDate: nil
        )
        mockSongRepo.songs = [song]

        await svc.play(song: song, in: .queue)
        #expect(svc.losslessBlockedSong?.id == song.id)
        #expect(svc.isPlaying == false)
    }

    // MARK: - playPrevious threshold

    @Test("playPrevious 在 >3s 进度时回到开头而不是上一首")
    func testPlayPreviousRestartsAfterThreshold() async {
        let svc = makeService()
        let songA = makeSong(title: "A")
        let songB = makeSong(title: "B")
        mockSongRepo.songs = [songA, songB]

        await svc.play(song: songA, in: .queue)
        mockEngine.currentTime = 5.0

        svc.playPrevious()
        #expect(mockEngine.currentTime == 0)
        #expect(svc.currentSong?.id == songA.id)
    }

    // MARK: - File not found handling

    @Test("loadAndPlay 文件不存在时自动跳到下一首")
    func testPlayFileNotFoundSkips() async {
        let svc = makeService()
        let songA = makeSong(title: "A")
        let songB = makeSong(title: "B")
        mockSongRepo.songs = [songA, songB]
        mockFileStorage.fileExistsResult = false

        await svc.play(song: songA, in: .allSongs(sortBy: .title))
        #expect(svc.isPlaying == false)
    }
}
