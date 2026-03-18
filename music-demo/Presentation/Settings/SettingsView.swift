import SwiftUI
import UserNotifications
import PhotosUI

struct SettingsView: View {
    @EnvironmentObject private var themeManager: ThemeManager
    @EnvironmentObject private var searchService: SearchService
    @EnvironmentObject private var importService: ImportService
    @EnvironmentObject private var libraryService: MusicLibraryService
    @EnvironmentObject private var wallpaperManager: WallpaperManager
    @Environment(\.themePalette) private var palette
    @Environment(\.colorScheme) private var colorScheme

    @AppStorage("recent_play_range")       private var recentPlayRange: Int = 7
    @AppStorage("speed_memory_mode")       private var speedMemoryMode: Int = 0
    @AppStorage("wifi_password_enabled")   private var wifiPasswordEnabled: Bool = false
    @AppStorage("sleep_timer_notification") private var sleepTimerNotification: Bool = true
    @AppStorage("cache_limit_mb")          private var cacheLimitMB: Int = 100

    @State private var currentCacheSize: String = "计算中..."
    @State private var showClearCacheConfirm = false
    @State private var showClearHistoryConfirm = false
    @State private var notificationPermissionStatus: UNAuthorizationStatus = .notDetermined

    @State private var expandedImport = false
    @State private var expandedAppearance = false
    @State private var expandedPlayback = false
    @State private var expandedStorage = false
    @State private var expandedAbout = false

    @State private var showDocumentPicker = false
    @State private var showWifiTransfer = false
    @State private var showAppleMusicImport = false
    @State private var selectedPhotoItem: PhotosPickerItem?

    @EnvironmentObject private var router: AppRouter

    private var listRowBg: Color {
        themeManager.currentStyle.hasCustomBackground
            ? palette.surface.opacity(0.75)
            : palette.surface
    }

    var body: some View {
        List {
            importSection
            appearanceSection
            playbackSection
            storageSection
            aboutSection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(themeManager.currentStyle.hasCustomBackground ? Color.clear : palette.background)
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(palette.surface, for: .navigationBar)
        .task {
            await calculateCacheSize()
            await checkNotificationPermission()
        }
        .fileImporter(
            isPresented: $showDocumentPicker,
            allowedContentTypes: [.audio, .mpeg4Audio],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                Task {
                    _ = await importService.importFromFiles(urls: urls) { _ in }
                    await libraryService.loadSongs()
                }
            }
        }
        .sheet(isPresented: $showWifiTransfer) {
            WiFiTransferView()
                .environment(\.themePalette, palette)
                .environmentObject(importService)
                .environmentObject(libraryService)
        }
        .sheet(isPresented: $showAppleMusicImport) {
            AppleMusicImportView()
                .environment(\.themePalette, palette)
                .environmentObject(importService)
                .environmentObject(libraryService)
        }
    }

    // MARK: - Import Section

