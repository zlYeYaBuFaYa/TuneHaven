import SwiftUI

struct PlayerView: View {
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var themeManager: ThemeManager
    @EnvironmentObject private var libraryService: MusicLibraryService
    @EnvironmentObject private var playlistService: PlaylistService
    @EnvironmentObject private var playback: PlaybackService
    @EnvironmentObject private var engine: AudioEngine
    @EnvironmentObject private var lyricsService: LyricsService
    @Environment(\.themePalette) private var palette
    private enum ActiveSheet: Identifiable {
        case moreActions
        case sleepTimer
        case speedPicker
        case addToPlaylist(songIds: [UUID])
        case lyricsSearch(Song)

        var id: String {
            switch self {
            case .moreActions: return "moreActions"
            case .sleepTimer: return "sleepTimer"
            case .speedPicker: return "speedPicker"
            case .addToPlaylist(let ids): return "addToPlaylist_\(ids.first?.uuidString ?? "")"
            case .lyricsSearch: return "lyricsSearch"
            }
        }
    }

    @State private var lyricsData: LyricsData?
    @State private var showQueue = false
    @State private var activeSheet: ActiveSheet?
    @State private var dragOffset: CGFloat = 0
    @State private var dragOffsetX: CGFloat = 0
    @State private var dragDirection: DragDirection? = nil
    @State private var showDeleteLyricsConfirm = false
    @State private var showLyricsImporter = false
    @State private var showLyricsPage = false
    @State private var pendingSheetTask: Task<Void, Never>?

    @AppStorage(AppStorageKey.lyricsPreferSimplified) private var lyricsPreferSimplified: Bool = true


