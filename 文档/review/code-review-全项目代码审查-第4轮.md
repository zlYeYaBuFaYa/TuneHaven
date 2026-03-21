# 全项目代码审查 - 第 4 轮

> 日期：2026-03-21 | 类型：AI 全量审查 | 范围：全部 144 个 Swift 源文件

---

## 结论：不通过

| 维度 | 结论 | 说明 |
|------|------|------|
| 逻辑正确性 | ❌ | 存在多处静默失败、状态不一致、取消机制失效等问题 |
| 错误处理 | ❌ | 大量 `try?` 静默吞错、错误类型不统一（WebDAVError vs AppError）、ErrorLogger 未充分使用 |
| 安全 | ⚠️ | WiFiTransfer 上传无鉴权校验、WebDAV 自签证书配置有竞态 |
| 线程安全 | ❌ | `WebDAVAccountStore` 读写无同步、`LyricsService` 无 actor 隔离、`@objc` 在非 NSObject 类上 |
| 架构合规 | ❌ | Clean Architecture 被系统性违反：Domain 直接依赖 Data/Core，协议完全未使用 |
| 代码风格 | ⚠️ | 总体良好，局部有死代码、魔法数字、重复实现 |
| API 设计 | ⚠️ | 接口语义基本清晰，部分方法签名与协议不匹配 |
| 性能 | ⚠️ | WebDAV 逐字节下载、全表扫描分组、缓存每次存储全量排序 |
| 内存管理 | ⚠️ | URLSession 未释放、大文件全量内存加载（TuneHavenCore） |
| 可维护性 | ❌ | TuneHavenCore 为失效冗余包、PlaybackService 职责过重（God Class） |

---

## 统计汇总

| 层级 | 🔴 阻塞 | 🟡 建议 | 🟢 优化 | 合计 |
|------|---------|---------|---------|------|
| Core（音频/缓存/网络/持久化/存储/工具） | 5 | 17 | 21 | 43 |
| Data（Mapper/Parser/Repository） | 7 | 22 | 9 | 38 |
| Domain（Entity/Protocol/Service） | 12 | 18 | 11 | 41 |
| Presentation（View/Sheet/Common） | 4 | 14 | 12 | 30 |
| App + TuneHavenCore | 6 | 9 | 9 | 24 |
| **合计** | **34** | **80** | **62** | **176** |

---

## 🔴 阻塞问题（34 项，必须修复）

### 一、架构级问题（最高优先级）

#### 1. Clean Architecture 被系统性违反 — 协议完全未使用
**影响范围：全部 3 个 Repository + 全部 10 个 Service**

Domain 层定义了 `SongRepository`、`PlaylistRepository`、`PlaylistGroupRepository` 三个协议，但：
- 具体实现类（`CoreDataSongRepository` 等）**未声明协议遵守**
- 方法签名**严重不一致**（如协议定义 `create(_ song:)` 而实现为 `insert(song:)`）
- 所有 Service **直接实例化具体 Data/Core 类**，完全绕过 DI

```
// 当前：Domain 直接依赖 Data（错误方向）
PlaybackService → CoreDataSongRepository (具体类)
SearchService → CoreDataStack (直接 CoreData！)
ImportService → FileStorageService, AudioMetadataParser, ThumbnailGenerator...

// 正确：Domain 依赖抽象协议
PlaybackService → SongRepository (协议)
```

**建议**：让具体 Repository 类遵守 Domain 协议，统一方法签名，通过初始化器注入协议类型。

---

#### 2. TuneHavenCore 为失效冗余包 — 从未被 `import`
**影响范围：TuneHavenCore 全部 11 个文件**

主应用**从未 `import TuneHavenCore`**。两个 target 维护各自的副本且已严重分歧：

