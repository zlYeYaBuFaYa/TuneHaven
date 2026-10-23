import SwiftUI

enum MiniPlayerLayout {
    static let listBottomPadding: CGFloat = 80
}

private struct MiniPlayerProgressBar: View {
    @EnvironmentObject private var engine: AudioEngine
    let gradientColors: [Color]

    var body: some View {
        GeometryReader { geo in
            let progress = engine.duration > 0 ? engine.currentTime / engine.duration : 0
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: gradientColors,
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: geo.size.width * progress)
        }
        .frame(height: 3)
    }
}

struct MiniPlayerBar: View {
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var playback: PlaybackService
    @Environment(\.themePalette) private var palette

    var body: some View {
        if let song = playback.currentSong {
            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        CoverImageView(path: song.coverImagePath, size: 44, cornerRadius: 8)
                            .shadow(color: palette.cardShadow, radius: 4, y: 2)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(song.title)
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(palette.textPrimary)
                                .lineLimit(1)
                            Text(song.artist)
                                .font(.caption)
                                .foregroundColor(palette.textSecondary)
                                .lineLimit(1)
                        }

                        Spacer()

                        HStack(spacing: 16) {
                            Button {
                                Task {
                                    await playback.toggleCurrentSongFavorite()
                                }
                            } label: {
                                Image(systemName: song.isFavorite ? "heart.fill" : "heart")
                                    .font(.body)
                                    .foregroundColor(song.isFavorite ? palette.accent : palette.textSecondary)
                            }
                            .buttonStyle(.plain)

                            Button {
                                playback.togglePlayPause()
                            } label: {
                                Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.title3)
                                    .foregroundColor(palette.primary)
                            }
                            .buttonStyle(.plain)

                            Button {
                                playback.playNext()
                            } label: {
                                Image(systemName: "forward.fill")
                                    .font(.title3)
                                    .foregroundColor(palette.textSecondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)

                    MiniPlayerProgressBar(gradientColors: [palette.gradientStart, palette.gradientEnd])
                }
                .background {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(palette.miniPlayerBg)
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.ultraThinMaterial)
                }
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: palette.cardShadow, radius: 8, y: 4)
                .contentShape(Rectangle())
                .onTapGesture {
                    router.openPlayer()
                }
            }
            .padding(.horizontal, 8)
        }
    }
}
