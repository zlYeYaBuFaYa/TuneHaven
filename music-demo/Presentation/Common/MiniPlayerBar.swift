import SwiftUI

struct MiniPlayerBar: View {
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var libraryService: MusicLibraryService
    @ObservedObject private var playback = PlaybackService.shared
    @ObservedObject private var engine = AudioEngine.shared
    @Environment(\.themePalette) private var palette

    var body: some View {
        if let song = playback.currentSong {
            Button {
                router.openPlayer()
            } label: {
                HStack(spacing: 12) {
                    CoverImageView(path: song.coverImagePath, size: 44, cornerRadius: 6)

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
                                if let id = playback.currentSong?.id {
                                    try? await libraryService.toggleFavorite(songId: id)
                                    playback.toggleCurrentSongFavorite()
                                }
                            }
                        } label: {
                            Image(systemName: song.isFavorite ? "heart.fill" : "heart")
                                .font(.body)
                                .foregroundColor(song.isFavorite ? SemanticColor.danger : palette.textSecondary)
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
                                .foregroundColor(palette.primary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.trailing, 8)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(palette.surface)
                        .shadow(color: .black.opacity(0.1), radius: 8, y: -2)
                )
                .overlay(
                    GeometryReader { geo in
                        let progress = engine.duration > 0 ? engine.currentTime / engine.duration : 0
                        Rectangle()
                            .fill(palette.primary.opacity(0.3))
                            .frame(width: geo.size.width * progress, height: 2)
                            .frame(maxHeight: .infinity, alignment: .bottom)
                    }
                )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
        }
    }
}
