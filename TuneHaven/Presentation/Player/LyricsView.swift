import SwiftUI

struct LyricsPageView: View {
    let lyricsData: LyricsData?
    let onDismiss: () -> Void
    let onSearchLyrics: () -> Void
    let onOpenQueue: () -> Void

    @EnvironmentObject private var playback: PlaybackService
    @EnvironmentObject private var engine: AudioEngine
    @Environment(\.themePalette) private var palette

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

    private var effectiveScale: CGFloat {
        min(max(lyricsScale * pinchScale, 0.8), 2.0)
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

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                Capsule()
                    .fill(palette.textTertiary.opacity(0.4))
                    .frame(width: 36, height: 5)
                    .padding(.bottom, 8)

                headerSection
                    .padding(.bottom, 12)
            }
            .contentShape(Rectangle())
            .gesture(dismissGesture)

            lyricsContent
                .frame(maxHeight: .infinity)

            progressSection
                .padding(.top, 8)

            controlsSection
                .contentShape(Rectangle())
                .gesture(dismissGesture)
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 36)
        .offset(x: dragOffsetX, y: dragOffset)
        .onAppear { dragOffset = 0; dragOffsetX = 0 }
        .onChange(of: engine.currentTime) { _ in
            currentLineIndex = computeCurrentLineIndex()
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
                handleUserScroll()

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
                lyricsScale = min(max(lyricsScale * value, 0.8), 2.0)
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
        VStack(spacing: 8) {
            HStack {
                Button(action: onDismiss) {
                    Image(systemName: "chevron.down")
                        .font(.title3)
                        .foregroundColor(palette.textPrimary)
                }
                Spacer()
            }

            HStack {
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
                    Task { await playback.toggleCurrentSongFavorite() }
                } label: {
                    Image(systemName: playback.currentSong?.isFavorite == true ? "heart.fill" : "heart")
                        .font(.title2)
                        .foregroundColor(playback.currentSong?.isFavorite == true ? SemanticColor.danger : palette.textSecondary)
                }
            }
        }
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
                LazyVStack(alignment: .center, spacing: 24) {
                    Color.clear.frame(height: 20)

                    ForEach(Array(data.lines.enumerated()), id: \.element.id) { index, line in
                        lyricsLineButton(line: line, index: index)
                    }

                    Color.clear.frame(height: 200)
                }
            }
            .simultaneousGesture(lyricsAreaGesture)
            .simultaneousGesture(lyricsPinchGesture)
            .onChange(of: currentLineIndex) { newIdx in
                guard !isUserScrolling, let idx = newIdx,
                      idx < data.lines.count else { return }
                withAnimation(.easeInOut(duration: 0.4)) {
                    proxy.scrollTo(data.lines[idx].id, anchor: .center)
                }
            }
            .task {
                try? await Task.sleep(for: .seconds(0.15))
                guard !Task.isCancelled,
                      !hasPerformedInitialScroll,
                      let idx = currentLineIndex,
                      idx < data.lines.count else { return }
                proxy.scrollTo(data.lines[idx].id, anchor: .center)
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

    private func lyricsLineButton(line: LyricsLine, index: Int) -> some View {
        let isCurrent = currentLineIndex == index
        let fontSize = (isCurrent ? 28 : 20) * effectiveScale
        let fontWeight: Font.Weight = isCurrent ? .black : .regular

        let text = displayText(line.text)
        return Button {
            playback.seek(to: line.timestamp)
        } label: {
            if isCurrent {
                karaokeText(text, fontSize: fontSize, fontWeight: fontWeight, progress: lineProgress(for: index))
            } else {
                Text(text)
                    .font(.system(size: fontSize, weight: fontWeight))
                    .foregroundColor(palette.textPrimary)
            }
        }
        .opacity(lineOpacity(for: index))
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, alignment: .center)
        .scaleEffect(isCurrent ? 1.02 : 1.0)
        .contentShape(Rectangle())
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: isCurrent)
        .buttonStyle(.plain)
        .id(line.id)
    }

    private func karaokeText(_ text: String, fontSize: CGFloat, fontWeight: Font.Weight, progress: CGFloat) -> some View {
        Text(text)
            .font(.system(size: fontSize, weight: fontWeight))
            .multilineTextAlignment(.center)
            .foregroundColor(palette.textPrimary)
            .overlay(alignment: .leading) {
                GeometryReader { geo in
                    Text(text)
                        .font(.system(size: fontSize, weight: fontWeight))
                        .multilineTextAlignment(.center)
                        .foregroundColor(palette.primary)
                        .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
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
                .font(.system(size: 20 * effectiveScale))
                .foregroundColor(palette.playerSubtext)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 20)
        }
        .simultaneousGesture(lyricsAreaGesture)
        .simultaneousGesture(lyricsPinchGesture)
    }

    // MARK: - Empty

    private var emptyLyricsSection: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "music.note")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 40, height: 40)
                .foregroundColor(palette.textTertiary)
            Text("暂无歌词")
                .font(.body)
                .foregroundColor(palette.textTertiary)
            Button(action: onSearchLyrics) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                    Text("搜索歌词")
                }
                .font(.subheadline.weight(.medium))
                .foregroundColor(palette.primary)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(palette.primary.opacity(0.12))
                .clipShape(Capsule())
            }
            Spacer()
        }
    }

    // MARK: - Progress (compact)

    private var progressSection: some View {
        PlayerProgressBar(barHeight: 3, touchHeight: 20, timeFont: .caption2.monospacedDigit(), timeColor: palette.textTertiary)
            .padding(.bottom, 4)
    }

    // MARK: - Controls (compact)

    private var controlsSection: some View {
        PlayerControlsBar(
            playButtonSize: 52,
            navFont: .title2,
            modeFont: .body,
            onQueueTap: onOpenQueue
        )
        .padding(.vertical, 8)
    }

    // MARK: - Helpers

    private func lineOpacity(for index: Int) -> Double {
        guard let current = currentLineIndex else { return 0.4 }
        let distance = abs(index - current)
        if distance == 0 { return 1.0 }
        if distance == 1 { return 0.45 }
        if distance == 2 { return 0.3 }
        if distance <= 4 { return 0.2 }
        return 0.15
    }

    private func handleUserScroll() {
        isUserScrolling = true
        scrollResumeTask?.cancel()
        scrollResumeTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            isUserScrolling = false
        }
    }

    private func displayText(_ text: String) -> String {
        LyricsTextTransform.displayText(text, preferSimplified: preferSimplified)
    }
}
