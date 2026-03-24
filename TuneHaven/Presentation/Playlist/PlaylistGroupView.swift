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
                Section("未分组") {
                    ForEach(ungrouped) { playlist in
                        ungroupedPlaylistRow(playlist)
                    }
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
                        .foregroundColor(palette.primary)
                }
            }
            ToolbarItem(placement: .navigationBarLeading) {
                EditButton().foregroundColor(palette.primary)
            }
        }
        .task { await groupService.loadGroups() }
        .alert("新建分组", isPresented: $showCreateGroup) {
            TextField("分组名称", text: $newGroupName)
            Button("创建") {
                let name = newGroupName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return }
                Task {
                    do { try await groupService.createGroup(name: name) }
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
                .listRowBackground(palette.surface)
                .swipeActions(edge: .leading) {
                    Button {
                        movingPlaylist = playlist
                    } label: {
                        Label("移出分组", systemImage: "folder.badge.minus")
                    }
                    .tint(SemanticColor.warning)
                }
            }

            if group.playlists.isEmpty {
                Text("暂无歌单，可将歌单移入此分组")
                    .font(.caption)
                    .foregroundColor(palette.textTertiary)
                    .listRowBackground(palette.surface)
            }
        } header: {
            HStack {
                Image(systemName: "folder.fill")
                    .foregroundColor(palette.primary)
                Text(group.name)
                    .foregroundColor(palette.textSecondary)
                Spacer()
                Text("\(group.playlists.count) 个歌单")
                    .font(.caption)
                    .foregroundColor(palette.textTertiary)
                Menu {
                    Button {
                        renameTarget = group
                        renameText = group.name
                    } label: {
                        Label("重命名", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        Task {
                            do { try await groupService.deleteGroup(id: group.id) }
                            catch { snackbar.show(message: "删除分组失败") }
                        }
                    } label: {
                        Label("删除分组", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.caption)
                        .foregroundColor(palette.textTertiary)
                        .padding(4)
                }
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
        .listRowBackground(palette.surface)
        .swipeActions(edge: .leading) {
            Button {
                movingPlaylist = playlist
            } label: {
                Label("移入分组", systemImage: "folder.badge.plus")
            }
            .tint(palette.primary)
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
                        Image(systemName: "xmark.circle")
                            .foregroundColor(SemanticColor.danger)
                        Text("移出所有分组")
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
                                .foregroundColor(palette.primary)
                            Text(group.name)
                                .foregroundColor(palette.textPrimary)
                            Spacer()
                            Text("\(group.playlists.count) 个")
                                .font(.caption)
                                .foregroundColor(palette.textTertiary)
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
                        .foregroundColor(palette.primary)
                }
            }
        }
    }
}
