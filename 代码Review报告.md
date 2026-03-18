# 代码 Review 报告

## 文档信息

| 项目 | 内容 |
|------|------|
| 项目名称 | Music Demo — iOS 音乐播放器 |
| 审查日期 | 2026-03-18 |
| 审查范围 | 94 个 Swift 文件，约 11.8 万行代码 |
| 审查模块 | Core/Audio、Domain/Services、App/Theme、Presentation、Data/Repositories |
| 提交历史 | 10 次提交（Initial Commit → feat/theme-refactor） |

---

## 问题统计

| 级别 | 数量 | 说明 |
|------|------|------|
| **P0 致命** | 3 | 会直接导致数据丢失或核心功能异常 |
| **P1 严重** | 16 | 线程安全、逻辑错误、运行时崩溃风险 |
| **P2 中等** | 21 | 性能、错误处理、UI/UX、数据一致性 |
| **P3 建议** | 11 | 代码质量、架构改进、可维护性 |
| **合计** | **51** | |

---

## P0 致命问题（必须修复）

### #1 undoDelete 文件恢复路径参数错误 — 撤销删除后文件丢失

- **文件**: `Data/Repositories/CoreDataSongRepository.swift` L91-112
- **分类**: 数据一致性
- **问题**: `softDelete` 方法将 `moveToPendingDelete` 的返回值（临时路径）存入 `UndoToken.tempFilePaths`，但原始相对路径 `fileRelativePath` 在构造 token 时完全丢失。`undoDelete` 用同一个 `path` 同时作为 `fileName` 和 `originalRelativePath` 传入 `restoreFromPendingDelete`，会将文件恢复到错误位置，导致歌曲文件丢失且无法播放。
- **建议修复**: 将 `UndoToken.tempFilePaths` 改为 `[(tempPath: String, originalRelativePath: String)]` 结构，`softDelete` 中同时保存临时路径和原始路径。

---

### #2 performBackground 异常不回滚 — 脏数据残留

- **文件**: `Core/Persistence/CoreDataStack.swift` L44-58
- **分类**: CoreData / 数据一致性
- **问题**: 当 `block()` 执行到一半抛出异常时，`backgroundContext` 上已经产生的 unsaved changes 不会被回滚。由于 `backgroundContext` 是单例 lazy var，这些脏数据会残留在上下文中，污染后续所有 `performBackground` 调用。例如：批量删除操作做到一半失败 → 部分 entity 已被标记删除 → 下一次 save 会意外提交这些残留修改。
- **建议修复**:
```swift
} catch {
    self.backgroundContext.rollback()
    continuation.resume(throwing: error)
}
```

---

### #3 歌单播放只加载单首歌 — 下一首/上一首失效

- **文件**: `Domain/Services/PlaybackService.swift` L237-240
- **分类**: 逻辑错误
- **问题**: 当用户从歌单中点击一首歌播放时，`buildQueue` 只将当前点击的单首歌加入队列，歌单 ID 被 `_ = id` 直接丢弃。用户期望从歌单播放时，整个歌单的歌曲都应进入队列，实现"下一首/上一首"在歌单内切换。
- **建议修复**:
```swift
case .playlist(let id):
    let detail = await playlistService.fetchDetail(playlistId: id)
    songs = detail?.songs ?? [song]
    startIndex = songs.firstIndex(of: song) ?? 0
```

---

## P1 严重问题

### #4 playerItemDidFinish 可能在非主线程修改 @MainActor 状态

- **文件**: `Core/Audio/AudioEngine.swift` L218-223
- **分类**: 线程安全
- **问题**: 该方法通过 `addObserver(self, selector:, name: .AVPlayerItemDidPlayToEndTime, ...)` 注册，未指定 `queue` 参数。通知不保证在主线程发送，但方法直接修改了 `@MainActor` 隔离的 `@Published` 属性。
- **建议修复**: 方法内部包裹 `Task { @MainActor [weak self] in ... }`。

