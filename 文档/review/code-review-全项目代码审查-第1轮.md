# 代码 Review：全项目代码审查 - 第 1 轮

> 日期：2026-03-21 | 类型：AI 自审 | 范围：全部 133 个 Swift 源文件

## 结论：不通过

---


| 维度     | 结论  | 说明                                                                                              |
| ------ | --- | ----------------------------------------------------------------------------------------------- |
| 逻辑正确性  | ❌   | 发现多个实际 Bug（LyricsSource 映射丢失、收藏队列构建错误、随机播放模式切换逻辑错误等）                                            |
| 错误处理   | ❌   | 大量 `try?` 静默吞错、日志并发写入无序列化、部分关键路径无用户反馈                                                           |
| 安全     | 🟡  | WiFi 上传路径穿越风险、WebDAV 自签名证书信任无锁定                                                                 |
| 线程安全   | ❌   | AudioEngine.play() 未调用 player.play()、ErrorLogger/AppLogger 并发写未序列化、LyricsService 未标注 @MainActor |
| 架构合规   | 🟡  | Domain 层大量依赖 Core Data 具体实现和 UIKit，不符合 Clean Architecture 依赖方向                                  |
| 代码风格   | 🟡  | 少量死代码/未使用变量、全局扩展定义在 View 文件中                                                                    |
| API 设计 | ✅   | Service 接口设计合理，@Published 驱动 UI 刷新模式一致                                                          |
| 性能     | 🟡  | CoverImageView 同步磁盘读取、SHA256 全文件加载到内存、WebDAV 逐字节写入                                              |
| 内存管理   | ✅   | Combine/Timer 普遍使用 [weak self]，无明显循环引用                                                          |
| 可维护性   | 🟡  | TuneHavenCore 包未接入项目，与主工程代码严重重复且有偏差                                                             |


---

## 问题汇总

### 🔴 阻塞级（必须修复）

#### 1. [🔴] SongMapper: LyricsSource `.embedded` (rawValue=0) 持久化后读取变为 nil

**文件**: `TuneHaven/Data/Mappers/SongMapper.swift`

**问题**: `toDomain()` 中 `entity.lyricsSource != 0 ? LyricsSource(rawValue: ...) : nil`，而 `.embedded` 的 rawValue 恰好是 0。写入时 `song.lyricsSource?.rawValue ?? 0` 将 nil 和 `.embedded` 都存为 0。读取时 0 又被当作 nil。

**影响**: 所有内嵌歌词的歌曲在重启后 `lyricsSource` 丢失，歌词加载逻辑可能跳过内嵌歌词直接搜索在线歌词。

**建议**: 使用 sentinel 值（如 -1）表示 nil，或存储 Optional 并用 NSNull 处理。

---

#### 2. [🔴] SongListView: 收藏列表 PlayContext 使用随机 UUID

**文件**: `TuneHaven/Presentation/Playlist/SongListView.swift` ~行 76

**问题**: `.favorites` 上下文使用 `.playlist(id: UUID())`，每次生成一个新的随机 UUID。`PlaybackService.buildQueue` 按此 ID 查找歌单，必然找不到 → 播放队列回退为单首歌曲。

**影响**: 从"我喜欢"列表播放歌曲时，队列只有一首歌，无法顺序播放整个收藏列表。

**建议**: 应查找真实的"我喜欢"系统歌单 ID（如 `playlistService.playlists.first { $0.systemType == .favorites }?.id`）。

---

#### 3. [🔴] AudioEngine.play() 未调用 AVPlayer.play()

**文件**: `TuneHaven/Core/Audio/AudioEngine.swift` ~行 156-161

**问题**: `play()` 方法只设置 `player.rate = playbackSpeed` 和 `state = .playing`，未调用 `player.play()`。`AVPlayer` 在 `pause()` 后需要 `play()` 才能恢复播放。

**影响**: 设置 `player.rate` 在某些情况下可以启动播放（当 rate 从 0 变为非零），但这不是 AVPlayer 的标准 API 用法，可能在特定 iOS 版本或状态下失败。

