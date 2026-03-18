import SwiftUI

struct SleepTimerSheet: View {
    @EnvironmentObject private var playback: PlaybackService
    @Environment(\.themePalette) private var palette
    @Environment(\.dismiss) private var dismiss

    private let options: [(String, Int?)] = [
        ("关闭定时", nil),
        ("15 分钟", 15),
        ("30 分钟", 30),
        ("45 分钟", 45),
        ("60 分钟", 60),
        ("90 分钟", 90)
    ]

    var body: some View {
        NavigationStack {
            List {
                ForEach(options, id: \.0) { label, minutes in
                    Button {
                        playback.setSleepTimer(minutes: minutes)
                        dismiss()
                    } label: {
                        HStack {
                            Text(label)
                                .foregroundColor(palette.textPrimary)
                            Spacer()
                            if minutes == nil && playback.sleepTimerRemaining == nil {
                                Image(systemName: "checkmark").foregroundColor(palette.primary)
                            } else if let m = minutes, let remaining = playback.sleepTimerRemaining,
                                      Int(remaining / 60) == m {
                                Image(systemName: "checkmark").foregroundColor(palette.primary)
                            }
                        }
                    }
                    .listRowBackground(palette.surface)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .adaptiveBackground()
            .navigationTitle("定时停止播放")
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

struct PlaybackSpeedSheet: View {
    @EnvironmentObject private var playback: PlaybackService
    @Environment(\.themePalette) private var palette
    @Environment(\.dismiss) private var dismiss

    private let speeds: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]

    var body: some View {
        NavigationStack {
            List {
                ForEach(speeds, id: \.self) { speed in
                    Button {
                        playback.setSpeed(speed)
                        dismiss()
                    } label: {
                        HStack {
                            Text(String(format: "%.2fx", speed))
                                .foregroundColor(palette.textPrimary)
                            if speed == 1.0 {
                                Text("（默认）")
                                    .font(.caption)
                                    .foregroundColor(palette.textTertiary)
                            }
                            Spacer()
                            if playback.playbackSpeed == speed {
                                Image(systemName: "checkmark")
                                    .foregroundColor(palette.primary)
                            }
                        }
                    }
                    .listRowBackground(palette.surface)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .adaptiveBackground()
            .navigationTitle("播放速度")
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

struct PlaylistCoverPickerSheet: View {
    let playlistId: UUID
    @EnvironmentObject private var playlistService: PlaylistService
    @Environment(\.themePalette) private var palette
    @Environment(\.dismiss) private var dismiss

    @State private var showImagePicker = false

    var body: some View {
        NavigationStack {
            List {
                Button {
                    if let detail = playlistService.playlists.first(where: { $0.id == playlistId }) {
                        Task {
                            await playlistService.regenerateAutoCover(for: detail, songs: [])
                            dismiss()
                        }
                    }
                } label: {
                    Label("使用自动生成封面", systemImage: "wand.and.stars")
                        .foregroundColor(palette.textPrimary)
                }
                .listRowBackground(palette.surface)

                Button { showImagePicker = true } label: {
                    Label("从相册选择", systemImage: "photo")
                        .foregroundColor(palette.textPrimary)
                }
                .listRowBackground(palette.surface)
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .adaptiveBackground()
            .navigationTitle("更换封面")
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
