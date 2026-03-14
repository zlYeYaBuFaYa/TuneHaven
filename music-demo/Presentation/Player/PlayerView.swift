import SwiftUI

struct PlayerView: View {
    @EnvironmentObject private var router: AppRouter
    @ObservedObject private var playback = PlaybackService.shared
    @ObservedObject private var engine = AudioEngine.shared
    @Environment(\.themePalette) private var palette

    @State private var lyricsData: LyricsData?
    @State private var showQueue = false
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        ZStack {
            palette.playerBackground
                .ignoresSafeArea()

            if showQueue {
                PlayQueueView(onClose: { withAnimation { showQueue = false } })
                    .transition(.move(edge: .bottom))
            } else {
                mainPlayerContent
            }
        }
        .onChange(of: playback.currentSong?.id) { _, _ in
            Task { await loadLyrics() }
        }
        .task { await loadLyrics() }
    }

    private var mainPlayerContent: some View {
        VStack(spacing: 0) {
            dragHandle
            header
            Spacer(minLength: 16)
            coverSection
            Spacer(minLength: 24)
            songInfo
            progressBar
            controls
            bottomBar
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
    }

    private var dragHandle: some View {
        Button {
            router.closePlayer()
        } label: {
            Capsule()
                .fill(Color.white.opacity(0.3))
                .frame(width: 36, height: 4)
                .padding(.top, 12)
                .padding(.bottom, 8)
        }
    }

    private var header: some View {
        HStack {
            Button { router.closePlayer() } label: {
                Image(systemName: "chevron.down")
                    .font(.title3)
                    .foregroundColor(palette.playerText)
            }
            Spacer()
            if let song = playback.currentSong {
                Text(song.album.isEmpty || song.album == "未知专辑" ? "正在播放" : song.album)
                    .font(.subheadline)
                    .foregroundColor(palette.playerSubtext)
            }
            Spacer()
            Button { router.present(.addToPlaylist(songIds: [playback.currentSong?.id].compactMap { $0 })) } label: {
                Image(systemName: "ellipsis")
                    .font(.title3)
                    .foregroundColor(palette.playerText)
            }
        }
        .padding(.horizontal, 4)
    }

    private var coverSection: some View {
        Group {
            if let song = playback.currentSong {
                if let lData = lyricsData, !lData.lines.isEmpty {
                    LyricsView(lyricsData: lData, currentTime: engine.currentTime)
                        .frame(height: UIScreen.main.bounds.width - 48)
                } else {
                    CoverImageView(path: song.coverImagePath,
                                   size: UIScreen.main.bounds.width - 48,
                                   cornerRadius: 16)
                        .shadow(color: .black.opacity(0.4), radius: 20, y: 8)
                }
            } else {
                PlaceholderCoverView(size: UIScreen.main.bounds.width - 48)
            }
        }
    }

    private var songInfo: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(playback.currentSong?.title ?? "未在播放")
                    .font(.title3.bold())
                    .foregroundColor(palette.playerText)
                    .lineLimit(1)
                Text(playback.currentSong?.artist ?? "—")
                    .font(.subheadline)
                    .foregroundColor(palette.playerSubtext)
                    .lineLimit(1)
            }
            Spacer()
            Button {
                Task {
                    if let id = playback.currentSong?.id {
                        let lib = MusicLibraryService()
                        try? await lib.toggleFavorite(songId: id)
                    }
                }
            } label: {
                Image(systemName: playback.currentSong?.isFavorite == true ? "heart.fill" : "heart")
                    .font(.title2)
                    .foregroundColor(playback.currentSong?.isFavorite == true ? SemanticColor.danger : palette.playerSubtext)
            }
        }
        .padding(.vertical, 12)
    }

    private var progressBar: some View {
        VStack(spacing: 6) {
            Slider(
                value: Binding(
                    get: { engine.duration > 0 ? engine.currentTime / engine.duration : 0 },
                    set: { playback.seek(to: $0 * engine.duration) }
                )
            )
            .tint(palette.primary)

            HStack {
                Text(engine.currentTime.formattedTime)
                    .font(.caption.monospacedDigit())
                    .foregroundColor(palette.playerSubtext)
                Spacer()
                Text("-\((engine.duration - engine.currentTime).formattedTime)")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(palette.playerSubtext)
            }
        }
        .padding(.bottom, 8)
    }

    private var controls: some View {
        HStack(alignment: .center, spacing: 0) {
            Button { playback.cyclePlayMode() } label: {
                Image(systemName: playback.playMode.iconName)
                    .font(.title3)
                    .foregroundColor(palette.playerSubtext)
            }
            .frame(maxWidth: .infinity)

            Button { playback.playPrevious() } label: {
                Image(systemName: "backward.fill")
                    .font(.title)
                    .foregroundColor(palette.playerText)
            }
            .frame(maxWidth: .infinity)

            Button { playback.togglePlayPause() } label: {
                ZStack {
                    Circle()
                        .fill(palette.primary)
                        .frame(width: 64, height: 64)
                    Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2)
                        .foregroundColor(.white)
                }
            }
            .frame(maxWidth: .infinity)

            Button { playback.playNext() } label: {
                Image(systemName: "forward.fill")
                    .font(.title)
                    .foregroundColor(palette.playerText)
            }
            .frame(maxWidth: .infinity)

            Button { Task { await playback.dislikeAndSkip() } } label: {
                Image(systemName: "hand.thumbsdown")
                    .font(.title3)
                    .foregroundColor(palette.playerSubtext)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 8)
    }

    private var bottomBar: some View {
        HStack {
            Button { router.present(.setSleepTimer) } label: {
                HStack(spacing: 4) {
                    Image(systemName: "moon.zzz")
                    if let remaining = playback.sleepTimerRemaining {
                        Text(remaining.formattedTime)
                            .font(.caption.monospacedDigit())
                    }
                }
                .font(.title3)
                .foregroundColor(playback.sleepTimerRemaining != nil ? palette.primary : palette.playerSubtext)
            }
            Spacer()
            Button { router.present(.playbackSpeedPicker) } label: {
                Text("\(String(format: "%.1f", playback.playbackSpeed))x")
                    .font(.subheadline.bold())
                    .foregroundColor(playback.playbackSpeed != 1.0 ? palette.primary : palette.playerSubtext)
            }
            Spacer()
            Button { withAnimation { showQueue = true } } label: {
                Image(systemName: "list.bullet")
                    .font(.title3)
                    .foregroundColor(palette.playerSubtext)
            }
        }
        .padding(.top, 12)
    }

    private func loadLyrics() async {
        guard let song = playback.currentSong else { lyricsData = nil; return }
        lyricsData = await LyricsService.shared.loadLyrics(for: song)
    }
}
