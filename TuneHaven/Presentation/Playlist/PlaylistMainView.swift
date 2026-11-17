import SwiftUI

/// 歌单首页（docs/UI设计文档.md §6、§7.2；交互设计文档 §4.2、§5）
struct PlaylistMainView: View {
    @EnvironmentObject private var playlistService: PlaylistService
    @EnvironmentObject private var libraryService: MusicLibraryService
    @EnvironmentObject private var groupService: PlaylistGroupService
    @EnvironmentObject private var playback: PlaybackService
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var snackbar: SnackbarState
    @Environment(\.themePalette) private var palette
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    #if DEBUG
    @State private var showGroupManage = DebugLaunchRoute.raw == "playlist.groups"
    #else
    @State private var showGroupManage = false
    #endif
    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool
    @State private var editMode: EditMode = .inactive
    @State private var isReordering = false
    @State private var pendingDelete: Playlist?
    @State private var highlightDuration: TimeInterval?

    private var systemPlaylists: [Playlist] {
        playlistService.playlists.filter { $0.isSystem }.sorted { $0.systemType.rawValue < $1.systemType.rawValue }
    }

    private var userPlaylists: [Playlist] {
        playlistService.playlists.filter { !$0.isSystem }.sorted { $0.sortOrder < $1.sortOrder }
    }

