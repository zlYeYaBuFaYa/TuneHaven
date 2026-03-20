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
}