---

### #5 KVO 闭包跨 actor 隔离访问 @Published 属性

- **文件**: `Core/Audio/AudioEngine.swift` L112-130
- **分类**: 线程安全
- **问题**: `NSKeyValueObservation` 的闭包在任意线程执行。虽然内部用了 `DispatchQueue.main.async`，但 Swift 6 编译器不会将 GCD main queue 等同于 `@MainActor`，`self?.state = ...` 是对 `@MainActor` 隔离属性的跨隔离域访问。
- **建议修复**: 将 `DispatchQueue.main.async` 替换为 `Task { @MainActor in ... }`。

---

### #6 通知闭包同步调用 @MainActor 方法

- **文件**: `Core/Audio/AudioEngine.swift` L225-239
- **分类**: 线程安全
- **问题**: `setupNotifications` 中虽指定了 `queue: .main`，但闭包本身并非 `@MainActor` 隔离。`handleInterruption` 和 `handleRouteChange` 是 `@MainActor` 类的隐式 `@MainActor` 方法，从非隔离闭包同步调用违反了 actor 隔离原则。
- **建议修复**: 闭包内包裹 `Task { @MainActor [weak self] in ... }`。

---

### #7 周期时间观察闭包跨 actor 写入属性

- **文件**: `Core/Audio/AudioEngine.swift` L196-207
- **分类**: 线程安全
- **问题**: `addPeriodicTimeObserver` 的闭包虽指定 `queue: .main`，但闭包不是 `@MainActor` 隔离的，Swift 6 strict 模式下会报 actor 隔离错误。
- **建议修复**: 同 #5，替换为 `Task { @MainActor in ... }`。

---

### #8 Remote Command 回调访问 @MainActor 属性

- **文件**: `Core/Audio/NowPlayingManager.swift` L62-65
- **分类**: 线程安全
- **问题**: `MPRemoteCommandCenter` 的 command handler 不保证在主线程执行。`AudioEngine.shared.isPlaying` 是 `@MainActor` 隔离的计算属性，从非主线程访问构成数据竞争。
- **建议修复**: 将 `togglePlayPauseCommand` 的判断逻辑也交给调用方通过闭包注入，或使用 `Task { @MainActor in }` 调度。

---

### #9 收藏操作未持久化到数据库

- **文件**: `Domain/Services/PlaybackService.swift` L141-145
- **分类**: 逻辑错误
- **问题**: `Song` 是值类型(struct)，`toggleCurrentSongFavorite` 只修改了内存中的副本并更新了 `@Published` 属性。收藏操作没有调用 Repository 持久化到 CoreData，刷新/重启后收藏状态丢失。`favoriteDate` 也没有更新。
- **建议修复**: 改为 `async throws`，调用 `libraryService.toggleFavorite(songId:)` 持久化，然后重新从数据库获取最新状态。

---

### #10 封面 UUID 与 Song ID 不一致

- **文件**: `Domain/Services/ImportService.swift` L124, L135
- **分类**: 逻辑错误
- **问题**: 封面图片文件名使用 `UUID()` (A)，但紧接着创建 Song 时又生成了新的 `UUID()` (B)。如果任何代码尝试通过 `song.id` 反推封面路径就会失败。
- **建议修复**: 在方法开头生成一个统一的 `songId`，同时用于封面路径和 Song 初始化。

---

### #11 moveInQueue 未同步更新 currentIndex

- **文件**: `Domain/Services/PlayQueueService.swift` L50-52
- **分类**: 逻辑错误
- **问题**: 当用户拖拽重排播放队列时，`currentIndex` 没有跟随调整。如果当前正在播放的歌曲被移动，`currentIndex` 仍指向旧位置，导致"下一首"功能指向错误的歌曲。
- **建议修复**: 在 move 前记录当前歌曲 ID，move 后重新查找索引。

---

### #12 commitDelete 错误被 try? 吞掉