    /// 重点卡：最近更新的自建歌单
    private var highlight: Playlist? {
        userPlaylists.max { $0.updatedAt < $1.updatedAt }
    }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        List {
            searchField
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 8, trailing: 20))

            if isSearching {
                searchResults
            } else {
                folderCards
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 12, trailing: 20))

                myPlaylistsHeader
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 4, trailing: 12))

                if userPlaylists.isEmpty {
                    createFirstCard
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 8, trailing: 20))
                } else {
                    if !editMode.isEditing, let highlight {
                        PlaylistHighlightCard(
                            playlist: highlight,
                            totalDuration: highlightDuration,
                            onOpen: { router.navigate(to: .playlistDetail(id: highlight.id), in: .playlist) },
                            onPlay: { play(highlight) }
                        )
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 12, trailing: 20))
                    }
                    ForEach(editMode.isEditing ? userPlaylists : userPlaylists.filter { $0.id != highlight?.id }) { playlist in
                        playlistRow(playlist)
                    }
                    .onMove { src, dst in
                        var sorted = userPlaylists
                        sorted.move(fromOffsets: src, toOffset: dst)
                        savePlaylistOrder(sorted.map(\.id))
                    }
                }
            }

            Color.clear
                .frame(height: MiniPlayerLayout.listBottomPadding)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.editMode, $editMode)
        .navigationTitle("歌单")
        .navigationBarTitleDisplayMode(.large)
        .themeNavigationBarSurface()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if editMode.isEditing {
                    Button("完成") { withAnimation { editMode = .inactive } }
                        .fontWeight(.semibold)
                } else {
                    Button {
                        router.present(.createPlaylist)
                    } label: {
                        Image(systemName: "plus")
                            .font(.body.weight(.semibold))
                    }
                    .accessibilityLabel("创建歌单")
                }
            }
        }
        .task { await playlistService.loadPlaylists() }
        .task(id: highlight?.id) { await loadHighlightDuration() }
        .onReceive(libraryService.$songs.dropFirst().debounce(for: .milliseconds(500), scheduler: RunLoop.main)) { _ in
            Task { await playlistService.loadPlaylists() }
        }
        .confirmationDialog(
            pendingDelete.map { "删除歌单「\($0.name)」？" } ?? "",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { playlist in
            Button("删除歌单", role: .destructive) { delete(playlist) }
            Button("取消", role: .cancel) {}
        } message: { _ in
            Text("删除歌单不会删除音乐库中的歌曲")
        }
        .sheet(isPresented: $showGroupManage) {
            NavigationStack {
                PlaylistGroupView()
                    .sheetBackground()
                    .environmentObject(groupService)
                    .environmentObject(playlistService)
                    .environmentObject(router)
                    .environment(\.themePalette, palette)
            }
        }
    }

    // MARK: - Sections

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(palette.textSecondary)
                .accessibilityHidden(true)
            TextField("搜索你的歌单", text: $searchText)
                .focused($isSearchFocused)
                .textFieldStyle(.plain)
                .submitLabel(.search)
                .foregroundColor(palette.textPrimary)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    isSearchFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(palette.textSecondary)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清除搜索内容")
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .frame(minHeight: 44)
        .background(RoundedRectangle(cornerRadius: 15, style: .continuous).fill(palette.surface.opacity(0.72)))
        .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(palette.separator, lineWidth: 0.5))
    }

    @ViewBuilder
    private var searchResults: some View {
        let results = PlaylistNameFilter.filter(userPlaylists, query: searchText)
        if results.isEmpty {
            Text("没有找到相关歌单")
                .font(.subheadline)
                .foregroundColor(palette.textSecondary)
                .frame(maxWidth: .infinity, minHeight: 120)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        } else {
            ForEach(results) { playlist in
                playlistRow(playlist)
            }
        }
    }

    /// 「我喜欢」「最近播放」收藏夹卡，名称与数量来自系统歌单；大字号改单列
    private var folderCards: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 14))
            : AnyLayout(HStackLayout(spacing: 14))
        return layout {
            ForEach(systemPlaylists) { playlist in
                Button {
                    openSystemPlaylist(playlist)
                } label: {
                    FolderCard(
                        title: playlist.systemType == .favorites ? "我喜欢" : "最近播放",
                        subtitle: "\(playlist.songCount) 首",
                        symbol: playlist.systemType == .favorites ? "heart" : "clock"
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var myPlaylistsHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("我的歌单")
                .font(.headline)
                .foregroundColor(palette.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button {
                showGroupManage = true
            } label: {
                Label("分组", systemImage: "folder")
                    .labelStyle(CompactLabelStyle())
                    .font(.subheadline)
                    .foregroundColor(palette.textSecondary)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if userPlaylists.count > 1 {
                Button {
                    withAnimation { editMode = editMode.isEditing ? .inactive : .active }
                } label: {
                    Text(editMode.isEditing ? "完成" : "排序")
                        .font(.subheadline)
                        .foregroundColor(palette.textSecondary)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(editMode.isEditing ? "完成排序" : "调整歌单顺序")
            }
        }
    }

    private var createFirstCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("创建第一个歌单")
                .font(.title3.weight(.bold))
                .foregroundColor(palette.textPrimary)
            Text("把喜欢的歌整理在一起")
                .font(.subheadline)
                .foregroundColor(palette.textSecondary)
            Button {
                router.present(.createPlaylist)
            } label: {
                Label("创建歌单", systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(palette.onAction)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 40)
                    .background(Capsule().fill(palette.actionFill))
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 25, style: .continuous).fill(palette.surface.opacity(0.62)))
        .overlay(RoundedRectangle(cornerRadius: 25, style: .continuous).stroke(palette.separator, lineWidth: 0.5))
    }

    private func playlistRow(_ playlist: Playlist) -> some View {
        HStack(spacing: 4) {
            Button {
                router.navigate(to: .playlistDetail(id: playlist.id), in: .playlist)
            } label: {
                PlaylistRow(playlist: playlist, groupName: groupName(for: playlist))
            }
            .buttonStyle(.plain)
            if editMode.isEditing {
                OrderMoveMenu(title: playlist.name, canMoveUp: userPlaylists.first?.id != playlist.id,
                              canMoveDown: userPlaylists.last?.id != playlist.id) { offset in
                    guard let index = userPlaylists.firstIndex(where: { $0.id == playlist.id }),
                          userPlaylists.indices.contains(index + offset) else { return }
                    var ids = userPlaylists.map(\.id)
                    ids.swapAt(index, index + offset)
                    savePlaylistOrder(ids)
                }
                .disabled(isReordering)
            } else {
                Menu {
                    Button {
                        router.present(.editPlaylist(id: playlist.id))
                    } label: { Label("编辑歌单", systemImage: "pencil") }
                    Button(role: .destructive) {
                        pendingDelete = playlist
                    } label: { Label("删除歌单", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.body.weight(.semibold))
                        .foregroundColor(palette.textSecondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("更多操作：\(playlist.name)")
            }
        }
        .moveDisabled(!editMode.isEditing || isReordering)
        .listRowBackground(Color.clear)
        .listRowSeparatorTint(palette.separator)
        .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 8))
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                pendingDelete = playlist
            } label: { Label("删除歌单", systemImage: "trash") }
        }
        .swipeActions(edge: .leading) {
            Button {
                router.present(.editPlaylist(id: playlist.id))
            } label: { Label("编辑", systemImage: "pencil") }
            .tint(palette.accent)
        }
    }

    // MARK: - Actions

    private func savePlaylistOrder(_ ids: [UUID]) {
        guard !isReordering else { return }
        isReordering = true
        Task {
            defer { isReordering = false }
            do { try await playlistService.reorderPlaylists(orderedIds: ids) }
            catch { snackbar.show(message: "调整顺序失败，请重试") }
        }
    }

    private func groupName(for playlist: Playlist) -> String? {
        guard let gid = playlist.groupId else { return nil }
        return groupService.groupDetails.first { $0.id == gid }?.name
    }

    private func openSystemPlaylist(_ playlist: Playlist) {
        switch playlist.systemType {
        case .favorites:
            router.navigate(to: .songList(title: "我喜欢", context: .favorites), in: .playlist)
        case .recentlyPlayed:
            router.navigate(to: .songList(title: "最近播放", context: .recentlyPlayed), in: .playlist)
        default:
            router.navigate(to: .playlistDetail(id: playlist.id), in: .playlist)
        }
    }

    /// 以该歌单为队列上下文，从首个可播放项开始请求播放（交互设计文档 §5.1）
    private func play(_ playlist: Playlist) {
        Task {
            guard let detail = await playlistService.fetchDetail(playlistId: playlist.id),
                  let first = detail.songs.first(where: { !$0.isAudioMissing }) else {
                snackbar.show(message: "这个歌单还没有可播放的歌曲")
                return
            }
            await playback.play(song: first, in: .playlist(id: playlist.id))
            router.openPlayer()
        }
    }

    private func delete(_ playlist: Playlist) {
        Task {
            do {
                try await playlistService.deletePlaylist(id: playlist.id)
            } catch {
                snackbar.show(message: "删除歌单失败，请重试")
            }
        }
    }

    private func loadHighlightDuration() async {
        guard let id = highlight?.id else { highlightDuration = nil; return }
        let detail = await playlistService.fetchDetail(playlistId: id)
        guard !Task.isCancelled, highlight?.id == id else { return }
        highlightDuration = detail?.songs.reduce(0) { $0 + $1.duration }
    }
}

/// 收藏夹卡：保留目录页签形状（docs/UI设计文档.md §6：双列，默认高约 126）
struct FolderCard: View {
    let title: String
    let subtitle: String
    let symbol: String
    @Environment(\.themePalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundColor(palette.accent)
                .padding(.bottom, 10)
            Text(title)
                .font(.headline)
                .foregroundColor(palette.textPrimary)
            Text(subtitle)
                .font(.subheadline)
                .foregroundColor(palette.textSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
        .padding(16)
        .padding(.top, 8)
        .background(FolderShape().fill(palette.surface.opacity(0.62)))
        .overlay(FolderShape().stroke(palette.separator, lineWidth: 0.5))
        .contentShape(FolderShape())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title)，\(subtitle)")
        .accessibilityAddTraits(.isButton)
    }
}

/// 左上角带页签的目录形状。一条连续轮廓，描边时页签与主体之间没有接缝。
struct FolderShape: Shape {
    func path(in rect: CGRect) -> Path {
        let r: CGFloat = 20          // 主体圆角
        let tr: CGFloat = 8          // 页签圆角
        let tabHeight: CGFloat = 10
        let tabWidth = min(rect.width * 0.38, 76)
        let top = rect.minY + tabHeight
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY + tr))
        p.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY),
                 tangent2End: CGPoint(x: rect.minX + tr, y: rect.minY), radius: tr)
        p.addLine(to: CGPoint(x: rect.minX + tabWidth - tr, y: rect.minY))
        // 页签右侧斜坡下降到主体顶边
        p.addQuadCurve(to: CGPoint(x: rect.minX + tabWidth + tr, y: top),
                       control: CGPoint(x: rect.minX + tabWidth, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - r, y: top))
        p.addArc(tangent1End: CGPoint(x: rect.maxX, y: top),
                 tangent2End: CGPoint(x: rect.maxX, y: top + r), radius: r)
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        p.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY),
                 tangent2End: CGPoint(x: rect.maxX - r, y: rect.maxY), radius: r)
        p.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        p.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY),
                 tangent2End: CGPoint(x: rect.minX, y: rect.maxY - r), radius: r)
        p.closeSubpath()
        return p
    }
}

