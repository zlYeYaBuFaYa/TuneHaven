import SwiftUI

enum MiniPlayerLayout {
    /// 迷你播放器与底栏经 `safeAreaInset` 加入安全区域，列表已自动让出它们的真实高度；
    /// 这里只是列表末尾的呼吸间距，不再是固定 80 pt 的遮挡补偿（交互设计文档 §6）。
    static let listBottomPadding: CGFloat = 12
}

private struct MiniPlayerProgressBar: View {
    @EnvironmentObject private var engine: AudioEngine
    let color: Color
    let track: Color

    var body: some View {
        GeometryReader { geo in
            let progress = engine.duration > 0 ? min(max(engine.currentTime / engine.duration, 0), 1) : 0
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule().fill(color)
                    .frame(width: geo.size.width * progress)
            }
        }
        .frame(height: 2)
        .accessibilityHidden(true)
    }
}

/// 精简迷你播放器（docs/UI设计文档.md §6：视觉高 62、圆角 22、封面 42；交互设计文档 §6）。
/// 主体点击展开全屏；播放／暂停、下一首只切换状态，不展开。收藏在全屏播放器和歌曲更多菜单中可达。
struct MiniPlayerBar: View {
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var playback: PlaybackService
    @Environment(\.themePalette) private var palette

    var body: some View {
        if let song = playback.currentSong {
            VStack(spacing: 0) {
                HStack(spacing: 4) {
                    Button {
                        router.openPlayer()
                    } label: {
                        HStack(spacing: 12) {
                            CoverImageView(path: song.coverImagePath, size: 42, cornerRadius: 10)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(song.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(palette.textPrimary)
                                    .lineLimit(1)
                                Text(song.artist)
                                    .font(.caption)
                                    .foregroundColor(palette.textSecondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("当前歌曲：\(song.title)，\(song.artist)")
                    .accessibilityHint("展开播放器")

                    Button {
                        playback.togglePlayPause()
                    } label: {
                        Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title3)
                            .foregroundColor(palette.textPrimary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(playback.isPlaying ? "暂停" : "播放")

                    Button {
                        playback.playNext()
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.title3)
                            .foregroundColor(palette.textPrimary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("下一首")
                }
                .padding(.leading, 10)
                .padding(.trailing, 6)
                .padding(.vertical, 8)

                MiniPlayerProgressBar(color: palette.accent, track: palette.progressBackground)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 6)
            }
            .background {
                LiquidGlassPolicy.floatingBarBackdrop(surfaceTint: palette.surface, cornerRadius: 22)
            }
            .padding(.horizontal, 16)
        }
    }
}
