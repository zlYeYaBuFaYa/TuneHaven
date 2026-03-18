import SwiftUI

struct MiniPlayerBar: View {
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var libraryService: MusicLibraryService
    @ObservedObject private var playback = PlaybackService.shared
    @ObservedObject private var engine = AudioEngine.shared
    @Environment(\.themePalette) private var palette

    private var gradientBg: LinearGradient {
        LinearGradient(
            colors: [palette.gradientStart, palette.gradientEnd],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var body: some View {
        if let song = playback.currentSong {
            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        CoverImageView(path: song.coverImagePath, size: 44, cornerRadius: 8)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(song.title)
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(.white)
                                .lineLimit(1)
                            Text(song.artist)
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
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
                                    .foregroundColor(song.isFavorite ? .white : .white.opacity(0.8))
                            }
                            .buttonStyle(.plain)

                            Button {
                                playback.togglePlayPause()
                            } label: {
                                Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.title3)
                                    .foregroundColor(.white)
                            }
                            .buttonStyle(.plain)

                            Button {
                                playback.playNext()
                            } label: {
                                Image(systemName: "forward.fill")
                                    .font(.title3)
                                    .foregroundColor(.white.opacity(0.8))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)

                    GeometryReader { geo in
                        let progress = engine.duration > 0 ? engine.currentTime / engine.duration : 0
                        Rectangle()
                            .fill(Color.white.opacity(0.3))
                            .frame(width: geo.size.width * progress)
                    }
                    .frame(height: 2)
                }
                .background(gradientBg)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: palette.gradientStart.opacity(0.3), radius: 8, y: 2)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
                .onTapGesture {
                    router.openPlayer()
                }
            }
        }
    }
}
