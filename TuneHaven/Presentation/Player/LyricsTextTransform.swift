import Foundation

enum LyricsTextTransform {
    /// `preferSimplified == true`：繁体转简体显示（简体源基本不变）。
    /// `false`：按歌词文件原文显示。
    static func displayText(_ text: String, preferSimplified: Bool) -> String {
        guard preferSimplified else { return text }
        let mutable = NSMutableString(string: text)
        CFStringTransform(mutable, nil, "Traditional-Simplified" as CFString, false)
        return mutable as String
    }
}