/// 歌单重点卡：卡片主体打开详情，播放按钮从首个可播放项开始（交互设计文档 §5.1）
struct PlaylistHighlightCard: View {
    let playlist: Playlist
    let totalDuration: TimeInterval?
    let onOpen: () -> Void
    let onPlay: () -> Void
    @Environment(\.themePalette) private var palette

    private var subtitle: String {
        if let totalDuration, playlist.songCount > 0 {
            return "\(playlist.songCount) 首 · \(DurationFormatter.spoken(totalDuration))"
        }
        return "\(playlist.songCount) 首"
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Button(action: onOpen) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(playlist.name)
                            .font(.title3.weight(.bold))
                            .foregroundColor(palette.textPrimary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundColor(palette.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("歌单：\(playlist.name)，\(subtitle)")
                .accessibilityHint("打开歌单")

                if playlist.songCount > 0 {
                    Button(action: onPlay) {
                        HStack(spacing: 6) {
                            Image(systemName: "play.fill").font(.caption.weight(.bold))
                            Text("播放歌单").font(.subheadline.weight(.semibold))
                        }
                        .foregroundColor(palette.onAction)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 40)
                        .background(Capsule().fill(palette.actionFill))
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            ZStack {
                Circle()
                    .fill(AngularGradient(colors: [palette.glowA, palette.glowB, palette.glowC, palette.glowA], center: .center))
                CoverImageView(path: playlist.coverImagePath, size: 46, cornerRadius: 23)
                    .overlay(Circle().stroke(palette.surface, lineWidth: 3))
            }
            .frame(width: 104, height: 104)
            .accessibilityHidden(true)
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 25, style: .continuous).fill(palette.surface.opacity(0.62)))
        .overlay(RoundedRectangle(cornerRadius: 25, style: .continuous).stroke(palette.separator, lineWidth: 0.5))
    }
}

struct PlaylistRow: View {
    let playlist: Playlist
    var groupName: String? = nil
    @Environment(\.themePalette) private var palette

    var body: some View {
        HStack(spacing: 12) {
            CoverImageView(path: playlist.coverImagePath, size: 45, cornerRadius: 10)
            VStack(alignment: .leading, spacing: 3) {
                Text(playlist.name)
                    .font(.body.weight(.medium))
                    .foregroundColor(palette.textPrimary)
                    .lineLimit(1)
                Text(groupName.map { "\(playlist.songCount) 首歌曲 · \($0)" } ?? "\(playlist.songCount) 首歌曲")
                    .font(.footnote)
                    .foregroundColor(palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(groupName.map { "歌单：\(playlist.name)，\(playlist.songCount) 首，分组 \($0)" } ?? "歌单：\(playlist.name)，\(playlist.songCount) 首")
    }
}

/// 图标与文字紧挨的标签样式
struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon
            configuration.title
        }
    }
}
