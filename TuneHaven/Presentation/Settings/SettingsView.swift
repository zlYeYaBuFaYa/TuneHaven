import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

struct SettingsView: View {
    @EnvironmentObject private var themeManager: ThemeManager
    @EnvironmentObject private var importService: ImportService
    @EnvironmentObject private var libraryService: MusicLibraryService
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
    @State private var activeSheet: SettingsSheet?

    enum SettingsSheet: Identifiable {
        case wifiTransfer, appleMusicImport, cloudDriveImport, webDAVImport
        var id: Self { self }
    }

    private var hasCustomBg: Bool {
        themeManager.currentStyle.hasCustomBackground
    }

    private var listRowBg: Color {
        hasCustomBg ? palette.surface.opacity(0.75) : palette.surface
    }

    var body: some View {
        List {
            SettingsImportSection(
                isExpanded: $expandedImport,
                showDocumentPicker: $showDocumentPicker,
                activeSheet: $activeSheet
            )

            SettingsAppearanceSection(
                isExpanded: $expandedAppearance
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
            allowedContentTypes: UTType.allSupportedAudio,
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                Task {
                    _ = await importService.importFromFiles(urls: urls) { _ in }
                    await libraryService.loadSongs()
                }
            case .failure(let error):
                AppLogger.shared.error("[Settings] fileImporter failure: \(error.localizedDescription)")
            }
        }
        .sheet(item: $activeSheet) { sheet in
            Group {
                switch sheet {
                case .wifiTransfer:
                    WiFiTransferView()
                case .appleMusicImport:
                    AppleMusicImportView()
                case .cloudDriveImport:
                    CloudDriveImportView()
                case .webDAVImport:
                    WebDAVAccountListView()
                }
            }
            .environment(\.themePalette, palette)
            .environmentObject(importService)
            .environmentObject(libraryService)
        }
    }

    // MARK: - Helpers

    private func calculateCacheSize() async {
        let bytes = await libraryService.imageCache.cacheSizeAsync()
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