- **文件**: `Domain/Services/MusicLibraryService.swift` L99-103
- **分类**: 错误处理
- **问题**: `try?` 完全吞掉了 `commitDelete` 的错误。如果真正删除文件/数据库记录失败，不会有任何反馈，数据可能处于不一致状态。同时 `token.songIds.first ?? UUID()` 用作 timer key，多次批量删除可能覆盖前一个 timer。
- **建议修复**: 至少记录错误日志，并使用更可靠的 token 标识。

---

### #13 viewContext.perform 中捕获 @MainActor self

- **文件**: `Domain/Services/SearchService.swift` L58-70
- **分类**: 线程安全
- **问题**: `SearchService` 是 `@MainActor`，`viewContext.perform` 闭包中捕获了 `self`。在 Swift 6 严格并发模型下，`self`（`@MainActor` 隔离）在非隔离的 `perform` 闭包中被访问，会产生数据竞争警告。
- **建议修复**: 由于 `viewContext` 是主线程上下文，且方法已在 `@MainActor`，可以直接执行 fetch 而无需 `perform`。

---

### #14 lazy var backgroundContext 非线程安全

- **文件**: `Core/Persistence/CoreDataStack.swift` L11-15
- **分类**: CoreData / 线程安全
- **问题**: Swift 的 `lazy var` 不是线程安全的。如果多个异步任务同时首次调用 `performBackground`，可能导致 `backgroundContext` 被初始化多次。所有后台操作共享同一个 context 意味着全部串行执行，在大量导入场景下成为性能瓶颈。
- **建议修复**: 使用 `let` + 在 `load()` 中初始化，或在 `performBackground` 中每次创建新的 context。

---

### #15 delete(playlist:) 未清理关联 PlaylistSongEntity

- **文件**: `Data/Repositories/CoreDataPlaylistRepository.swift` L84-92
- **分类**: 数据一致性
- **问题**: 删除 Playlist 时只删除了 `PlaylistEntity`，未删除关联的 `PlaylistSongEntity` 中间表记录。CoreData 模型中没有配置 cascade delete rule，会在数据库中持续积累孤儿记录，长期导致歌曲数量统计错误。
- **建议修复**: 删除 PlaylistEntity 前先 fetch 并删除所有关联的 PlaylistSongEntity。

---

### #16 cleanupPendingDeletes 关联清理在错误的 if-let 分支

- **文件**: `Data/Repositories/CoreDataSongRepository.swift` L160-185
- **分类**: 数据一致性
- **问题**: `PlaylistSongEntity` 的清理逻辑被嵌套在 `if let hash = ..., let path = ...` 分支内。如果某个 SongEntity 的 `fileHash` 或 `fileRelativePath` 为 nil，entity 自身会被删除，但关联的 PlaylistSongEntity 不会被清理，产生孤儿记录。
- **建议修复**: 将 PlaylistSongEntity 的清理提到 `if let` 外面。

---

### #17 PassthroughSubject 在 struct View 中可能被重建

- **文件**: `Presentation/Library/LibraryMainView.swift` L18
- **分类**: 状态管理
- **问题**: `PassthroughSubject` 被声明为 `struct` 的 `private let` 属性。SwiftUI View 是值类型，body 重新求值时视图结构可能被重新创建，导致 subject 实例被替换，`.onReceive` 订阅的是旧的 subject，搜索防抖失效。
- **建议修复**: 将搜索逻辑提取到 `@StateObject` 的 ViewModel 中。

---

### #18 PlaylistGroupService 在两个 Tab 中独立创建

- **文件**: `Presentation/Library/LibraryTabView.swift` L9, `Presentation/Playlist/PlaylistTabView.swift` L7
- **分类**: 数据一致性
- **问题**: `LibraryTabView` 和 `PlaylistTabView` 各自创建了独立的 `PlaylistGroupService` 实例。如果用户在歌单 Tab 中修改了分组，音乐库 Tab 中的分组数据不会同步更新。
- **建议修复**: 提升到 App 层统一创建并通过 `.environmentObject()` 注入。

