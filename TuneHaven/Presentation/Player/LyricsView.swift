import SwiftUI

struct LyricsPageView: View {
    let lyricsData: LyricsData?
    let onDismiss: () -> Void
    let onSearchLyrics: () -> Void
    let onOpenQueue: () -> Void

    @EnvironmentObject private var playback: PlaybackService
    @EnvironmentObject private var engine: AudioEngine
    @Environment(\.themePalette) private var palette

    @State private var isUserScrolling = false
    @State private var scrollResumeTask: Task<Void, Never>?
    @State private var hasPerformedInitialScroll = false
    @State private var dragOffset: CGFloat = 0
    @State private var dragOffsetX: CGFloat = 0
    @State private var dragDirection: DragDirection? = nil
    @State private var lyricsScale: CGFloat = 1.0
    @GestureState private var pinchScale: CGFloat = 1.0
    @State private var isLyricsHorizontalSwipe = false

    private var effectiveScale: CGFloat {
        min(max(lyricsScale * pinchScale, 0.8), 2.0)
    }

    private var currentLineIndex: Int? {
        guard let lines = lyricsData?.lines, !lines.isEmpty else { return nil }
        for (i, line) in lines.enumerated().reversed() {
            if engine.currentTime >= line.timestamp { return i }
        }
        return nil
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
                VStack(alignment: .center, spacing: 24) {
                    Color.clear.frame(height: 20)

                    ForEach(Array(data.lines.enumerated()), id: \.element.id) { index, line in
                        lyricsLineButton(line: line, index: index)
                    }

                    Color.clear.frame(height: 200)
                }
            }
            .simultaneousGesture(lyricsAreaGesture)
            .simultaneousGesture(lyricsPinchGesture)
            .onChange(of: currentLineIndex) { _, newIdx in
                guard !isUserScrolling, let idx = newIdx,
                      idx < data.lines.count else { return }
                withAnimation(.easeInOut(duration: 0.4)) {
                    proxy.scrollTo(data.lines[idx].id, anchor: .center)
                }
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    guard !hasPerformedInitialScroll,
                          let idx = currentLineIndex,
                          idx < data.lines.count else { return }
                    proxy.scrollTo(data.lines[idx].id, anchor: .center)
                    hasPerformedInitialScroll = true
                }
            }
            .onDisappear {
                scrollResumeTask?.cancel()
                scrollResumeTask = nil
            }
        }
    }

    private func lyricsLineButton(line: LyricsLine, index: Int) -> some View {
        let isCurrent = currentLineIndex == index

        return Button {
            playback.seek(to: line.timestamp)
        } label: {
            Text(line.text)
                .font(.system(size: (isCurrent ? 28 : 20) * effectiveScale, weight: isCurrent ? .bold : .regular))
                .foregroundStyle(
                    isCurrent
                        ? AnyShapeStyle(LinearGradient(
                            colors: [palette.gradientStart, palette.gradientEnd],
                            startPoint: .leading,
                            endPoint: .trailing
                          ))
                        : AnyShapeStyle(palette.playerSubtext)
                )
                .opacity(lineOpacity(for: index))
                .shadow(color: isCurrent ? palette.gradientStart.opacity(0.6) : .clear, radius: isCurrent ? 10 : 0)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
                .scaleEffect(isCurrent ? 1.05 : 1.0)
                .contentShape(Rectangle())
                .animation(.spring(response: 0.4, dampingFraction: 0.75), value: isCurrent)
        }
        .buttonStyle(.plain)
        .id(line.id)
    }

    // MARK: - Plain Text

    private func plainTextSection(text: String) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            Text(text)
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
        VStack(spacing: 4) {
            GeometryReader { geo in
                let progress = engine.duration > 0 ? engine.currentTime / engine.duration : 0
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(palette.separator.opacity(0.6))
                        .frame(height: 3)
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [palette.gradientStart, palette.gradientEnd],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(geo.size.width * progress, 3), height: 3)
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
            .frame(height: 20)

            HStack {
                Text(engine.currentTime.formattedTime)
                    .font(.caption2.monospacedDigit())
                    .foregroundColor(palette.textTertiary)
                Spacer()
                Text("-\((engine.duration - engine.currentTime).formattedTime)")
                    .font(.caption2.monospacedDigit())
                    .foregroundColor(palette.textTertiary)
            }
        }
        .padding(.bottom, 4)
    }

    // MARK: - Controls (compact)

    private var controlsSection: some View {
        HStack(alignment: .center, spacing: 0) {
            Button { playback.cyclePlayMode() } label: {
                Image(systemName: playback.playMode.iconName)
                    .font(.body)
                    .foregroundColor(palette.textTertiary)
            }
            .frame(maxWidth: .infinity)

            Button { playback.playPrevious() } label: {
                Image(systemName: "backward.fill")
                    .font(.title2)
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
                        .frame(width: 52, height: 52)
                        .shadow(color: palette.gradientStart.opacity(0.25), radius: 8, y: 3)
                    Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                        .font(.body.weight(.semibold))
                        .foregroundColor(.white)
                }
            }
            .frame(maxWidth: .infinity)

            Button { playback.playNext() } label: {
                Image(systemName: "forward.fill")
                    .font(.title2)
                    .foregroundColor(palette.textPrimary)
            }
            .frame(maxWidth: .infinity)

            Button(action: onOpenQueue) {
                Image(systemName: "list.bullet")
                    .font(.body)
                    .foregroundColor(palette.textTertiary)
            }
            .frame(maxWidth: .infinity)
        }
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
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { isUserScrolling = false }
        }
    }
}
