import SwiftUI

struct WebDAVBrowserView: View {
    @EnvironmentObject private var webDAVService: WebDAVService
    @EnvironmentObject private var importService: ImportService
    @EnvironmentObject private var libraryService: MusicLibraryService
    @Environment(\.themePalette) private var palette

    let account: WebDAVAccount

    @State private var currentPath = "/"
    @State private var selectedFiles: Set<String> = []
    @State private var isConnecting = true
    @State private var errorMessage: String?
    @State private var showDownloadView = false

    var body: some View {
        ZStack {
            if isConnecting {
                ProgressView("连接中...")
                    .foregroundColor(palette.textSecondary)
            } else if let error = errorMessage {
                errorView(error)
            } else {
                fileListView
            }
        }
        .adaptiveBackground()
        .navigationTitle(account.effectiveDisplayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(palette.surface, for: .navigationBar)
        .toolbar {
            if !selectedFiles.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button { showDownloadView = true } label: {
                        Text("导入 (\(selectedFiles.count))")
                            .font(.subheadline.bold())
                    }
                    .foregroundColor(palette.primary)
                }
            }
        }
        .sheet(isPresented: $showDownloadView) {
            WebDAVDownloadView(
                files: webDAVService.currentFiles.filter { selectedFiles.contains($0.id) },
                account: account,
                onComplete: {
                    selectedFiles.removeAll()
                    Task { await libraryService.loadSongs() }
                }
            )
        }
        .task { await connect() }
    }

    // MARK: - File List

    private var fileListView: some View {
        VStack(spacing: 0) {
            pathBar
            List {
                if webDAVService.currentFiles.isEmpty {
                    emptyRow
                } else {
                    ForEach(webDAVService.currentFiles) { file in
                        if file.isDirectory {
                            directoryRow(file)
                        } else {
                            audioFileRow(file)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .refreshable { await loadCurrentDirectory() }

            if !selectedFiles.isEmpty {
                selectionBar
            }
        }
    }

    private var pathBar: some View {
        HStack {
            if currentPath != "/" {
                Button {
                    navigateToParent()
                } label: {
                    Image(systemName: "chevron.left")
                        .foregroundColor(palette.primary)
                        .font(.caption)
                }
            }
            Image(systemName: "folder.fill")
                .foregroundColor(palette.primary)
                .font(.caption)
            Text(currentPath)
                .font(.caption)
                .foregroundColor(palette.textSecondary)
                .lineLimit(1)
            Spacer()
            if webDAVService.isLoading {
                ProgressView()
                    .scaleEffect(0.7)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(palette.surfaceSecondary)
    }

    private var emptyRow: some View {
        HStack {
            Spacer()
            VStack(spacing: 8) {
                Image(systemName: "music.note.list")
                    .font(.title2)
                    .foregroundColor(palette.textTertiary)
                Text("此目录下没有音频文件")
                    .font(.subheadline)
                    .foregroundColor(palette.textSecondary)
            }
            .padding(.vertical, 24)
            Spacer()
        }
        .listRowBackground(palette.surface)
    }

    private func directoryRow(_ file: WebDAVFile) -> some View {
        Button {
            let newPath = file.href.hasSuffix("/") ? file.href : file.href + "/"
            currentPath = newPath
            selectedFiles.removeAll()
            Task { await loadCurrentDirectory() }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "folder.fill")
                    .foregroundColor(palette.primary)
                    .frame(width: 24)
                Text(file.fileName)
                    .font(.subheadline)
                    .foregroundColor(palette.textPrimary)
                    .lineLimit(1)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundColor(palette.textTertiary)
            }
            .padding(.vertical, 4)
        }
        .listRowBackground(palette.surface)
    }

    private func audioFileRow(_ file: WebDAVFile) -> some View {
        let isSelected = selectedFiles.contains(file.id)
        return Button {
            if isSelected {
                selectedFiles.remove(file.id)
            } else {
                selectedFiles.insert(file.id)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? palette.primary : palette.textTertiary)
                    .frame(width: 24)
                Image(systemName: "music.note")
                    .foregroundColor(palette.textSecondary)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(file.fileName)
                        .font(.subheadline)
                        .foregroundColor(palette.textPrimary)
                        .lineLimit(1)
                    Text(file.formattedSize)
                        .font(.caption)
                        .foregroundColor(palette.textTertiary)
                }
                Spacer()
            }
            .padding(.vertical, 4)
        }
        .listRowBackground(isSelected ? palette.primary.opacity(0.08) : palette.surface)
    }

    private var selectionBar: some View {
        let totalSize = webDAVService.currentFiles
            .filter { selectedFiles.contains($0.id) }
            .reduce(Int64(0)) { $0 + $1.contentLength }

        return HStack {
            Text("已选 \(selectedFiles.count) 首")
                .font(.subheadline)
                .foregroundColor(palette.textPrimary)
            Text(ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file))
                .font(.caption)
                .foregroundColor(palette.textSecondary)
            Spacer()
            Button { showDownloadView = true } label: {
                Text("下载导入")
                    .font(.subheadline.bold())
                    .foregroundColor(palette.textPrimary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(palette.primary))
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(palette.surface)
    }

    // MARK: - Error

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 40))
                .foregroundColor(palette.textTertiary)
            Text(message)
                .font(.subheadline)
                .foregroundColor(palette.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button("重试") {
                Task { await connect() }
            }
            .foregroundColor(palette.primary)
        }
    }

    // MARK: - Logic

    private func connect() async {
        isConnecting = true
        errorMessage = nil
        do {
            try await webDAVService.connect(to: account)
            currentPath = "/"
            isConnecting = false
        } catch {
            errorMessage = error.localizedDescription
            isConnecting = false
        }
    }

    private func navigateToParent() {
        var path = currentPath
        if path.hasSuffix("/") { path = String(path.dropLast()) }
        let parent = (path as NSString).deletingLastPathComponent
        currentPath = parent.hasSuffix("/") ? parent : parent + "/"
        selectedFiles.removeAll()
        Task { await loadCurrentDirectory() }
    }

    private func loadCurrentDirectory() async {
        errorMessage = nil
        do {
            try await webDAVService.loadDirectory(currentPath)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
