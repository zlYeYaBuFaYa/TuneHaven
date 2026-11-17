import SwiftUI

struct PlayerMoreActionsSheet: View {
    let hasLyrics: Bool
    let onSleepTimer: () -> Void
    let onSpeedPicker: () -> Void
    let onAddToPlaylist: (UUID) -> Void
    let onSearchLyrics: (Song) -> Void
    let onImportLyrics: () -> Void
    let onDeleteLyrics: () -> Void
    let onDismiss: () -> Void

    @EnvironmentObject private var playback: PlaybackService
    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.themePalette) private var palette
    @AppStorage(AppStorageKey.playerCoverStyle) private var coverStyleRaw = PlayerCoverStyle.auto.rawValue

    private var resolvedCoverStyle: PlayerCoverStyle {
        (PlayerCoverStyle(rawValue: coverStyleRaw) ?? .auto).resolved(themeID: themeManager.currentStyle.id)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button(action: onSleepTimer) {
                        HStack(spacing: 12) {
                            Image(systemName: playback.sleepTimerRemaining != nil ? "moon.zzz.fill" : "moon.zzz")
                                .font(.body)
                                .foregroundColor(palette.primary)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("定时关闭")
                                    .font(.subheadline)
                                    .foregroundColor(palette.textPrimary)
                                if let remaining = playback.sleepTimerRemaining {
                                    Text(remaining.formattedTime)
                                        .font(.caption)
                                        .foregroundColor(palette.textSecondary)
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundColor(palette.textTertiary)
                        }
                    }
                    .listRowBackground(palette.surface)

                    Button(action: onSpeedPicker) {
                        HStack(spacing: 12) {
                            Image(systemName: "speedometer")
                                .font(.body)
                                .foregroundColor(palette.primary)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("倍速播放")
                                    .font(.subheadline)
                                    .foregroundColor(palette.textPrimary)
                                Text("\(String(format: "%.1f", playback.playbackSpeed))x")
                                    .font(.caption)
                                    .foregroundColor(palette.textSecondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundColor(palette.textTertiary)
                        }
                    }
                    .listRowBackground(palette.surface)
                }

                Section {
                    // 唱片与完整方形封面之间切换，不修改原封面文件
                    Button {
                        coverStyleRaw = (resolvedCoverStyle == .disc ? PlayerCoverStyle.square : .disc).rawValue
                    } label: {
                        actionRow(
                            icon: resolvedCoverStyle == .disc ? "square" : "opticaldisc",
                            title: resolvedCoverStyle == .disc ? "显示完整方形封面" : "以唱片样式显示封面"
                        )
                    }
                    .listRowBackground(palette.surface)
                }

                if let song = playback.currentSong {
                    Section {
                        Button { onAddToPlaylist(song.id) } label: {
                            actionRow(icon: "text.badge.plus", title: "添加到歌单")
                        }
                        .listRowBackground(palette.surface)
                    }

                    Section {
                        Button { onSearchLyrics(song) } label: {
                            actionRow(icon: "magnifyingglass", title: "搜索歌词")
                        }
                        .listRowBackground(palette.surface)

                        Button(action: onImportLyrics) {
                            actionRow(icon: "doc.text", title: "导入歌词")
                        }
                        .listRowBackground(palette.surface)

                        if hasLyrics {
                            Button(action: onDeleteLyrics) {
                                actionRow(icon: "trash", title: "删除歌词", destructive: true)
                            }
                            .listRowBackground(palette.surface)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .adaptiveBackground()
            .navigationTitle("更多操作")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成", action: onDismiss)
                        .font(.subheadline)
                        .foregroundColor(palette.primary)
                }
            }
        }
    }

    private func actionRow(icon: String, title: String, destructive: Bool = false) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundColor(destructive ? SemanticColor.danger : palette.primary)
                .frame(width: 28)
            Text(title)
                .font(.subheadline)
                .foregroundColor(destructive ? SemanticColor.danger : palette.textPrimary)
            Spacer()
        }
    }
}
