# 代码 Review：全局代码审查（全量迭代后） - 第 1 轮

> 日期：2026-03-22 | 类型：AI 自审 | 范围：全部 120 源文件 + 18 测试文件

## 结论：不通过

| 维度 | 结论 | 说明 |
|------|------|------|
| 逻辑正确性 | ❌ | PlaylistGroupView 导航 Tab 错误；PlaybackState.error 比较语义不当；歌词搜索线程安全问题 |
| 错误处理 | ❌ | 大量 try? 吞错无用户提示；LRCLibAPIClient 错误与 nil 混淆；CoreDataStack 未统一 AppError |
| 安全 | ❌ | ImageCacheManager key 路径注入风险；FileStorageService relativePath 未防 `..` 穿越 |
| 线程安全 | ❌ | LyricsSearchView 异步回主线程缺 MainActor；ImageCacheManager cacheLimitMB 数据竞争 |
| 架构合规 | ❌ | Domain 层 6 个 Service 默认依赖 CoreData* 具体实现，违反 Clean Architecture |
| 代码风格 | ❌ | PlayerView/LyricsView 硬编码 .white；多处 SemanticColor 与 palette 规范不统一 |
| API 设计 | ✅ | Repository 协议粒度合理；Service API 语义清晰 |
| 性能 | ❌ | ImageCacheManager 主线程同步读盘；LyricsView 全量 VStack；搜索全量 filter |
| 内存管理 | ✅ | [weak self]、cancellables 使用规范；无明显循环引用 |
| 可维护性 | ❌ | 测试 mirror 实现与生产脱节；AudioEngineTests 文件名与内容不符；CosmicParticlesBackground 缺失 |

---

## 🔴 阻塞问题（共 10 项，必须修复）

### 🔴-01 Domain 层 Service 默认依赖 Data 层具体实现
- **文件**：`PlaybackService.swift`、`MusicLibraryService.swift`、`ImportService.swift`、`LyricsService.swift`、`PlaylistService.swift`、`PlaylistGroupService.swift`、`SearchService.swift`
- **描述**：init 参数默认值直接引用 `CoreDataSongRepository()`、`CoreDataPlaylistRepository()` 等 Data 层具体类型，Domain 层依赖了 Data 层实现，违反 Clean Architecture「向内依赖抽象」原则
- **建议**：移除默认参数，全部通过 `AppDIContainer` 注入协议类型

### 🔴-02 WebDAVService 直接绑定具体客户端与密钥存储
- **文件**：`WebDAVService.swift`
- **描述**：Domain Service 直接使用 `WebDAVAccountStore.shared`、`WebDAVClient` 具体类型
- **建议**：定义 `WebDAVClientProtocol` / `AccountSecretsProviding` 协议，在 App 层组装

### 🔴-03 PlaylistGroupView 导航 Tab 错误
- **文件**：`PlaylistGroupView.swift`
- **描述**：`router.navigate(to: .playlistDetail(id:), in: .library)` 在歌单 Tab 场景下会切到资料库 Tab 并写入 libraryPath，用户关闭 sheet 后落在错误 Tab
- **建议**：改为 `in: .playlist`

### 🔴-04 PlayerView/LyricsView 硬编码颜色 .white
- **文件**：`PlayerView.swift`（约 595 行）、`LyricsView.swift`（约 447 行）
- **描述**：播放/暂停按钮使用 `.foregroundColor(.white)` 硬编码，违反「禁止硬编码颜色」规则
- **建议**：使用 palette 语义色（如 `onPrimary` / `inverseText`），需在 ThemeColorPalette 补充对应字段

### 🔴-05 PlayerView 未通过 Environment 获取 themePalette
- **文件**：`PlayerView.swift`
- **描述**：使用 `themeManager.palette` 而非 `@Environment(\.themePalette)` 取色，与统一规范不一致
- **建议**：改为 `@Environment(\.themePalette) private var palette`

