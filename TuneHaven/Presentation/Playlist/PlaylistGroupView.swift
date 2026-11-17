import SwiftUI

struct PlaylistGroupView: View {
    @EnvironmentObject private var groupService: PlaylistGroupService
    @EnvironmentObject private var playlistService: PlaylistService
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var snackbar: SnackbarState
    @Environment(\.themePalette) private var palette

    @State private var showCreateGroup = false
    @State private var newGroupName = ""
    @State private var renameTarget: PlaylistGroupDetail?
    @State private var renameText = ""
    @State private var showMoveSheet = false
    @State private var movingPlaylist: Playlist? = nil
    @State private var deleteTarget: PlaylistGroupDetail?

    private var rowBackground: Color { palette.surface }

    var body: some View {
        List {
            if groupService.groupDetails.isEmpty {
                EmptyStateView(
                    icon: "folder.badge.plus",
                    title: "暂无分组",
                    subtitle: "创建分组可以整理你的歌单",
                    actionTitle: "创建分组",
                    action: { showCreateGroup = true }
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else {
                ForEach(groupService.groupDetails) { group in
                    groupSection(group)
                }
                .onMove { src, dst in
                    var ids = groupService.groupDetails.map { $0.id }
                    ids.move(fromOffsets: src, toOffset: dst)
                    Task {
                        do { try await groupService.reorderGroups(orderedIds: ids) }
                        catch { snackbar.show(message: "分组排序失败") }
                    }
                }
            }

            // 未分组歌单
            let ungrouped = ungroupedPlaylists
            if !ungrouped.isEmpty {
                Section {
                    ForEach(ungrouped) { playlist in
                        ungroupedPlaylistRow(playlist)
                    }
                } header: {
                    ListSectionTitle(title: "未分组", count: ungrouped.count)
                        .textCase(nil)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .adaptiveBackground()
        .navigationTitle("管理分组")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showCreateGroup = true
                } label: {
                    Image(systemName: "folder.badge.plus")
                        .foregroundColor(palette.textPrimary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("新建分组")
            }
            ToolbarItem(placement: .navigationBarLeading) {
                EditButton().foregroundColor(palette.accent)
            }
        }
        .task { await groupService.loadGroups() }
        .confirmationDialog(
            "删除分组「\(deleteTarget?.name ?? "")」？",
            isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }),
            titleVisibility: .visible
        ) {
            Button("删除分组", role: .destructive) {
                guard let target = deleteTarget else { return }
                Task {
                    do { try await groupService.deleteGroup(id: target.id) }
                    catch { snackbar.show(message: "删除分组失败") }
                }
                deleteTarget = nil
            }
            Button("取消", role: .cancel) { deleteTarget = nil }
        } message: {
            Text("分组内的歌单会移回未分组，歌单本身不会删除")
        }
        .alert("新建分组", isPresented: $showCreateGroup) {
            TextField("分组名称", text: $newGroupName)
            Button("创建") {
                let name = newGroupName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return }
                Task {
                    do { _ = try await groupService.createGroup(name: name) }
                    catch { snackbar.show(message: "创建分组失败") }
                    newGroupName = ""
                }
            }
            Button("取消", role: .cancel) { newGroupName = "" }
        }
        .alert("重命名分组", isPresented: Binding(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } }
        )) {
            TextField("新名称", text: $renameText)
            Button("确认") {
                guard let target = renameTarget else { return }
                let name = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return }
                Task {
                    do { try await groupService.renameGroup(id: target.id, name: name) }
                    catch { snackbar.show(message: "重命名失败") }
                    renameTarget = nil
                    renameText = ""
                }
            }
            Button("取消", role: .cancel) { renameTarget = nil; renameText = "" }
        } message: {
            if let target = renameTarget { Text("重命名「\(target.name)」") }
        }
        .sheet(item: $movingPlaylist) { playlist in
            MoveToGroupSheet(
                playlist: playlist,
                groups: groupService.groupDetails,
                onMove: { groupId in
                    Task {
                        do { try await groupService.movePlaylist(playlist.id, toGroup: groupId) }
                        catch { snackbar.show(message: "移动歌单失败") }
                        movingPlaylist = nil
                    }
                }
            )
            .sheetBackground()
            .environment(\.themePalette, palette)
        }
    }

    // MARK: - Section 视图

    @ViewBuilder
    private func groupSection(_ group: PlaylistGroupDetail) -> some View {
        Section {
            ForEach(group.playlists) { playlist in
                Button {
                    router.navigate(to: .playlistDetail(id: playlist.id), in: .playlist)
                } label: {
                    PlaylistRow(playlist: playlist)
                }
                .listRowBackground(rowBackground)
                .swipeActions(edge: .leading) {
                    Button {
                        movingPlaylist = playlist
                    } label: {
                        Label("移动分组", systemImage: "folder")
                    }
                    .tint(palette.accent)
                }
                .contextMenu {
                    Button { movingPlaylist = playlist } label: {
                        Label("移动到其他分组", systemImage: "folder")
                    }
                }
            }

            if group.playlists.isEmpty {
                Text("暂无歌单。在下方未分组歌单上长按或右滑即可移入")
                    .font(.footnote)
                    .foregroundColor(palette.textSecondary)
                    .listRowBackground(rowBackground)
            }
        } header: {
            HStack(spacing: 8) {
                Image(systemName: "folder.fill")
                    .foregroundColor(palette.accent)
                    .accessibilityHidden(true)
                Text(group.name)
                    .font(.headline)
                    .foregroundColor(palette.textPrimary)
                    .textCase(nil)
                Text("\(group.playlists.count)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundColor(palette.textSecondary)
                Spacer()
                Menu {
                    Button {
                        renameTarget = group
                        renameText = group.name
                    } label: {
                        Label("重命名", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        deleteTarget = group
                    } label: {
                        Label("删除分组", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.body.weight(.semibold))
                        .foregroundColor(palette.textSecondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("分组「\(group.name)」操作")
            }
        }
    }

    @ViewBuilder
    private func ungroupedPlaylistRow(_ playlist: Playlist) -> some View {
        Button {
            router.navigate(to: .playlistDetail(id: playlist.id), in: .playlist)
        } label: {
            PlaylistRow(playlist: playlist)
        }
        .listRowBackground(rowBackground)
        .swipeActions(edge: .leading) {
            Button {
                movingPlaylist = playlist
            } label: {
                Label("移入分组", systemImage: "folder.badge.plus")
            }
            .tint(palette.accent)
        }
        .contextMenu {
            Button { movingPlaylist = playlist } label: {
                Label("移入分组", systemImage: "folder.badge.plus")
            }
        }
    }

    private var ungroupedPlaylists: [Playlist] {
        let groupedIds = Set(groupService.groupDetails.flatMap { $0.playlists.map { $0.id } })
        return playlistService.playlists.filter { !$0.isSystem && !groupedIds.contains($0.id) }
    }
}

// MARK: - 移入分组 Sheet

struct MoveToGroupSheet: View {
    let playlist: Playlist
    let groups: [PlaylistGroupDetail]
    let onMove: (UUID?) -> Void

    @Environment(\.themePalette) private var palette
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Button {
                    onMove(nil)
                    dismiss()
                } label: {
                    HStack {
                        Image(systemName: "tray")
                            .foregroundColor(palette.textSecondary)
                        Text("不分组")
                            .foregroundColor(palette.textPrimary)
                    }
                }
                .listRowBackground(palette.surface)

                ForEach(groups) { group in
                    Button {
                        onMove(group.id)
                        dismiss()
                    } label: {
                        HStack {
                            Image(systemName: "folder.fill")
                                .foregroundColor(palette.accent)
                            Text(group.name)
                                .foregroundColor(palette.textPrimary)
                            Spacer()
                            if group.playlists.contains(where: { $0.id == playlist.id }) {
                                Image(systemName: "checkmark")
                                    .foregroundColor(palette.accent)
                                    .accessibilityLabel("当前分组")
                            } else {
                                Text("\(group.playlists.count) 个")
                                    .font(.footnote)
                                    .foregroundColor(palette.textSecondary)
                            }
                        }
                    }
                    .listRowBackground(palette.surface)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .adaptiveBackground()
            .navigationTitle("移入分组")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .foregroundColor(palette.textPrimary)
                }
            }
        }
    }
}
