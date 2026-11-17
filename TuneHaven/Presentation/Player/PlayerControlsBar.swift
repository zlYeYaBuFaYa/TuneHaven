import SwiftUI

private enum PlayerControlsBarLayout {
    static let defaultPlayButtonSize: CGFloat = 68
    static let largePlayButtonThreshold: CGFloat = 60
    static let hStackSpacing: CGFloat = 0
    static let pressScaleWhenLarge: CGFloat = 0.97
    static let pressScaleWhenSmall: CGFloat = 0.98
}

/// 播放控制栏组件，在 PlayerView 和 LyricsPageView 中共享
struct PlayerControlsBar: View {
    let playButtonSize: CGFloat
    let navFont: Font
    let modeFont: Font
    let onQueueTap: () -> Void

    @EnvironmentObject private var playback: PlaybackService
    @Environment(\.themePalette) private var palette

    init(
        playButtonSize: CGFloat = PlayerControlsBarLayout.defaultPlayButtonSize,
        navFont: Font = .title,
        modeFont: Font = .title3,
        onQueueTap: @escaping () -> Void
    ) {
        self.playButtonSize = playButtonSize
        self.navFont = navFont
        self.modeFont = modeFont
        self.onQueueTap = onQueueTap
    }

    var body: some View {
        HStack(alignment: .center, spacing: PlayerControlsBarLayout.hStackSpacing) {
            controlButton(symbol: playback.playMode.iconName, font: modeFont, color: palette.textPrimary,
                          label: "播放模式：\(playback.playMode.displayName)") {
                playback.cyclePlayMode()
            }

            controlButton(symbol: "backward.fill", font: navFont, color: palette.textPrimary, label: "上一首") {
                playback.playPrevious()
            }

            // 主播放键：主操作色实心圆（docs/UI设计文档.md §6：视觉 67–68）
            Button { playback.togglePlayPause() } label: {
                ZStack {
                    Circle()
                        .fill(palette.actionFill)
                        .frame(width: playButtonSize, height: playButtonSize)
                        .shadow(color: palette.cardShadow, radius: 12, y: 6)
                    Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                        .font(playButtonSize >= PlayerControlsBarLayout.largePlayButtonThreshold ? .title2 : .body.weight(.semibold))
                        .foregroundColor(palette.onAction)
                }
            }
            .buttonStyle(PressableButtonStyle(scale: playButtonSize >= PlayerControlsBarLayout.largePlayButtonThreshold ? PlayerControlsBarLayout.pressScaleWhenLarge : PlayerControlsBarLayout.pressScaleWhenSmall))
            .frame(maxWidth: .infinity)
            .accessibilityLabel(playback.isPlaying ? "暂停" : "播放")
            .accessibilityIdentifier("player.playPause")

            controlButton(symbol: "forward.fill", font: navFont, color: palette.textPrimary, label: "下一首") {
                playback.playNext()
            }

            controlButton(symbol: "list.bullet", font: modeFont, color: palette.textPrimary, label: "播放队列", action: onQueueTap)
        }
    }

    private func controlButton(symbol: String, font: Font, color: Color, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(font)
                .foregroundColor(color)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .accessibilityLabel(label)
    }
}
