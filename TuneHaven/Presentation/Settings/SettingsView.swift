import SwiftUI
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
    @AppStorage(AppStorageKey.autoMatchLyrics)       private var autoMatchLyrics: Bool = true
    @AppStorage(AppStorageKey.lyricsPreferSimplified) private var lyricsPreferSimplified: Bool = true

    @State private var currentCacheSize: String = "计算中..."
    @State private var showClearHistoryConfirm = false
    @State private var notificationPermissionStatus: UNAuthorizationStatus = .notDetermined

    #if DEBUG
    @State private var expandedSubscription = DebugLaunchRoute.raw == "settings.open"
    #else
    @State private var expandedSubscription = false
    #endif
    #if DEBUG
    @State private var expandedImport = DebugLaunchRoute.raw == "settings.open"
    #else
    @State private var expandedImport = false
    #endif
    @State private var expandedShare = false
    @State private var expandedBackup = false
    #if DEBUG
    @State private var expandedAppearance = DebugLaunchRoute.raw == "settings.open2"
    #else
    @State private var expandedAppearance = false
    #endif
    #if DEBUG
    @State private var expandedPlayback = DebugLaunchRoute.raw == "settings.open2"
    #else
    @State private var expandedPlayback = false
    #endif
    @State private var expandedStorage = false
    @State private var expandedAbout = false

    @State private var activeSheet: SettingsSheet?

    enum SettingsSheet: Identifiable {
        case shareSend, shareReceive
        var id: Self { self }
    }

    private var hasCustomBg: Bool {
        themeManager.currentStyle.hasCustomBackground
    }

    private var listRowBg: Color {
        hasCustomBg ? palette.surface.opacity(0.72) : palette.surface
    }

    var body: some View {
        List {
            SettingsSubscriptionSection(isExpanded: $expandedSubscription)

            SettingsImportSection(isExpanded: $expandedImport)

            SettingsShareSection(
                isExpanded: $expandedShare,
                activeSheet: $activeSheet
            )

            SettingsBackupSection(isExpanded: $expandedBackup)

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
                currentCacheSize: $currentCacheSize,
                showClearHistoryConfirm: $showClearHistoryConfirm
            )

            SettingsAboutSection(isExpanded: $expandedAbout)
        }
        .environment(\.settingsListRowBg, listRowBg)
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
        .scrollContentBackground(.hidden)
        .background(hasCustomBg ? Color.clear : palette.background)
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.large)
        .themeNavigationBarSurface()
        .task {
            await calculateCacheSize()
            await checkNotificationPermission()
            #if DEBUG
            if DebugLaunchRoute.raw == "share.send" { activeSheet = .shareSend }
            if DebugLaunchRoute.raw == "share.receive" { activeSheet = .shareReceive }
            #endif
        }
        .sheet(item: $activeSheet) { sheet in
            Group {
                switch sheet {
                case .shareSend:
                    ShareSendView()
                case .shareReceive:
                    ShareReceiveView()
                }
            }
            .sheetBackground()
            .environment(\.themePalette, palette)
            .environmentObject(importService)
            .environmentObject(libraryService)
        }
    }

    // MARK: - Helpers

    private func calculateCacheSize() async {
        currentCacheSize = await libraryService.imageCache.formattedCacheSize()
    }

    private func checkNotificationPermission() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationPermissionStatus = settings.authorizationStatus
    }
}

