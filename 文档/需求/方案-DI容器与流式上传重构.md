# 方案：DI 容器与流式上传重构

> 创建日期：2026-03-22 | 状态：Review 通过（4 轮，待用户确认） | 需求数：2

---

## 需求 1：DI 容器架构重构（合并 Review #30 + #27）

### 1.1 需求概述

将 `TuneHavenApp` 中 10 个 `@StateObject` 和 2 个散落的单例（`PlaybackService.shared`、`AudioEngine.shared`）以及 Presentation 层 8 处直接使用的 `LyricsService.shared`，统一收敛到 DI 容器中。降低根视图重算频率，消除单例直接访问，为后续 Clean Architecture 全面重构铺路。

**当前问题：**
- `TuneHavenApp` 持有 10 个 `@StateObject`，任一 Service 的 `@Published` 变化都触发根视图 body 重算
- `LyricsService.shared` 在 `PlayerView`（3 处）、`SongInfoEditView`（2 处）、`LyricsSearchView`（3 处）被直接访问，绕过 DI 链路
- `PlaybackService.shared` 和 `AudioEngine.shared` 作为全局单例使用，不利于测试和解耦

**验收标准：**
1. `TuneHavenApp` 的 `@StateObject` 数量降至 ≤3 个
2. Presentation 层零处直接使用 `LyricsService.shared`
3. 所有 Service 通过 DI 容器创建和管理，可通过 `@EnvironmentObject` 或 `@Environment` 访问
4. 现有功能不受影响，所有页面正常工作

### 1.2 现状分析

#### 当前 TuneHavenApp 结构

```swift
// 10 个 @StateObject
@StateObject private var themeManager = ThemeManager()
@StateObject private var libraryService = MusicLibraryService()
@StateObject private var playlistService = PlaylistService()
@StateObject private var importService = ImportService()
@StateObject private var searchService = SearchService()
@StateObject private var router = AppRouter()
@StateObject private var snackbar = SnackbarState()
@StateObject private var wallpaperManager = WallpaperManager()
@StateObject private var groupService = PlaylistGroupService()
@StateObject private var webDAVService = WebDAVService()

// 2 个单例
private let playbackService = PlaybackService.shared
// AudioEngine.shared 在 .environmentObject() 中直接引用
```

12 个 `.environmentObject()` 注入到 `RootTabView`，子视图分别通过 `@EnvironmentObject` 获取。

#### LyricsService.shared 使用分布

| 文件 | 调用次数 | 方法 |
|------|----------|------|
| `PlayerView.swift` | 3 | `loadLyrics`、`importLyricsFile`、`deleteLyrics` |
| `SongInfoEditView.swift` | 2 | `importLyricsFile`、`deleteLyrics` |
| `LyricsSearchView.swift` | 3 | `saveLyrics`、`searchOnline` |

#### Service 依赖关系图

```
TuneHavenApp
├── ThemeManager           (独立，UI 状态)
├── WallpaperManager       (独立，UI 状态)
├── AppRouter              (独立，导航状态)
├── SnackbarState          (独立，UI 状态)
├── MusicLibraryService    → SongRepository
├── PlaylistService        → PlaylistRepository, SongRepository
├── PlaylistGroupService   → PlaylistGroupRepository
├── ImportService          → SongRepository, FileStorageService
├── SearchService          → SearchHistoryRepository
├── WebDAVService          → WebDAVAccountStore, WebDAVClient
├── PlaybackService.shared → PlaylistRepository, SongRepository, PlayQueueService, MusicLibraryService, AudioEngine
└── AudioEngine.shared     (独立，音频引擎)
    LyricsService.shared   → SongRepository, LRCLibAPIClient (散落在 Presentation 层)
```

#### 需修改的文件清单

