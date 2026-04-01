import SwiftUI
import UserNotifications

struct SettingsPlaybackSection: View {
    @Environment(\.themePalette) private var palette
    @Environment(\.settingsListRowBg) private var listRowBg

    @Binding var isExpanded: Bool
    @Binding var recentPlayRange: Int
    @Binding var speedMemoryMode: Int
    @Binding var sleepTimerNotification: Bool
    @Binding var wifiPasswordEnabled: Bool
    @Binding var autoMatchLyrics: Bool
    @Binding var lyricsPreferSimplified: Bool
    @Binding var notificationPermissionStatus: UNAuthorizationStatus

    var body: some View {
        Section {
            DisclosureGroup(isExpanded: $isExpanded) {
                recentPlayRow
                speedMemoryRow
                autoMatchLyricsRow
                lyricsScriptRow
                sleepTimerRow
                notificationWarning
                wifiPasswordRow
            } label: {
                Label {
                    Text("播放")
                        .foregroundColor(palette.textPrimary)
                } icon: {
                    SettingsSectionIcon(systemName: "play.circle")
                }
            }
            .tint(palette.textSecondary)
            .listRowBackground(listRowBg)
        }
    }

    private var recentPlayRow: some View {
        HStack {
            Label("最近播放范围", systemImage: "clock")
                .font(.subheadline)
                .foregroundColor(palette.textPrimary)
            Spacer()
            Menu {
                ForEach(RecentPlayRange.allCases) { range in
                    Button {
                        recentPlayRange = range.days
                    } label: {
                        HStack {
                            Text(range.displayName)
                            if recentPlayRange == range.days {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Text(RecentPlayRange(days: recentPlayRange)?.displayName ?? "\(recentPlayRange)天")
                    .font(.subheadline)
                    .foregroundColor(palette.primary)
            }
        }
        .listRowBackground(listRowBg)
    }

    private var speedMemoryRow: some View {
        HStack {
            Label("速度记忆模式", systemImage: "speedometer")
                .font(.subheadline)
                .foregroundColor(palette.textPrimary)
            Spacer()
            Picker("", selection: $speedMemoryMode) {
                Text("全局").tag(0)
                Text("单曲").tag(1)
            }
            .pickerStyle(.segmented)
            .frame(width: 120)
        }
        .listRowBackground(listRowBg)
    }

    private var sleepTimerRow: some View {
        Toggle(isOn: $sleepTimerNotification) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("定时停止提醒")
                        .font(.subheadline)
                        .foregroundColor(palette.textPrimary)
                    Text("定时结束前发送通知")
                        .font(.caption)
                        .foregroundColor(palette.textSecondary)
                }
            } icon: {
                Image(systemName: "moon.zzz")
                    .foregroundColor(palette.primary)
            }
        }
        .tint(palette.primary)
        .listRowBackground(listRowBg)
        .onChange(of: sleepTimerNotification) { enabled in
            if enabled { requestNotificationPermission() }
        }
    }

    @ViewBuilder
    private var notificationWarning: some View {
        if notificationPermissionStatus == .denied && sleepTimerNotification {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(SemanticColor.warning)
                Text("通知权限已关闭，请在系统设置中开启")
                    .font(.caption)
                    .foregroundColor(palette.textSecondary)
                Spacer()
                Button("去开启") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .font(.caption)
                .foregroundColor(palette.primary)
            }
            .listRowBackground(palette.surfaceSecondary)
        }
    }

    private var wifiPasswordRow: some View {
        Toggle(isOn: $wifiPasswordEnabled) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("WiFi 传输密码保护")
                        .font(.subheadline)
                        .foregroundColor(palette.textPrimary)
                    Text("开启后上传文件需要密码")
                        .font(.caption)
                        .foregroundColor(palette.textSecondary)
                }
            } icon: {
                Image(systemName: "lock.shield")
                    .foregroundColor(palette.primary)
            }
        }
        .tint(palette.primary)
        .listRowBackground(listRowBg)
    }

    private var autoMatchLyricsRow: some View {
        Toggle(isOn: $autoMatchLyrics) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("自动匹配在线歌词")
                        .font(.subheadline)
                        .foregroundColor(palette.textPrimary)
                    Text("播放时自动搜索并下载歌词")
                        .font(.caption)
                        .foregroundColor(palette.textSecondary)
                }
            } icon: {
                Image(systemName: "text.magnifyingglass")
                    .foregroundColor(palette.primary)
            }
        }
        .tint(palette.primary)
        .listRowBackground(listRowBg)
    }

    private var lyricsScriptRow: some View {
        HStack {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("歌词字形")
                        .font(.subheadline)
                        .foregroundColor(palette.textPrimary)
                    Text("默认简体；原文保留文件中的繁简")
                        .font(.caption)
                        .foregroundColor(palette.textSecondary)
                }
            } icon: {
                Image(systemName: "character.textbox")
                    .foregroundColor(palette.primary)
            }
            Spacer(minLength: 8)
            Picker("", selection: $lyricsPreferSimplified) {
                Text("简体").tag(true)
                Text("原文").tag(false)
            }
            .pickerStyle(.segmented)
            .frame(width: 140)
        }
        .listRowBackground(listRowBg)
    }

    private func requestNotificationPermission() {
        Task {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            notificationPermissionStatus = settings.authorizationStatus
        }
    }
}
