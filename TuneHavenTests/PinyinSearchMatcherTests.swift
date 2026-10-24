import Testing
import Foundation
@testable import TuneHaven

@Suite("PinyinSearchMatcher Tests")
struct PinyinSearchMatcherTests {

    private func key(_ normalized: String, _ parts: [String]) -> PinyinSearchMatcher.Key {
        var full = ""
        var starts: [Int] = []
        var initials = ""
        for part in parts {
            starts.append(full.count)
            full.append(contentsOf: part)
            if let first = part.first {
                initials.append(first)
            }
        }
        return PinyinSearchMatcher.Key(
            normalized: normalized,
            full: full,
            initials: initials,
            syllableStarts: starts
        )
    }

    private func matches(_ normalized: String, _ parts: [String], query raw: String) -> Bool {
        guard let prepared = PinyinSearchMatcher.prepare(raw) else { return false }
        return PinyinSearchMatcher.matches(key: key(normalized, parts), query: prepared)
    }

    // MARK: - 原文 contains

    @Test("空 query 与空白 query 不匹配")
    func testEmptyQuery() {
        #expect(PinyinSearchMatcher.prepare("") == nil)
        #expect(PinyinSearchMatcher.prepare("   ") == nil)
        #expect(!PinyinSearchMatcher.songMatches(makeSong(title: "七里香"), query: "  "))
    }

    @Test("汉字子串包含，包括非前缀")
    func testChineseContains() {
        #expect(matches("七里香", ["qi", "li", "xiang"], query: "里香"))
        #expect(matches("七里香", ["qi", "li", "xiang"], query: "香"))
        #expect(matches("夜曲", ["ye", "qu"], query: "曲"))
        #expect(!matches("七里香", ["qi", "li", "xiang"], query: "七里乡"))
    }

    @Test("拉丁原文包含且大小写不敏感")
    func testLatinContainsCaseInsensitive() {
        #expect(matches("perfect", ["perfect"], query: "PERFECT"))
        #expect(matches("perfect", ["perfect"], query: "erfe"))
        #expect(matches("ed sheeran", ["ed", "sheeran"], query: "Ed"))
    }

    // MARK: - 全拼与首字母

    @Test("全拼从音节起点前缀匹配")
    func testFullPinyinSyllablePrefix() {
        #expect(matches("七里香", ["qi", "li", "xiang"], query: "qili"))
        #expect(matches("七里香", ["qi", "li", "xiang"], query: "qilixiang"))
        #expect(matches("七里香", ["qi", "li", "xiang"], query: "xiang"))
        #expect(matches("周杰伦", ["zhou", "jie", "lun"], query: "zhou"))
        #expect(matches("周杰伦", ["zhou", "jie", "lun"], query: "zh"))
        #expect(matches("周杰伦", ["zhou", "jie", "lun"], query: "jie"))
        #expect(!matches("七里香", ["qi", "li", "xiang"], query: "ili"))
    }

    @Test("空格和大小写折成同一条全拼")
    func testPinyinIgnoresSpaceAndCase() {
        #expect(matches("七里香", ["qi", "li", "xiang"], query: "qi li xiang"))
        #expect(matches("七里香", ["qi", "li", "xiang"], query: "QLX"))
        #expect(matches("周杰伦", ["zhou", "jie", "lun"], query: "ZjL"))
    }

    @Test("首字母连续包含")
    func testInitialsContains() {
        #expect(matches("七里香", ["qi", "li", "xiang"], query: "qlx"))
        #expect(matches("七里香", ["qi", "li", "xiang"], query: "ql"))
        #expect(matches("七里香", ["qi", "li", "xiang"], query: "lx"))
        #expect(matches("周杰伦", ["zhou", "jie", "lun"], query: "zjl"))
        #expect(matches("周杰伦", ["zhou", "jie", "lun"], query: "zj"))
        #expect(matches("shape of you", ["shape", "of", "you"], query: "soy"))
    }

    @Test("单个拉丁字母不走拼音索引")
    func testSingleLatinLetterSkipsPinyin() {
        #expect(!matches("七里香", ["qi", "li", "xiang"], query: "q"))
        #expect(!matches("周杰伦", ["zhou", "jie", "lun"], query: "z"))
        #expect(matches("adele", ["adele"], query: "a"))
    }

    @Test("跨音节子串不算全拼命中")
    func testDoesNotMatchAcrossSyllableBoundary() {
        let album = ["shi", "yi", "yue", "de", "xiao", "bang"]
        #expect(!matches("十一月的萧邦", album, query: "ed"))
        #expect(matches("十一月的萧邦", album, query: "de"))
        #expect(matches("十一月的萧邦", album, query: "xiao"))
    }

    // MARK: - 编辑距离

    @Test("整段全拼编辑距离 1：替换、插入、删除")
    func testFullPinyinEditDistanceOne() {
        #expect(matches("七里香", ["qi", "li", "xiang"], query: "qilixiayg"))
        #expect(matches("七里香", ["qi", "li", "xiang"], query: "xqilixiang"))
        #expect(matches("七里香", ["qi", "li", "xiang"], query: "qilxiang"))
        #expect(matches("七里香", ["qi", "li", "xiang"], query: "qilixiangg"))
        #expect(matches("perfect", ["perfect"], query: "perfeet"))
    }