| 文件 | 改动类型 |
|------|----------|
| `TuneHaven/App/TuneHavenApp.swift` | 重构：用 DI 容器替代 10 个 @StateObject |
| `TuneHaven/App/AppDIContainer.swift` | **新增**：DI 容器 |
| `TuneHaven/Domain/Services/LyricsService.swift` | 修改：移除 `static let shared` |
| `TuneHaven/Domain/Services/PlaybackService.swift` | 修改：移除 `static let shared`，改为外部创建 |
| `TuneHaven/Core/Audio/AudioEngine.swift` | **不改动**：保留 `static let shared`（渐进策略） |
| `TuneHaven/Presentation/Player/PlayerView.swift` | 修改：替换 `LyricsService.shared` 为 @EnvironmentObject |
| `TuneHaven/Presentation/Settings/SongInfoEditView.swift` | 修改：替换 `LyricsService.shared` 为 @EnvironmentObject |
| `TuneHaven/Presentation/Player/LyricsSearchView.swift` | 修改：替换 `LyricsService.shared` 为 @EnvironmentObject |
| `TuneHaven/Presentation/Root/RootTabView.swift` | 微调：@EnvironmentObject 声明可能变化 |
| `TuneHavenTests/LyricsServiceTests.swift` | 修改：`LyricsService.shared` → `LyricsService()` |

### 1.3 技术方案

#### 1.3.1 整体设计

采用 **服务容器模式**（Service Container）：引入一个 `@MainActor` 的 `ObservableObject` 类 `AppDIContainer`，统一持有所有 Service 实例。`TuneHavenApp` 只创建一个 `@StateObject` 容器，通过 `.environmentObject()` 将各 Service 分别注入。

**分层策略：**

```
AppDIContainer (容器本身不发布属性变化，仅作为持有者)
├── UIState 组（需要驱动视图更新 → 保留独立 @StateObject 或 @EnvironmentObject）
│   ├── ThemeManager
│   ├── WallpaperManager
│   ├── AppRouter
│   └── SnackbarState
│
├── Service 组（业务服务 → 通过容器持有，各自独立注入）
│   ├── MusicLibraryService
│   ├── PlaylistService
│   ├── PlaylistGroupService
│   ├── ImportService
│   ├── SearchService
│   ├── WebDAVService
│   ├── PlaybackService
│   └── LyricsService   ← 新增注入
│
└── Infrastructure 组
    └── AudioEngine
```

**关键设计决策：**

为什么不把所有 Service 放进一个 `ObservableObject` 的 `@Published` 属性？因为 SwiftUI 的 `ObservableObject` 任何 `@Published` 变化都触发订阅者更新。如果容器本身是 `ObservableObject` 且持有多个 `@Published` 的 Service，等于回到了同样的问题。

因此，DI 容器**仅作为实例工厂和持有者**，不声明任何 `@Published` 属性。各 Service 仍然作为独立的 `@EnvironmentObject` 注入。容器的价值在于：
1. **集中创建**：所有 Service 的创建和依赖关系在一个地方管理
2. **减少 @StateObject**：`TuneHavenApp` 从 10 个 `@StateObject` 减至 1 个
3. **统一生命周期**：Service 的生命周期由容器管理，非 `static let shared`
4. **可测试**：测试时可创建配有 Mock Service 的容器

#### 1.3.2 详细实现

##### 新增：AppDIContainer

```swift
// TuneHaven/App/AppDIContainer.swift

@MainActor
final class AppDIContainer: ObservableObject {
    // MARK: - UI State
    let themeManager: ThemeManager
    let wallpaperManager: WallpaperManager
    let router: AppRouter
    let snackbar: SnackbarState

    // MARK: - Infrastructure
    let audioEngine: AudioEngine

    // MARK: - Services
    let libraryService: MusicLibraryService
    let playlistService: PlaylistService
    let groupService: PlaylistGroupService
    let importService: ImportService
    let searchService: SearchService
    let webDAVService: WebDAVService
    let playbackService: PlaybackService
    let lyricsService: LyricsService

    init() {
        // 1. Infrastructure — AudioEngine 保留 shared（private init 未改）
        self.audioEngine = AudioEngine.shared

        // 2. UI State
        self.themeManager = ThemeManager()
        self.wallpaperManager = WallpaperManager()
        self.router = AppRouter()
        self.snackbar = SnackbarState()

        // 3. Services（按依赖顺序创建）
        self.libraryService = MusicLibraryService()
        self.playlistService = PlaylistService()
        self.groupService = PlaylistGroupService()
        self.importService = ImportService()
        self.searchService = SearchService()
        self.webDAVService = WebDAVService()
        self.lyricsService = LyricsService()

        // 4. PlaybackService — private init 改为 internal init，使用默认参数
        self.playbackService = PlaybackService()
    }
}
```

