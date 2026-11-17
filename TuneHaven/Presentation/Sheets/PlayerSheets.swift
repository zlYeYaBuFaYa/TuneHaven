import PhotosUI
import SwiftUI

struct SleepTimerSheet: View {
    @EnvironmentObject private var playback: PlaybackService
    @Environment(\.themePalette) private var palette
    @Environment(\.dismiss) private var dismiss

    private struct TimerOption: Identifiable {
        let id: Int
        let label: String
        let minutes: Int?
    }

    private let options: [TimerOption] = [
        TimerOption(id: 0, label: "关闭定时", minutes: nil),
        TimerOption(id: 15, label: "15 分钟", minutes: 15),
        TimerOption(id: 30, label: "30 分钟", minutes: 30),
        TimerOption(id: 45, label: "45 分钟", minutes: 45),
        TimerOption(id: 60, label: "60 分钟", minutes: 60),
        TimerOption(id: 90, label: "90 分钟", minutes: 90)
    ]

    var body: some View {
        NavigationStack {
            List {
                if let remaining = playback.sleepTimerRemaining {
                    Section {
                        HStack {
                            Image(systemName: "moon.zzz.fill")
                                .foregroundColor(palette.accent)
                                .accessibilityHidden(true)
                            Text("剩余 \(remaining.formattedTime)")
                                .font(.body.monospacedDigit())
                                .foregroundColor(palette.textPrimary)
                        }
                        .listRowBackground(palette.surface)
                    }
                }
                ForEach(options) { option in
                    let label = option.label
                    let minutes = option.minutes
                    Button {
                        playback.setSleepTimer(minutes: minutes)
                        dismiss()
                    } label: {
                        HStack {
                            Text(label)
                                .foregroundColor(palette.textPrimary)
                            Spacer()
                            if minutes == nil && playback.sleepTimerOriginalMinutes == nil {
                                Image(systemName: "checkmark").foregroundColor(palette.accent).accessibilityLabel("当前选择")
                            } else if let m = minutes, playback.sleepTimerOriginalMinutes == m {
                                Image(systemName: "checkmark").foregroundColor(palette.accent).accessibilityLabel("当前选择")
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
                        .foregroundColor(palette.textPrimary)
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

    /// 0.5×、0.75×、1×、1.25×：去掉多余的 0
    static func speedText(_ speed: Float) -> String {
        var text = String(format: "%.2f", speed)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text + "×"
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(speeds, id: \.self) { speed in
                    Button {
                        playback.setSpeed(speed)
                        dismiss()
                    } label: {
                        HStack {
                            Text(Self.speedText(speed))
                                .foregroundColor(palette.textPrimary)
                            if speed == 1.0 {
                                Text("（默认）")
                                    .font(.caption)
                                    .foregroundColor(palette.textSecondary)
                            }
                            Spacer()
                            if playback.playbackSpeed == speed {
                                Image(systemName: "checkmark")
                                    .foregroundColor(palette.accent)
                                    .accessibilityLabel("当前选择")
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
                        .foregroundColor(palette.textPrimary)
                }
            }
        }
    }
}

struct PlaylistCoverPickerSheet: View {
    let playlistId: UUID
    @EnvironmentObject private var playlistService: PlaylistService
    @EnvironmentObject private var snackbar: SnackbarState
    @Environment(\.themePalette) private var palette
    @Environment(\.dismiss) private var dismiss

    @State private var selectedPhotoItem: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            List {
                Button {
                    if let detail = playlistService.playlists.first(where: { $0.id == playlistId }) {
                        Task {
                            let playlistDetail = await playlistService.fetchDetail(playlistId: playlistId)
                            let songs = playlistDetail?.songs ?? []
                            await playlistService.regenerateAutoCover(for: detail, songs: songs)
                            dismiss()
                        }
                    }
                } label: {
                    Label("使用自动生成封面", systemImage: "wand.and.stars")
                        .foregroundColor(palette.textPrimary)
                }
                .listRowBackground(palette.surface)

                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
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
                        .foregroundColor(palette.textPrimary)
                }
            }
            .onChange(of: selectedPhotoItem) { newItem in
                guard let newItem else { return }
                Task {
                    do {
                        guard let data = try await newItem.loadTransferable(type: Data.self) else {
                            snackbar.show(message: "无法读取所选图片")
                            return
                        }
                        try await playlistService.setCustomCover(playlistId: playlistId, imageData: data)
                        dismiss()
                    } catch {
                        snackbar.show(message: "封面设置失败")
                    }
                }
            }
        }
    }
}
