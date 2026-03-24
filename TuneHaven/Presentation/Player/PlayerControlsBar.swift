import SwiftUI

/// 播放控制栏组件，在 PlayerView 和 LyricsPageView 中共享
struct PlayerControlsBar: View {
    let playButtonSize: CGFloat
    let navFont: Font
    let modeFont: Font
    let onQueueTap: () -> Void

    @EnvironmentObject private var playback: PlaybackService
    @Environment(\.themePalette) private var palette

    init(
        playButtonSize: CGFloat = 68,
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
        HStack(alignment: .center, spacing: 0) {
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
                        .shadow(color: palette.gradientStart.opacity(playButtonSize >= 60 ? 0.35 : 0.25), radius: playButtonSize >= 60 ? 10 : 8, y: playButtonSize >= 60 ? 4 : 3)
                    Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                        .font(playButtonSize >= 60 ? .title2 : .body.weight(.semibold))
                        .foregroundColor(palette.onPrimary)
                }
            }
            .buttonStyle(PressableButtonStyle(scale: playButtonSize >= 60 ? 0.97 : 0.98))
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