---

### #19 ThemeManager/WallpaperManager 缺少 @MainActor 标注

- **文件**: `App/Theme/ThemeManager.swift` L18, `App/Theme/WallpaperManager.swift` L4
- **分类**: 线程安全
- **问题**: `ThemeManager.applyToWindows()` 直接操作 `UIApplication.shared.connectedScenes` 和 `UIWindow`，这些是 main thread only API。缺少 `@MainActor` 标注意味着无法保证在主线程执行。
- **建议修复**: 添加 `@MainActor` 注解。

---

## P2 中等问题

### #20 AudioSessionManager.configure() 重试逻辑错误

- **文件**: `Core/Audio/AudioSessionManager.swift` L12-29
- **分类**: 逻辑错误
- **问题**: 注释写的是 "retry activation"，但代码重试的却是 `setCategory`。如果 `setCategory` 成功但 `setActive` 失败，重试 `setCategory` 毫无意义。
- **建议修复**: 重试应该是 `setActive`。

---

### #21 ensureActive() 错误被 print 吞掉

- **文件**: `Core/Audio/AudioSessionManager.swift` L31-45
- **分类**: 错误处理
- **问题**: 如果音频会话激活失败，错误仅通过 `print` 输出，后续的 `player.play()` 将静默失败（无声音、无报错）。
- **建议修复**: 改为 `throws` 或返回 `Bool`，替换 `print` 为 `AppLogger`。

---

### #22 play() 短暂 1x 速率后再切到目标速率

- **文件**: `Core/Audio/AudioEngine.swift` L142-150
- **分类**: 逻辑错误
- **问题**: `player.play()` 内部将 `rate` 设为 `1.0`，当 `playbackSpeed` 非 1.0 时会有微小的变速感。
- **建议修复**: 直接设置 `player.rate = playbackSpeed` 来启动播放。

---

### #23 快速切歌时未先清理旧 KVO 观察

- **文件**: `Core/Audio/AudioEngine.swift` L109-133
- **分类**: 逻辑错误
- **问题**: 连续快速切歌时，新的 `load` 调用不会先 `invalidate` 旧的 `statusObservation` / `itemObservation`，极短窗口内旧的和新的观察同时存在。
- **建议修复**: 在创建新观察前显式 `invalidate` 旧的。

---

### #24 中断恢复不检查 session 激活成功

- **文件**: `Core/Audio/AudioEngine.swift` L248-264
- **分类**: 错误处理
- **问题**: 如果 `ensureActive()` 失败但 `state` 仍被设为 `.playing`，造成 UI 状态与实际播放状态不一致。
- **建议修复**: 根据 `ensureActive()` 结果决定是否恢复播放。

---

### #25 AudioSessionManager 无 actor 隔离

- **文件**: `Core/Audio/AudioSessionManager.swift`
- **分类**: 线程安全
- **问题**: 没有 `@MainActor` 或 `Sendable` 标注，`isConfigured` 属性存在潜在数据竞争。
- **建议修复**: 添加 `@MainActor` 注解。

---

### #26 ImportService @Published progress 未更新

- **文件**: `Domain/Services/ImportService.swift` L8, L33-40
- **分类**: 状态同步
- **问题**: `progress` 属性是 `@Published`，但在导入循环中只通过 `onProgress` 回调通知，从未给 `self.progress` 赋值。View 层观察不到更新。
- **建议修复**: 在循环中同步更新 `self.progress = currentProgress`。

---

### #27 安全作用域资源返回值被忽略

- **文件**: `Domain/Services/ImportService.swift` L90
- **分类**: 错误处理
- **问题**: `startAccessingSecurityScopedResource()` 返回 `Bool`，返回 `false` 时不应调用 `stop`，否则导致访问计数不平衡。
- **建议修复**: `let hasAccess = url.startAccessing...`; `defer { if hasAccess { url.stop... } }`。

