import SwiftUI

struct MiniPlayerBar: View {
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var libraryService: MusicLibraryService
    @EnvironmentObject private var playback: PlaybackService
    @EnvironmentObject private var engine: AudioEngine
    @Environment(\.themePalette) private var palette

    var body: some View {
        if let song = playback.currentSong {
            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        CoverImageView(path: song.coverImagePath, size: 44, cornerRadius: 8)

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
                                    .foregroundColor(song.isFavorite ? palette.accent : palette.iconSecondary)
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
                                    .foregroundColor(palette.iconSecondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)

                    GeometryReader { geo in
                        let progress = engine.duration > 0 ? engine.currentTime / engine.duration : 0
                        Rectangle()
                            .fill(palette.primary.opacity(0.4))
                            .frame(width: geo.size.width * progress)
                    }
                    .frame(height: 2)
                }
                .background(palette.surface)
                .contentShape(Rectangle())
                .onTapGesture {
                    router.openPlayer()
                }
            }
        }
    }
}
