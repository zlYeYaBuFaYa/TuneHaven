import Foundation

/// 从「音乐」App 导出 MP3 时补写的标签。逐帧拷出的数据不含 ID3，只能从 `MPMediaItem` 补回。
struct MP3Tags: Sendable {
    var title: String?
    var artist: String?
    var album: String?
    var year: Int?
    var genre: String?
    var trackNumber: Int?
    var lyrics: String?
    var coverJPEG: Data?
}

/// 生成 ID3v2.3 标签。文本统一用带 BOM 的 UTF-16，中文标题和歌词才能被各家播放器正确读出。
enum ID3v2TagBuilder {
    static func build(_ tags: MP3Tags) -> Data {
        var frames = Data()
        appendText("TIT2", tags.title, to: &frames)
        appendText("TPE1", tags.artist, to: &frames)
        appendText("TALB", tags.album, to: &frames)
        appendText("TYER", tags.year.map(String.init), to: &frames)
        appendText("TCON", tags.genre, to: &frames)
        appendText("TRCK", tags.trackNumber.map(String.init), to: &frames)

        if let lyrics = tags.lyrics, !lyrics.isEmpty {
            // 编码、语言、空描述（UTF-16 以两个 0 结尾）、正文
            var body = Data([0x01]) + Data("und".utf8)
            body += utf16(""); body += Data([0, 0])
            body += utf16(lyrics)
            appendFrame("USLT", body, to: &frames)
        }
        if let cover = tags.coverJPEG, !cover.isEmpty {
            // 编码、MIME、图片类型 3（封面正面）、空描述、图片
            var body = Data([0x00]) + Data("image/jpeg".utf8) + Data([0x00, 0x03, 0x00])
            body += cover
            appendFrame("APIC", body, to: &frames)
        }
        guard !frames.isEmpty else { return Data() }

        var header = Data("ID3".utf8) + Data([0x03, 0x00, 0x00])
        header += syncsafe(frames.count)
        return header + frames
    }

    private static func appendText(_ id: String, _ value: String?, to frames: inout Data) {
        guard let value, !value.isEmpty else { return }
        appendFrame(id, Data([0x01]) + utf16(value), to: &frames)
    }

    private static func appendFrame(_ id: String, _ body: Data, to frames: inout Data) {
        frames += Data(id.utf8)
        frames += bigEndian(UInt32(body.count))
        frames += Data([0x00, 0x00])
        frames += body
    }

    private static func utf16(_ string: String) -> Data {
        var data = Data([0xFF, 0xFE])
        for unit in string.utf16 {
            data.append(UInt8(unit & 0xFF))
            data.append(UInt8(unit >> 8))
        }
        return data
    }

    private static func syncsafe(_ value: Int) -> Data {
        Data([UInt8((value >> 21) & 0x7F), UInt8((value >> 14) & 0x7F), UInt8((value >> 7) & 0x7F), UInt8(value & 0x7F)])
    }
}

/// MPEG Layer III 的 Xing 信息帧，记录总帧数、总字节数和 100 点定位表。
///
/// 逐帧拷出的 MP3 没有这一帧，VBR 歌曲的时长只能按开头码率估算，拖动进度也会跳不准。
/// 这一帧本身按静音帧编码，不认识它的解码器最多多播 1 帧静音。
struct MP3XingFrame {
    let frameLength: Int
    private let header: [UInt8]
    private let tagOffset: Int

    private static let sampleRates: [[Int]] = [[11025, 12000, 8000], [], [22050, 24000, 16000], [44100, 48000, 32000]]
    private static let mpeg1Bitrates = [0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320]
    private static let mpeg2Bitrates = [0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160]

    /// 按第一帧的版本、采样率、声道生成同规格的信息帧；不是 Layer III 时返回 nil。
    init?(firstFrameHeader h: [UInt8]) {
        guard h.count >= 4, h[0] == 0xFF, h[1] & 0xE0 == 0xE0 else { return nil }
        let version = Int((h[1] >> 3) & 0x03)
        let layer = (h[1] >> 1) & 0x03
        let sampleRateIndex = Int((h[2] >> 2) & 0x03)
        guard version != 1, layer == 0x01, sampleRateIndex != 3 else { return nil }

        let isMPEG1 = version == 3
        let isMono = (h[3] >> 6) & 0x03 == 0x03
        let sideInfo = isMPEG1 ? (isMono ? 17 : 32) : (isMono ? 9 : 17)
        tagOffset = 4 + sideInfo
        let needed = tagOffset + 16 + 100

        let sampleRate = Self.sampleRates[version][sampleRateIndex]
        let coefficient = isMPEG1 ? 144 : 72
        let bitrates = isMPEG1 ? Self.mpeg1Bitrates : Self.mpeg2Bitrates
        guard let index = (1..<bitrates.count).first(where: { coefficient * bitrates[$0] * 1000 / sampleRate >= needed }) else {
            return nil
        }
        frameLength = coefficient * bitrates[index] * 1000 / sampleRate
        // 去掉 CRC、换成足够大的码率、不加填充，其余沿用原帧
        header = [0xFF, h[1] | 0x01, UInt8(index << 4) | UInt8(sampleRateIndex << 2), h[3]]
    }

    /// `frameSizes` 是之后每个音频帧的字节数，不含信息帧本身。
    func build(frameSizes: [Int]) -> Data {
        var frame = Data(count: frameLength)
        frame.replaceSubrange(0..<4, with: header)

        let totalBytes = frameLength + frameSizes.reduce(0, +)
        var toc = [UInt8](repeating: 0, count: 100)
        if !frameSizes.isEmpty {
            var offsets: [Int] = []
            offsets.reserveCapacity(frameSizes.count)
            var position = frameLength
            for size in frameSizes {
                offsets.append(position)
                position += size
            }
            for i in 0..<100 {
                let offset = offsets[min(frameSizes.count - 1, i * frameSizes.count / 100)]
                toc[i] = UInt8(min(255, offset * 256 / totalBytes))
            }
        }

        var tag = Data("Xing".utf8)
        tag += bigEndian(UInt32(0x07)) // 帧数、字节数、定位表
        tag += bigEndian(UInt32(frameSizes.count))
        tag += bigEndian(UInt32(totalBytes))
        tag += Data(toc)
        frame.replaceSubrange(tagOffset..<(tagOffset + tag.count), with: tag)
        return frame
    }
}

private func bigEndian(_ value: UInt32) -> Data {
    Data([UInt8(value >> 24), UInt8((value >> 16) & 0xFF), UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)])
}