### 🔴-06 WiFiTransferServer receive 回调 weak self 导致连接挂死
- **文件**：`WiFiTransferServer.swift`（约 130-167 行）
- **描述**：`receive` 回调中 `guard let self else { return }` 后若 self 已释放，不再继续 `headerReadLoop()`，连接可能挂起不收数据
- **建议**：用本地强引用完成该次请求的生命周期，或在无 self 时 `connection.cancel()`

### 🔴-07 CosmicParticlesBackground.swift 文件缺失
- **文件**：`TuneHaven/App/Theme/Backgrounds/CosmicParticlesBackground.swift`
- **描述**：项目文档和技术设计文档引用该文件，但仓库中不存在；cosmic_tech 主题的粒子背景动画无法生效
- **建议**：补全实现或更新文档移除引用

### 🔴-08 MusicLibraryServiceTests mirror 实现与生产脱节
- **文件**：`MusicLibraryServiceTests.swift`
- **描述**：测试文件中私有复制了 `groupSongsByArtist`/`groupSongsByAlbum` 的逻辑，测的是测试副本而非真实 Service，生产代码改坏测试仍绿
- **建议**：改为调用真实 Service 方法或提取纯函数到 Domain 层并单测

### 🔴-09 P2FixTests AlbumKey 使用测试内局部类型
- **文件**：`P2FixTests.swift`
- **描述**：`AlbumKeySeparatorTests` 使用测试内局部 `struct AlbumKey`，不是业务中的真实类型，无法防止回归
- **建议**：改为使用真实业务类型

### 🔴-10 AudioEngineTests.swift 文件名与内容严重不符
- **文件**：`AudioEngineTests.swift`
- **描述**：文件名为 AudioEngine 测试，内容却是 AppError 播放相关 + PlaybackState 枚举测试，无真实音频引擎测试
- **建议**：重命名为 `PlaybackStateTests.swift` 或补全真实 AudioEngine 测试

---

## 🟡 建议问题（共 52 项，强烈建议修复）

### Core 层（11 项）

| # | 文件 | 问题 | 建议 |
|---|------|------|------|
| 01 | AudioEngine.swift | PlaybackState `.error` 比较恒为 true，UI 可能误判 | 对 .error 使用关联值比较 |
| 02 | AudioEngine.swift | `load` 前未显式 stop/removeTimeObserver，快速连续 load 可能重叠 | 统一入口先 stop 再加载 |
| 03 | AudioEngine.swift | `play()` ensureActive 失败未置 state 为 .error | 与 load 对齐失败行为 |
| 04 | NowPlayingManager.swift | 未保存 addTarget 返回值，重复调用依赖全清 | 文档约定仅调一次或精确移除 |
| 05 | ImageCacheManager.swift | 主线程同步读磁盘 | 异步加载 + 占位显示 |
| 06 | ImageCacheManager.swift | cacheLimitMB 主线程改、fileQueue 读，数据竞争 | 统一串行上下文或 actor |
| 07 | ImageCacheManager.swift | key 未规范化，含 `../` 可能路径越界 | 禁止路径分隔符或仅用安全字符 |
| 08 | WiFiTransferServer.swift | 大文件整体读入内存解析 multipart | 流式解析或限制单文件最大字节 |
| 09 | WiFiTransferServer.swift | `body.data(using: .utf8)!` 强制解包 | guard let + 500 响应回退 |
| 10 | LRCLibAPIClient.swift | `components.url` 失败 return nil 与 throw AppError 不一致 | 改为 throw |
| 11 | LRCLibAPIClient.swift | HTTP 错误无状态码信息 | 带上 statusCode |

### Data 层（9 项）