| 类型 | 主应用版本 | Core 版本差异 |
|------|-----------|-------------|
| `AppError` | 32 个 case + Equatable | 22 个 case，缺 WebDAV/歌词 case |
| `ErrorLogger` | 有 DispatchQueue 线程安全 | **无线程安全**，并发写入会数据损坏 |
| `FileStorageService` | 流式 SHA256，9 种格式 | **全量内存加载**，500MB 文件会 OOM |
| `PlayQueueService` | move 时更新 currentIndex | **未更新 currentIndex**，移动后播错歌 |
| `Song` / `Playlist` | 有 formatDuration 等方法 | 缺少字段和方法 |

此外 `Package.swift` 声明 `.macOS(.v13)` 平台（应为 `.iOS`），`PlayQueueService` 引用不存在的 `PlaylistService`，无法编译。

**建议**：删除 TuneHavenCore 或将其作为唯一源并让主应用 import。

---

#### 3. Domain 层存在 UIKit 依赖
**影响文件：`CloudDriveProvider.swift`、`ImportService.swift`、`PlaylistService.swift`**

Domain 层 `import UIKit` 使用 `UIImage`、`UIApplication.shared.canOpenURL()`，违反 Clean Architecture（Domain 不应依赖框架）。

**建议**：将图片处理移到 Core/Data 层，`isInstalled` 检测通过闭包注入。

---

#### 4. SearchService 在 Domain 层直接操作 CoreData
**影响文件：`SearchService.swift`**

`import CoreData`，直接使用 `NSFetchRequest`、`NSPredicate`、`SearchHistoryEntity`。搜索历史的 CRUD 应抽取到 `SearchHistoryRepository`。

---

#### 5. PlaybackService 是 God Class（~410 行）
**影响文件：`PlaybackService.swift`**

混合了播放控制、队列委派、倍速管理、睡眠定时、NowPlaying 信息中心、封面缓存、播放模式切换、歌曲跳过追踪、最后播放持久化等 8+ 种职责。`AppStorageKey` 全局常量也定义在此。

**建议**：拆分为 PlaybackController、SleepTimerService、NowPlayingInfoService、PlaybackPreferencesStore 等。

---

#### 6. Presentation 层直接访问 Data 层
**影响文件：`SongInfoEditView.swift`、`BatchAddSongsView.swift`、`SongListView.swift`**

直接实例化 `CoreDataSongRepository()` 和 `CoreDataStack.shared.performBackground`，绕过 Service 层。

**建议**：在 `MusicLibraryService` 中添加 `updateSongInfo()`、`fetchAllSongs()` 等方法。

---

### 二、编译/崩溃问题

#### 7. `@objc` 用于非 NSObject 类 — 编译错误
**影响文件：`AudioEngine.swift`、`ImageCacheManager.swift`**

两个类使用 `#selector` + `@objc` 但未继承 `NSObject`。Swift 要求 `@objc` 方法必须在 `NSObject` 子类中。

**建议**：改用闭包式 `NotificationCenter.default.addObserver(forName:object:queue:using:)`。

---

#### 8. WiFiTransferServer 文件写入失败仍报成功
**影响文件：`WiFiTransferServer.swift`**

```swift
try? Data(fileData).write(to: destURL)  // 静默失败
sendJSON(connection: connection, status: 200, body: #"{"success":true}"#)  // 依然返回成功
onFileReceived?(filename, destURL)  // 回调一个不存在的 URL
```

磁盘满时用户看到"上传成功"但文件丢失。

---

#### 9. WebDAVClient 取消下载机制失效
**影响文件：`WebDAVClient.swift`**

`currentDownloadTask` 从未被赋值（使用的是 `session.bytes(for:)` 而非下载任务），`cancelDownload()` 调用 `currentDownloadTask?.cancel()` 等于无操作。唯一的取消方式是 `isCancelled` 标志位，逐字节检查，大文件取消极慢。

---

#### 10. WebDAVClient 逐字节异步迭代 — 严重性能问题
**影响文件：`WebDAVClient.swift`**

100MB 文件产生约 1 亿次异步 yield。应使用 `session.download(for:)` 或分块读取。

---

#### 11. WebDAVAccountStore 无线程同步
**影响文件：`WebDAVAccountStore.swift`**

