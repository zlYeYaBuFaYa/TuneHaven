import Testing
import Foundation
@testable import TuneHaven

// MARK: - AudioEngineError Tests

@Suite("AudioEngineError Tests")
struct AudioEngineErrorTests {

    @Test("fileNotFound 错误包含文件名")
    func testFileNotFoundDescription() {
        let url = URL(fileURLWithPath: "/path/to/夜曲.mp3")
        let error = AudioEngineError.fileNotFound(url)
        #expect(error.errorDescription?.contains("夜曲.mp3") == true)
    }

    @Test("unsupportedFormat 错误包含格式名")
    func testUnsupportedFormatDescription() {
        let error = AudioEngineError.unsupportedFormat("ogg")
        #expect(error.errorDescription?.contains("ogg") == true)
    }

    @Test("assetNotPlayable 错误包含文件名")
    func testAssetNotPlayableDescription() {
        let url = URL(fileURLWithPath: "/path/to/damaged.flac")
        let error = AudioEngineError.assetNotPlayable(url)
        #expect(error.errorDescription?.contains("damaged.flac") == true)
    }

    @Test("loadFailed 错误包含底层错误信息")
    func testLoadFailedDescription() {
        let underlying = NSError(domain: "test", code: -1, userInfo: [NSLocalizedDescriptionKey: "decode error"])
        let error = AudioEngineError.loadFailed(underlying: underlying)
        #expect(error.errorDescription?.contains("decode error") == true)
    }

    @Test("所有错误 case 都有非空描述")
    func testAllCasesHaveDescription() {
        let url = URL(fileURLWithPath: "/test.mp3")
        let underlying = NSError(domain: "test", code: 0)
        let errors: [AudioEngineError] = [
            .fileNotFound(url),
            .unsupportedFormat("xyz"),
            .assetNotPlayable(url),
            .loadFailed(underlying: underlying)
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
        let err = AudioEngineError.unsupportedFormat("ogg")
        let state: PlaybackState = .error(err)
        if case .error(let e) = state {
            #expect(e.localizedDescription.contains("ogg"))
        } else {
            #expect(Bool(false), "应为 error 状态")
        }
    }
}
