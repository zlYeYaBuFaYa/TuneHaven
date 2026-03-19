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

    private var currentLineIndex: Int? {
        guard let lines = lyricsData?.lines, !lines.isEmpty else { return nil }
        for (i, line) in lines.enumerated().reversed() {
            if engine.currentTime >= line.timestamp { return i }
        }
        return nil
    }

    var body: some View {
        VStack(spacing: 0) {
            headerSection
                .padding(.bottom, 12)

            lyricsContent
                .frame(maxHeight: .infinity)

            progressSection
                .padding(.top, 8)
            controlsSection
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 36)
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
        } else if let data = lyricsData, !data.rawText.isEmpty {
            plainTextSection(text: data.rawText)
        } else {
            emptyLyricsSection
        }
    }

    // MARK: - Synced Lyrics

    private func syncedLyricsSection(data: LyricsData) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    Color.clear.frame(height: 20)

                    ForEach(Array(data.lines.enumerated()), id: \.element.id) { index, line in
                        lyricsLineButton(line: line, index: index)
                    }

                    Color.clear.frame(height: 200)
                }
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 5)
                    .onChanged { _ in handleUserScroll() }
            )
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
                .font(isCurrent ? .title2.bold() : .body)
                .foregroundColor(isCurrent ? palette.primary : palette.playerSubtext)
                .opacity(lineOpacity(for: index))
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .animation(.easeInOut(duration: 0.3), value: isCurrent)
        }
        .buttonStyle(.plain)
        .id(line.id)
    }

    // MARK: - Plain Text

    private func plainTextSection(text: String) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            Text(text)
                .font(.body)
                .foregroundColor(palette.playerSubtext)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 20)
        }
    }

    // MARK: - Empty

    private var emptyLyricsSection: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "music.note")
                .font(.system(size: 40))
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

    // MARK: - Progress

    private var progressSection: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                let progress = engine.duration > 0 ? engine.currentTime / engine.duration : 0
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(palette.separator)
                        .frame(height: 4)
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [palette.gradientStart, palette.gradientEnd],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(geo.size.width * progress, 4), height: 4)
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

    // MARK: - Controls

    private var controlsSection: some View {
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

            Button(action: onOpenQueue) {
                Image(systemName: "list.bullet")
                    .font(.title3)
                    .foregroundColor(palette.textSecondary)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 12)
    }

    // MARK: - Helpers

    private func lineOpacity(for index: Int) -> Double {
        guard let current = currentLineIndex else { return 0.5 }
        let distance = abs(index - current)
        if distance == 0 { return 1.0 }
        if distance == 1 { return 0.65 }
        if distance == 2 { return 0.5 }
        if distance <= 4 { return 0.4 }
        return 0.3
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
