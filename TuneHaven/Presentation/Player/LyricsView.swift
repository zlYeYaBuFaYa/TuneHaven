import SwiftUI

struct LyricsPageView: View {
    let lyricsData: LyricsData?
    let onDismiss: () -> Void
    let onSearchLyrics: () -> Void
    let onImportLyrics: () -> Void
    let onOpenQueue: () -> Void

    @EnvironmentObject private var playback: PlaybackService
    @EnvironmentObject private var engine: AudioEngine
    @EnvironmentObject private var subscriptionService: SubscriptionService
    @EnvironmentObject private var router: AppRouter
    @Environment(\.themePalette) private var palette
    @Environment(\.colorScheme) private var colorScheme

    @AppStorage(AppStorageKey.lyricsPreferSimplified) private var preferSimplified: Bool = true
    @State private var isUserScrolling = false
    @State private var scrollResumeTask: Task<Void, Never>?
    @State private var hasPerformedInitialScroll = false
    @State private var dragOffset: CGFloat = 0
    @State private var dragOffsetX: CGFloat = 0
    @State private var dragDirection: DragDirection? = nil
    @State private var lyricsScale: CGFloat = 1.0
    @GestureState private var pinchScale: CGFloat = 1.0
    @State private var isLyricsHorizontalSwipe = false
    @State private var currentLineIndex: Int?
    /// 「回到当前句」触发计数，ScrollViewReader 内监听后立即定位
    @State private var recenterToken = 0

    private static let scaleRange: ClosedRange<CGFloat> = 0.8...2.0
    private static let scaleStep: CGFloat = 0.1

    private var effectiveScale: CGFloat {
        min(max(lyricsScale * pinchScale, Self.scaleRange.lowerBound), Self.scaleRange.upperBound)
    }

    private func computeCurrentLineIndex() -> Int? {
        guard let lines = lyricsData?.lines, !lines.isEmpty else { return nil }
        let time = engine.currentTime
        if time < lines[0].timestamp { return nil }
        var lo = 0, hi = lines.count - 1
        while lo < hi {
            let mid = lo + (hi - lo + 1) / 2
            if lines[mid].timestamp <= time {
                lo = mid
            } else {
                hi = mid - 1
            }
        }
        return lo
    }