`loadAccounts()`、`saveAccount()`、`deleteAccount()` 对同一 UserDefaults key 做读-改-写无锁保护，并发调用会丢数据。

---

#### 12. CoreData Repository 协议遵守声明缺失 + 签名不匹配
**影响文件：`CoreDataSongRepository.swift`、`CoreDataPlaylistRepository.swift`、`CoreDataPlaylistGroupRepository.swift`**

三个实现类均未声明 `: XXXRepository`。方法签名与协议严重不一致（见第 1 点）。

---

#### 13. softDelete DB/文件操作非原子性
**影响文件：`CoreDataSongRepository.swift`**

数据库事务先提交，文件移动在事务外执行。崩溃可能导致数据库标记已删但文件未移动，或反之。

---

#### 14. MusicLibraryService 全表扫描后内存分组
**影响文件：`MusicLibraryService.swift`**

`fetchSongsByArtist()` 和 `fetchSongsByAlbum()` 调用 `fetchAll()` 加载全部歌曲到内存后在内存中分组。千首歌曲库下严重低效，应在数据库层面分组查询。

---

#### 15. LyricsService 缺少 actor 隔离
**影响文件：`LyricsService.swift`**

`final class` 含可变状态但无 `@MainActor` 或 actor 隔离，被多个 `@MainActor` 上下文并发访问，Swift 6 严格并发下存在数据竞态风险。

---

#### 16. WiFiTransferServer 上传无鉴权校验
**影响文件：`WiFiTransferServer.swift`**

`passwordEnabled` 开启时，`handleUpload()` 不验证客户端是否已通过 `/auth`。任何客户端可直接 POST `/upload` 绕过密码。

---

#### 17. PlaylistCoverPickerSheet 传入空数组
**影响文件：`PlayerSheets.swift`**

`regenerateAutoCover(for: detail, songs: [])` 传入空数组，生成空白封面。应先获取歌单实际歌曲列表。

---

### 三、其他阻塞问题

| # | 文件 | 问题 |
|---|------|------|
| 18 | `AudioEngine.swift` | `AudioEngineError` 独立类型，未使用 `AppError`，错误链不完整 |
| 19 | `CoreDataStack.swift` | `performBackground` 可返回 `NSManagedObject` 跨上下文，线程违规 |
| 20 | `CoreDataStack.swift` | `save(context:)` 静默吞错，调用方无法得知保存失败 |
| 21 | `PlaylistMapper.swift` | `toEntity` 总是创建新实体，存在 ID 重复风险 |
| 22 | `SongMapper.swift` | `toEntity` 硬编码 `softDeleted = false`，更新场景会错误覆盖 |
| 23 | `CoreDataPlaylistGroupRepository.swift` | `create()` 中 `guard let ... as PlaylistGroup?` 永远成功，死代码 |
| 24-34 | TuneHavenCore 全部 | 见第 2 点，含 6 个编译/运行时阻塞问题 |

---

## 🟡 建议问题（80 项，强烈建议修复）

### 性能类

| # | 文件 | 问题 |
|---|------|------|
| 1 | `PlaylistMapper.swift` | `computeSongCount` 用 `fetch().count` 替代 `count(for:)`，全量加载对象仅计数 |
| 2 | `CoreDataPlaylistRepository.swift` | `addSongs` 获取全部关联实体算最大排序，应用 `fetchLimit=1` + 排序 |
| 3 | `ImageCacheManager.swift` | `evictIfNeeded()` 每次 store 都全量扫描排序，O(n log n) |
| 4 | `MiniPlayerBar.swift` | `GeometryReader` + `engine.currentTime` 导致每秒 60 次全组件重建 |
| 5 | `AudioMetadataParser.swift` | `ParsedMetadata.coverImage` 持有大 UIImage，应延迟解码 |
| 6 | `SearchService.swift` | `search()` 要求全部歌曲在内存，应数据库层过滤 |

### 错误处理类

