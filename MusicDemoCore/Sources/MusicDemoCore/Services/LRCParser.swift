import Foundation

/// LRC 格式歌词解析器（纯 Foundation 实现，提取自 LyricsService）
public enum LRCParser {

    /// 解析 LRC 格式字符串为歌词时间轴
    public static func parse(_ content: String) -> [LyricsLine] {
        var lines: [LyricsLine] = []
        let rawLines = content.components(separatedBy: "\n")
        let pattern = #"\[(\d{2}):(\d{2})\.(\d{2,3})\](.*)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        for line in rawLines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("[") else { continue }
            guard let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) else { continue }

            func group(_ i: Int) -> String {
                guard let r = Range(match.range(at: i), in: trimmed) else { return "" }
                return String(trimmed[r])
            }

            let minutes = Double(group(1)) ?? 0
            let seconds = Double(group(2)) ?? 0
            let centiseconds = Double(group(3)) ?? 0
            let divisor: Double = group(3).count == 3 ? 1000 : 100
            let timestamp = minutes * 60 + seconds + centiseconds / divisor
            let text = group(4).trimmingCharacters(in: .whitespaces)
            if !text.isEmpty {
                lines.append(LyricsLine(timestamp: timestamp, text: text))
            }
        }
        return lines.sorted { $0.timestamp < $1.timestamp }
    }
}