    @Test("整段首字母编辑距离 1")
    func testInitialsEditDistanceOne() {
        #expect(matches("周杰伦", ["zhou", "jie", "lun"], query: "zjk"))
        #expect(matches("七里香", ["qi", "li", "xiang"], query: "qlg"))
        #expect(matches("周杰伦", ["zhou", "jie", "lun"], query: "zjlx"))
    }

    @Test("长度不超过 2 时关闭模糊")
    func testFuzzyDisabledForShortQuery() {
        #expect(!matches("周杰伦", ["zhou", "jie", "lun"], query: "zg"))
        #expect(!matches("七里香", ["qi", "li", "xiang"], query: "qx"))
        #expect(matches("周杰伦", ["zhou", "jie", "lun"], query: "zj"))
    }

    @Test("编辑距离 2 与相邻对调不命中")
    func testEditDistanceTwoAndTranspositionMiss() {
        #expect(!matches("七里香", ["qi", "li", "xiang"], query: "qilixagn"))
        #expect(!matches("七里香", ["qi", "li", "xiang"], query: "xyz"))
        #expect(!matches("perfect", ["perfect"], query: "prefect"))
    }

    @Test("模糊不做滑窗，短 query 不误中其它音节")
    func testFuzzyDoesNotSlideIntoOtherSyllables() {
        #expect(!matches("月", ["yue"], query: "you"))
        #expect(!matches("十一月的萧邦", ["shi", "yi", "yue", "de", "xiao", "bang"], query: "soy"))
        #expect(!matches("周杰伦", ["zhou", "jie", "lun"], query: "jay"))
    }

    @Test("符号曲名只走原文")
    func testSymbolOnlyTitle() {
        let song = makeSong(title: "♪★", artist: "——", album: "…")
        #expect(PinyinSearchMatcher.songMatches(song, query: "♪"))
        #expect(!PinyinSearchMatcher.songMatches(song, query: "abc"))
    }

    @Test("歌曲三字段任一命中即可")
    func testSongMatchesAnyField() {
        let song = makeSong(title: "晴天", artist: "周杰伦", album: "叶惠美")
        #expect(PinyinSearchMatcher.songMatches(song, query: "晴"))
        #expect(PinyinSearchMatcher.songMatches(song, query: "周杰"))
        #expect(PinyinSearchMatcher.songMatches(song, query: "叶惠"))
        #expect(matches("叶惠美", ["ye", "hui", "mei"], query: "yhm"))
    }

    // MARK: - 系统罗马字

    @Test("七里香的系统全拼和首字母")
    func testSystemKeyQiLiXiang() {
        let key = PinyinSearchMatcher.key(for: "七里香")
        #expect(key.full == "qilixiang")
        #expect(key.initials == "qlx")
        #expect(key.syllableStarts == [0, 2, 4])
    }

    @Test("周杰伦的系统全拼和首字母")
    func testSystemKeyZhouJieLun() {
        let key = PinyinSearchMatcher.key(for: "周杰伦")
        #expect(key.full == "zhoujielun")
        #expect(key.initials == "zjl")
        #expect(key.syllableStarts == [0, 4, 7])
    }

    @Test("繁体按库存字形生成，与对应简体键一致")
    func testTraditionalUsesStoredGlyphs() {
        let traditional = PinyinSearchMatcher.key(for: "週傑倫")
        let simplified = PinyinSearchMatcher.key(for: "周杰伦")
        #expect(traditional.full == simplified.full)
        #expect(traditional.initials == simplified.initials)
    }

    @Test("拉丁原文按词切成音节")
    func testSystemKeyLatin() {
        let artist = PinyinSearchMatcher.key(for: "Ed Sheeran")
        #expect(artist.normalized == "ed sheeran")
        #expect(artist.full == "edsheeran")
        #expect(artist.initials == "es")

        let title = PinyinSearchMatcher.key(for: "Shape of You")
        #expect(title.full == "shapeofyou")
        #expect(title.initials == "soy")
    }

    @Test("中英混合名字保留两边的首字母")
    func testMixedChineseAndLatin() {
        let key = PinyinSearchMatcher.key(for: "周杰伦 Jay")
        #expect(key.full.contains("zhoujielun"))
        #expect(key.initials.contains("zjl"))
        let song = makeSong(title: "晴天", artist: "周杰伦 Jay", album: "叶惠美")
        #expect(PinyinSearchMatcher.songMatches(song, query: "zjl"))
    }

    @Test("没有可读字母的符号不产生拼音键")
    func testSystemKeySymbolsAreEmpty() {
        let key = PinyinSearchMatcher.key(for: "♪★")
        #expect(key.full.isEmpty)
        #expect(key.initials.isEmpty)
        #expect(key.syllableStarts.isEmpty)
    }

    @Test("同一字符串的拼音键会被缓存复用")
    func testKeyCacheIsStable() {
        let first = PinyinSearchMatcher.key(for: "七里香")
        let second = PinyinSearchMatcher.key(for: "七里香")
        #expect(first == second)
    }

    @Test("带声调的拉丁 query 去掉声调后命中")
    func testQueryStripsDiacritics() {
        let song = makeSong(title: "七里香", artist: "周杰伦", album: "七里香")
        #expect(PinyinSearchMatcher.songMatches(song, query: "qīlǐxiāng"))
    }
}