    var body: some View {
        ZStack {
            LinearGradient(
                colors: [palette.background, palette.surfaceSecondary, palette.highlight],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            Group {
                if showLyricsPage {
                    LyricsPageView(
                        lyricsData: lyricsData,
                        onDismiss: {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                                showLyricsPage = false
                            }
                        },
                        onSearchLyrics: {
                            if let song = playback.currentSong {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                                    showLyricsPage = false
                                }
                                switchSheet(to: .lyricsSearch(song))
                            }
                        },
                        onOpenQueue: {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                                showLyricsPage = false
                                showQueue = true
                            }
                        }
                    )
                    .id(playback.currentSong?.id)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                } else if showQueue {
                    PlayQueueView(onClose: { withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) { showQueue = false } })
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    mainPlayerContent
                        .transition(.opacity)
                }
            }
            .offset(x: dragOffsetX, y: dragOffset)
        }
        .environment(\.themePalette, palette)
        .onAppear { dragOffset = 0; dragOffsetX = 0 }
        .sheet(item: $activeSheet) { sheet in
            Group {
                switch sheet {
                case .moreActions:
                    moreActionSheet
                        .presentationDetents([.medium])
                        .presentationDragIndicator(.visible)
                case .sleepTimer:
                    SleepTimerSheet()
                case .speedPicker:
                    PlaybackSpeedSheet()
                case .addToPlaylist(let ids):
                    AddToPlaylistSheet(songIds: ids)
                case .lyricsSearch(let song):
                    LyricsSearchView(song: song) {
                        Task { await loadLyrics() }
                    }
                }
            }
            .environment(\.themePalette, palette)
            .environmentObject(playlistService)
        }
        .fileImporter(
            isPresented: $showLyricsImporter,
            allowedContentTypes: [.plainText],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result,
                  let url = urls.first,
                  let song = playback.currentSong else { return }
            Task {
                try? await lyricsService.importLyricsFile(url: url, for: song)
                await loadLyrics()
            }
        }
        .alert("删除歌词", isPresented: $showDeleteLyricsConfirm) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                guard let song = playback.currentSong else { return }
                Task {
                    try? await lyricsService.deleteLyrics(for: song)
                    lyricsData = nil
                }
            }
        } message: {
            Text("确定要删除当前歌曲的歌词吗？")
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
                guard !showQueue, !showLyricsPage else { return }
                let dx = value.translation.width
                let dy = value.translation.height

                if dragDirection == nil {
                    dragDirection = abs(dx) > abs(dy) ? .horizontal : .vertical
                }

                switch dragDirection {
                case .horizontal where dx > 0:
                    dragOffsetX = dx * 0.7
                case .vertical where dy > 0:
                    dragOffset = dy * 0.7
                case .vertical:
                    dragOffset = dy * 0.1
                default: break
                }
            }
            .onEnded { value in
                guard !showQueue, !showLyricsPage else { return }
                let dir = dragDirection
                dragDirection = nil

                let dx = value.translation.width
                let dy = value.translation.height
                let vx = value.predictedEndTranslation.width
                let vy = value.predictedEndTranslation.height

                let shouldDismiss: Bool
                switch dir {
                case .horizontal: shouldDismiss = dx > 100 || vx > 400
                case .vertical:   shouldDismiss = dy > 100 || vy > 400
                case .none:       shouldDismiss = false
                }

                if shouldDismiss {
                    router.closePlayer()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                        dragOffset = 0
                        dragOffsetX = 0
                    }
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                        dragOffset = 0
                        dragOffsetX = 0
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
                Spacer(minLength: 16)
                songInfo
                currentLyricsPreview
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
                Text(song.album.isEmpty || song.album == SongDefaults.unknownAlbum ? "正在播放" : song.album)
                    .font(.subheadline)
                    .foregroundColor(palette.textSecondary)
            }
            Spacer()
            Button { activeSheet = .moreActions } label: {
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
                        switchSheet(to: .sleepTimer)
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
                        switchSheet(to: .speedPicker)
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

                if let song = playback.currentSong {
                    Section {
                        Button {
                            switchSheet(to: .addToPlaylist(songIds: [song.id]))
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

                    Section {
                        Button {
                            switchSheet(to: .lyricsSearch(song))
                        } label: {
                            moreActionRow(icon: "magnifyingglass", title: "搜索歌词")
                        }
                        .listRowBackground(palette.surface)

                        Button {
                            scheduleAfterSheetDismiss { showLyricsImporter = true }
                        } label: {
                            moreActionRow(icon: "doc.text", title: "导入歌词")
                        }
                        .listRowBackground(palette.surface)

                        if lyricsData != nil {
                            Button {
                                scheduleAfterSheetDismiss { showDeleteLyricsConfirm = true }
                            } label: {
                                moreActionRow(icon: "trash", title: "删除歌词", destructive: true)
                            }
                            .listRowBackground(palette.surface)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .adaptiveBackground()
            .navigationTitle("更多操作")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { activeSheet = nil }
                        .font(.subheadline)
                        .foregroundColor(palette.primary)
                }
            }
        }
    }

    // MARK: - Cover / Info / Progress / Controls

    private var coverSection: some View {
        GeometryReader { geo in
            let coverSize = geo.size.width * 0.75
            ZStack(alignment: .bottom) {
                albumCoverImage(size: coverSize)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if let song = playback.currentSong {
                    let hasLyrics = lyricsData.map { !$0.lines.isEmpty || !$0.rawText.isEmpty } ?? false
                    if !hasLyrics {
                        Button {
                            activeSheet = .lyricsSearch(song)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "magnifyingglass")
                                Text("搜索歌词")
                            }
                            .font(.caption.weight(.medium))
                            .foregroundColor(palette.textPrimary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                        }
                        .padding(.bottom, 8)
                    }
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    @ViewBuilder
    private func albumCoverImage(size: CGFloat) -> some View {
        if let path = playback.currentSong?.coverImagePath,
           let image = ImageCacheManager.shared.image(forKey: path) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: palette.cardShadow, radius: 20, y: 10)
        } else {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [palette.gradientStart.opacity(0.5), palette.gradientEnd.opacity(0.3)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size)
                .overlay {
                    Image(systemName: "music.note")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: size * 0.25)
                        .foregroundColor(palette.iconSecondary.opacity(0.5))
                }
                .shadow(color: palette.cardShadow, radius: 16, y: 8)
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
                    await playback.toggleCurrentSongFavorite()
                }
            } label: {
                Image(systemName: playback.currentSong?.isFavorite == true ? "heart.fill" : "heart")
                    .font(.title2)
                    .foregroundColor(playback.currentSong?.isFavorite == true ? SemanticColor.danger : palette.textSecondary)
            }
        }
        .padding(.vertical, 12)
    }

    private var currentLyricsPreview: some View {
        Group {
            if let data = lyricsData, !data.lines.isEmpty {
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                        showLyricsPage = true
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(currentLyricsText(from: data) ?? " ")
                            .font(.subheadline)
                            .foregroundColor(palette.textSecondary)
                            .lineLimit(1)
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundColor(palette.textTertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .padding(.top, 8)
            } else if let data = lyricsData, !data.rawText.isEmpty {
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                        showLyricsPage = true
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text("查看歌词")
                            .font(.subheadline)
                            .foregroundColor(palette.textTertiary)
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundColor(palette.textTertiary)
                    }
                }
                .padding(.top, 8)
            }
        }
    }

    private func currentLyricsText(from data: LyricsData) -> String? {
        let raw: String? = {
            for line in data.lines.reversed() {
                if engine.currentTime >= line.timestamp { return line.text }
            }
            return data.lines.first?.text
        }()
        return raw.map { LyricsTextTransform.displayText($0, preferSimplified: lyricsPreferSimplified) }
    }

    private var progressBar: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                let progress = engine.duration > 0 ? engine.currentTime / engine.duration : 0
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(palette.progressBackground)
                        .frame(height: 6)
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [palette.gradientStart, palette.gradientEnd],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(geo.size.width * progress, 6), height: 6)
                }
                .frame(maxHeight: .infinity, alignment: .center)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let ratio = min(max(value.location.x / geo.size.width, 0), 1)
                            playback.seek(to: ratio * engine.duration)
                        }
                )
            }
            .frame(height: 24)

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
                        .fill(
                            LinearGradient(
                                colors: [palette.gradientStart, palette.gradientEnd],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 68, height: 68)
                        .shadow(color: palette.gradientStart.opacity(0.35), radius: 10, y: 4)
                    Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2)
                        .foregroundColor(palette.onPrimary)
                }
            }
            .buttonStyle(PressableButtonStyle())
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

    private func moreActionRow(icon: String, title: String, destructive: Bool = false) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundColor(destructive ? SemanticColor.danger : palette.primary)
                .frame(width: 28)
            Text(title)
                .font(.subheadline)
                .foregroundColor(destructive ? SemanticColor.danger : palette.textPrimary)
            Spacer()
        }
    }

    private func loadLyrics() async {
        guard let song = playback.currentSong else { lyricsData = nil; return }
        lyricsData = await lyricsService.loadLyrics(for: song)
    }

    private func switchSheet(to newSheet: ActiveSheet, delay: TimeInterval = 0.3) {
        pendingSheetTask?.cancel()
        activeSheet = nil
        pendingSheetTask = Task {
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            activeSheet = newSheet
        }
    }

    private func scheduleAfterSheetDismiss(_ action: @escaping @MainActor () -> Void, delay: TimeInterval = 0.3) {
        pendingSheetTask?.cancel()
        activeSheet = nil
        pendingSheetTask = Task {
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            action()
        }
    }
}

enum DragDirection {
    case horizontal, vertical
}