| # | 文件 | 问题 | 建议 |
|---|------|------|------|
| 12 | CoreDataSongRepository.swift | 多处 `try?` fetch 失败被吞 | ErrorLogger + AppError.databaseError |
| 13 | CoreDataSongRepository.swift | fetchRecentlyPlayed 分页在高度重复播放时不可靠 | 数据库侧去重分页 |
| 14 | CoreDataSongRepository.swift | fetchArtistGroups/fetchAlbumGroups 全表拉取 | 聚合 fetch 或缓存 |
| 15 | CoreDataPlaylistRepository.swift | reorder/reorderSongs 部分 ID 更新一致性 | 校验或文档说明 |
| 16 | CoreDataPlaylistGroupRepository.swift | `entity.id!` 强制解包 | guard let + throw |
| 17 | CoreDataSearchHistoryRepository.swift | 持久化失败完全忽略无日志 | ErrorLogger 记录 |
| 18 | SongMapper.swift | `0` 视为无效，track/year=0 场景会丢数据 | 与元数据约定对齐 |
| 19 | AudioMetadataParser.swift | catch 仅设 isIncomplete 无日志 | ErrorLogger 记录 |
| 20 | WebDAVAccountStore.swift | loadAccounts 与 save/delete 不走同一队列 | 统一串行队列或 actor |

### Domain 层（10 项）

| # | 文件 | 问题 | 建议 |
|---|------|------|------|
| 21 | PlaybackService.swift | loadAndPlay `try?` 吞掉 recordPlay 失败 | try await + ErrorLogger |
| 22 | PlaybackService.swift | 文件不存在连续 playNext 无上限 | 连续失败计数 + 停止 |
| 23 | PlayQueueService.swift | shuffle 全队列已播放时无下一轮策略 | 与 repeatAll 统一重置 |
| 24 | MusicLibraryService.swift | Token 用 songIds.first 做 Timer key 可能覆盖 | 增加 UUID 做 key |
| 25 | SearchService.swift | tab 参数未参与过滤，可能误导 | 按 tab 过滤或移除参数 |
| 26 | SearchService.swift | allSongs 全量 filter 大库卡主线程 | 后台 Task.detached 或索引 |
| 27 | SleepTimerService.swift | Timer 在 current RunLoop 滚动时可能暂停 | .common mode |
| 28 | CloudDriveProvider.swift | Domain 依赖 UIKit UIApplication | 移到 Presentation/App 层 |
| 29 | LyricsService.swift | startAccessingSecurityScopedResource false 直接失败 | 文档或 fallback |
| 30 | LibraryTypes.swift | ArtistGroup/AlbumGroup id 由名称拼接可能冲突 | UUID 或文档约定 |

### App 层（7 项）

| # | 文件 | 问题 | 建议 |
|---|------|------|------|
| 31 | AppDelegate.swift | `"theme_style"` 字面量与 AppStorageKey 重复 | 统一常量 |
| 32 | AppDelegate.swift | 默认主题 `"mint_breeze"` 与 ThemeManager `"cloud_white"` 不一致 | 共用默认 id |
| 33 | AppDIContainer.swift | 所有 Service 同步创建，冷启动成本集中 | 非首屏依赖考虑 lazy |
| 34 | ThemeManager.swift | `@AppStorage("theme_style")` 字面量重复 | AppStorageKey |
| 35 | ThemeRegistry.swift | `@unchecked Sendable` 含 SwiftUI Color | 改为 @MainActor |
| 36 | WallpaperManager.swift | saveToDisk 失败静默 | 返回 Bool 或 throws |
| 37 | Color+Hex.swift | 非法 Hex 退化为黑色难发现 | DEBUG 洋红色 |

### Presentation 层（15 项）