##### 重构：TuneHavenApp

```swift
// TuneHaven/App/TuneHavenApp.swift

@main
struct TuneHavenApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var container = AppDIContainer()

    @Environment(\.scenePhase) private var scenePhase
    @State private var isReady = false
    @State private var initError: String?
    @State private var pendingImportURLs: [URL] = []
    @State private var openInHandler: OpenInImportHandler?

    var body: some Scene {
        WindowGroup {
            ZStack {
                container.themeManager.palette.background
                    .ignoresSafeArea()

                if isReady {
                    RootTabView()
                        .environmentObject(container.themeManager)
                        .environmentObject(container.libraryService)
                        .environmentObject(container.playlistService)
                        .environmentObject(container.importService)
                        .environmentObject(container.searchService)
                        .environmentObject(container.router)
                        .environmentObject(container.snackbar)
                        .environmentObject(container.wallpaperManager)
                        .environmentObject(container.groupService)
                        .environmentObject(container.playbackService)
                        .environmentObject(container.audioEngine)
                        .environmentObject(container.webDAVService)
                        .environmentObject(container.lyricsService)
                        .environment(\.themePalette, container.themeManager.palette)
                        .snackbar(container.snackbar)
                } else if let error = initError {
                    // ... 保持不变
                } else {
                    ProgressView("加载中...")
                        .progressViewStyle(.circular)
                }
            }
            .preferredColorScheme(container.themeManager.colorScheme)
            .task { await initialize() }
            // ... 其余保持不变
        }
    }
}
```

**优势**：`TuneHavenApp` 仅一个 `@StateObject`。由于 `AppDIContainer` 的属性都是 `let`（无 `@Published`），容器自身不会触发视图重算，各 Service 的 `@Published` 变化只影响订阅了该 Service 的具体子视图。

##### 重构：TuneHavenApp 内部方法

`TuneHavenApp` 中所有直接引用旧 Service 属性的方法体，需统一改为 `container.xxx`：

```swift
private func initialize() async {
    do {
        AppLogger.shared.info("[App] initialize start")
        MigrationManager.shared.runVersionUpgradeTasks()
        try await CoreDataStack.shared.load()
        await MigrationManager.shared.runPostLoadMigrations()
        SandboxPathManager.createAllDirectories()
        WiFiTransferServer.cleanupTempFiles()  // 新增：清理残留临时文件
        try await container.playlistService.initializeSystemPlaylists()
        await container.libraryService.loadSongs()
        await container.libraryService.cleanupOnLaunch()
        OpenInImportHandler.cleanupInbox()
        container.playbackService.checkSleepTimerOnForeground()
        isReady = true
        AppLogger.shared.info("[App] initialize done — isReady=true")

        if !pendingImportURLs.isEmpty {
            let urls = pendingImportURLs
            pendingImportURLs.removeAll()
            ensureOpenInHandler().enqueue(urls: urls)
        }

        container.themeManager.scheduleWindowRefresh(delay: 0.15, fullApply: true)
    } catch {
        initError = error.localizedDescription
        AppLogger.shared.error("[App] initialize FAILED: \(error)")
    }
}

private func ensureOpenInHandler() -> OpenInImportHandler {
    if let handler = openInHandler { return handler }
    let handler = OpenInImportHandler(
        importService: container.importService,
        libraryService: container.libraryService,
        snackbar: container.snackbar
    )
    openInHandler = handler
    return handler
}
```

