import SwiftUI

struct PlayerView: View {
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var themeManager: ThemeManager
    @EnvironmentObject private var libraryService: MusicLibraryService
    @EnvironmentObject private var playlistService: PlaylistService
    @EnvironmentObject private var playback: PlaybackService
    @EnvironmentObject private var engine: AudioEngine
    @EnvironmentObject private var lyricsService: LyricsService
    @EnvironmentObject private var snackbar: SnackbarState
    @EnvironmentObject private var subscriptionService: SubscriptionService
    @Environment(\.themePalette) private var palette
    private enum ActiveSheet: Identifiable {
        case moreActions
        case sleepTimer
        case speedPicker
        case addToPlaylist(songIds: [UUID])
        case lyricsSearch(Song)
        case losslessPaywall

        var id: String {
            switch self {
            case .moreActions: return "moreActions"
            case .sleepTimer: return "sleepTimer"
            case .speedPicker: return "speedPicker"
            case .addToPlaylist(let ids): return "addToPlaylist_\(ids.first?.uuidString ?? "")"
            case .lyricsSearch: return "lyricsSearch"
            case .losslessPaywall: return "losslessPaywall"
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
    @State private var losslessPaywallTask: Task<Void, Never>?

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
        .onAppear {
            dragOffset = 0
            dragOffsetX = 0
            scheduleLosslessPaywall()
        }
        .onChange(of: router.playerModalReset) { _ in
            pendingSheetTask?.cancel()
            losslessPaywallTask?.cancel()
            activeSheet = nil
            if router.externalBackupTakesModal {
                playback.clearLosslessBlock()
            }
        }
        .onChange(of: playback.losslessBlockedSong?.id) { _ in
            scheduleLosslessPaywall()
        }
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
                case .losslessPaywall:
                    PaywallView(triggerFeature: .losslessPlayback)
                        .environmentObject(subscriptionService)
                        .environmentObject(router)
                }
            }
            .environment(\.themePalette, palette)
            .environmentObject(playlistService)
            .environmentObject(subscriptionService)
            .environmentObject(router)
        }
        .fileImporter(
            isPresented: $showLyricsImporter,
            allowedContentTypes: [.plainText],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first, let song = playback.currentSong else { return }
                Task {
                    do {
                        try await lyricsService.importLyricsFile(url: url, for: song)
                        await loadLyrics()
                    } catch {
                        snackbar.show(message: "歌词导入失败")
                    }
                }
            case .failure(let error):
                AppLogger.shared.error(error, context: "文件选择失败")
                snackbar.show(message: "文件选择失败")
            }
        }
        .alert("删除歌词", isPresented: $showDeleteLyricsConfirm) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                guard let song = playback.currentSong else { return }
                Task {
                    do {
                        try await lyricsService.deleteLyrics(for: song)
                        lyricsData = nil
                    } catch {
                        snackbar.show(message: "歌词删除失败")
                    }
                }
            }
        } message: {
            Text("确定要删除当前歌曲的歌词吗？")
        }
        .onChange(of: playback.currentSong?.id) { newValue in
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
                    Task {
                        try? await Task.sleep(for: .seconds(0.45))
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
        PlayerMoreActionsSheet(
            hasLyrics: lyricsData != nil,
            onSleepTimer: { switchSheet(to: .sleepTimer) },
            onSpeedPicker: { switchSheet(to: .speedPicker) },
            onAddToPlaylist: { songId in switchSheet(to: .addToPlaylist(songIds: [songId])) },
            onSearchLyrics: { song in switchSheet(to: .lyricsSearch(song)) },
            onImportLyrics: { scheduleAfterSheetDismiss { showLyricsImporter = true } },
            onDeleteLyrics: { scheduleAfterSheetDismiss { showDeleteLyricsConfirm = true } },
            onDismiss: { activeSheet = nil }
        )
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
        CoverImageView(path: playback.currentSong?.coverImagePath, size: size, cornerRadius: 16)
            .shadow(color: palette.cardShadow, radius: 20, y: 10)
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
        let lines = data.lines
        guard !lines.isEmpty else { return nil }
        let time = engine.currentTime
        if time < lines[0].timestamp { return LyricsTextTransform.displayText(lines[0].text, preferSimplified: lyricsPreferSimplified) }
        var lo = 0, hi = lines.count - 1
        while lo < hi {
            let mid = lo + (hi - lo + 1) / 2
            if lines[mid].timestamp <= time {
                lo = mid
            } else {
                hi = mid - 1
            }
        }
        return LyricsTextTransform.displayText(lines[lo].text, preferSimplified: lyricsPreferSimplified)
    }

    private var progressBar: some View {
        PlayerProgressBar(barHeight: 6, touchHeight: 24, timeFont: .caption.monospacedDigit())
            .padding(.bottom, 8)
    }

    private var controls: some View {
        PlayerControlsBar(
            playButtonSize: 68,
            navFont: .title,
            modeFont: .title3,
            onQueueTap: { withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) { showQueue = true } }
        )
        .padding(.vertical, 12)
    }

    /// 全屏播放器盖住 RootTabView 的 sheet。等封面稳定后再把软墙挂到播放器自己的 sheet 上。
    /// onAppear 当下弹 sheet 不可靠；已有其它 sheet 时再延时一轮，与歌词搜索的付费墙一致。
    private func scheduleLosslessPaywall() {
        guard playback.losslessBlockedSong != nil else { return }
        losslessPaywallTask?.cancel()
        losslessPaywallTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.35))
            guard !Task.isCancelled else { return }
            guard playback.losslessBlockedSong != nil else { return }
            if router.externalBackupTakesModal {
                playback.clearLosslessBlock()
                return
            }
            if router.isPlayerPresented {
                presentLosslessPaywallIfNeeded()
            } else {
                playback.clearLosslessBlock()
                router.present(.paywall(feature: .losslessPlayback))
            }
        }
    }

    private func presentLosslessPaywallIfNeeded() {
        guard playback.losslessBlockedSong != nil else { return }
        playback.clearLosslessBlock()
        if case .losslessPaywall = activeSheet { return }
        if activeSheet != nil {
            switchSheet(to: .losslessPaywall, delay: 0.35)
        } else {
            activeSheet = .losslessPaywall
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
