import SwiftUI

private enum PlayerControlsBarLayout {
    static let defaultPlayButtonSize: CGFloat = 68
    static let largePlayButtonThreshold: CGFloat = 60
    static let hStackSpacing: CGFloat = 0
    static let shadowOpacityWhenLarge: Double = 0.35
    static let shadowOpacityWhenSmall: Double = 0.25
    static let shadowRadiusWhenLarge: CGFloat = 10
    static let shadowRadiusWhenSmall: CGFloat = 8
    static let shadowYOffsetWhenLarge: CGFloat = 4
    static let shadowYOffsetWhenSmall: CGFloat = 3
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
            Button { playback.cyclePlayMode() } label: {
                Image(systemName: playback.playMode.iconName)
                    .font(modeFont)
                    .foregroundColor(palette.textSecondary)
            }
            .frame(maxWidth: .infinity)

            Button { playback.playPrevious() } label: {
                Image(systemName: "backward.fill")
                    .font(navFont)
                    .foregroundColor(palette.textPrimary)
            }
            .frame(maxWidth: .infinity)

            Button { playback.togglePlayPause() } label: {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [palette.gradientStart, palette.gradientEnd],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: playButtonSize, height: playButtonSize)
                        .shadow(
                            color: palette.gradientStart.opacity(playButtonSize >= PlayerControlsBarLayout.largePlayButtonThreshold ? PlayerControlsBarLayout.shadowOpacityWhenLarge : PlayerControlsBarLayout.shadowOpacityWhenSmall),
                            radius: playButtonSize >= PlayerControlsBarLayout.largePlayButtonThreshold ? PlayerControlsBarLayout.shadowRadiusWhenLarge : PlayerControlsBarLayout.shadowRadiusWhenSmall,
                            y: playButtonSize >= PlayerControlsBarLayout.largePlayButtonThreshold ? PlayerControlsBarLayout.shadowYOffsetWhenLarge : PlayerControlsBarLayout.shadowYOffsetWhenSmall
                        )
                    Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                        .font(playButtonSize >= PlayerControlsBarLayout.largePlayButtonThreshold ? .title2 : .body.weight(.semibold))
                        .foregroundColor(palette.onPrimary)
                }
            }
            .buttonStyle(PressableButtonStyle(scale: playButtonSize >= PlayerControlsBarLayout.largePlayButtonThreshold ? PlayerControlsBarLayout.pressScaleWhenLarge : PlayerControlsBarLayout.pressScaleWhenSmall))
            .frame(maxWidth: .infinity)

            Button { playback.playNext() } label: {
                Image(systemName: "forward.fill")
                    .font(navFont)
                    .foregroundColor(palette.textPrimary)
            }
            .frame(maxWidth: .infinity)

            Button(action: onQueueTap) {
                Image(systemName: "list.bullet")
                    .font(modeFont)
                    .foregroundColor(palette.textSecondary)
            }
            .frame(maxWidth: .infinity)
        }
    }
}
