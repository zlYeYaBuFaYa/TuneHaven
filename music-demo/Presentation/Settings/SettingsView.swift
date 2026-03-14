import SwiftUI
import UserNotifications

struct SettingsView: View {
    @EnvironmentObject private var themeManager: ThemeManager
    @EnvironmentObject private var searchService: SearchService
    @Environment(\.themePalette) private var palette
    @Environment(\.colorScheme) private var colorScheme

    // MARK: - UserDefaults Keys (TDD Section 2.5)
    @AppStorage("color_mode")              private var colorModeRaw: Int = 0
    @AppStorage("recent_play_range")       private var recentPlayRange: Int = 7
    @AppStorage("speed_memory_mode")       private var speedMemoryMode: Int = 0
    @AppStorage("wifi_password_enabled")   private var wifiPasswordEnabled: Bool = false
    @AppStorage("sleep_timer_notification") private var sleepTimerNotification: Bool = true
    @AppStorage("cache_limit_mb")          private var cacheLimitMB: Int = 100

    @State private var currentCacheSize: String = "计算中..."
    @State private var showClearCacheConfirm = false
    @State private var showClearHistoryConfirm = false
    @State private var notificationPermissionStatus: UNAuthorizationStatus = .notDetermined

    var body: some View {
        List {
            appearanceSection
            playbackSection
            wifiSection
            storageSection
            privacySection
            aboutSection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(palette.background)
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.large)
        .task {
            await calculateCacheSize()
            await checkNotificationPermission()
        }
    }

    // MARK: - Appearance Section
    private var appearanceSection: some View {
        Section {
            // 颜色模式选择（TDD Section 8.1）
            VStack(alignment: .leading, spacing: 10) {
                Text("颜色模式")
                    .font(.subheadline)
                    .foregroundColor(palette.textSecondary)
                HStack(spacing: 0) {
                    ForEach(ColorMode.allCases) { mode in
                        Button {
                            themeManager.setColorMode(mode)
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: mode.iconName)
                                    .font(.subheadline)
                                Text(mode.displayName)
                                    .font(.caption2)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(
                                themeManager.colorMode == mode
                                    ? palette.primary.opacity(0.15)
                                    : Color.clear
                            )
                            .foregroundColor(
                                themeManager.colorMode == mode
                                    ? palette.primary
                                    : palette.textSecondary
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(
                                        themeManager.colorMode == mode ? palette.primary : Color.clear,
                                        lineWidth: 1.5
                                    )
                            )
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .listRowBackground(palette.surface)

            // 主题风格选择（TDD Section 8.3）
            VStack(alignment: .leading, spacing: 10) {
                Text("主题风格")
                    .font(.subheadline)
                    .foregroundColor(palette.textSecondary)
                ForEach(ThemeStyle.allStyles) { style in
                    Button {
                        themeManager.setTheme(style)
                    } label: {
                        HStack(spacing: 14) {
                            Circle()
                                .fill(style.previewColor)
                                .frame(width: 30, height: 30)
                                .shadow(color: style.previewColor.opacity(0.4), radius: 4)
                            Text(style.displayName)
                                .foregroundColor(palette.textPrimary)
                            Spacer()
                            if themeManager.currentStyle.id == style.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(palette.primary)
                            }
                        }
                    }
                    .listRowBackground(palette.surface)
                }
            }
            .padding(.vertical, 4)
            .listRowBackground(palette.surface)
        } header: {
            Text("外观")
                .foregroundColor(palette.textSecondary)
        }
    }

    // MARK: - Playback Section
    private var playbackSection: some View {
        Section {
            // 最近播放时间范围
            HStack {
                Label("最近播放范围", systemImage: "clock")
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
            .listRowBackground(palette.surface)

            // 播放速度记忆模式
            HStack {
                Label("速度记忆模式", systemImage: "speedometer")
                    .foregroundColor(palette.textPrimary)
                Spacer()
                Picker("", selection: $speedMemoryMode) {
                    Text("全局记忆").tag(0)
                    Text("单曲记忆").tag(1)
                }
                .pickerStyle(.segmented)
                .frame(width: 150)
            }
            .listRowBackground(palette.surface)

            // 定时停止通知
            Toggle(isOn: $sleepTimerNotification) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("定时停止提醒")
                            .foregroundColor(palette.textPrimary)
                        Text("定时结束前发送本地通知")
                            .font(.caption)
                            .foregroundColor(palette.textSecondary)
                    }
                } icon: {
                    Image(systemName: "moon.zzz")
                        .foregroundColor(palette.primary)
                }
            }
            .tint(palette.primary)
            .listRowBackground(palette.surface)
            .onChange(of: sleepTimerNotification) { _, enabled in
                if enabled { requestNotificationPermission() }
            }

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
        } header: {
            Text("播放")
                .foregroundColor(palette.textSecondary)
        }
    }