`body` 中 `onChange(of: scenePhase)` 和 `onAppear` 中的引用也需同步修改：

```swift
.onAppear {
    AppLogger.shared.debug("[App] onAppear — applying window theme")
    container.themeManager.scheduleWindowRefresh(delay: 0.1, fullApply: true)
}
.onChange(of: scenePhase) { _, phase in
    AppLogger.shared.debug("[App] scenePhase → \(phase)")
    switch phase {
    case .active:
        container.playbackService.checkSleepTimerOnForeground()
    case .background:
        AudioSessionManager.shared.ensureActive()
    default:
        break
    }
}
```

共 9 处属性引用需改为 `container.xxx`（详见方案 Review 第 3 轮）。

##### 重构：PlaybackService — 移除 shared 单例

经验证 `PlaybackService.shared` 仅在 `TuneHavenApp.swift` 第 19 行被引用，无其他文件使用。

```swift
// 移除: static let shared = PlaybackService()
// 将 private init 改为 internal init，保持现有默认参数不变
@MainActor
final class PlaybackService: ObservableObject {
    private let log = AppLogger.shared

    // ... 属性不变 ...

    init(playlistRepo: PlaylistRepository = CoreDataPlaylistRepository(),
         songRepo: SongRepository = CoreDataSongRepository()) {
        self.engine = AudioEngine.shared  // AudioEngine 保持 shared（private init 未改）
        self.queueService = PlayQueueService()
        self.libraryService = MusicLibraryService()
        self.playlistRepo = playlistRepo
        self.songRepo = songRepo
        setupBindings()
        sleepTimer.configure { [weak self] in
            AudioEngine.shared.pause()
            self?.isPlaying = false
        }
        Task { await restoreLastPlayedSong() }
    }
}
```

##### 重构：LyricsService — 移除 shared，添加 ObservableObject，注入

当前 `LyricsService` 未遵守 `ObservableObject`，无法作为 `@EnvironmentObject` 注入。需添加协议遵守（虽无 `@Published` 属性，但满足类型约束即可）。

```swift
@MainActor
final class LyricsService: ObservableObject {  // 添加 ObservableObject 遵守
    // 移除: static let shared = LyricsService()
    private let log = AppLogger.shared
    private let repo: SongRepository
    private let api: LRCLibAPIClientProtocol

    // init 保持不变，已支持协议注入
    init(repo: SongRepository = CoreDataSongRepository(),
         api: LRCLibAPIClientProtocol = LRCLibAPIClient.shared) {
        self.repo = repo
        self.api = api
    }
    // ... 方法不变 ...
}
```

##### 重构：Presentation 层 — 替换 LyricsService.shared

**PlayerView.swift**（3 处）：
```swift
// 新增
@EnvironmentObject private var lyricsService: LyricsService

// 替换所有 LyricsService.shared → lyricsService
// 例如：
lyricsData = await lyricsService.loadLyrics(for: song)
try? await lyricsService.importLyricsFile(url: url, for: song)
try? await lyricsService.deleteLyrics(for: song)
```

**SongInfoEditView.swift**（2 处）、**LyricsSearchView.swift**（3 处）：同理添加 `@EnvironmentObject` 并替换所有直接引用。

##### AudioEngine — 渐进策略

经验证 `AudioEngine.shared` 在以下位置被引用：
- `PlaybackService.swift`：`private let engine = AudioEngine.shared`
- `TuneHavenApp.swift`：`.environmentObject(AudioEngine.shared)`

`AudioEngine` 的 init 为 `private`，本次**不改动 AudioEngine 本身**，采用渐进策略：
- 保留 `AudioEngine.shared` 的 `static let` 和 `private init`
- 容器创建时 `self.audioEngine = AudioEngine.shared`（引用同一实例）
- 后续迭代中可将 `private init` 改为 `internal init`，由容器独占创建

#### 1.3.3 备选方案

