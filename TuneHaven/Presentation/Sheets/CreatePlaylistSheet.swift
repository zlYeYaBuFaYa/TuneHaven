import SwiftUI

/// 新建歌单（交互设计文档 §5.2）：打开即聚焦名称；去首尾空白；错误就近显示；提交中防重复点击，失败保留输入
struct CreatePlaylistSheet: View {
    @EnvironmentObject private var playlistService: PlaylistService
    @EnvironmentObject private var router: AppRouter
    @Environment(\.themePalette) private var palette
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var description = ""
    @State private var errorMessage: String?
    @State private var isLoading = false
    @FocusState private var nameFocused: Bool

    var body: some View {
        NavigationStack {
            PlaylistForm(
                name: $name,
                description: $description,
                namePlaceholder: "歌单名称（必填）",
                errorMessage: errorMessage,
                nameFocused: $nameFocused
            )
            .navigationTitle("新建歌单")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .foregroundColor(palette.textPrimary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        createPlaylist()
                    } label: {
                        if isLoading { ProgressView() } else { Text("创建").fontWeight(.semibold) }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
                    .foregroundColor(palette.accent)
                }
            }
        }
        // 呈现动画结束后再聚焦；呈现过程中设置焦点会让 sheet 内容空白
        .task {
            try? await Task.sleep(for: .milliseconds(450))
            nameFocused = true
        }
        .onChange(of: name) { _ in errorMessage = nil }
    }

    private func createPlaylist() {
        guard !isLoading else { return }
        isLoading = true
        Task {
            do {
                let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
                _ = try await playlistService.createPlaylist(name: name, description: trimmed.isEmpty ? nil : trimmed)
                try? await Task.sleep(nanoseconds: 300_000_000)
                dismiss()
            } catch {
                AppLogger.shared.error(error, context: "创建歌单失败")
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}

/// 编辑歌单：保留原始值识别修改；有未保存修改时关闭需确认（交互设计文档 §5.2 第 4 条）
struct EditPlaylistSheet: View {
    let playlistId: UUID
    @EnvironmentObject private var playlistService: PlaylistService
    @Environment(\.themePalette) private var palette
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var description = ""
    @State private var originalName = ""
    @State private var originalDescription = ""
    @State private var loaded = false
    @State private var errorMessage: String?
    @State private var isSaving = false
    @State private var showDiscardConfirm = false
    @FocusState private var nameFocused: Bool

    private var hasChanges: Bool {
        loaded && (name != originalName || description != originalDescription)
    }

    var body: some View {
        NavigationStack {
            PlaylistForm(
                name: $name,
                description: $description,
                namePlaceholder: "歌单名称",
                errorMessage: errorMessage,
                nameFocused: $nameFocused
            )
            .navigationTitle("编辑歌单")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        if hasChanges { showDiscardConfirm = true } else { dismiss() }
                    }
                    .foregroundColor(palette.textPrimary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        save()
                    } label: {
                        if isSaving { ProgressView() } else { Text("保存").fontWeight(.semibold) }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving || !hasChanges)
                    .foregroundColor(palette.accent)
                }
            }
            .confirmationDialog("放弃对歌单的修改？", isPresented: $showDiscardConfirm, titleVisibility: .visible) {
                Button("放弃修改", role: .destructive) { dismiss() }
                Button("继续编辑", role: .cancel) {}
            }
        }
        // 有修改时禁止下拉直接关闭，改走上面的确认
        .interactiveDismissDisabled(hasChanges)
        .onChange(of: name) { _ in errorMessage = nil }
        .task {
            guard !loaded else { return }
            if let playlist = playlistService.playlists.first(where: { $0.id == playlistId }) {
                name = playlist.name
                description = playlist.description ?? ""
                originalName = name
                originalDescription = description
            }
            loaded = true
        }
    }

    private func save() {
        guard !isSaving else { return }
        isSaving = true
        Task {
            do {
                let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
                try await playlistService.updatePlaylist(id: playlistId, name: name, description: trimmed.isEmpty ? nil : trimmed)
                dismiss()
            } catch {
                AppLogger.shared.error(error, context: "编辑歌单失败")
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }
}

/// 新建／编辑共用表单：名称、简介；错误显示在名称下方
private struct PlaylistForm: View {
    @Binding var name: String
    @Binding var description: String
    let namePlaceholder: String
    let errorMessage: String?
    var nameFocused: FocusState<Bool>.Binding

    @Environment(\.themePalette) private var palette

    var body: some View {
        Form {
            Section {
                TextField(namePlaceholder, text: $name)
                    .focused(nameFocused)
                    .submitLabel(.next)
                    .foregroundColor(palette.textPrimary)
                    .listRowBackground(palette.surface)
            } header: {
                Text("名称")
            } footer: {
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.circle")
                        .font(.footnote)
                        .foregroundColor(SemanticColor.danger)
                } else {
                    Text("不能为空，也不能叫「我喜欢」或「最近播放」")
                        .font(.footnote)
                        .foregroundColor(palette.textSecondary)
                }
            }
            Section("简介（选填）") {
                TextField("写点什么", text: $description, axis: .vertical)
                    .lineLimit(3...5)
                    .foregroundColor(palette.textPrimary)
                    .listRowBackground(palette.surface)
            }
        }
        .scrollContentBackground(.hidden)
        .adaptiveBackground()
    }
}