    // MARK: - WiFi Section
    private var wifiSection: some View {
        Section {
            Toggle(isOn: $wifiPasswordEnabled) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("WiFi 传输密码保护")
                            .foregroundColor(palette.textPrimary)
                        Text("开启后需要输入密码才能上传文件")
                            .font(.caption)
                            .foregroundColor(palette.textSecondary)
                    }
                } icon: {
                    Image(systemName: "lock.wifi")
                        .foregroundColor(palette.primary)
                }
            }
            .tint(palette.primary)
            .listRowBackground(palette.surface)
        } header: {
            Text("WiFi 传输")
                .foregroundColor(palette.textSecondary)
        }
    }

    // MARK: - Storage Section
    private var storageSection: some View {
        Section {
            HStack {
                Label("封面缓存占用", systemImage: "photo.stack")
                    .foregroundColor(palette.textPrimary)
                Spacer()
                Text(currentCacheSize)
                    .font(.subheadline)
                    .foregroundColor(palette.textSecondary)
            }
            .listRowBackground(palette.surface)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("最大缓存限制")
                        .foregroundColor(palette.textPrimary)
                    Spacer()
                    Text("\(cacheLimitMB) MB")
                        .font(.subheadline.monospacedDigit())
                        .foregroundColor(palette.textSecondary)
                }
                Slider(value: Binding(
                    get: { Double(cacheLimitMB) },
                    set: {
                        cacheLimitMB = Int($0)
                        ImageCacheManager.shared.setCacheLimit(cacheLimitMB)
                    }
                ), in: 50...300, step: 50)
                .tint(palette.primary)
            }
            .listRowBackground(palette.surface)

            Button {
                showClearCacheConfirm = true
            } label: {
                Label("清理封面缓存", systemImage: "trash")
                    .foregroundColor(SemanticColor.danger)
            }
            .listRowBackground(palette.surface)
            .confirmationDialog("清理缓存", isPresented: $showClearCacheConfirm) {
                Button("清理", role: .destructive) {
                    Task {
                        await ImageCacheManager.shared.clearAll()
                        await calculateCacheSize()
                    }
                }
            } message: {
                Text("将清除所有封面图片缓存，下次加载时会重新生成")
            }
        } header: {
            Text("存储")
                .foregroundColor(palette.textSecondary)
        }
    }

    // MARK: - Privacy Section
    private var privacySection: some View {
        Section {
            Button {
                showClearHistoryConfirm = true
            } label: {
                Label("清除搜索记录", systemImage: "magnifyingglass.circle")
                    .foregroundColor(SemanticColor.danger)
            }
            .listRowBackground(palette.surface)
            .confirmationDialog("清除搜索记录", isPresented: $showClearHistoryConfirm) {
                Button("清除", role: .destructive) {
                    Task { await searchService.clearHistory() }
                }
            } message: {
                Text("将清除所有搜索历史记录")
            }
        } header: {
            Text("隐私")
                .foregroundColor(palette.textSecondary)
        }
    }

    // MARK: - About Section
    private var aboutSection: some View {
        Section {
            infoRow("版本", Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
            infoRow("支持格式", "MP3 / M4A / AAC / WAV / ALAC")
            infoRow("最大文件", "500 MB / 首")
            infoRow("数据存储", "iTunes 文件共享 / iCloud 备份")
        } header: {
            Text("关于")
                .foregroundColor(palette.textSecondary)
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundColor(palette.textPrimary)
            Spacer()
            Text(value).font(.subheadline).foregroundColor(palette.textSecondary).multilineTextAlignment(.trailing)
        }
        .listRowBackground(palette.surface)
    }

    // MARK: - Helpers

    private func calculateCacheSize() async {
        let bytes = ImageCacheManager.shared.cacheSize()
        let mb = Double(bytes) / 1024 / 1024
        currentCacheSize = mb < 1
            ? String(format: "%.0f KB", Double(bytes) / 1024)
            : String(format: "%.1f MB", mb)
    }

    private func checkNotificationPermission() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationPermissionStatus = settings.authorizationStatus
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in
            Task { await checkNotificationPermission() }
        }
    }
}

// MARK: - 最近播放时间范围枚举（TDD Section 2.5 recent_play_range）
enum RecentPlayRange: Int, CaseIterable, Identifiable {
    case three  = 3
    case seven  = 7
    case fourteen = 14
    case thirty = 30
    case all    = 0

    var id: Int { rawValue }
    var days: Int { rawValue }

    var displayName: String {
        switch self {
        case .three:    return "最近 3 天"
        case .seven:    return "最近 7 天"
        case .fourteen: return "最近 14 天"
        case .thirty:   return "最近 30 天"
        case .all:      return "全部历史"
        }
    }

    init?(days: Int) {
        self.init(rawValue: days)
    }
}