---

### #28 PlayQueueService repeatAll 缺少空队列防护

- **文件**: `Domain/Services/PlayQueueService.swift` L74-77
- **分类**: 逻辑错误
- **问题**: 列表循环模式下，重置标记后直接返回 `queue.first`，但未检查队列是否为空。
- **建议修复**: 增加 `guard !queue.isEmpty else { return nil }`。

---

### #29 SearchService @Published result 从未赋值

- **文件**: `Domain/Services/SearchService.swift` L6, L11
- **分类**: 状态同步
- **问题**: `search` 方法返回 `SearchResult` 但从未赋值给 `self.result`，View 层通过 `@ObservedObject` 观察永远看到空结果。
- **建议修复**: 更新 `@Published` 属性，或移除避免误导。

---

### #30 "/" 分隔符导致含 "/" 的名称解析错误

- **文件**: `Domain/Services/MusicLibraryService.swift` L40, L45
- **分类**: 逻辑错误
- **问题**: 使用 `"artist/album"` 作为字典 key，通过 `split(separator: "/").last` 提取专辑名。如果名称包含 "/"（如 "AC/DC"），解析会出错。
- **建议修复**: 使用结构体 `(artist, album)` 作为 key，或使用不会出现在数据中的分隔符。

---

### #31 fetchFavorites 全量加载内存过滤

- **文件**: `Domain/Services/PlaylistService.swift` L80-86
- **分类**: 性能
- **问题**: 先加载全部歌曲再内存过滤收藏。当曲库较大时造成不必要的内存和 CPU 开销。
- **建议修复**: 在 Repository 层添加 `fetchSongs(byIds:)` 方法，用 `NSPredicate(format: "id IN %@")` 查询。

---

### #32 setCustomCover 无效图片静默返回不抛错

- **文件**: `Domain/Services/PlaylistService.swift` L51
- **分类**: 错误处理
- **问题**: 方法签名为 `async throws`，但当图片数据无效时直接 `return`，调用方无法区分成功和失败。
- **建议修复**: 抛出明确错误。

---

### #33 fullScreenCover/sheet 缺少部分 EnvironmentObject

- **文件**: `Presentation/Root/RootTabView.swift` L32-50
- **分类**: 运行时错误
- **问题**: `fullScreenCover` 和 `sheet` 会创建新的 presentation context，不自动继承父视图的 `@EnvironmentObject`。当前 `PlayerView` 缺少 `wallpaperManager`；`sheet` 缺少 `libraryService`、`themeManager` 等。如果子视图需要这些对象会崩溃。
- **建议修复**: 完整传入所有 EnvironmentObject，或创建统一注入的 ViewModifier。

---

### #34 PlayerView 双层 .sheet 存在冲突风险

- **文件**: `Presentation/Player/PlayerView.swift` L38-49
- **分类**: 导航/Sheet
- **问题**: 同一视图上挂了两个 `.sheet` modifier，快速连续触发时可能出现 sheet 无法弹出。当前用 `asyncAfter(0.3)` 硬编码延迟缓解，但这是脆弱的。
- **建议修复**: 统一为一个 sheet 状态源。

---

### #35 withAnimation 对 fullScreenCover 无效

- **文件**: `App/Navigation/AppRouter.swift` L41-50
- **分类**: UI 动画
- **问题**: `fullScreenCover` 的 present/dismiss 动画由 UIKit 管理，不受 SwiftUI `withAnimation` 控制。自定义 spring 参数被忽略。
- **建议修复**: 如需自定义转场动画改用 `.overlay` + 自定义动画，或接受系统默认动画。

---

### #36 PlayerView 使用已废弃的 UIScreen.main

- **文件**: `Presentation/Player/PlayerView.swift` L254, L257, L262
- **分类**: UI 布局
- **问题**: `UIScreen.main` 在 iOS 16+ 已标记 deprecated，且在 iPad 分屏、Stage Manager 等场景下不等于实际可用宽度。
- **建议修复**: 使用 `GeometryReader` 获取实际可用空间。