| 方案 | 优点 | 缺点 |
|------|------|------|
| A. 自定义 Environment Key 注入（每个 Service 一个 Key） | 类型安全、编译期检查 | 改动量大，每个 Service 需定义 EnvironmentKey + extension |
| **B. DI 容器 + environmentObject（推荐）** | 改动最小、渐进兼容、保留现有 @EnvironmentObject 模式 | 仍依赖运行时查找 |
| C. Swift 6 @Observable + @Entry macro | 最现代化、自动粒度更新 | 需 iOS 17+，项目要求 iOS 16.1+，不可行 |

推荐方案 B：与现有代码模式一致，改动量最小，且不受 iOS 版本限制。

### 1.4 影响范围

| 模块 | 影响程度 | 说明 |
|------|----------|------|
| App 层 | 高 | TuneHavenApp 重构，新增 AppDIContainer |
| Domain/Services | 中 | LyricsService 移除 shared，PlaybackService 调整 init |
| Presentation | 中 | 3 个文件替换 LyricsService.shared，新增 @EnvironmentObject |
| Core | 低 | AudioEngine 保持 shared 兼容 |
| Data | 无 | 不涉及 |

- 向后兼容性：不涉及数据库变更，不影响用户数据
- 所有现有 `@EnvironmentObject` 访问模式保持不变

### 1.5 测试要点

| 场景 | 验证内容 |
|------|----------|
| App 启动 | 容器正确创建所有 Service，初始化流程不变 |
| 页面导航 | 所有页面能正常获取 @EnvironmentObject |
| 歌词加载 | PlayerView 通过注入的 LyricsService 加载歌词 |
| 歌词搜索 | LyricsSearchView 在线搜索、保存歌词 |
| 歌词导入/删除 | SongInfoEditView 导入和删除歌词 |
| 播放功能 | PlaybackService 通过容器创建后播放正常 |
| 主题切换 | ThemeManager 通过容器注入后主题切换正常 |
| 单元测试 | LyricsService 可注入 Mock Repository 和 Mock API 进行测试 |

### 1.6 风险评估

| 风险 | 概率 | 影响 | 应对 |
|------|------|------|------|
| PlaybackService.shared 被其他未发现的文件引用 | 低（已验证仅 1 处） | 编译错误 | 编码阶段全局搜索再次确认 |
| Service 创建顺序依赖导致初始化失败 | 低 | 启动崩溃 | DI 容器 init 中严格按依赖顺序创建 |
| @EnvironmentObject 遗漏注入导致运行时崩溃 | 中 | 页面崩溃 | 编码后逐页面测试；后续可考虑 Environment Key 替代 |
| AudioEngine 渐进策略与未来全面 DI 冲突 | 低 | 需二次重构 | 本次保留 shared 兼容，下一轮重构统一移除 |

---

## 需求 2：WiFiTransferServer 流式上传重构（Review #12）

### 2.1 需求概述

改造 `WiFiTransferServer` 的 HTTP 请求接收机制，将当前的"全量内存累积"模式改为"Header 内存 + Body 流式写入临时文件"模式。解决大文件（如 500MB FLAC）上传时 OOM 的问题。

**当前问题：**
- `receiveHTTPRequest` 使用 `var accumulatedData = Data()` 累积所有接收到的数据
- 对于 `POST /upload`，整个 HTTP 请求（Header + Body）全量存在内存中
- 500MB 文件上传 = 500MB+ 内存占用，iOS 设备极易触发 OOM

**验收标准：**
1. 上传 500MB 文件时，内存峰值增量 ≤ 10MB
2. 上传功能行为不变：支持 multipart/form-data、密码验证、错误提示
3. 传输进度信息可用（`WiFiTransferProgress` 能正确更新）
4. GET 请求（页面/状态/心跳）和 POST /auth 仍正常工作

### 2.2 现状分析

#### 当前数据流

