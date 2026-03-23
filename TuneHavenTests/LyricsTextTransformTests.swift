import Testing
import Foundation
@testable import TuneHaven

@Suite("LyricsTextTransform")
struct LyricsTextTransformTests {

    @Test("preferSimplified 为 false 时保持原文")
    func passthroughWhenFalse() {
        let s = "繁體與简体"
        #expect(LyricsTextTransform.displayText(s, preferSimplified: false) == s)
    }

    @Test("preferSimplified 为 true 时将常见繁体转为简体")
    func simplifiesTraditional() {
        let out = LyricsTextTransform.displayText("國", preferSimplified: true)
        #expect(out == "国")
    }

    @Test("简体输入在 preferSimplified 下基本不变")
    func simplifiedInputStable() {
        let s = "七里香"
        #expect(LyricsTextTransform.displayText(s, preferSimplified: true) == s)
    }

    // MARK: - 补充用例

    @Test("空字符串两种模式下都返回空串")
    func emptyString() {
        #expect(LyricsTextTransform.displayText("", preferSimplified: false) == "")
        #expect(LyricsTextTransform.displayText("", preferSimplified: true) == "")
    }

    @Test("纯英文/数字/符号在简体模式下不变")
    func asciiOnly() {
        let s = "Hello World 123!@#"
        #expect(LyricsTextTransform.displayText(s, preferSimplified: true) == s)
    }

    @Test("长文本繁转简不截断")
    func longText() {
        let line = "這是一段很長的繁體歌詞文字，用於測試轉換功能是否正常運作"
        let result = LyricsTextTransform.displayText(line, preferSimplified: true)
        #expect(result.count == line.count)
        #expect(result != line)
    }

    @Test("混合中英文歌词正确转换")
    func mixedChineseEnglish() {
        let s = "Love 愛 Forever 國"
        let result = LyricsTextTransform.displayText(s, preferSimplified: true)
        #expect(result.contains("Love"))
        #expect(result.contains("Forever"))
    }

    @Test("多行歌词正确处理")
    func multiLine() {
        let s = "第一行國\n第二行愛\n第三行"
        let result = LyricsTextTransform.displayText(s, preferSimplified: true)
        #expect(result.contains("\n"))
        let lines = result.components(separatedBy: "\n")
        #expect(lines.count == 3)
    }

    @Test("特殊 Unicode 字符不被破坏")
    func specialUnicode() {
        let s = "🎵 音樂 ♬ 節奏"
        let result = LyricsTextTransform.displayText(s, preferSimplified: true)
        #expect(result.contains("🎵"))
        #expect(result.contains("♬"))
    }
}
