import SwiftUI

struct PlayerView: View {
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var themeManager: ThemeManager
    @EnvironmentObject private var libraryService: MusicLibraryService
    @EnvironmentObject private var playlistService: PlaylistService
    @ObservedObject private var playback = PlaybackService.shared
    @ObservedObject private var engine = AudioEngine.shared
    @Environment(\.colorScheme) private var colorScheme

    @State private var lyricsData: LyricsData?
    @State private var showQueue = false
    @State private var playerSheet: SheetDestination? = nil
    @State private var showMoreSheet = false
    @State private var dragOffset: CGFloat = 0

    private var palette: ThemeColorPalette {
        themeManager.resolvedPalette(for: colorScheme)
    }

    var body: some View {
        ZStack {
            palette.background
                .ignoresSafeArea()

            if showQueue {
                PlayQueueView(onClose: { withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) { showQueue = false } })
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                mainPlayerContent
                    .transition(.opacity)
            }
        }
        .offset(y: dragOffset)
        .environment(\.themePalette, palette)
        .onAppear { dragOffset = 0 }
        .sheet(item: $playerSheet) { destination in
            playerSheetView(for: destination)
                .environment(\.themePalette, palette)
                .environmentObject(playlistService)
        }
        .sheet(isPresented: $showMoreSheet) {
            moreActionSheet
                .environment(\.themePalette, palette)
                .environmentObject(playlistService)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .onChange(of: playback.currentSong?.id) { _, newValue in
            if newValue == nil {
                router.closePlayer()
            }
            Task { await loadLyrics() }
        }
        .task { await loadLyrics() }
    }