**建议**: 在设置 rate 前先调用 `player.play()`，或改为 `player.play()` 后再 `player.rate = playbackSpeed`。

---

#### 4. [🔴] WiFiTransferServer: HTTP Body 只 receive 一次，大文件上传可能不完整

**文件**: `TuneHaven/Core/Network/WiFiTransferServer.swift` ~行 112-122

**问题**: 使用单次 `receive(minimumIncompleteLength:maximumLength:)` 接收上传数据，没有循环读取。对于超出单次缓冲区大小的文件，数据会被截断。

**影响**: WiFi 传输大型音乐文件可能导入不完整或失败。

**建议**: 实现循环读取直到 `isComplete` 或 content-length 满足。

---

#### 5. [🔴] WiFiTransferServer: 上传文件名路径穿越风险

**文件**: `TuneHaven/Core/Network/WiFiTransferServer.swift` ~行 199-201

**问题**: 从 HTTP 头部提取的 `filename` 直接用于 `appendingPathComponent(filename)`，未过滤 `../` 或绝对路径。

**影响**: 恶意客户端可能构造文件名写入沙盒内其他目录（虽然 iOS 沙盒有限制，但行为不正确）。

**建议**: 对 filename 做 `lastPathComponent` 处理，或过滤路径分隔符和 `..`。

---

#### 6. [🔴] Playlist 实体 Hashable 契约违反

**文件**: `TuneHaven/Domain/Entities/Playlist.swift` ~行 17-24

**问题**: `==` 比较 id + name + songCount + coverImagePath + updatedAt，但 `hash(into:)` 只 hash `id`。两个 id 相同但 name 不同的 Playlist 会 hash 相同但不相等，违反 `Hashable` 契约。

**影响**: 在 `Set<Playlist>` 或 `Dictionary<Playlist, ...>` 中可能出现意外行为。SwiftUI 的 `ForEach` 依赖正确的 identity。

**建议**: 要么 `==` 也只比较 id，要么 `hash(into:)` 也 hash 所有比较字段。

---

#### 7. [🔴] WebDAVClient: 逐字节写入性能极差

**文件**: `TuneHaven/Core/Network/WebDAVClient.swift` ~行 140-142

**问题**: `for try await byte in asyncBytes` 循环中，每个字节都创建 `Data([byte])` 并调用 `handle.write()`。

**影响**: 下载大文件时产生大量内存分配和 I/O 系统调用，速度极慢。

**建议**: 使用缓冲区（如 64KB），批量写入。

---

#### 8. [🔴] PlaybackService.loadAndPlay: 文件不存在时 currentSong 未重置

**文件**: `TuneHaven/Domain/Services/PlaybackService.swift` ~行 285-293

**问题**: `loadAndPlay` 在检查文件存在之前就设置了 `currentSong = song`。如果文件不存在，方法 return 但 `currentSong` 仍指向该歌曲。

**影响**: UI 显示一首无法播放的歌曲为"当前播放"，迷你播放器和播放页面显示不正确。

**建议**: 将 `currentSong = song` 移到文件存在性检查之后，或在检查失败时重置 `currentSong`。

---

#### 9. [🔴] PlayerSheets: PlaylistCoverPickerSheet 相册选择功能未实现

**文件**: `TuneHaven/Presentation/Sheets/PlayerSheets.swift` ~行 127

**问题**: "从相册选择" 按钮设置 `showImagePicker = true`，但该文件中没有绑定任何 `.sheet` 或 `PhotosPicker` 来响应此状态变化。

**影响**: 用户点击"从相册选择"歌单封面无任何反应。

**建议**: 添加 `PhotosPicker` 或 `.sheet(isPresented: $showImagePicker)` 实现。

---

### 🟡 建议级（强烈建议修复）

#### 10. [🟡] ErrorLogger / AppLogger: 并发文件写入无序列化

**文件**: `TuneHaven/App/AppError.swift` ~行 131-141, 217-227

**问题**: `appendToLog` / `appendToFile` 执行文件读写没有锁或串行队列保护。多线程并发日志可能导致内容交错或损坏。