| # | 文件 | 问题 |
|---|------|------|
| 7 | `AudioEngine.swift` | `ensureActive()` 返回值两处被忽略，音频会话激活失败后继续播放 |
| 8 | `AudioEngine.swift` | `duration` 在独立 Task 中异步加载，调用方 `play()` 时可能仍为 0 |
| 9 | `LRCLibAPIClient.swift` | `URLComponents` 强制解包，含特殊字符的 baseURL 会崩溃 |
| 10 | `WebDAVClient.swift` | `URLSession` 从未 invalidate，session + delegate 泄漏 |
| 11 | `WiFiTransferServer.swift` | `failedAttempts` 冷却后未重置，下次错误立即重新触发冷却 |
| 12 | `WiFiTransferServer.swift` | 大文件上传全量累积在内存，500MB 文件可能 OOM |
| 13 | `ImportService.swift` | 封面写入 `try?` 失败后 `coverImagePath` 仍被设置，产生悬空引用 |
| 14 | `LyricsService.swift` | 冷却字典在 UserDefaults 中永不清理过期条目，持续膨胀 |
| 15 | `PlaybackService.swift` | `loadAndPlay()` 文件不存在时静默返回，用户无反馈 |
| 16 | `PlaylistService.swift` | `setCustomCover()` JPEG 压缩返回 nil 时静默成功 |
| 17 | `PlaylistService.swift` | `regenerateAutoCover()` 全程 `try?`，文件/DB 不一致 |
| 18 | 多个 Repository | entity 未找到时静默返回（rename/update/delete/addSongs） |
| 19 | `CoreDataSongRepository.swift` | `cleanupPendingDeletes` 顶层 `try?`，DB 失败不报错 |
| 20 | `AppError.swift` | `AppLogger.error()` 未传递 `line` 参数，ErrorLogger 记录的行号永远是 ~210 |
| 21 | `WebDAVAccountEditView.swift` | HTTP 公网地址保存时静默 return，用户无任何反馈 |
| 22 | `CreatePlaylistSheet.swift` | `try? addSongs` 失败仍 dismiss，用户不知操作是否成功 |

### 架构/设计类

| # | 文件 | 问题 |
|---|------|------|
| 23 | `CoreDataStack.swift` | 手动 merge + `automaticallyMergesChangesFromParent` 重复处理 |
| 24 | `QRCodeGenerator.swift` | `QRCodeView`（SwiftUI View）放在 Core 层，应在 Presentation |
| 25 | `AppleMusicImportView.swift` | ~115 行导入逻辑放在 View 中，应移至 ImportService |
| 26 | `PlaylistMainView.swift` | 4 处触发 `loadPlaylists()`（.task + .onAppear + .onChange + .onReceive），双重加载 |
| 27 | 多处 | `LyricsService.shared` 在 Presentation 层直接使用单例，未注入 |
| 28 | `SettingsView.swift` | 文件选择器用 `[.audio, .mpeg4Audio]`，与 `ImportFilesView` 的 `allSupportedAudio` 不一致 |
| 29 | `AppDelegate.swift` | 音频会话手动配置后又调用 `AudioSessionManager.configure()`，可能重复 |
| 30 | `TuneHavenApp.swift` | 9 个 `@StateObject` 服务，任一属性变化都触发根视图重算 |
| 31 | `AppDestination.swift` | `addToPlaylist` 的 `id` 仅取首个 UUID，内容不同可能 id 相同，sheet 不重现 |

### 线程安全类

| # | 文件 | 问题 |
|---|------|------|
| 32 | `NowPlayingManager.swift` | 远程命令回调在系统队列执行，未确保 `@MainActor` |
| 33 | `WebDAVSessionDelegate.swift` | `trustSelfSignedCert` 是 `var`，跨隔离域访问有竞态风险 |
| 34 | `ImageCacheManager.swift` | 文件操作无同步保护，并发 store/evict 可能竞态 |
| 35 | `SnackbarState` | 类缺少 `@MainActor`，`action`/`hideTask` 属性无隔离 |
| 36 | `ThemeManager.swift` | `@MainActor` 中使用 GCD DispatchWorkItem，Swift 6 可能 Sendable 警告 |

### 数据完整性类

