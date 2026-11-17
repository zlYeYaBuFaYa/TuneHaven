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
    #if DEBUG
    @State private var showLyricsPage = DebugLaunchRoute.raw == "player.lyrics"
    #else
    @State private var showLyricsPage = false
    #endif
    @State private var pendingSheetTask: Task<Void, Never>?
    @State private var losslessPaywallTask: Task<Void, Never>?

    @AppStorage(AppStorageKey.lyricsPreferSimplified) private var lyricsPreferSimplified: Bool = true
    @AppStorage(AppStorageKey.playerCoverStyle) private var coverStyleRaw = PlayerCoverStyle.auto.rawValue

    private var coverStyle: PlayerCoverStyle {
        (PlayerCoverStyle(rawValue: coverStyleRaw) ?? .auto).resolved(themeID: themeManager.currentStyle.id)
    }


    var body: some View {
        ZStack {
            ThemeBackgroundView()

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
                        onImportLyrics: { showLyricsImporter = true },
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
            #if DEBUG
            switch DebugLaunchRoute.raw {
            case "player.more": activeSheet = .moreActions
            case "player.sleep": activeSheet = .sleepTimer
            case "player.speed": activeSheet = .speedPicker
            case "player.lyricsSearch": if let song = playback.currentSong { activeSheet = .lyricsSearch(song) }
            default: break
            }
            #endif
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
            .sheetBackground()
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
        }
        // 按歌曲 id 绑定：切歌时 SwiftUI 取消上一首的加载
        .task(id: playback.currentSong?.id) { await loadLyrics() }
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

    /// 顺序：收起／来源／更多 → 封面 → 曲名／艺术家／收藏 → 真实音质 → 歌词预览 → 进度 → 五项控制 → 音频输出
    /// （docs/UI设计文档.md §7.3）。上半部分可下拖收起；控制区固定在下方便于触达。
    private var mainPlayerContent: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                header
                    .padding(.bottom, 8)
                coverSection
                    .padding(.vertical, 12)
                    .frame(maxHeight: .infinity)
                songInfo
                qualityTags
                currentLyricsPreview
                    .padding(.top, 14)
            }
            .contentShape(Rectangle())
            .gesture(playerDismissGesture)

            progressBar
                .padding(.top, 12)
            controls
            AudioOutputButton()
                .padding(.top, 2)
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    private var header: some View {
        HStack {
            Button { router.closePlayer() } label: {
                Image(systemName: "chevron.down")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(palette.textPrimary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("收起播放器")
            Spacer()
            VStack(spacing: 2) {
                Text("正在播放")
                    .font(.caption)
                    .foregroundColor(palette.textSecondary)
                if let song = playback.currentSong {
                    Text(song.album.isEmpty || song.album == SongDefaults.unknownAlbum ? "音乐库" : song.album)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(palette.textPrimary)
                        .lineLimit(1)
                }
            }
            .accessibilityElement(children: .combine)
            Spacer()
            Button { activeSheet = .moreActions } label: {
                Image(systemName: "ellipsis")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(palette.textPrimary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("更多操作")
        }
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

    /// 大封面：宽高共同约束，小高度设备自动缩小（docs/UI设计文档.md §6、§7.3）
    private var coverSection: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height, 320)
            PlayerCoverArt(path: playback.currentSong?.coverImagePath, style: coverStyle, size: side)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minHeight: 160)
        .accessibilityHidden(true)
    }

    private var songInfo: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(playback.currentSong?.title ?? "未在播放")
                    .font(.title2.weight(.semibold))
                    .foregroundColor(palette.textPrimary)
                    .lineLimit(2)
                Text(playback.currentSong?.artist ?? "—")
                    .font(.body)
                    .foregroundColor(palette.textSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)

            let isFavorite = playback.currentSong?.isFavorite == true
            Button {
                Task { await playback.toggleCurrentSongFavorite() }
            } label: {
                Image(systemName: isFavorite ? "heart.fill" : "heart")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(isFavorite ? palette.accent : palette.textPrimary)
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(palette.surface.opacity(0.7)))
                    .overlay(Circle().stroke(palette.separator, lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isFavorite ? "已收藏" : "收藏")
        }
    }

    /// 只展示真实已知的音质：无损来自 Song.isLossless，采样率来自元数据；当前没有位深字段，不显示
    @ViewBuilder
    private var qualityTags: some View {
        if let song = playback.currentSong {
            let tags = PlayerQualityTag.tags(for: song)
            if !tags.isEmpty {
                HStack(spacing: 8) {
                    ForEach(tags, id: \.self) { tag in
                        Text(tag)
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(palette.textSecondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(palette.separator, lineWidth: 1))
                    }
                    Spacer()
                }
                .padding(.top, 10)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("音质：\(PlayerQualityTag.spoken(for: song))")
            }
        }
    }

    /// 歌词预览：有歌词点击进入歌词页；没有时给出添加歌词入口（交互设计文档 §7.3）
    @ViewBuilder
    private var currentLyricsPreview: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        Group {
            if let data = lyricsData, !data.lines.isEmpty || !data.rawText.isEmpty {
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                        showLyricsPage = true
                    }
                } label: {
                    HStack(spacing: 8) {
                        Text(data.lines.isEmpty ? "查看歌词" : "「\(currentLyricsText(from: data) ?? "")」")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(palette.accent)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(palette.textSecondary)
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 48)
                    .contentShape(shape)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("歌词")
                .accessibilityHint("打开歌词页")
            } else if let song = playback.currentSong {
                Menu {
                    Button { activeSheet = .lyricsSearch(song) } label: {
                        Label("搜索歌词", systemImage: "magnifyingglass")
                    }
                    Button { showLyricsImporter = true } label: {
                        Label("导入 LRC 文件", systemImage: "doc.text")
                    }
                } label: {
                    HStack(spacing: 8) {
                        Text("暂无歌词")
                            .font(.subheadline)
                            .foregroundColor(palette.textSecondary)
                        Spacer(minLength: 0)
                        Label("添加歌词", systemImage: "plus")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(palette.accent)
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 48)
                    .contentShape(shape)
                }
            }
        }
        .background(shape.fill(palette.surface.opacity(0.5)))
        .overlay(shape.stroke(palette.separator, lineWidth: 0.5))
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
        PlayerProgressBar(barHeight: 5, touchHeight: 44, timeFont: .caption.monospacedDigit())
    }

    private var controls: some View {
        PlayerControlsBar(
            playButtonSize: 68,
            navFont: .title2,
            modeFont: .title3,
            onQueueTap: { withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) { showQueue = true } }
        )
        .padding(.vertical, 8)
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
        let data = await lyricsService.loadLyrics(for: song)
        // 在线匹配可能很慢：期间已切歌就丢弃，避免旧歌词覆盖新歌曲
        guard !Task.isCancelled, playback.currentSong?.id == song.id else { return }
        lyricsData = data
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