**建议**: 使用 DispatchQueue 或 actor 序列化日志写入。

---

#### 11. [🟡] CoreDataStack: performBackground save 失败时通知 observer 泄漏

**文件**: `TuneHaven/Core/Persistence/CoreDataStack.swift` ~行 49-57

**问题**: `addObserver` 之后如果 `backgroundContext.save()` 抛出异常，跳到 catch 分支，`removeObserver(token)` 不会执行。

**建议**: 使用 `defer { NotificationCenter.default.removeObserver(token) }` 确保清理。

---

#### 12. [🟡] AlbumDetailView: 随机播放按钮逻辑错误

**文件**: `TuneHaven/Presentation/Library/AlbumDetailView.swift` ~行 72-77

**问题**: "随机播放"按钮调用 `cyclePlayMode()` 一次。PlayMode 顺序是 `sequential → repeatOne → repeatAll → shuffle`，所以如果当前是 sequential，一次 cycle 只到 repeatOne，并非 shuffle。

**建议**: 直接设置 `playback.playMode = .shuffle` 而不是 cycle。

---

#### 13. [🟡] LibraryMainView: 搜索 Task 无取消机制导致竞态

**文件**: `TuneHaven/Presentation/Library/LibraryMainView.swift` ~行 272-277

**问题**: `performSearch` 每次创建新 `Task` 但不取消旧 Task。较慢的搜索可能在新搜索之后完成，覆盖正确结果。

**建议**: 使用 `.task(id:)` 或手动管理 `Task` 取消。

---

#### 14. [🟡] SearchService: 搜索结果中 album 名称使用 `/` 分割会被截断

**文件**: `TuneHaven/Domain/Services/SearchService.swift` ~行 49-55

**问题**: Album key 用 `"\(artist)/\(album)"` 构建，后续用 `split(separator: "/").last` 提取 album 名称。艺术家或专辑名含 `/` 时会得到错误结果。

**建议**: 使用 tuple 或结构体作为 key，避免字符串拼接。

---

#### 15. [🟡] WallpaperManager: 磁盘加载失败时状态不一致

**文件**: `TuneHaven/App/Theme/WallpaperManager.swift` ~行 12-16

**问题**: `useCustomWallpaper = true` 但 `loadFromDisk()` 返回 nil 时，`currentWallpaper` 为 nil 而 `useCustomWallpaper` 仍为 true。ThemeBackgroundView 根据此状态显示主题背景而非壁纸，但标志仍显示已启用壁纸。

**建议**: 加载失败时重置 `useCustomWallpaper = false`。

---

#### 16. [🟡] CoverImageView: body 中同步磁盘读取

**文件**: `TuneHaven/Presentation/Common/CoverImageView.swift`

**问题**: `ImageCacheManager.image(forKey:)` 可能在 SwiftUI body 求值时同步从磁盘读取图片，阻塞主线程。在列表滚动场景下影响帧率。

**建议**: 使用异步图片加载 + @State 缓存模式。

---

#### 17. [🟡] FileStorageService.sha256: 大文件全量加载到内存

**文件**: `TuneHaven/Core/Storage/FileStorageService.swift` ~行 12-15

**问题**: `Data(contentsOf:)` 将整个文件加载到内存。导入 500MB 文件时可能 OOM。

**建议**: 使用流式 SHA256 计算（`CC_SHA256_Update` 分块读取）。

---

#### 18. [🟡] Domain 层架构违规: Service 直接依赖具体实现