| # | 文件 | 问题 |
|---|------|------|
| 37 | `SongMapper.swift` | `-1` 作为 nil 哨兵值存储 `lyricsSource`，脆弱 |
| 38 | `SongMapper.swift` | `0` 作为 nil 哨兵存 `trackNumber`/`year`，track 0 会被误映射为 nil |
| 39 | `PlaylistMapper.swift` | `coverImagePath` 往返映射有损，`autoCoverHash` 清除后归属错误 |
| 40 | `ImageCacheManager.swift` | `evictIfNeeded()` 只驱逐 coverImages 目录，不处理 playlistCovers |
| 41 | `ImageCacheManager.swift` | `store()` 未设 NSCache cost，`totalCostLimit` 无效 |
| 42 | `MigrationManager.swift` | 版本号字符串比较，`"10.0" < "2.0"` 为 true（词典序） |

### 其他建议

| # | 文件 | 问题 |
|---|------|------|
| 43 | `CoreDataPlaylistRepository.swift` | `createSystemPlaylists` 使用魔法数字 `1`/`2` 代替枚举 |
| 44 | `WebDAVService.swift` | 使用 `WebDAVError` 而非 `AppError`，错误类型不统一 |
| 45 | `PlayQueueService.swift` | `saveQueueAsPlaylist` 接收 `PlaylistService` 参数，紧耦合 |
| 46 | `PlayQueueService.swift` | `repeatAll` 模式不处理 dislike 加权 |
| 47 | `PlaylistService.swift` | 保留名 `["我喜欢","最近播放"]` 硬编码中文，不支持国际化 |
| 48 | `PlayerView.swift` | `switchSheet` 使用 DispatchWorkItem，cancel 不可靠有时序窗口 |
| 49 | `LyricsView.swift` | `DispatchQueue.main.asyncAfter` 而非现代 `Task.sleep` |
| 50 | `AlbumDetailView.swift` | 直接写 `UserDefaults.standard.set` 绕过 `@AppStorage` 观察机制 |
| 51 | `SleepTimerSheet` | `Int(remaining/60)` 截断导致定时器选中状态闪烁 |
| 52-80 | 其余文件 | 单例无协议抽象、硬编码中文字符串、可选强引用、序列化问题等 |

---

## 🟢 优化问题（62 项，应当修复）

### 代码质量

| # | 文件 | 问题 |
|---|------|------|
| 1 | `AudioEngine.swift` | `playbackEndedSubject`/`timeUpdateSubject` 应为 private(set) 或暴露 AnyPublisher |
| 2 | `AudioEngine.swift` | PlaybackState.== 用 `localizedDescription` 比较 Error |
| 3 | `UTType+Audio.swift` | `.audio` 是所有音频父类型，文件选择器会允许不支持的格式 |
| 4 | `WebDAVXMLParser.swift` | `localName()` 冗余，`shouldProcessNamespaces` 已启用 |
| 5 | `WiFiTransferServer.swift` | HTTP status text 全为 "OK"，404/429 返回 "404 OK" 违反协议 |
| 6 | `ContentView.swift` | 死文件，仅含 `EmptyView()`，应删除 |
| 7 | `CoreDataSongRepository.swift` | `fetchDeletedSong` 私有且未使用，死代码 |
| 8 | `SearchService.swift` | `artistNames`/`albumKeys` 集合构建后未使用，死代码 |
| 9 | `ThumbnailGenerator.swift` | `resize()` 不保持宽高比，会拉伸图片 |
| 10 | `SandboxPathManager.swift` | `ThumbnailSize` 定义在此文件，应在 ThumbnailGenerator 旁 |

### UI/UX

| # | 文件 | 问题 |
|---|------|------|
| 11 | `CoverImageView.swift` | `PlaceholderCoverView` 硬编码 `cornerRadius: 8`，不跟随父组件参数 |
| 12 | `ArtistDetailView.swift` | 专辑行无年份时仍显示 "·" 分隔符 |
| 13 | `SongRow.swift` | 使用 `onTapGesture` 而非 `Button`，无无障碍/触觉反馈支持 |
| 14 | `PlayQueueView.swift` | 列表永久处于编辑模式，界面拥挤 |