    /// 布局（docs/UI设计文档.md §7.4）：小封面与歌曲信息 → 歌词 → 轻工具条 → 进度 → 控制 → 音频输出。
    /// 歌词区竖向手势优先阅读；收起按钮、右滑或在非歌词区下滑返回封面播放器（交互设计文档 §8.1）。
    var body: some View {
        VStack(spacing: 0) {
            headerSection
                .padding(.bottom, 8)
                .contentShape(Rectangle())
                .gesture(dismissGesture)

            lyricsContent
                .frame(maxHeight: .infinity)

            VStack(spacing: 0) {
                lyricsToolbar
                    .padding(.vertical, 8)
                progressSection
                controlsSection
                AudioOutputButton()
            }
            .contentShape(Rectangle())
            .gesture(dismissGesture)
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .offset(x: dragOffsetX, y: dragOffset)
        .onAppear { dragOffset = 0; dragOffsetX = 0 }
        .onChange(of: engine.currentTime) { _ in
            currentLineIndex = computeCurrentLineIndex()
        }
        .onChange(of: playback.currentSong?.id) { _ in
            resumeFollowing()
            hasPerformedInitialScroll = false
        }
    }

    // MARK: - Gestures

    private var dismissGesture: some Gesture {
        DragGesture(minimumDistance: 20, coordinateSpace: .global)
            .onChanged { value in
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
                let dir = dragDirection
                dragDirection = nil
                finishDismissGesture(dir: dir, value: value)
            }
    }

    private var lyricsAreaGesture: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .onChanged { value in
                let dx = value.translation.width
                let dy = value.translation.height

                if !isLyricsHorizontalSwipe && abs(dx) > abs(dy) * 1.3 && dx > 10 {
                    isLyricsHorizontalSwipe = true
                }

                if isLyricsHorizontalSwipe {
                    dragOffsetX = max(dx * 0.7, 0)
                }
            }
            .onEnded { value in
                guard isLyricsHorizontalSwipe else {
                    isLyricsHorizontalSwipe = false
                    return
                }
                isLyricsHorizontalSwipe = false

                let dx = value.translation.width
                let vx = value.predictedEndTranslation.width

                if dx > 100 || vx > 400 {
                    dragOffsetX = 0
                    onDismiss()
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                        dragOffsetX = 0
                    }
                }
            }
    }

    private var lyricsPinchGesture: some Gesture {
        MagnificationGesture()
            .updating($pinchScale) { value, state, _ in
                state = value
            }
            .onEnded { value in
                lyricsScale = min(max(lyricsScale * value, Self.scaleRange.lowerBound), Self.scaleRange.upperBound)
            }
    }

    private func finishDismissGesture(dir: DragDirection?, value: DragGesture.Value) {
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
            dragOffset = 0
            dragOffsetX = 0
            onDismiss()
        } else {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                dragOffset = 0
                dragOffsetX = 0
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 12) {
            HStack {
                Button(action: onDismiss) {
                    Image(systemName: "chevron.down")
                        .font(.title3.weight(.semibold))
                        .foregroundColor(palette.textPrimary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("返回封面播放器")
                Spacer()
                VStack(spacing: 2) {
                    Text("歌词")
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
                Color.clear.frame(width: 44, height: 44)
            }

            HStack(spacing: 12) {
                CoverImageView(path: playback.currentSong?.coverImagePath, size: 56, cornerRadius: 12)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(playback.currentSong?.title ?? "未在播放")
                        .font(.headline)
                        .foregroundColor(palette.textPrimary)
                        .lineLimit(1)
                    Text(playback.currentSong?.artist ?? "—")
                        .font(.subheadline)
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
                        .font(.body.weight(.semibold))
                        .foregroundColor(isFavorite ? palette.accent : palette.textPrimary)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(palette.surface.opacity(0.7)))
                        .overlay(Circle().stroke(palette.separator, lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isFavorite ? "已收藏" : "收藏")
            }
        }
    }

    // MARK: - Toolbar

    /// 底部轻工具条：字号、字形、回到当前句（docs/UI设计文档.md §7.4）。按钮与双指缩放共用同一字号状态
    private var lyricsToolbar: some View {
        let hasText = lyricsData.map { !$0.lines.isEmpty || !$0.rawText.isEmpty } ?? false
        let isSynced = !(lyricsData?.lines.isEmpty ?? true)
        return HStack(spacing: 8) {
            toolbarButton(systemImage: "textformat.size.smaller", label: "缩小歌词",
                          disabled: !hasText || lyricsScale <= Self.scaleRange.lowerBound + 0.001) {
                lyricsScale = max(lyricsScale - Self.scaleStep, Self.scaleRange.lowerBound)
            }
            toolbarButton(systemImage: "textformat.size.larger", label: "放大歌词",
                          disabled: !hasText || lyricsScale >= Self.scaleRange.upperBound - 0.001) {
                lyricsScale = min(lyricsScale + Self.scaleStep, Self.scaleRange.upperBound)
            }
            toolbarButton(title: preferSimplified ? "简体" : "原文",
                          label: "歌词字形：\(preferSimplified ? "简体" : "原文")", disabled: !hasText) {
                preferSimplified.toggle()
            }
            if isSynced {
                toolbarButton(systemImage: "scope", title: "回到当前句", label: "回到当前句",
                              disabled: !isUserScrolling) {
                    resumeFollowing()
                    recenterToken += 1
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func toolbarButton(
        systemImage: String? = nil,
        title: String? = nil,
        label: String,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let systemImage { Image(systemName: systemImage) }
                if let title { Text(title) }
            }
            .font(.footnote.weight(.semibold))
            .foregroundColor(palette.textPrimary)
            .padding(.horizontal, 12)
            .frame(minWidth: 44, minHeight: 36)
            .background(Capsule().fill(palette.surface.opacity(0.6)))
            .overlay(Capsule().stroke(palette.separator, lineWidth: 0.5))
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
        .accessibilityLabel(label)
    }

    // MARK: - Lyrics Content

    @ViewBuilder
    private var lyricsContent: some View {
        if let data = lyricsData, !data.lines.isEmpty {
            syncedLyricsSection(data: data)
                .mask(lyricsEdgeMask)
        } else if let data = lyricsData, !data.rawText.isEmpty {
            plainTextSection(text: data.rawText)
                .mask(lyricsEdgeMask)
        } else {
            emptyLyricsSection
        }
    }

    private var lyricsEdgeMask: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                .frame(height: 32)
            Color.black
            LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 48)
        }
    }

    // MARK: - Synced Lyrics

    private func syncedLyricsSection(data: LyricsData) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 22) {
                    Color.clear.frame(height: 40)

                    ForEach(Array(data.lines.enumerated()), id: \.element.id) { index, line in
                        lyricsLineButton(line: line, index: index)
                    }

                    Color.clear.frame(height: 200)
                }
            }
            .simultaneousGesture(lyricsAreaGesture)
            .simultaneousGesture(lyricsPinchGesture)
            // 只有手指拖动才暂停跟随；停下（含惯性结束）3 秒后恢复，手指仍按住时不抢回位置
            .onScrollPhaseChange { _, phase in
                switch phase {
                case .interacting:
                    isUserScrolling = true
                    scrollResumeTask?.cancel()
                case .idle:
                    if isUserScrolling { scheduleResumeFollowing() }
                default:
                    break
                }
            }
            .onChange(of: currentLineIndex) { newIdx in
                guard !isUserScrolling, let idx = newIdx,
                      idx < data.lines.count else { return }
                withAnimation(.easeInOut(duration: 0.4)) {
                    proxy.scrollTo(data.lines[idx].id, anchor: UnitPoint(x: 0.5, y: 0.42))
                }
            }
            .onChange(of: recenterToken) { _ in
                guard let idx = currentLineIndex, idx < data.lines.count else { return }
                withAnimation(.easeInOut(duration: 0.35)) {
                    proxy.scrollTo(data.lines[idx].id, anchor: UnitPoint(x: 0.5, y: 0.42))
                }
            }
            .task {
                try? await Task.sleep(for: .seconds(0.15))
                guard !Task.isCancelled,
                      !hasPerformedInitialScroll,
                      let idx = currentLineIndex,
                      idx < data.lines.count else { return }
                proxy.scrollTo(data.lines[idx].id, anchor: UnitPoint(x: 0.5, y: 0.42))
                hasPerformedInitialScroll = true
            }
            .onDisappear {
                scrollResumeTask?.cancel()
                scrollResumeTask = nil
            }
        }
    }

    private func lineProgress(for index: Int) -> CGFloat {
        guard let lines = lyricsData?.lines,
              currentLineIndex == index else { return 0 }
        let lineStart = lines[index].timestamp
        let lineEnd = index + 1 < lines.count ? lines[index + 1].timestamp : engine.duration
        let lineDuration = lineEnd - lineStart
        guard lineDuration > 0 else { return 1 }
        return min(max(CGFloat((engine.currentTime - lineStart) / lineDuration), 0), 1)
    }

    /// 左对齐；长句自然换行。当前行加重并以强调色逐行填充，黑夜用浅色填充保持柔白当前句
    private func lyricsLineButton(line: LyricsLine, index: Int) -> some View {
        let isCurrent = currentLineIndex == index
        let fontSize = (isCurrent ? 27 : 21) * effectiveScale
        let fontWeight: Font.Weight = isCurrent ? .bold : .semibold

        let text = displayText(line.text)
        return Button {
            playback.seek(to: line.timestamp)
            resumeFollowing()
        } label: {
            Group {
                if isCurrent {
                    karaokeText(text, fontSize: fontSize, fontWeight: fontWeight, progress: lineProgress(for: index))
                } else {
                    Text(text)
                        .font(.system(size: fontSize, weight: fontWeight))
                        .foregroundColor(palette.textSecondary)
                        .opacity(lineOpacity(for: index))
                }
            }
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .animation(.easeOut(duration: 0.25), value: isCurrent)
        .buttonStyle(.plain)
        .accessibilityLabel(text)
        .accessibilityValue(isCurrent ? "当前句" : "")
        .accessibilityHint("跳转到这一句")
        .id(line.id)
    }

    private var karaokeFill: Color {
        colorScheme == .dark ? palette.textPrimary : palette.accent
    }

    private func karaokeText(_ text: String, fontSize: CGFloat, fontWeight: Font.Weight, progress: CGFloat) -> some View {
        Text(text)
            .font(.system(size: fontSize, weight: fontWeight))
            .multilineTextAlignment(.leading)
            .foregroundColor(palette.textPrimary.opacity(colorScheme == .dark ? 0.55 : 0.75))
            .overlay(alignment: .leading) {
                GeometryReader { geo in
                    Text(text)
                        .font(.system(size: fontSize, weight: fontWeight))
                        .multilineTextAlignment(.leading)
                        .foregroundColor(karaokeFill)
                        .frame(width: geo.size.width, height: geo.size.height, alignment: .leading)
                        .mask(alignment: .leading) {
                            Rectangle()
                                .frame(width: geo.size.width * progress)
                        }
                }
            }
    }

    // MARK: - Plain Text

    private func plainTextSection(text: String) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            Text(displayText(text))
                .font(.system(size: 19 * effectiveScale, weight: .medium))
                .foregroundColor(palette.textPrimary)
                .lineSpacing(8 * effectiveScale)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 20)
        }
        .simultaneousGesture(lyricsAreaGesture)
        .simultaneousGesture(lyricsPinchGesture)
    }

    // MARK: - Empty

    /// 暂无歌词：导入 LRC 与搜索／粘贴（在线搜索标明 Premium，手动粘贴免费）
    private var emptyLyricsSection: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "text.quote")
                .font(.system(size: 40, weight: .light))
                .foregroundColor(palette.accent)
                .accessibilityHidden(true)
            Text("暂无歌词")
                .font(.headline)
                .foregroundColor(palette.textPrimary)
            Text("可以导入 LRC 文件，或搜索、粘贴歌词")
                .font(.subheadline)
                .foregroundColor(palette.textSecondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 10) {
                Button(action: onImportLyrics) {
                    Label("导入 LRC", systemImage: "doc.text")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(palette.onAction)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 44)
                        .background(Capsule().fill(palette.actionFill))
                }
                .buttonStyle(.plain)

                Button(action: onSearchLyrics) {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                        Text("搜索／粘贴")
                        if !subscriptionService.canAccess(.onlineLyricsSearch) {
                            Text("Premium")
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(palette.tagBackground))
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(palette.textPrimary)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 44)
                    .background(Capsule().fill(palette.surface.opacity(0.7)))
                    .overlay(Capsule().stroke(palette.separator, lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(subscriptionService.canAccess(.onlineLyricsSearch)
                                    ? "搜索或粘贴歌词" : "搜索或粘贴歌词，在线搜索需要 Premium")
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Progress (compact)

    private var progressSection: some View {
        PlayerProgressBar(barHeight: 4, touchHeight: 44, timeFont: .caption2.monospacedDigit())
    }

    // MARK: - Controls (compact)

    private var controlsSection: some View {
        PlayerControlsBar(
            playButtonSize: 56,
            navFont: .title3,
            modeFont: .body,
            onQueueTap: onOpenQueue
        )
        .padding(.vertical, 4)
    }

    // MARK: - Helpers

    /// 非当前句保持可读：最低 0.55（docs/UI设计文档.md §7.4）
    private func lineOpacity(for index: Int) -> Double {
        guard let current = currentLineIndex else { return 0.8 }
        switch abs(index - current) {
        case 0: return 1.0
        case 1: return 0.9
        case 2: return 0.75
        default: return 0.55
        }
    }

    private func scheduleResumeFollowing() {
        scrollResumeTask?.cancel()
        scrollResumeTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            isUserScrolling = false
            recenterToken += 1
        }
    }

    private func resumeFollowing() {
        scrollResumeTask?.cancel()
        scrollResumeTask = nil
        isUserScrolling = false
    }

    private func displayText(_ text: String) -> String {
        LyricsTextTransform.displayText(text, preferSimplified: preferSimplified)
    }
}