    private var importSection: some View {
        Section {
            DisclosureGroup(isExpanded: $expandedImport) {
                Button {
                    showDocumentPicker = true
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("文件导入")
                                .font(.subheadline)
                                .foregroundColor(palette.textPrimary)
                            Text("从 Files 导入 MP3, M4A 等格式")
                                .font(.caption)
                                .foregroundColor(palette.textSecondary)
                        }
                    } icon: {
                        Image(systemName: "folder")
                            .foregroundColor(palette.primary)
                    }
                }
                .listRowBackground(palette.surface)

                Button {
                    showAppleMusicImport = true
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("从 Apple Music 资料库导入")
                                .font(.subheadline)
                                .foregroundColor(palette.textPrimary)
                            Text("扫描设备上已下载的本地音乐")
                                .font(.caption)
                                .foregroundColor(palette.textSecondary)
                        }
                    } icon: {
                        Image(systemName: "music.note.house")
                            .foregroundColor(palette.primary)
                    }
                }
                .listRowBackground(palette.surface)

                Button {
                    showWifiTransfer = true
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("WiFi 传输")
                                .font(.subheadline)
                                .foregroundColor(palette.textPrimary)
                            Text("通过浏览器从电脑无线传输音乐")
                                .font(.caption)
                                .foregroundColor(palette.textSecondary)
                        }
                    } icon: {
                        Image(systemName: "wifi")
                            .foregroundColor(palette.primary)
                    }
                }
                .listRowBackground(palette.surface)
            } label: {
                Label {
                    Text("导入音乐")
                        .foregroundColor(palette.textPrimary)
                } icon: {
                    Image(systemName: "square.and.arrow.down")
                        .foregroundColor(palette.primary)
                }
            }
            .tint(palette.textSecondary)
            .listRowBackground(palette.surface)
        }
    }

    // MARK: - Appearance Section

    private var appearanceSection: some View {
        Section {
            DisclosureGroup(isExpanded: $expandedAppearance) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("颜色模式")
                        .font(.caption)
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
                            .buttonStyle(.borderless)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .listRowBackground(palette.surface)

                VStack(alignment: .leading, spacing: 10) {
                    Text("主题风格")
                        .font(.caption)
                        .foregroundColor(palette.textSecondary)
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10)
                    ], spacing: 10) {
                        ForEach(ThemeRegistry.shared.allThemes) { style in
                            Button {
                                themeManager.setTheme(style)
                            } label: {
                                themeCard(style: style)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
                .padding(.vertical, 4)
                .listRowBackground(palette.surface)
            } label: {
                Label {
                    Text("外观")
                        .foregroundColor(palette.textPrimary)
                } icon: {
                    Image(systemName: "paintbrush")
                        .foregroundColor(palette.primary)
                }
            }
            .tint(palette.textSecondary)
            .listRowBackground(palette.surface)
        }
    }

    // MARK: - Playback Section

    private var playbackSection: some View {
        Section {
            DisclosureGroup(isExpanded: $expandedPlayback) {
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
                .listRowBackground(palette.surface)

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
                .listRowBackground(palette.surface)

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
                .listRowBackground(palette.surface)
            } label: {
                Label {
                    Text("播放")
                        .foregroundColor(palette.textPrimary)
                } icon: {
                    Image(systemName: "play.circle")
                        .foregroundColor(palette.primary)
                }
            }
            .tint(palette.textSecondary)
            .listRowBackground(palette.surface)
        }
    }

    // MARK: - Storage Section

    private var storageSection: some View {
        Section {
            DisclosureGroup(isExpanded: $expandedStorage) {
                HStack {
                    Label("封面缓存占用", systemImage: "photo.stack")
                        .font(.subheadline)
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
                            .font(.subheadline)
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
                        .font(.subheadline)
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

                Button {
                    showClearHistoryConfirm = true
                } label: {
                    Label("清除搜索记录", systemImage: "magnifyingglass")
                        .font(.subheadline)
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
            } label: {
                Label {
                    Text("存储与隐私")
                        .foregroundColor(palette.textPrimary)
                } icon: {
                    Image(systemName: "externaldrive")
                        .foregroundColor(palette.primary)
                }
            }
            .tint(palette.textSecondary)
            .listRowBackground(palette.surface)
        }
    }

    // MARK: - About Section

    private var aboutSection: some View {
        Section {
            DisclosureGroup(isExpanded: $expandedAbout) {
                infoRow("版本", Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                infoRow("支持格式", "MP3 / M4A / AAC / WAV / ALAC")
                infoRow("最大文件", "500 MB / 首")
                infoRow("数据存储", "iTunes 文件共享 / iCloud 备份")
            } label: {
                Label {
                    Text("关于")
                        .foregroundColor(palette.textPrimary)
                } icon: {
                    Image(systemName: "info.circle")
                        .foregroundColor(palette.primary)
                }
            }
            .tint(palette.textSecondary)
            .listRowBackground(palette.surface)
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(palette.textPrimary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .foregroundColor(palette.textSecondary)
                .multilineTextAlignment(.trailing)
        }
        .listRowBackground(palette.surface)
    }

    // MARK: - Theme Card

    private func themeCard(style: ThemeStyle) -> some View {
        let isSelected = themeManager.currentStyle.id == style.id
        return VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        LinearGradient(
                            colors: [style.lightPalette.gradientStart, style.lightPalette.gradientEnd],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(height: 44)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.bold())
                        .foregroundColor(.white)
                        .padding(4)
                        .background(Circle().fill(Color.white.opacity(0.3)))
                }
            }
            Text(style.displayName)
                .font(.caption2)
                .foregroundColor(isSelected ? palette.primary : palette.textSecondary)
                .lineLimit(1)
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isSelected ? palette.primary.opacity(0.08) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? palette.primary : Color.clear, lineWidth: 1.5)
        )
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