```
NWConnection.receive (1MB/次)
    → append 到 accumulatedData (Data)
    → 循环直到 isCompleteHTTPRequest 为 true
    → 整个 accumulatedData 传入 handleHTTPData
    → handleUpload 再次从 Data 中 extractBodyData
    → parseMultipart 从 Body 中切分文件数据
    → Data(fileData).write(to: destURL)
```

全过程中，文件数据在内存中存在 **至少 2 份拷贝**（accumulatedData + fileData slice 转 Data）。

#### 需修改的文件清单

| 文件 | 改动类型 |
|------|----------|
| `TuneHaven/Core/Network/WiFiTransferServer.swift` | 重构：流式上传逻辑 |

### 2.3 技术方案

#### 2.3.1 整体设计

采用 **两阶段解析** 策略：

```
阶段 1（内存）：接收并解析 HTTP Header
    → 判断请求类型（GET/POST）
    → 提取 Content-Length、Content-Type、Boundary
    → 对于非上传请求（GET、POST /auth），沿用现有逻辑

阶段 2（流式）：仅对 POST /upload，Body 数据流式写入临时文件
    → 创建临时文件 FileHandle
    → 每次 NWConnection.receive 的数据直接 write 到 FileHandle
    → 计数已接收字节 vs Content-Length，判断完成
    → 完成后从临时文件中解析 multipart boundary，提取文件
```

#### 2.3.2 详细实现

##### 核心数据结构

使用 `class`（引用类型），因为 NWConnection.receive 的 `@escaping` 闭包需要持有并修改 context。添加 `@unchecked Sendable` 以满足 Swift 6 严格并发（实际读写均在 `@MainActor` 上执行）：

```swift
private final class StreamingUploadContext: @unchecked Sendable {
    let contentLength: Int
    let boundary: String
    let tempFileURL: URL
    let fileHandle: FileHandle
    var bytesReceived: Int = 0
    let startTime: Date = Date()

    init(contentLength: Int, boundary: String, tempFileURL: URL, fileHandle: FileHandle) {
        self.contentLength = contentLength
        self.boundary = boundary
        self.tempFileURL = tempFileURL
        self.fileHandle = fileHandle
    }
}
```

##### 重构：receiveHTTPRequest → 两阶段

```swift
private func receiveHTTPRequest(connection: NWConnection, ip: String) {
    var headerData = Data()
    var uploadContext: StreamingUploadContext?

    func headerReadLoop() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty { headerData.append(data) }
            Task { @MainActor [weak self] in
                guard let self else { return }
                if isComplete || error != nil {
                    if !headerData.isEmpty {
                        self.handleSmallRequest(headerData, connection: connection, ip: ip)
                    }
                    self.connectionState = .idle
                    return
                }

                let headerEndMarker = "\r\n\r\n".data(using: .utf8)!
                if let headerEndRange = headerData.range(of: headerEndMarker) {
                    let headers = headerData[headerData.startIndex..<headerEndRange.upperBound]
                    let overflow = headerData[headerEndRange.upperBound...]

                    if self.isUploadRequest(headers),
                       let ctx = self.beginStreamingUpload(headers: headers) {
                        if !overflow.isEmpty {
                            ctx.fileHandle.write(Data(overflow))
                            ctx.bytesReceived = overflow.count
                            self.updateTransferProgress(ctx)
                        }
                        uploadContext = ctx
                        bodyReadLoop(context: ctx, connection: connection)
                    } else {
                        // 非上传请求：继续用内存模式读取少量 Body
                        self.finishSmallRequest(headerData: headerData, connection: connection, ip: ip)
                    }
                } else if headerData.count > 16_384 {
                    // Header 超过 16KB 异常
                    self.sendJSON(connection: connection, status: 400, body: #"{"error":"请求头过大"}"#)
                } else {
                    headerReadLoop()
                }
            }
        }
    }

    func bodyReadLoop(context: StreamingUploadContext, connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1_048_576) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let data, !data.isEmpty {
                    context.fileHandle.write(data)
                    context.bytesReceived += data.count
                    self.updateTransferProgress(context)
                }
                if isComplete || error != nil || context.bytesReceived >= context.contentLength {
                    context.fileHandle.closeFile()
                    self.processUploadedTempFile(context: context, connection: connection)
                } else {
                    bodyReadLoop(context: context, connection: connection)
                }
            }
        }
    }

    headerReadLoop()
}
```

