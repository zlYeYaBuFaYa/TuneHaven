import SwiftUI

struct LyricsSearchView: View {
    let song: Song
    var onSaved: (() -> Void)?

    @EnvironmentObject private var lyricsService: LyricsService
    @Environment(\.themePalette) private var palette
    @Environment(\.dismiss) private var dismiss

    @State private var trackName: String
    @State private var artistName: String
    @State private var results: [LRCLibTrack] = []
    @State private var expandedId: Int?
    @State private var isSearching = false
    @State private var isSaving = false
    @State private var searchError: String?
    @State private var saveError: String?
    @State private var hasSearched = false
    @State private var showManualInput = false
    @State private var manualLyricsText = ""

    init(song: Song, onSaved: (() -> Void)? = nil) {
        self.song = song
        self.onSaved = onSaved
        _trackName = State(initialValue: song.title)
        _artistName = State(initialValue: song.artist == SongDefaults.unknownArtist ? "" : song.artist)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchForm
                Divider().foregroundColor(palette.separator)
                resultContent
            }
            .adaptiveBackground()
            .navigationTitle("搜索歌词")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(palette.surface, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                        .foregroundColor(palette.primary)
                }
            }
            .alert("保存失败", isPresented: .init(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )) {
                Button("确定") { saveError = nil }
            } message: {
                Text(saveError ?? "")
            }
            .sheet(isPresented: $showManualInput) {
                manualInputView
                    .environment(\.themePalette, palette)
            }
        }
    }

    // MARK: - Manual Input

    private var manualInputView: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Text("粘贴 LRC 格式歌词或纯文本歌词")
                    .font(.caption)
                    .foregroundColor(palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)

                TextEditor(text: $manualLyricsText)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(palette.textPrimary)
                    .scrollContentBackground(.hidden)
                    .padding(12)
                    .background(palette.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal, 16)
            }
            .padding(.top, 8)
            .adaptiveBackground()
            .navigationTitle("手动输入歌词")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(palette.surface, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { showManualInput = false }
                        .foregroundColor(palette.primary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { saveManualLyrics() }
                        .foregroundColor(palette.primary)
                        .disabled(manualLyricsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }
            }
        }
    }

    private func saveManualLyrics() {
        let content = manualLyricsText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }
        isSaving = true

        Task {
            do {
                try await lyricsService.saveLyrics(content, for: song)
                await MainActor.run {
                    isSaving = false
                    showManualInput = false
                    onSaved?()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    saveError = "歌词保存失败，请重试"
                }
            }
        }
    }

    // MARK: - Search Form

    private var searchForm: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "music.note")
                    .foregroundColor(palette.textSecondary)
                    .frame(width: 20)
                TextField("歌曲名称", text: $trackName)
                    .textFieldStyle(.plain)
                    .foregroundColor(palette.textPrimary)
            }
            .padding(12)
            .background(palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            HStack(spacing: 8) {
                Image(systemName: "person")
                    .foregroundColor(palette.textSecondary)
                    .frame(width: 20)
                TextField("艺术家（可选）", text: $artistName)
                    .textFieldStyle(.plain)
                    .foregroundColor(palette.textPrimary)
            }
            .padding(12)
            .background(palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            HStack(spacing: 12) {
                Button {
                    performSearch()
                } label: {
                    HStack {
                        if isSearching {
                            ProgressView()
                                .tint(.white)
                        }
                        Text("搜索")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(searchDisabled ? palette.textTertiary : palette.primary)
                    )
                }
                .disabled(searchDisabled)

                Button {
                    showManualInput = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.pencil")
                        Text("手动输入")
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(palette.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(palette.primary, lineWidth: 1)
                    )
                }
            }
        }
        .padding(16)
    }

    private var searchDisabled: Bool {
        trackName.trimmingCharacters(in: .whitespaces).isEmpty || isSearching
    }

    // MARK: - Result Content

    @ViewBuilder
    private var resultContent: some View {
        if isSearching && results.isEmpty {
            Spacer()
            ProgressView("正在搜索歌词...")
                .foregroundColor(palette.textSecondary)
            Spacer()
        } else if let error = searchError {
            Spacer()
            VStack(spacing: 12) {
                Image(systemName: "wifi.slash")
                    .font(.largeTitle)
                    .foregroundColor(palette.textTertiary)
                Text(error)
                    .font(.subheadline)
                    .foregroundColor(palette.textSecondary)
                    .multilineTextAlignment(.center)
                Button("重试") { performSearch() }
                    .font(.subheadline)
                    .foregroundColor(palette.primary)
            }
            Spacer()
        } else if hasSearched && results.isEmpty {
            Spacer()
            VStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.largeTitle)
                    .foregroundColor(palette.textTertiary)
                Text("未找到匹配歌词")
                    .font(.subheadline)
                    .foregroundColor(palette.textSecondary)
                Text("请尝试修改关键词重新搜索")
                    .font(.caption)
                    .foregroundColor(palette.textTertiary)
            }
            Spacer()
        } else if !results.isEmpty {
            ScrollView {
                LazyVStack(spacing: 0) {
                    HStack {
                        Text("搜索结果 (\(results.count))")
                            .font(.caption)
                            .foregroundColor(palette.textSecondary)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)

                    ForEach(results) { track in
                        trackRow(track)
                        Divider().padding(.leading, 16)
                    }
                }
            }
        } else {
            Spacer()
            VStack(spacing: 8) {
                Image(systemName: "text.magnifyingglass")
                    .font(.largeTitle)
                    .foregroundColor(palette.textTertiary)
                Text("输入歌曲信息搜索歌词")
                    .font(.subheadline)
                    .foregroundColor(palette.textSecondary)
            }
            Spacer()
        }
    }

    // MARK: - Track Row

    private func trackRow(_ track: LRCLibTrack) -> some View {
        let isExpanded = expandedId == track.id
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    expandedId = isExpanded ? nil : track.id
                }
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption2)
                            .foregroundColor(palette.textTertiary)
                        Text(track.trackName)
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(palette.textPrimary)
                            .lineLimit(1)
                    }

                    Text("\(track.artistName) · \(track.albumName)")
                        .font(.caption)
                        .foregroundColor(palette.textSecondary)
                        .lineLimit(1)
                        .padding(.leading, 18)

                    HStack(spacing: 6) {
                        Text(track.durationText)
                            .font(.caption)
                            .foregroundColor(palette.textTertiary)

                        if track.instrumental {
                            Label("器乐曲（无歌词）", systemImage: "music.note")
                                .font(.caption)
                                .foregroundColor(palette.textTertiary)
                        } else if track.hasSyncedLyrics {
                            Label("有时间轴歌词", systemImage: "checkmark")
                                .font(.caption)
                                .foregroundColor(SemanticColor.success)
                        } else if track.hasAnyLyrics {
                            Label("仅纯文本歌词", systemImage: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundColor(SemanticColor.warning)
                        } else {
                            Text("无可用歌词")
                                .font(.caption)
                                .foregroundColor(palette.textTertiary)
                        }
                    }
                    .padding(.leading, 18)
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded, let lyrics = track.bestLyrics {
                lyricsPreview(lyrics)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }

            if !track.instrumental && track.hasAnyLyrics {
                HStack {
                    Spacer()
                    Button {
                        useTrack(track)
                    } label: {
                        HStack(spacing: 4) {
                            if isSaving {
                                ProgressView()
                                    .scaleEffect(0.7)
                            }
                            Text("使用此歌词")
                                .font(.caption.weight(.medium))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(palette.primary)
                        .clipShape(Capsule())
                    }
                    .disabled(isSaving)
                    .padding(.trailing, 16)
                    .padding(.bottom, 8)
                }
            }
        }
    }

    private func lyricsPreview(_ lyrics: String) -> some View {
        let nonEmptyLines = lyrics.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let previewLines = nonEmptyLines.prefix(6)

        return VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(previewLines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.caption2)
                    .foregroundColor(palette.textSecondary)
                    .lineLimit(1)
            }
            if nonEmptyLines.count > 6 {
                Text("...")
                    .font(.caption2)
                    .foregroundColor(palette.textTertiary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.surfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.leading, 18)
    }

    // MARK: - Actions

    private func performSearch() {
        let query = trackName.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return }
        isSearching = true
        searchError = nil
        hasSearched = false

        Task {
            do {
                let artist = artistName.trimmingCharacters(in: .whitespaces)
                results = try await lyricsService.searchOnline(
                    title: query,
                    artist: artist.isEmpty ? nil : artist
                )
                hasSearched = true
            } catch {
                searchError = "搜索失败，请检查网络连接"
            }
            isSearching = false
        }
    }

    private func useTrack(_ track: LRCLibTrack) {
        guard let lyrics = track.bestLyrics else { return }
        isSaving = true

        Task {
            do {
                try await lyricsService.saveLyrics(lyrics, for: song)
                await MainActor.run {
                    onSaved?()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    saveError = "歌词保存失败，请重试"
                }
            }
        }
    }
}