---

### #37 MiniPlayerBar 嵌套 Button 导致手势冲突

- **文件**: `Presentation/Common/MiniPlayerBar.swift` L16-83
- **分类**: UI 交互
- **问题**: 外层大 Button 用于打开播放器，内部嵌套了三个小 Button。点击内部小按钮时，外部大按钮也可能被触发。
- **建议修复**: 外层改为 `.onTapGesture`，配合 `.highPriorityGesture()` 让内部按钮优先响应。

---

### #38 fetchRecentlyPlayed 全量加载后内存分页

- **文件**: `Data/Repositories/CoreDataSongRepository.swift` L187-232
- **分类**: 性能
- **问题**: 加载全部 PlayRecordEntity 到内存后内存中去重 + 分页。大量播放记录时开销显著。
- **建议修复**: 使用 `NSDictionaryResultType` + `NSExpression` 在数据库层面做 distinct。

---

### #39 softDelete 标记与文件操作非原子

- **文件**: `Data/Repositories/CoreDataSongRepository.swift` L65-98
- **分类**: 数据一致性
- **问题**: CoreData 事务完成后才执行文件移动。如果 App 在两步之间崩溃，数据库已标记删除但文件未移动。
- **建议修复**: 将文件操作移入同一错误处理范围，或 `undoDelete` 中增加文件位置检查 fallback。

---

### #40 PlaylistMapper.toEntity 字段映射不完整

- **文件**: `Data/Mappers/PlaylistMapper.swift` L56-68
- **分类**: Mapper 正确性
- **问题**: `toEntity` 缺少 `coverImagePath` → `customCoverPath` / `autoCoverPath`、`autoCoverHash` 的映射。数据迁移或导入导出场景下封面信息会丢失。
- **建议修复**: 补全缺失字段映射。

---

## P3 建议

### #41 AudioEngine 单例 deinit 是死代码

- **文件**: `Core/Audio/AudioEngine.swift` L66-73
- **问题**: `static let shared` 单例的 `deinit` 永远不会被调用。Swift 6 中 `@MainActor` 类的 `deinit` 不保证在主线程执行，访问隔离属性不安全。
- **建议修复**: 移除 `deinit`，如需支持非单例模式提供显式 `cleanup()` 方法。

---

### #42 NowPlayingManager 与 AudioEngine 紧耦合

- **文件**: `Core/Audio/NowPlayingManager.swift` L62-65
- **问题**: `togglePlayPauseCommand` 直接引用 `AudioEngine.shared.isPlaying`，违反单一职责。
- **建议修复**: 增加 `onTogglePlayPause` 参数，让调用方注入判断逻辑。

---

### #43 回调闭包与项目 Combine 风格不一致

- **文件**: `Core/Audio/AudioEngine.swift` L193-194
- **问题**: `onPlaybackEnded` 和 `onTimeUpdate` 使用闭包回调，而项目已大量使用 Combine。任何代码都可以覆盖，每次赋值丢失前一个订阅者。
- **建议修复**: 改用 `PassthroughSubject` 或 `AsyncStream`。

---

### #44 PlaybackState.error(Error) 不支持 Equatable

- **文件**: `Core/Audio/AudioEngine.swift` L5-8
- **问题**: `Error` 不遵循 `Equatable`，导致 `PlaybackState` 无法用于 `==` 比较，在 SwiftUI diff 和测试中不便。
- **建议修复**: 手动实现 `Equatable`，或将关联值改为具体 error 类型。

---

### #45 RootTabView 调试 print 应替换为 AppLogger

- **文件**: `Presentation/Root/RootTabView.swift` L52, L83
- **问题**: 项目已有 `AppLogger` 日志系统，但仍使用 `print` 进行调试输出，Release 包也会输出。
- **建议修复**: 替换为 `AppLogger.shared.debug(...)`。

---