    private var playerDismissGesture: some Gesture {
        DragGesture(minimumDistance: 20, coordinateSpace: .global)
            .onChanged { value in
                guard !showQueue else { return }
                let dy = value.translation.height
                if dy > 0 {
                    dragOffset = dy * 0.7
                } else {
                    dragOffset = dy * 0.1
                }
            }
            .onEnded { value in
                guard !showQueue else { return }
                let velocity = value.predictedEndTranslation.height
                if value.translation.height > 100 || velocity > 400 {
                    router.closePlayer()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                        dragOffset = 0
                    }
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                        dragOffset = 0
                    }
                }
            }
    }

    // MARK: - Main Content

    private var mainPlayerContent: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                dragIndicator
                header
                    .padding(.bottom, 4)
                Spacer(minLength: 20)
                coverSection
                Spacer(minLength: 28)
                songInfo
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(playerDismissGesture)

            progressBar
            controls
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 36)
    }

    private var dragIndicator: some View {
        Capsule()
            .fill(palette.textTertiary.opacity(0.4))
            .frame(width: 36, height: 5)
            .padding(.bottom, 8)
    }

    private var header: some View {
        HStack {
            Button { router.closePlayer() } label: {
                Image(systemName: "chevron.down")
                    .font(.title3)
                    .foregroundColor(palette.textPrimary)
            }
            Spacer()
            if let song = playback.currentSong {
                Text(song.album.isEmpty || song.album == "未知专辑" ? "正在播放" : song.album)
                    .font(.subheadline)
                    .foregroundColor(palette.textSecondary)
            }
            Spacer()
            Button { showMoreSheet = true } label: {
                Image(systemName: "ellipsis")
                    .font(.title3)
                    .foregroundColor(palette.textPrimary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
        }
        .padding(.horizontal, 4)
    }

    // MARK: - More Action Sheet

    private var moreActionSheet: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        showMoreSheet = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            playerSheet = .setSleepTimer
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: playback.sleepTimerRemaining != nil ? "moon.zzz.fill" : "moon.zzz")
                                .font(.body)
                                .foregroundColor(palette.primary)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("定时关闭")
                                    .font(.subheadline)
                                    .foregroundColor(palette.textPrimary)
                                if let remaining = playback.sleepTimerRemaining {
                                    Text(remaining.formattedTime)
                                        .font(.caption)
                                        .foregroundColor(palette.textSecondary)
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundColor(palette.textTertiary)
                        }
                    }
                    .listRowBackground(palette.surface)

                    Button {
                        showMoreSheet = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            playerSheet = .playbackSpeedPicker
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "speedometer")
                                .font(.body)
                                .foregroundColor(palette.primary)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("倍速播放")
                                    .font(.subheadline)
                                    .foregroundColor(palette.textPrimary)
                                Text("\(String(format: "%.1f", playback.playbackSpeed))x")
                                    .font(.caption)
                                    .foregroundColor(palette.textSecondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundColor(palette.textTertiary)
                        }
                    }
                    .listRowBackground(palette.surface)
                }

                if let songId = playback.currentSong?.id {
                    Section {
                        Button {
                            showMoreSheet = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                playerSheet = .addToPlaylist(songIds: [songId])
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "text.badge.plus")
                                    .font(.body)
                                    .foregroundColor(palette.primary)
                                    .frame(width: 28)
                                Text("添加到歌单")
                                    .font(.subheadline)
                                    .foregroundColor(palette.textPrimary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                                    .foregroundColor(palette.textTertiary)
                            }
                        }
                        .listRowBackground(palette.surface)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(palette.background)
            .navigationTitle("更多操作")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { showMoreSheet = false }
                        .font(.subheadline)
                        .foregroundColor(palette.primary)
                }
            }
        }
    }

    // MARK: - Cover / Info / Progress / Controls

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
                        .shadow(color: .black.opacity(0.3), radius: 20, y: 8)
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
                    .foregroundColor(palette.textPrimary)
                    .lineLimit(1)
                Text(playback.currentSong?.artist ?? "—")
                    .font(.subheadline)
                    .foregroundColor(palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            Button {
                Task {
                    if let id = playback.currentSong?.id {
                        try? await libraryService.toggleFavorite(songId: id)
                        playback.toggleCurrentSongFavorite()
                    }
                }
            } label: {
                Image(systemName: playback.currentSong?.isFavorite == true ? "heart.fill" : "heart")
                    .font(.title2)
                    .foregroundColor(playback.currentSong?.isFavorite == true ? SemanticColor.danger : palette.textSecondary)
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
                    .foregroundColor(palette.textSecondary)
                Spacer()
                Text("-\((engine.duration - engine.currentTime).formattedTime)")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(palette.textSecondary)
            }
        }
        .padding(.bottom, 8)
    }

    private var controls: some View {
        HStack(alignment: .center, spacing: 0) {
            Button { playback.cyclePlayMode() } label: {
                Image(systemName: playback.playMode.iconName)
                    .font(.title3)
                    .foregroundColor(palette.textSecondary)
            }
            .frame(maxWidth: .infinity)

            Button { playback.playPrevious() } label: {
                Image(systemName: "backward.fill")
                    .font(.title)
                    .foregroundColor(palette.textPrimary)
            }
            .frame(maxWidth: .infinity)

            Button { playback.togglePlayPause() } label: {
                ZStack {
                    Circle()
                        .fill(palette.primary)
                        .frame(width: 68, height: 68)
                        .shadow(color: palette.primary.opacity(0.3), radius: 10, y: 4)
                    Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2)
                        .foregroundColor(.white)
                }
            }
            .frame(maxWidth: .infinity)

            Button { playback.playNext() } label: {
                Image(systemName: "forward.fill")
                    .font(.title)
                    .foregroundColor(palette.textPrimary)
            }
            .frame(maxWidth: .infinity)

            Button { withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) { showQueue = true } } label: {
                Image(systemName: "list.bullet")
                    .font(.title3)
                    .foregroundColor(palette.textSecondary)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 12)
    }

    // MARK: - Player Sheet Router

    @ViewBuilder
    private func playerSheetView(for destination: SheetDestination) -> some View {
        switch destination {
        case .setSleepTimer:
            SleepTimerSheet()
        case .playbackSpeedPicker:
            PlaybackSpeedSheet()
        case .addToPlaylist(let ids):
            AddToPlaylistSheet(songIds: ids)
        default:
            EmptyView()
        }
    }

    private func loadLyrics() async {
        guard let song = playback.currentSong else { lyricsData = nil; return }
        lyricsData = await LyricsService.shared.loadLyrics(for: song)
    }
}
