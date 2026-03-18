import Testing
import Foundation
@testable import TuneHaven

// MARK: - AudioFormat Enum Tests

@Suite("AudioFormat Tests")
struct AudioFormatTests {

    // MARK: - 枚举完整性

    @Test("AudioFormat 包含所有支持的格式")
    func testAllFormatsPresent() {
        let expected: [AudioFormat] = [.all, .mp3, .m4a, .aac, .alac, .wav, .flac, .aiff, .caf]
        for format in expected {
            #expect(AudioFormat.allCases.contains(format), "\(format.rawValue) 应在 allCases 中")
        }
    }

    @Test("AudioFormat.allCases 数量正确")
    func testAllCasesCount() {
        #expect(AudioFormat.allCases.count == 9)
    }

    // MARK: - displayName

    @Test("每个格式都有非空 displayName")
    func testDisplayNameNotEmpty() {
        for format in AudioFormat.allCases {
            #expect(!format.displayName.isEmpty, "\(format.rawValue) 的 displayName 不应为空")
        }
    }

    @Test("无损格式 displayName 包含'无损'标记")
    func testLosslessDisplayNameLabel() {
        let losslessFormats: [AudioFormat] = [.alac, .flac, .aiff]
        for format in losslessFormats {
            #expect(format.displayName.contains("无损"), "\(format.rawValue) 的 displayName 应包含'无损'")
        }
    }

    @Test("FLAC displayName 不再标注'暂不支持'")
    func testFlacNoLongerUnsupported() {
        #expect(!AudioFormat.flac.displayName.contains("暂不支持"))
        #expect(AudioFormat.flac.displayName.contains("无损"))
    }

    @Test("all 格式的 displayName 为'全部格式'")
    func testAllFormatDisplayName() {
        #expect(AudioFormat.all.displayName == "全部格式")
    }

    // MARK: - isLossless

    @Test("无损格式 isLossless 返回 true")
    func testIsLosslessTrueForLossless() {
        let lossless: [AudioFormat] = [.alac, .wav, .flac, .aiff, .caf]
        for format in lossless {
            #expect(format.isLossless, "\(format.rawValue) 应为无损格式")
        }
    }

    @Test("有损格式 isLossless 返回 false")
    func testIsLosslessFalseForLossy() {
        let lossy: [AudioFormat] = [.mp3, .m4a, .aac, .all]
        for format in lossy {
            #expect(!format.isLossless, "\(format.rawValue) 不应为无损格式")
        }
    }

    // MARK: - rawValue

    @Test("rawValue 与格式扩展名一致")
    func testRawValues() {
        #expect(AudioFormat.mp3.rawValue == "mp3")
        #expect(AudioFormat.m4a.rawValue == "m4a")
        #expect(AudioFormat.aac.rawValue == "aac")
        #expect(AudioFormat.alac.rawValue == "alac")
        #expect(AudioFormat.wav.rawValue == "wav")
        #expect(AudioFormat.flac.rawValue == "flac")
        #expect(AudioFormat.aiff.rawValue == "aiff")
        #expect(AudioFormat.caf.rawValue == "caf")
    }

    @Test("rawValue 可反向初始化")
    func testInitFromRawValue() {
        for format in AudioFormat.allCases {
            let recovered = AudioFormat(rawValue: format.rawValue)
            #expect(recovered == format)
        }
    }

    // MARK: - FileStorageService 格式一致性

    @Test("AudioFormat 枚举与 FileStorageService.supportedExtensions 一致")
    func testFormatConsistencyWithFileStorage() {
        let enumFormats = AudioFormat.allCases
            .filter { $0 != .all }
            .map { $0.rawValue }
        let supported = FileStorageService.supportedExtensions

        for ext in enumFormats {
            if ext == "aiff" {
                #expect(supported.contains("aiff") || supported.contains("aif"),
                        "AIFF 格式应在 supportedExtensions 中（aiff 或 aif）")
            } else {
                #expect(supported.contains(ext), "AudioFormat.\(ext) 应在 supportedExtensions 中")
            }
        }
    }
}
