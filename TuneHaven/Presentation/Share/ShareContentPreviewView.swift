import SwiftUI

struct ShareContentPreviewView: View {
    let analysis: ShareAnalysis

    @Environment(\.themePalette) private var palette

    private var newSongsTotalBytes: Int64 {
        analysis.newSongs.reduce(0) { $0 + $1.fileSize }
    }

    private var showLargeDownloadWarning: Bool {
        analysis.estimatedDownloadSize >= 500 * 1024 * 1024
    }

    var body: some View {
        List {
            if !analysis.songs.isEmpty {
                Section {
                    HStack {
                        Text("新歌曲：\(analysis.newSongs.count) 首（\(ByteCountFormatter.string(fromByteCount: newSongsTotalBytes, countStyle: .file))）")
                        Spacer()
                    }
                    .foregroundColor(SemanticColor.success)
                    .listRowBackground(palette.surface)

                    if !analysis.exactMatchSongs.isEmpty {
                        HStack {
                            Text("已有歌曲：\(analysis.exactMatchSongs.count) 首（将跳过）")
                            Spacer()
                        }
                        .foregroundColor(palette.textSecondary)
                        .listRowBackground(palette.surface)
                    }

                    if !analysis.fuzzyMatchSongs.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("同名但版本可能不同：\(analysis.fuzzyMatchSongs.count) 首（将跳过）")
                                .foregroundColor(SemanticColor.warning)
                            Text("本地已有同名歌曲，但专辑或时长不同")
                                .font(.caption)
                                .foregroundColor(palette.textTertiary)
                        }
                        .listRowBackground(palette.surface)
                    }
                } header: {
                    Label("歌曲", systemImage: "music.note")
                        .font(.subheadline)
                        .foregroundColor(palette.textSecondary)
                }
            }

            if !analysis.playlists.isEmpty {
                Section {
                    ForEach(analysis.playlists) { playlist in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(playlist.name)
                                    .foregroundColor(palette.textPrimary)
                                Spacer()
                                Text("\(playlist.songCount) 首")
                                    .foregroundColor(palette.textSecondary)
                            }
                            if let localCount = analysis.playlistLocalSongs[playlist.name], localCount > 0 {
                                Text("关联 \(localCount) 首本地歌曲")
                                    .font(.caption)
                                    .foregroundColor(palette.textSecondary)
                            }
                        }
                        .listRowBackground(palette.surface)
                    }
                } header: {
                    Label("歌单", systemImage: "list.bullet.rectangle")
                        .font(.subheadline)
                        .foregroundColor(palette.textSecondary)
                }
            }

            Section {
                Text("预计下载：\(ByteCountFormatter.string(fromByteCount: analysis.estimatedDownloadSize, countStyle: .file))")
                    .foregroundColor(palette.textPrimary)
                    .listRowBackground(palette.surface)

                if showLargeDownloadWarning {
                    Text("下载体积较大，请确认设备存储空间充足。")
                        .font(.subheadline)
                        .foregroundColor(SemanticColor.warning)
                        .listRowBackground(palette.surface)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .adaptiveBackground()
        .navigationTitle("来自「\(analysis.sessionInfo.deviceName)」的分享")
        .navigationBarTitleDisplayMode(.inline)
    }
}
