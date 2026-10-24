import Foundation

/// 本地拼音 / 首字母 / 轻度模糊匹配。
///
/// 拼音键是展示字符串的纯函数，放在进程内缓存里。改标题、艺术家或专辑会换成新字符串，
/// 因此不写 Core Data，避免迁移和导入、编辑路径上的脏键。
enum PinyinSearchMatcher {

    struct Key: Equatable, Sendable {
        /// `lowercased()` 后的原文，给汉字和拉丁 `contains`
        let normalized: String
        /// 去声调、无空格的全拼，只含 ASCII 字母数字
        let full: String
        /// 每个音节的首字母
        let initials: String
        /// `full` 中每个音节的字符偏移
        let syllableStarts: [Int]
    }

    struct Query: Equatable, Sendable {
        /// trim + lowercased
        let raw: String
        /// 去声调后的 ASCII 字母数字。`qi li`、`QLX` 会变成 `qili`、`qlx`
        let latin: String
        /// 拉丁长度达到 3 才允许编辑距离 1
        let allowsFuzzy: Bool
    }

    private static let minimumPinyinLength = 2
    private static let minimumFuzzyLength = 3
    private static let cache = KeyCache()

    static func prepare(_ query: String) -> Query? {
        let raw = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !raw.isEmpty else { return nil }

        let folded = raw.applyingTransform(.stripDiacritics, reverse: false) ?? raw
        var latin = ""
        latin.reserveCapacity(folded.count)
        for scalar in folded.unicodeScalars where isAsciiAlphanumeric(scalar) {
            latin.append(Character(scalar))
        }
        return Query(raw: raw, latin: latin, allowsFuzzy: latin.count >= minimumFuzzyLength)
    }

    static func key(for text: String) -> Key {
        cache.key(for: text)
    }

    static func matches(text: String, query: Query) -> Bool {
        if text.isEmpty || query.raw.isEmpty { return false }
        return matches(key: key(for: text), query: query)
    }

    static func matches(key: Key, query: Query) -> Bool {
        if query.raw.isEmpty { return false }
        if key.normalized.contains(query.raw) { return true }
        guard query.latin.count >= minimumPinyinLength else { return false }

        if matchesSyllablePrefix(key, needle: query.latin) { return true }
        if key.initials.contains(query.latin) { return true }
        guard query.allowsFuzzy else { return false }

        if withinEditDistanceOne(key.full, query.latin) { return true }
        if withinEditDistanceOne(key.initials, query.latin) { return true }
        return false
    }

    static func matchesSong(_ song: Song, query: Query) -> Bool {
        matches(text: song.title, query: query)
            || matches(text: song.artist, query: query)
            || matches(text: song.album, query: query)
    }

    static func songMatches(_ song: Song, query: String) -> Bool {
        guard let prepared = prepare(query) else { return false }
        return matchesSong(song, query: prepared)
    }

    // MARK: - 拼音键

    /// 系统普通话罗马字按音节插空格。首字母依赖这些边界；若将来系统不再分词，单测会先失败。
    private static func derive(_ text: String) -> Key {
        let normalized = text.lowercased()
        let mandarin = text.applyingTransform(.mandarinToLatin, reverse: false) ?? text
        let stripped = mandarin.applyingTransform(.stripDiacritics, reverse: false) ?? mandarin
        let lowered = stripped.lowercased()

        var full = ""
        var initials = ""
        var syllableStarts: [Int] = []
        var current = ""

        func flush() {
            guard let first = current.first else { return }
            syllableStarts.append(full.count)
            full.append(contentsOf: current)
            initials.append(first)
            current.removeAll(keepingCapacity: true)
        }

        for scalar in lowered.unicodeScalars {
            if isAsciiAlphanumeric(scalar) {
                current.append(Character(scalar))
            } else {
                flush()
            }
        }
        flush()

        return Key(
            normalized: normalized,
            full: full,
            initials: initials,
            syllableStarts: syllableStarts
        )
    }

    /// 全拼必须从音节起点开始，避免 `yue` + `de` 被 `ed` 这样的跨音节子串命中。
    private static func matchesSyllablePrefix(_ key: Key, needle: String) -> Bool {
        guard !key.full.isEmpty, !needle.isEmpty else { return false }
        for start in key.syllableStarts where start < key.full.count {
            if key.full.dropFirst(start).hasPrefix(needle) {
                return true
            }
        }
        return false
    }

    private static func isAsciiAlphanumeric(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 48...57, 65...90, 97...122:
            return true
        default:
            return false
        }
    }

    /// 整段比较，不做滑窗。长度差大于 1 时不可能是编辑距离 1。
    /// 相邻字母对调是两次替换，不命中。
    private static func withinEditDistanceOne(_ haystack: String, _ needle: String) -> Bool {
        if haystack.isEmpty || needle.isEmpty { return false }
        let h = Array(haystack.utf8)
        let n = Array(needle.utf8)
        let window = h.count
        let nLen = n.count
        let diff = window - nLen
        if abs(diff) > 1 { return false }

        if diff == 0 {
            var mismatches = 0
            for index in 0..<nLen {
                if h[index] != n[index] {
                    mismatches += 1
                    if mismatches > 1 { return false }
                }
            }
            return true
        }

        let longerIsHaystack = diff == 1
        var haystackIndex = 0
        var needleIndex = 0
        var skipped = false
        while haystackIndex < window && needleIndex < nLen {
            if h[haystackIndex] == n[needleIndex] {
                haystackIndex += 1
                needleIndex += 1
            } else if !skipped {
                skipped = true
                if longerIsHaystack {
                    haystackIndex += 1
                } else {
                    needleIndex += 1
                }
            } else {
                return false
            }
        }

        let remainHaystack = window - haystackIndex
        let remainNeedle = nLen - needleIndex
        if longerIsHaystack {
            if remainNeedle != 0 { return false }
            return remainHaystack == 0 || (remainHaystack == 1 && !skipped)
        }
        if remainHaystack != 0 { return false }
        return remainNeedle == 0 || (remainNeedle == 1 && !skipped)
    }

    private final class KeyCache: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [String: Key] = [:]

        func key(for text: String) -> Key {
            lock.lock()
            if let cached = storage[text] {
                lock.unlock()
                return cached
            }
            lock.unlock()

            let derived = PinyinSearchMatcher.derive(text)

            lock.lock()
            if let cached = storage[text] {
                lock.unlock()
                return cached
            }
            storage[text] = derived
            lock.unlock()
            return derived
        }
    }
}
