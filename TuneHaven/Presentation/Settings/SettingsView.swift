import SwiftUI
import UserNotifications
import PhotosUI

struct SettingsView: View {
    @EnvironmentObject private var themeManager: ThemeManager
    @EnvironmentObject private var importService: ImportService
    @EnvironmentObject private var libraryService: MusicLibraryService
    @EnvironmentObject private var wallpaperManager: WallpaperManager
    @Environment(\.themePalette) private var palette

    @AppStorage(AppStorageKey.recentPlayRange)       private var recentPlayRange: Int = 7
    @AppStorage(AppStorageKey.speedMemoryMode)       private var speedMemoryMode: Int = 0
    @AppStorage(AppStorageKey.wifiPasswordEnabled)   private var wifiPasswordEnabled: Bool = false
    @AppStorage(AppStorageKey.sleepTimerNotification) private var sleepTimerNotification: Bool = true
    @AppStorage(AppStorageKey.cacheLimitMB)          private var cacheLimitMB: Int = 100
    @AppStorage(AppStorageKey.autoMatchLyrics)       private var autoMatchLyrics: Bool = true
    @AppStorage(AppStorageKey.lyricsPreferSimplified) private var lyricsPreferSimplified: Bool = true

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
    @State private var showCloudDriveImport = false
    @State private var showWebDAVImport = false
    @State private var selectedPhotoItem: PhotosPickerItem?

    private var hasCustomBg: Bool {
        themeManager.currentStyle.hasCustomBackground || wallpaperManager.useCustomWallpaper
    }

    private var listRowBg: Color {
        hasCustomBg ? palette.surface.opacity(0.75) : palette.surface
    }

    var body: some View {
        List {
            SettingsImportSection(
                isExpanded: $expandedImport,
                showDocumentPicker: $showDocumentPicker,
                showAppleMusicImport: $showAppleMusicImport,
                showCloudDriveImport: $showCloudDriveImport,
                showWifiTransfer: $showWifiTransfer,
                showWebDAVImport: $showWebDAVImport
            )

            SettingsAppearanceSection(
                isExpanded: $expandedAppearance,
                selectedPhotoItem: $selectedPhotoItem
            )

            SettingsPlaybackSection(
                isExpanded: $expandedPlayback,
                recentPlayRange: $recentPlayRange,
                speedMemoryMode: $speedMemoryMode,
                sleepTimerNotification: $sleepTimerNotification,
                wifiPasswordEnabled: $wifiPasswordEnabled,
                autoMatchLyrics: $autoMatchLyrics,
                lyricsPreferSimplified: $lyricsPreferSimplified,
                notificationPermissionStatus: $notificationPermissionStatus
            )

            SettingsStorageSection(
                isExpanded: $expandedStorage,
                cacheLimitMB: $cacheLimitMB,
                currentCacheSize: $currentCacheSize,
                showClearCacheConfirm: $showClearCacheConfirm,
                showClearHistoryConfirm: $showClearHistoryConfirm
            )

            SettingsAboutSection(isExpanded: $expandedAbout)
        }
        .environment(\.settingsListRowBg, listRowBg)
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(hasCustomBg ? Color.clear : palette.background)
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
        .sheet(isPresented: $showCloudDriveImport) {
            CloudDriveImportView()
                .environment(\.themePalette, palette)
                .environmentObject(importService)
                .environmentObject(libraryService)
        }
        .sheet(isPresented: $showWebDAVImport) {
            WebDAVAccountListView()
                .environment(\.themePalette, palette)
                .environmentObject(importService)
                .environmentObject(libraryService)
        }
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