### #46 SettingsView 过大（650行），职责过重

- **文件**: `Presentation/Settings/SettingsView.swift`
- **问题**: 12 个 `@State`、5 个 `@EnvironmentObject`、5 个 `@AppStorage`，近 650 行代码，承担过多职责。
- **建议修复**: 将各 Section 拆分为独立子视图。

---

### #47 PlaybackService/AudioEngine 单例绕过 DI

- **文件**: 多个 Presentation 文件
- **问题**: 多个视图中直接通过 `.shared` 引用单例而非 `@EnvironmentObject` 注入，无法在 Preview 或单元测试中替换为 mock。
- **建议修复**: 从 App 层通过 `.environmentObject()` 注入。

---

### #48 Tab 路由 default: EmptyView() 静默吞掉未知路由

- **文件**: `Presentation/Playlist/PlaylistTabView.swift` L42, `Presentation/Settings/SettingsTabView.swift` L31
- **问题**: `default: EmptyView()` 会静默吞掉未处理的 `AppDestination` case，新增 case 忘了处理时用户看到空白页。
- **建议修复**: `default` 中添加 `assertionFailure("Unhandled destination")`。

---

### #49 FrostEleganceBackground.iceShards 有死代码

- **文件**: `App/Theme/Backgrounds/FrostEleganceBackground.swift` L99
- **问题**: `endY` 被计算后从未使用，且表达式本身极难理解。
- **建议修复**: 删除死代码。

---

### #50 WallpaperManager 单例与 EnvironmentObject 注入模式冲突

- **文件**: `App/Theme/WallpaperManager.swift` L5, `App/Theme/ThemeBackgroundView.swift` L5
- **问题**: 声明了 `static let shared` 单例，同时又通过 `@EnvironmentObject` 注入。注入实例与 `.shared` 可能不一致。
- **建议修复**: 统一使用一种注入方式。

---

### #51 CoreData entity.id! 强制解包有崩溃风险

- **文件**: `Data/Repositories/CoreDataSongRepository.swift` L122, L177
- **问题**: 多处使用 `entity.id!` 强制解包，数据损坏或迁移异常时直接崩溃。
- **建议修复**: 使用 `guard let id = entity.id else { continue }` 安全解包。

---

## 建议修复优先级

### 第一批：影响核心功能，立即修复

| # | 问题 | 影响 |
|---|------|------|
| #1 | undoDelete 路径错误 | 撤销删除后文件丢失 |
| #2 | performBackground 不回滚 | 脏数据残留污染后续操作 |
| #3 | 歌单播放只加载单首 | 下一首/上一首完全失效 |
| #9 | 收藏未持久化 | 重启后收藏丢失 |
| #10 | 封面 UUID 不一致 | 封面可能显示不出 |
| #33 | EnvironmentObject 缺失 | 特定路径运行时崩溃 |

### 第二批：线程安全，Swift 6 迁移必修

| # | 问题 |
|---|------|
| #4~#8 | AudioEngine 的 5 处跨 actor 隔离访问 |
| #13 | SearchService viewContext.perform 捕获 @MainActor self |
| #14 | lazy var backgroundContext 非线程安全 |
| #19 | ThemeManager/WallpaperManager 缺少 @MainActor |
| #25 | AudioSessionManager 无 actor 隔离 |

### 第三批：用户体验

| # | 问题 |
|---|------|
| #11 | 队列拖拽后索引错乱 |
| #15 | 删除歌单不清理关联数据 |
| #17 | 搜索防抖可能失效 |
| #18 | 歌单分组数据不同步 |
| #37 | 迷你播放器按钮手势冲突 |

### 第四批：性能与代码质量

| # | 问题 |
|---|------|
| #31 | 收藏列表全量加载 |
| #38 | 最近播放全量加载 |
| #40 | Mapper 字段遗漏 |
| #46 | SettingsView 拆分 |
| #47 | 单例改 DI 注入 |

---

**报告结束**