### 重复代码

| # | 涉及文件 | 问题 |
|---|----------|------|
| 15 | `SettingsStorageSection` + `SettingsView` | `calculateCacheSize()` 实现完全重复 |
| 16 | `ImportFilesView` + `CloudDriveImportView` | `resultRow` 和导入结果展示重复 |
| 17 | `LibraryMainView` + `WebDAVAccountListView` | `Date.relativeDescription` / `Date.relativeDisplay` 重复 |
| 18 | `Song.formatDuration()` + `LRCLibTrack.durationText` | 时间格式化逻辑重复 |

### 其他优化

| # | 涉及文件 | 问题 |
|---|----------|------|
| 19 | `AppError.swift` | `Equatable` 实现忽略关联值，仅比较 errorCode |
| 20 | `AppError.swift`/`AppLogger` | 日志轮转策略不一致（一个删除/一个备份） |
| 21 | `WallpaperManager.swift` | 直接用 FileManager 构建路径，未使用 SandboxPathManager |
| 22 | `ThemeRegistry.swift` | 使用 NSLock 但未声明 `@unchecked Sendable` |
| 23 | `AudioMetadataParser.swift` | 双 switch 对同一 `item.identifier`，可合并 |
| 24 | `AudioMetadataParser.swift` | 默认值 "未知艺术家"/"未知专辑" 硬编码，不支持 i18n |
| 25 | `LRCParser.swift`(Core) | 正则要求两位数分钟，无法解析 `[1:23.45]` |
| 26-62 | 其余 | 缺少访问控制、冗余代码、文档缺失等 |

---

## 优先修复建议（按影响排序）

### P0 — 架构修复（影响全局，建议最先处理）

1. **统一 Repository 协议**：让 `CoreDataXXXRepository` 遵守 Domain 协议，统一方法签名，Service 通过初始化器注入协议
2. **处理 TuneHavenCore**：删除或重构为唯一源，消除代码分歧
3. **移除 Domain 层的 UIKit 依赖**：图片处理下沉到 Core 层
4. **拆分 PlaybackService**：至少拆为 4 个职责单一的 Service
5. **SearchService 抽离 CoreData**：创建 SearchHistoryRepository

### P1 — 编译/崩溃修复

6. **修复 `@objc` 在非 NSObject 类上**（AudioEngine、ImageCacheManager）
7. **WiFiTransferServer 文件写入错误处理** + 上传鉴权
8. **WebDAVClient 取消机制** + 改为分块下载
9. **WebDAVAccountStore 加锁**
10. **softDelete 原子性**：至少记录部分失败用于恢复

### P2 — 性能优化

11. **`computeSongCount` 改用 `count(for:)`**
12. **MusicLibraryService 数据库层分组查询**
13. **MiniPlayerBar 进度条提取独立 View**
14. **ImageCacheManager 增量跟踪缓存大小**

### P3 — 错误处理 & 数据完整性

15. **统一错误类型为 AppError**，移除 AudioEngineError、WebDAVError
16. **关键路径 `try?` 改为 `try` + 错误上报**
17. **修复哨兵值映射**（lyricsSource -1、trackNumber 0）
18. **AppLogger 行号传递修复**

---

## 积极发现

1. **主题系统设计良好**：`@Environment(\.themePalette)` 使用一致，主题扩展结构清晰
2. **导航架构清晰**：`AppRouter` + `NavigationStack(path:)` 模式统一
3. **导入流程反馈完善**：成功/重复/失败计数明确
4. **SwiftUI 使用规范**：合理使用 `.listRowBackground`、`.scrollContentBackground(.hidden)`、`.adaptiveBackground()`
5. **无障碍基础**：大部分交互元素使用 `Label` + SF Symbols
6. **Snackbar/EmptyState 复用良好**：公共组件设计合理
7. **错误日志基础设施完善**：AppLogger + ErrorLogger 双层日志，文件轮转机制