**文件**: 多个 Domain/Services/*.swift

**问题**: `PlaybackService`、`MusicLibraryService`、`PlaylistService`、`SearchService`、`LyricsService` 等直接 import UIKit、AVFoundation，并引用 `CoreDataSongRepository`、`CoreDataPlaylistRepository` 等具体实现类。

**影响**: 违反 Clean Architecture 依赖方向规则（Domain 不应依赖 Data/Core 层具体实现）。单元测试无法注入 Mock。

**建议**: 通过 Repository Protocol 注入，将具体依赖提升到 App 层的组合根。

---

#### 19. [🟡] CoreDataPlaylistRepository.addSongs: sortOrder 不连续

**文件**: `TuneHaven/Data/Repositories/CoreDataPlaylistRepository.swift` ~行 108-115

**问题**: `enumerated()` 索引包含被跳过的重复项，导致 sortOrder 不连续（如 10, 12, 14 而非 10, 11, 12）。

**建议**: 使用独立计数器只在实际添加时递增。

---

#### 20. [🟡] CoreDataSongRepository: softDelete 批量操作中重复文件移动

**文件**: `TuneHaven/Data/Repositories/CoreDataSongRepository.swift` ~行 108-122

**问题**: 批量删除共享同一 fileHash 的歌曲时，每首歌都会尝试移动文件，但第一次移动后文件已不存在，后续移动失败，生成空 `tempPath` 影响撤销功能。

**建议**: 在 `filesToMove` 中按 hash 去重。

---

#### 21. [🟡] PlaylistMapper: 使用 fetch 而非 count(for:) 统计歌曲数

**文件**: `TuneHaven/Data/Mappers/PlaylistMapper.swift` ~行 39-54

**问题**: 系统歌单（收藏/最近播放）和普通歌单都通过 `fetch` + `.count` 统计歌曲数，会将所有匹配实体加载到内存。

**建议**: 使用 `ctx.count(for: request)` 替代，避免不必要的对象实例化。

---

#### 22. [🟡] AudioMetadataParser: formatDescriptions 强制转换可能崩溃

**文件**: `TuneHaven/Data/MetadataParser/AudioMetadataParser.swift` ~行 103-104

**问题**: `desc as! CMAudioFormatDescription` 对非音频 track 的 formatDescription 会 crash。

**建议**: 使用 `as?` 可选绑定。

---

#### 23. [🟡] LyricsSearchView: performSearch 中 @State 更新可能不在主线程

**文件**: `TuneHaven/Presentation/Player/LyricsSearchView.swift` ~行 387-406

**问题**: `Task` 中 `await` 之后修改 `@State` 属性（results, isSearching 等），如果 async 方法不保证主线程返回，UI 更新不安全。

**建议**: 使用 `@MainActor` 标注或 `await MainActor.run {}`。

---

### 🟢 优化级（建议优化）

#### 24. [🟢] TuneHavenCore 包: 未接入项目，代码与主工程严重重复且偏差

**问题**: 整个 TuneHavenCore SPM 包没有被 Xcode 项目引用，无 `import TuneHavenCore`。包内代码与主工程实体/服务存在多处偏差（Playlist 缺少 autoCoverHash、AudioFormat 列表不同、PlayQueueService.moveInQueue 缺少 currentIndex 修复）。包的 Package.swift 测试目标路径不存在，`swift build` 无法编译。

**建议**: 要么正式接入并统一代码，要么删除避免维护混乱。

---

#### 25. [🟢] NavigationBackgroundFixer: 生产代码中使用 print

**文件**: `TuneHaven/Presentation/Common/NavigationBackgroundFixer.swift` ~行 45

**建议**: 替换为 `AppLogger` 或移除。

---

#### 26. [🟢] SheetDestination.id: addToPlaylist 身份冲突

**文件**: `TuneHaven/App/Navigation/AppDestination.swift` ~行 35-36

**问题**: `.addToPlaylist(ids)` 的 id 只使用 `ids.first?.uuidString`，不同的歌曲选择集合可能产生相同 id，导致 SwiftUI sheet 身份冲突。

**建议**: 使用完整 ids 的 hash 或拼接。

---

#### 27. [🟢] QRCodeGenerator: 每次调用创建新 CIContext

**文件**: `TuneHaven/Core/Utils/QRCodeGenerator.swift` ~行 8

**建议**: 缓存 CIContext 实例复用。

---

#### 28. [🟢] Color+Hex: 无效 hex 静默返回黑色

**文件**: `TuneHaven/App/Theme/Color+Hex.swift` ~行 7-20

**建议**: 在 DEBUG 模式下 assertionFailure 提示设计 token 错误。

---

#### 29. [🟢] SongRow: TimeInterval 扩展定义在 View 文件中

**文件**: `TuneHaven/Presentation/Common/SongRow.swift` ~行 111-123

**问题**: `TimeInterval.formattedTime` 全局扩展定义在 Presentation 文件中，可能与其他模块冲突。

**建议**: 移到 Utils 或 Domain 层的独立文件。

---

#### 30. [🟢] 部分主题颜色硬编码

**文件**: 多个 Presentation 文件

**问题**: `SnackbarView` 的 `.white` 文本色、`PlaceholderCoverView` 的 `.white.opacity(0.8)`、`LibraryMainView` 标签选中时的 `.white`、`AlbumDetailView` 的 `.black.opacity(0.15)` 阴影等未使用 palette token。

**建议**: 统一使用 `palette` 中的语义化颜色。

---

#### 31. [🟢] RootTabView: 三个 Tab 始终保持在视图层级中

**文件**: `TuneHaven/Presentation/Root/RootTabView.swift` ~行 19-32

**问题**: 使用 opacity + allowsHitTesting 切换 Tab，隐藏的 Tab 仍可能响应 @Published 属性变化触发重绘。

**建议**: 这是有意设计（避免 NavigationStack 状态丢失），但可考虑对非活跃 Tab 冻结某些订阅。

---

#### 32. [🟢] SearchResultView: 搜索结果 prefix 截断但标题显示完整数量

**文件**: `TuneHaven/Presentation/Library/SearchResultView.swift` ~行 18-19

**问题**: Section 标题显示 "歌曲 (50)" 但只显示前 10 条，用户可能误以为只有 10 首匹配歌曲。

**建议**: 显示为 "歌曲 (显示 10/50)" 或提供"查看全部"入口。

---

#### 33. [🟢] MiniPlayerBar: 未使用的 @EnvironmentObject themeManager

**文件**: `TuneHaven/Presentation/Common/MiniPlayerBar.swift` ~行 6

**建议**: 移除未使用的声明。

---

#### 34. [🟢] AllSongsView: pendingDeleteToken 写入但从未读取

**文件**: `TuneHaven/Presentation/Library/AllSongsView.swift` ~行 14-15

**建议**: 移除死代码或接入撤销 UI。

---

#### 35. [🟢] SearchResultView: tab 参数未使用

**文件**: `TuneHaven/Presentation/Library/SearchResultView.swift` ~行 6

**建议**: 移除参数或实现按标签页过滤。

---

---

## 修改记录

（第 1 轮，无历史修改记录）

---

## 统计


| 级别     | 数量     |
| ------ | ------ |
| 🔴 阻塞  | 9      |
| 🟡 建议  | 14     |
| 🟢 优化  | 12     |
| **合计** | **35** |


---

## 建议修复优先级

### P0（立即修复 - 功能性 Bug）

1. SongMapper LyricsSource 映射丢失 (#1)
2. SongListView 收藏列表 PlayContext 错误 (#2)
3. PlaybackService 文件不存在时 currentSong 未重置 (#8)
4. Playlist Hashable 契约违反 (#6)

### P1（尽快修复 - 用户体验 / 安全）

1. WiFi 上传路径穿越 (#5)
2. WiFi 上传大文件截断 (#4)
3. AudioEngine.play() 标准化 (#3)
4. WebDAV 逐字节写入性能 (#7)
5. AlbumDetailView 随机播放逻辑 (#12)
6. PlayerSheets 相册选择未实现 (#9)

### P2（计划修复 - 稳定性 / 性能）

1. ErrorLogger 并发写入 (#10)
2. CoreDataStack observer 泄漏 (#11)
3. 搜索竞态条件 (#13)
4. SHA256 大文件 OOM (#17)
5. CoverImageView 同步磁盘读取 (#16)

### P3（优化提升 - 架构 / 代码质量）

1. Domain 层架构违规 (#18)
2. TuneHavenCore 包处理 (#24)
3. 其余 🟢 优化项

