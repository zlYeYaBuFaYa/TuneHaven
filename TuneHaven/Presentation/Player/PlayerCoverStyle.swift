import Foundation

/// 播放器封面样式（docs/UI设计文档.md §7.3）。唱片只是展示，不修改原封面文件；
/// 圆形可能裁到封面边缘的文字，所以始终允许切回完整方形。
enum PlayerCoverStyle: String {
    case auto
    case square
    case disc

    /// 「自动」时晴屿用唱片，其他主题用方形
    func resolved(themeID: String) -> PlayerCoverStyle {
        guard self == .auto else { return self }
        return themeID == "clear_isle" ? .disc : .square
    }
}

/// 播放器音质标签。只展示真实已知数据：无损来自 `Song.isLossless`，采样率来自元数据。
/// `Metadata` 没有位深字段，不显示「24-BIT」之类的固定值；未知字段隐藏（docs/UI设计文档.md §7.3）。
enum PlayerQualityTag {
    static func tags(for song: Song) -> [String] {
        var tags: [String] = []
        if song.isLossless { tags.append("LOSSLESS") }
        if let rate = sampleRateText(song.metadata.sampleRate) { tags.append(rate) }
        return tags
    }

    /// VoiceOver 读法：「无损，48 千赫」
    static func spoken(for song: Song) -> String {
        var parts: [String] = []
        if song.isLossless { parts.append("无损") }
        if let rate = sampleRateText(song.metadata.sampleRate) {
            parts.append(rate.replacingOccurrences(of: " kHz", with: " 千赫"))
        }
        return parts.joined(separator: "，")
    }

    static func sampleRateText(_ hz: Int?) -> String? {
        guard let hz, hz > 0 else { return nil }
        let khz = Double(hz) / 1000
        let text = khz.rounded() == khz ? String(Int(khz)) : String(format: "%.1f", khz)
        return "\(text) kHz"
    }
}
