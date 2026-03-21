import Testing
import Foundation
@testable import TuneHaven

// MARK: - AppError (playback) Tests

@Suite("AppError Playback Tests")
struct AppErrorPlaybackTests {

    @Test("playbackFileNotFound 有非空描述")
    func testPlaybackFileNotFoundDescription() {
        let error = AppError.playbackFileNotFound(UUID())
        #expect(error.errorDescription?.contains("文件") == true)
    }

    @Test("playbackUnsupportedFormat 错误包含格式名")
    func testUnsupportedFormatDescription() {
        let error = AppError.playbackUnsupportedFormat("ogg")
        #expect(error.errorDescription?.contains("ogg") == true)
    }

    @Test("无法播放 描述包含文件名")
    func testAssetNotPlayableStyleDescription() {
        let error = AppError.playbackUnsupportedFormat("无法播放：damaged.flac")
        #expect(error.errorDescription?.contains("damaged.flac") == true)
    }

    @Test("加载失败 描述包含底层错误信息")
    func testLoadFailedStyleDescription() {
        let error = AppError.playbackUnsupportedFormat("加载失败：decode error")
        #expect(error.errorDescription?.contains("decode error") == true)
    }

    @Test("相关 case 都有非空描述")
    func testCasesHaveDescription() {
        let url = URL(fileURLWithPath: "/test.mp3")
        let underlying = NSError(domain: "test", code: 0)
        let errors: [AppError] = [
            .playbackFileNotFound(UUID()),
            .playbackUnsupportedFormat("xyz"),
            .playbackUnsupportedFormat("无法播放：\(url.lastPathComponent)"),
            .playbackUnsupportedFormat("加载失败：\(underlying.localizedDescription)")
        ]
        for error in errors {
            #expect(error.errorDescription != nil)
            #expect(!error.errorDescription!.isEmpty)
        }
    }
}

// MARK: - PlaybackState Tests

@Suite("PlaybackState Tests")
struct PlaybackStateTests {

    @Test("idle 状态可正常创建")
    func testIdleState() {
        let state: PlaybackState = .idle
        if case .idle = state {
            #expect(true)
        } else {
            #expect(Bool(false), "应为 idle 状态")
        }
    }

    @Test("loading 状态可正常创建")
    func testLoadingState() {
        let state: PlaybackState = .loading
        if case .loading = state {
            #expect(true)
        } else {
            #expect(Bool(false), "应为 loading 状态")
        }
    }

    @Test("playing 状态可正常创建")
    func testPlayingState() {
        let state: PlaybackState = .playing
        if case .playing = state {
            #expect(true)
        } else {
            #expect(Bool(false), "应为 playing 状态")
        }
    }

    @Test("paused 状态可正常创建")
    func testPausedState() {
        let state: PlaybackState = .paused
        if case .paused = state {
            #expect(true)
        } else {
            #expect(Bool(false), "应为 paused 状态")
        }
    }

    @Test("error 状态携带错误信息")
    func testErrorState() {
        let err = AppError.playbackUnsupportedFormat("ogg")
        let state: PlaybackState = .error(err)
        if case .error(let e) = state {
            #expect(e.localizedDescription.contains("ogg"))
        } else {
            #expect(Bool(false), "应为 error 状态")
        }
    }
}
