import Testing
import Foundation
import AVFoundation
@testable import TuneHaven

// MARK: - 导出前查重

@Suite("Apple Music 导出前查重")
struct AppleMusicDuplicateIndexTests {

    @Test("歌名、艺术家相同且时长在 1.5 秒内视为已导入，忽略大小写和首尾空格")
    func matchesSameSong() {
        let index = AppleMusicDuplicateIndex(songs: [makeSong(title: "七里香", artist: "周杰伦", duration: 299.4)])
        #expect(index.contains(title: "七里香", artist: "周杰伦", duration: 299.4))
        #expect(index.contains(title: " 七里香 ", artist: "周杰伦", duration: 300.8))
        let latin = AppleMusicDuplicateIndex(songs: [makeSong(title: "Yesterday", artist: "The Beatles", duration: 125)])
        #expect(latin.contains(title: "yesterday", artist: "the beatles", duration: 125))
    }

    @Test("时长相差超过 1.5 秒、歌名或艺术家不同都不算重复")
    func rejectsDifferentSong() {
        let index = AppleMusicDuplicateIndex(songs: [makeSong(title: "七里香", artist: "周杰伦", duration: 299)])
        #expect(!index.contains(title: "七里香", artist: "周杰伦", duration: 302))
        #expect(!index.contains(title: "七里香 (Live)", artist: "周杰伦", duration: 299))
        #expect(!index.contains(title: "七里香", artist: "未知艺术家", duration: 299))
    }

    @Test("音频缺失的占位歌曲不算已导入，让导入流程把音频挂回去")
    func ignoresMissingAudioSongs() {
        let base = makeSong(title: "夜曲", artist: "周杰伦", duration: 226)
        let missing = Song(
            id: base.id, title: base.title, artist: base.artist, album: base.album,
            duration: base.duration, fileHash: base.fileHash, fileRelativePath: "missing/\(base.id.uuidString)",
            coverImagePath: nil, lyricsPath: nil, lyricsSource: nil, metadata: base.metadata,
            importDate: base.importDate, fileSize: 0, playCount: 0, isFavorite: false,
            favoriteDate: nil, lastPlayedDate: nil
        )
        #expect(missing.isAudioMissing)
        let index = AppleMusicDuplicateIndex(songs: [missing])
        #expect(!index.contains(title: "夜曲", artist: "周杰伦", duration: 226))
    }
}

// MARK: - 按编码导出

@Suite("Apple Music 按编码原样导出")
struct AppleMusicExporterTests {

    private func makeDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("am-export-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func duration(of url: URL) async throws -> Double {
        try await AVURLAsset(url: url).load(.duration).seconds
    }

    /// 用 AVAudioFile 写一段 1 秒的正弦波
    private func writeTone(to url: URL, settings: [String: Any]) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        let file = try AVAudioFile(forWriting: url, settings: settings)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44100)!
        buffer.frameLength = 44100
        let samples = buffer.floatChannelData![0]
        for i in 0..<44100 { samples[i] = Float(sin(2 * Double.pi * 440 * Double(i) / 44100)) * 0.3 }
        try file.write(from: buffer)
    }

    @Test("MP3 原样提取为 mp3，不转码，时长不变")
    func mp3IsExtractedWithoutTranscoding() async throws {
        let source = try #require(Bundle(for: TestBundleToken.self).url(forResource: "sine-2s", withExtension: "mp3"))
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let output = try #require(await AppleMusicExporter.export(assetURL: source, to: dir))
        #expect(output.fileExtension == "mp3")
        #expect(!output.transcoded)
        #expect(try await AVURLAsset(url: output.url).load(.isPlayable))
        let expected = try await duration(of: source)
        #expect(abs(try await duration(of: output.url) - expected) < 0.1)
    }

    @Test("AAC 原样导出为 m4a，不转码")
    func aacIsPassedThrough() async throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appendingPathComponent("tone.m4a")
        try writeTone(to: source, settings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
        ])

        let output = try #require(await AppleMusicExporter.export(assetURL: source, to: dir))
        #expect(output.fileExtension == "m4a")
        #expect(!output.transcoded)
    }

    @Test("PCM 原样导出为 wav，不转码")
    func pcmIsPassedThroughAsWav() async throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appendingPathComponent("tone.wav")
        try writeTone(to: source, settings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ])

        let output = try #require(await AppleMusicExporter.export(assetURL: source, to: dir))
        #expect(output.fileExtension == "wav")
        #expect(!output.transcoded)
    }
}

private final class TestBundleToken {}

// MARK: - 临时文件移动进 Music 目录

@Suite("FileStorageService.moveToMusic", .serialized)
struct MoveToMusicTests {

    private func makeTempFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mp3")
        try Data(repeating: 1, count: 64).write(to: url)
        return url
    }

    @Test("移动后源文件消失，目标文件存在")
    func movesFile() throws {
        SandboxPathManager.createAllDirectories()
        let source = try makeTempFile()
        let hash = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let relativePath = try FileStorageService.shared.moveToMusic(from: source, fileHash: hash, originalFileName: "move-test.mp3")
        let dest = SandboxPathManager.musicFileURL(relativePath: relativePath)
        defer { try? FileManager.default.removeItem(at: dest) }

        #expect(!FileManager.default.fileExists(atPath: source.path))
        #expect(FileManager.default.fileExists(atPath: dest.path))
    }

    @Test("目标已存在时保留目标，删除源文件")
    func keepsExistingDestination() throws {
        SandboxPathManager.createAllDirectories()
        let hash = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let first = try makeTempFile()
        let relativePath = try FileStorageService.shared.moveToMusic(from: first, fileHash: hash, originalFileName: "dup-test.mp3")
        let dest = SandboxPathManager.musicFileURL(relativePath: relativePath)
        defer { try? FileManager.default.removeItem(at: dest) }

        let second = try makeTempFile()
        let again = try FileStorageService.shared.moveToMusic(from: second, fileHash: hash, originalFileName: "dup-test.mp3")
        #expect(again == relativePath)
        #expect(!FileManager.default.fileExists(atPath: second.path))
        #expect(FileManager.default.fileExists(atPath: dest.path))
    }
}