| # | 文件 | 问题 | 建议 |
|---|------|------|------|
| 38 | MiniPlayerBar.swift | 未使用 libraryService 但触发重绘 | 删除未使用的 @EnvironmentObject |
| 39 | CoverImageView.swift | 异步缓存写入后不通知 SwiftUI 刷新 | 订阅缓存变化或强制 id |
| 40 | QRCodeView.swift | 主线程生成 QR 大尺寸掉帧 | 后台生成 |
| 41 | LyricsSearchView.swift | 异步完成改 @State 未保证 MainActor | await MainActor.run |
| 42 | LyricsView.swift | VStack 全量歌词行非懒加载 | LazyVStack |
| 43 | LyricsView.swift | currentLineIndex 线性扫描每次 time 更新 | 二分或缓存上次索引 |
| 44 | SearchResultView.swift | tab 参数未使用，播放上下文固定 allSongs | 按 tab 构建上下文 |
| 45 | PlayQueueView.swift | 重复 song.id 时 firstIndex 高亮错误行 | 用队列项自身 id |
| 46 | PlaylistMainView.swift | 删除/重排 try? 失败无提示 | 用户提示 |
| 47 | PlaylistDetailView.swift | 删除歌单失败仍 popToRoot | 失败时不退出 |
| 48 | BatchAddSongsView.swift | addSongs 失败仍 dismiss | 失败时提示 |
| 49 | CloudDriveImportView.swift | fileImporter 未处理 .failure | 补全 failure 分支 |
| 50 | WiFiTransferView.swift | passwordEnabled 本地 State 与 AppStorage 不同步 | 统一 AppStorage |
| 51 | LibraryTabView.swift | 未使用 PlaylistGroupService @EnvironmentObject | 删除 |
| 52 | SettingsAppearanceSection.swift | 主题卡选中勾 .foregroundColor(.white) | palette 语义色 |

---

## 🟢 优化问题（共 30+ 项，主要列举代表性的）

| # | 文件 | 问题 | 建议 |
|---|------|------|------|
| 01 | AudioEngine.swift | seek 未 clamp 到 [0, duration] | 边界约束 |
| 02 | ThumbnailGenerator.swift | `images.count > i` 可读性差 | `i < images.count` |
| 03 | WiFiTransferServer.swift | 多网卡 IP 不确定 | 优先 Wi-Fi 接口 |
| 04 | CoreDataSongRepository.swift | insert 无幂等 | 按 fileHash upsert |
| 05 | CoreDataPlaylistRepository.swift | maxSortOrder 拉全表 | MAX 聚合查询 |
| 06 | Song.swift | 展示文案混在实体 | 迁到 Presentation |
| 07 | Playlist.swift | PagedResult 定义在 Playlist.swift | 移到独立文件 |
| 08 | QueueItem.swift | PlayQueueConstants 仅其他层使用 | 移到使用层 |
| 09 | SongRow.swift | TimeInterval 扩展放在 View 文件 | 移到 Extensions |
| 10 | RootTabView.swift | onAppear debug 日志发布版仍输出 | #if DEBUG |
| 11 | AppErrorTests.swift | 固定列表不随枚举扩展自动失败 | allCases 或反射 |
| 12 | LyricsTextTransformTests.swift | 仅 3 条用例 | 补充空串、长文本等 |
| 13 | SearchServiceTests.swift | 全用 tab: .all | 覆盖不同 tab |
| 14 | ThemeTests.swift | Color hex 不断言颜色分量 | 验证 RGB 值 |

---

## 测试覆盖评估

### 已覆盖模块
AppError、PlayQueueService、SearchService、LyricsService（LRC 解析）、FileStorageService、AudioFormat、ThemeRegistry、WebDAV XML 解析、工具类扩展

### 缺失覆盖的重要模块
- AudioEngine（真实音频链路）
- CoreData Repository（CRUD/迁移/双上下文）
- ImportService（全流程）
- AudioMetadataParser
- PlaybackService
- Presentation/ViewModel 行为
- 网络客户端（LRCLib/WebDAV）

### 测试质量评分：6.5/10

---

## 修复优先级建议

1. **P0（阻塞）**：🔴-03 导航 Tab 错误 → 🔴-06 WiFi 连接挂死 → 🔴-04/05 硬编码颜色
2. **P1（架构）**：🔴-01/02 Domain 依赖治理 → 🔴-07 缺失文件
3. **P2（质量）**：🟡 错误处理统一 → 🟡 线程安全 → 🟡 性能优化
4. **P3（测试）**：🔴-08/09/10 测试修正 → 补充缺失覆盖
