import Foundation
import Testing
@testable import TuneHaven

@Suite("FLAC 原生标签")
struct FLACMetadataTests {
    private final class BundleToken {}

    @Test("真实 FLAC 经导入解析器得到中文标签和音频属性")
    func taggedFile() async throws {
        let url = try #require(Bundle(for: BundleToken.self).url(forResource: "tagged", withExtension: "flac"))
        let metadata = await AudioMetadataParser.shared.parse(url: url)
        #expect(metadata.title == "测试夜曲")
        #expect(metadata.artist == "TuneHaven Artist")
        #expect(metadata.album == "标签专辑")
        #expect(metadata.trackNumber == 3)
        #expect(metadata.year == 2026)
        #expect(metadata.genre == "Ambient")
        #expect(metadata.sampleRate == 22050)
        #expect(metadata.channels == 1)
        #expect(metadata.duration > 0)
    }

    @Test("大小写标签、等号内容、空值与损坏长度安全处理")
    func commentsAndBounds() throws {
        var comments = little(0) + little(4)
        for field in ["title=", "TiTlE=夜=曲", "ARTIST=测试艺术家", "ALBUM=专辑"] {
            comments += little(field.utf8.count) + Data(field.utf8)
        }
        let parsed = try read(block: comments, type: 4)
        #expect(parsed?.tags["TITLE"] == "夜=曲")
        #expect(parsed?.tags["ARTIST"] == "测试艺术家")
        #expect(try read(block: little(Int(UInt32.max)), type: 4)?.tags.isEmpty == true)
    }

    @Test("图片块优先采用封面，忽略外部 URL 图片")
    func frontCover() throws {
        func picture(type: Int, mime: String, payload: Data) -> Data {
            big(type) + big(mime.utf8.count) + Data(mime.utf8) + big(0) + Data(repeating: 0, count: 16) + big(payload.count) + payload
        }
        let back = picture(type: 4, mime: "image/jpeg", payload: Data([1]))
        let front = picture(type: 3, mime: "image/png", payload: Data([2, 3]))
        let data = Data("fLaC".utf8) + header(back.count, type: 6) + back + header(front.count, type: 0x86) + front
        #expect(try read(data)?.coverImageData == Data([2, 3]))
        #expect(try read(block: picture(type: 3, mime: "-->", payload: Data("https://example.com".utf8)), type: 6)?.coverImageData == nil)
    }

    @Test("非 FLAC 和截断数据不越界")
    func truncated() throws {
        #expect(try read(Data("nope".utf8)) == nil)
        #expect(try read(Data("fLaC".utf8) + header(200, type: 0x84) + Data([0]))?.tags.isEmpty == true)
    }

    private func read(block: Data, type: UInt8) throws -> FLACMetadataReader? {
        try read(Data("fLaC".utf8) + header(block.count, type: type | 0x80) + block)
    }
    private func read(_ data: Data) throws -> FLACMetadataReader? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        return FLACMetadataReader.read(url: url)
    }
    private func header(_ length: Int, type: UInt8) -> Data {
        Data([type, UInt8(truncatingIfNeeded: length >> 16), UInt8(truncatingIfNeeded: length >> 8), UInt8(truncatingIfNeeded: length)])
    }
    private func little(_ value: Int) -> Data { Data((0..<4).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) }) }
    private func big(_ value: Int) -> Data { Data((0..<4).reversed().map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) }) }
}