/// 添加到歌单：成功关闭并提示；失败保留在 sheet 内说明原因
struct AddToPlaylistSheet: View {
    let songIds: [UUID]
    @EnvironmentObject private var playlistService: PlaylistService
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var snackbar: SnackbarState
    @Environment(\.themePalette) private var palette
    @Environment(\.dismiss) private var dismiss

    @State private var selectedId: UUID?
    @State private var errorMessage: String?

    private var userPlaylists: [Playlist] {
        playlistService.playlists.filter { !$0.isSystem }
    }

    var body: some View {
        NavigationStack {
            List {
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.circle")
                        .font(.footnote)
                        .foregroundColor(SemanticColor.danger)
                        .listRowBackground(palette.surface)
                }
                if userPlaylists.isEmpty {
                    VStack(spacing: 12) {
                        Text("还没有自建歌单")
                            .font(.headline)
                            .foregroundColor(palette.textPrimary)
                        Button {
                            router.present(.createPlaylist)
                            dismiss()
                        } label: {
                            Label("新建歌单", systemImage: "plus")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(palette.onAction)
                                .padding(.horizontal, 20)
                                .frame(minHeight: 44)
                                .background(Capsule().fill(palette.actionFill))
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .listRowBackground(Color.clear)
                }
                ForEach(userPlaylists) { playlist in
                    Button {
                        add(to: playlist)
                    } label: {
                        HStack(spacing: 12) {
                            CoverImageView(path: playlist.coverImagePath, size: 44, cornerRadius: 10)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(playlist.name)
                                    .font(.body.weight(.medium))
                                    .foregroundColor(palette.textPrimary)
                                    .lineLimit(1)
                                Text("\(playlist.songCount) 首")
                                    .font(.footnote)
                                    .foregroundColor(palette.textSecondary)
                            }
                            Spacer()
                            if selectedId == playlist.id {
                                ProgressView()
                            }
                        }
                        .frame(minHeight: 52)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedId != nil)
                    .listRowBackground(palette.surface)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .adaptiveBackground()
            .navigationTitle(songIds.count > 1 ? "添加 \(songIds.count) 首到歌单" : "添加到歌单")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .foregroundColor(palette.textPrimary)
                }
                // TODO: 考虑内嵌导航，创建歌单后自动将歌曲添加到新歌单，避免工作流中断
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        router.present(.createPlaylist)
                        dismiss()
                    } label: {
                        Image(systemName: "plus")
                            .foregroundColor(palette.textPrimary)
                    }
                    .accessibilityLabel("新建歌单")
                }
            }
        }
    }

    private func add(to playlist: Playlist) {
        selectedId = playlist.id
        errorMessage = nil
        Task {
            do {
                try await playlistService.addSongs(songIds, to: playlist.id)
                dismiss()
                snackbar.show(message: "已添加到「\(playlist.name)」")
            } catch {
                AppLogger.shared.error(error, context: "添加歌曲到歌单失败")
                errorMessage = "添加失败，请重试"
                selectedId = nil
            }
        }
    }
}