##### 辅助方法

```swift
private func isUploadRequest(_ headerData: Data) -> Bool {
    guard let str = String(data: headerData, encoding: .utf8) else { return false }
    return str.hasPrefix("POST") && str.contains("/upload")
}

private func beginStreamingUpload(headers: Data) -> StreamingUploadContext? {
    guard let contentLengthStr = extractHeader(from: headers, key: "Content-Length"),
          let contentLength = Int(contentLengthStr),
          let contentType = extractHeader(from: headers, key: "Content-Type"),
          let boundary = extractBoundary(from: contentType) else { return nil }

    let tempURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("wifi_upload_\(UUID().uuidString).tmp")
    FileManager.default.createFile(atPath: tempURL.path, contents: nil)
    guard let handle = FileHandle(forWritingAtPath: tempURL.path) else { return nil }

    connectionState = .transferring(ip: "")
    return StreamingUploadContext(
        contentLength: contentLength,
        boundary: boundary,
        tempFileURL: tempURL,
        fileHandle: handle)
}

private func processUploadedTempFile(context: StreamingUploadContext, connection: NWConnection) {
    defer {
        try? FileManager.default.removeItem(at: context.tempFileURL)
        transferProgress = nil
    }

    guard let bodyData = try? Data(contentsOf: context.tempFileURL, options: .mappedIfSafe) else {
        sendJSON(connection: connection, status: 500, body: #"{"error":"临时文件读取失败"}"#)
        connectionState = .idle
        return
    }
    parseMultipart(bodyData: bodyData, boundary: context.boundary, connection: connection)
}
```

> **关键优化**：`Data(contentsOf:options:.mappedIfSafe)` 使用内存映射（mmap），操作系统按需分页加载，不会一次性将 500MB 全部载入物理内存。这比原来的 `Data.append` 累积方式内存效率高一个数量级。

**附加优化**：`parseMultipart` 中现有的 `Data(fileData).write(to: destURL)` 会创建物理内存拷贝，应一并改为 `try fileData.write(to: destURL)`，直接从 mmap 映射写入目标文件，避免内存峰值。

##### 进度更新

```swift
private func updateTransferProgress(_ context: StreamingUploadContext) {
    let elapsed = Date().timeIntervalSince(context.startTime)
    let speed = elapsed > 0 ? Double(context.bytesReceived) / elapsed : 0
    transferProgress = WiFiTransferProgress(
        fileName: "",
        bytesReceived: Int64(context.bytesReceived),
        totalBytes: Int64(context.contentLength),
        speed: speed
    )
}
```

##### 临时文件启动清理

在 `WiFiTransferServer` 中添加静态清理方法，由 `TuneHavenApp.initialize()` 调用：

```swift
// WiFiTransferServer 中添加
static func cleanupTempFiles() {
    let tmpDir = FileManager.default.temporaryDirectory
    let contents = (try? FileManager.default.contentsOfDirectory(
        at: tmpDir, includingPropertiesForKeys: nil)) ?? []
    for url in contents where url.lastPathComponent.hasPrefix("wifi_upload_") {
        try? FileManager.default.removeItem(at: url)
    }
}

// TuneHavenApp.initialize() 中添加（在 SandboxPathManager.createAllDirectories() 之后）
WiFiTransferServer.cleanupTempFiles()
```

##### 非上传请求兼容

GET 请求和 POST /auth 的数据量很小（< 1KB），继续使用内存模式：

