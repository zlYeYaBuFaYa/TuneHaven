import SwiftUI

/// 正在播放标记。只在真正播放时跳动；暂停或开启「减少动态效果」时静止（docs/UI设计文档.md §7.1、§8）。
struct WaveformIndicator: View {
    let color: Color
    var isAnimating: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Image(systemName: "waveform")
            .font(.subheadline.weight(.semibold))
            .foregroundColor(color)
            .symbolEffect(.variableColor.iterative, isActive: isAnimating && !reduceMotion)
            .accessibilityHidden(true)
    }
}
