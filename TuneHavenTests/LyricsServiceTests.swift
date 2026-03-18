import Testing
import Foundation
@testable import TuneHaven

// MARK: - LyricsService Tests

@Suite("LyricsService Tests - LRC 解析")
struct LyricsServiceTests {

    private let service = LyricsService.shared

    // MARK: - 基础 LRC 解析

    @Test("解析标准 LRC 格式（厘秒 .xx）")
    func testParseLRCBasicCentiseconds() {
        let lrc = """
        [00:12.34]第一行歌词
        [01:05.78]第二行歌词
        [02:30.00]第三行歌词
        """

        let lines = service.parseLRC(lrc)

        #expect(lines.count == 3)
        #expect(lines[0].text == "第一行歌词")
        #expect(abs(lines[0].timestamp - 12.34) < 0.01)
        #expect(lines[1].text == "第二行歌词")
        #expect(abs(lines[1].timestamp - 65.78) < 0.01)
        #expect(lines[2].text == "第三行歌词")
        #expect(abs(lines[2].timestamp - 150.0) < 0.01)
    }

    @Test("解析毫秒格式 LRC（.xxx 三位）")
    func testParseLRCMilliseconds() {
        let lrc = """
        [00:15.500]带毫秒的歌词
        [01:20.750]第二行毫秒歌词
        """

        let lines = service.parseLRC(lrc)

        #expect(lines.count == 2)
        #expect(abs(lines[0].timestamp - 15.5) < 0.001)
        #expect(abs(lines[1].timestamp - 80.75) < 0.001)
    }

    @Test("解析带分钟的 LRC 时间戳")
    func testParseLRCWithMinutes() {
        let lrc = """
        [03:45.00]三分四十五秒处的歌词
        [10:00.00]十分钟处的歌词
        """

        let lines = service.parseLRC(lrc)

        #expect(lines.count == 2)
        #expect(abs(lines[0].timestamp - 225.0) < 0.01) // 3*60 + 45 = 225
        #expect(abs(lines[1].timestamp - 600.0) < 0.01) // 10*60 = 600
    }

    // MARK: - 排序

    @Test("解析结果按时间戳升序排列")
    func testParseLRCSortedByTimestamp() {
        // LRC 中时间戳故意乱序
        let lrc = """
        [02:00.00]第三行
        [00:30.00]第一行
        [01:15.00]第二行
        """

        let lines = service.parseLRC(lrc)

        #expect(lines.count == 3)
        #expect(lines[0].text == "第一行")
        #expect(lines[1].text == "第二行")
        #expect(lines[2].text == "第三行")
        // 验证时间戳是升序
        for i in 1..<lines.count {
            #expect(lines[i].timestamp >= lines[i-1].timestamp)
        }
    }

    // MARK: - 空内容处理

    @Test("空字符串返回空数组")
    func testParseLRCEmpty() {
        let lines = service.parseLRC("")
        #expect(lines.isEmpty)
    }

    @Test("无时间戳的内容返回空数组")
    func testParseLRCNoTimestamps() {
        let content = """
        这是纯文本
        没有时间戳格式
        [标题]但不是时间格式的标签
        """

        let lines = service.parseLRC(content)
        #expect(lines.isEmpty)
    }

    @Test("空文本行（有时间戳但无歌词）被跳过")
    func testParseLRCEmptyTextLines() {
        let lrc = """
        [00:10.00]有歌词的行
        [00:20.00]
        [00:30.00]也有歌词
        """

        let lines = service.parseLRC(lrc)

        #expect(lines.count == 2)
        #expect(lines[0].text == "有歌词的行")
        #expect(lines[1].text == "也有歌词")
    }

    // MARK: - 边界情况

    @Test("仅有一行 LRC")
    func testParseLRCSingleLine() {
        let lrc = "[00:00.00]唯一的一行歌词"
        let lines = service.parseLRC(lrc)

        #expect(lines.count == 1)
        #expect(lines[0].text == "唯一的一行歌词")
        #expect(abs(lines[0].timestamp - 0.0) < 0.01)
    }

    @Test("歌词行包含前后空格时会被裁剪")
    func testParseLRCTrimsTextWhitespace() {
        let lrc = "[00:10.00]  前后有空格的歌词  "
        let lines = service.parseLRC(lrc)

        #expect(lines.count == 1)
        #expect(lines[0].text == "前后有空格的歌词")
    }

    @Test("LRC 包含混合格式（标准元数据标签 + 歌词）")
    func testParseLRCWithMetadataTags() {
        let lrc = """
        [ti:夜曲]
        [ar:周杰伦]
        [al:十一月的萧邦]
        [00:00.00]第一行歌词
        [00:30.00]第二行歌词
        """

        let lines = service.parseLRC(lrc)

        // 元数据标签不应被解析为歌词行（因为格式不匹配 [mm:ss.xx] 格式）
        #expect(lines.count == 2)
        #expect(lines[0].text == "第一行歌词")
    }

    @Test("每行都有唯一的 id")
    func testParseLRCUniqueIds() {
        let lrc = """
        [00:10.00]行一
        [00:20.00]行二
        [00:30.00]行三
        """

        let lines = service.parseLRC(lrc)
        let ids = lines.map { $0.id }
        let uniqueIds = Set(ids)

        #expect(ids.count == uniqueIds.count)
    }

    @Test("大型 LRC 文件解析性能")
    func testParseLRCLargeFile() {
        var lrcLines: [String] = []
        for i in 0..<200 {
            let minutes = i / 60
            let seconds = i % 60
            lrcLines.append(String(format: "[%02d:%02d.00]第 %d 行歌词", minutes, seconds, i + 1))
        }
        let lrc = lrcLines.joined(separator: "\n")

        let lines = service.parseLRC(lrc)
        #expect(lines.count == 200)
    }

    // MARK: - 时间戳精度

    @Test("时间戳计算精度：00:01.50 = 1.5 秒")
    func testParseLRCTimestampPrecision() {
        let lrc = "[00:01.50]精度测试"
        let lines = service.parseLRC(lrc)

        #expect(lines.count == 1)
        #expect(abs(lines[0].timestamp - 1.5) < 0.01)
    }

    @Test("时间戳计算精度：01:01.01 = 61.01 秒")
    func testParseLRCTimestampCalculation() {
        let lrc = "[01:01.01]计算测试"
        let lines = service.parseLRC(lrc)

        #expect(lines.count == 1)
        #expect(abs(lines[0].timestamp - 61.01) < 0.01)
    }

    @Test("同一时间戳的多行歌词都被解析")
    func testParseLRCSameTimestamp() {
        // 某些 LRC 文件中同一时间可能有多行（虽然不常见）
        let lrc = """
        [00:10.00]行一
        [00:10.00]行二（相同时间）
        [00:20.00]行三
        """

        let lines = service.parseLRC(lrc)
        #expect(lines.count == 3)
    }
}