```swift
private func handleSmallRequest(_ data: Data, connection: NWConnection, ip: String) {
    handleHTTPData(data, connection: connection, ip: ip)
}

private func finishSmallRequest(headerData: Data, connection: NWConnection, ip: String) {
    // 对于小请求，继续累积少量 Body 后处理
    // 复用现有 isCompleteHTTPRequest 逻辑
    if isCompleteHTTPRequest(headerData) {
        handleHTTPData(headerData, connection: connection, ip: ip)
    } else {
        // 继续读取少量 Body（POST /auth 等）
        receiveSmallBody(existingData: headerData, connection: connection, ip: ip)
    }
}

private func receiveSmallBody(existingData: Data, connection: NWConnection, ip: String) {
    var data = existingData
    connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] chunk, _, isComplete, error in
        guard let self else { return }
        if let chunk { data.append(chunk) }
        Task { @MainActor [weak self] in
            guard let self else { return }
            if isComplete || error != nil || self.isCompleteHTTPRequest(data) {
                self.handleHTTPData(data, connection: connection, ip: ip)
                if isComplete || error != nil { self.connectionState = .idle }
            } else if data.count > 1_048_576 {
                self.sendJSON(connection: connection, status: 413, body: #"{"error":"请求体过大"}"#)
            } else {
                self.receiveSmallBody(existingData: data, connection: connection, ip: ip)
            }
        }
    }
}
```

#### 2.3.3 备选方案

| 方案 | 优点 | 缺点 |
|------|------|------|
| A. 仅增大 `maximumLength` 减少 append 次数 | 改动最小 | 未解决根本问题，内存仍全量 |
| B. 在 parseMultipart 中分块处理（不改 receive） | 不改接收逻辑 | accumulatedData 仍在内存，治标不治本 |
| **C. Header 内存 + Body 流式写入临时文件（推荐）** | 内存峰值可控、支持进度回调 | 改动较大，需临时文件管理 |
| D. 重写为完整的 HTTP 流式 multipart 解析器 | 最优内存表现 | 实现复杂度极高，multipart 边界对齐困难 |

推荐方案 C：平衡了内存效率和实现复杂度。mmap 读取进一步降低了解析阶段的内存开销。

### 2.4 影响范围

| 模块 | 影响程度 | 说明 |
|------|----------|------|
| Core/Network | 高 | WiFiTransferServer 接收逻辑重构 |
| Presentation/Import | 低 | WiFiTransferView 无需改动，依赖 @Published 属性不变 |
| 其他模块 | 无 | 不涉及 |

- `WiFiTransferServer` 的公开接口不变（`start`、`stop`、`onFileReceived`、`@Published` 属性）
- `WiFiTransferView` 无需改动
- 不涉及数据库变更

### 2.5 测试要点

| 场景 | 验证内容 |
|------|----------|
| 小文件上传（< 1MB） | 功能正常，文件完整 |
| 大文件上传（≥ 100MB） | 内存峰值 ≤ 10MB，文件完整 |
| 多文件顺序上传 | 临时文件正确清理 |
| 上传中连接断开 | 临时文件清理，状态回 idle |
| GET 页面 / 状态 / 心跳 | 功能不受影响 |
| POST /auth 密码验证 | 功能不受影响 |
| 密码保护 + 上传 | 鉴权后上传正常 |
| 传输进度 | `transferProgress` 实时更新 |
| 超大 Header（> 16KB 异常） | 返回 400 错误 |

### 2.6 风险评估

| 风险 | 概率 | 影响 | 应对 |
|------|------|------|------|
| mmap 在极端情况下回退为全量加载 | 低 | 内存短暂升高 | `.mappedIfSafe` 已处理，退化为普通加载也比双份拷贝好 |
| 临时文件未清理（崩溃场景） | 中 | 磁盘泄漏 | App 启动时扫描 `wifi_upload_*.tmp` 并清理 |
| StreamingUploadContext 闭包捕获 | 无（已用 class） | — | 已采用 class 引用语义，闭包可直接持有并修改 |
| multipart boundary 跨 chunk 被分割 | 无 | — | Body 已完整写入临时文件后再解析，不存在跨 chunk 问题 |
