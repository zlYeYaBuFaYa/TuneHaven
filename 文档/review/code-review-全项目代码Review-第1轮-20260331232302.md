# 代码 Review：全项目代码 Review - 第 1 轮（已验证）

> 日期：2026-03-31 | 类型：AI 自审 + 源码交叉验证 | 范围：全项目 195 个 Swift 文件
> 验证方式：逐条读取对应源文件，确认问题真实存在

## 结论：不通过（存在阻塞级问题需修复）

---

## 总览

| 层 | 文件数 | 🔴 阻塞 | 🟡 重要 | 🟢 轻微 |
|---|--------|---------|---------|---------|
| App | 23 | 0 | 3 | 2 |
| Core | 27 | 0 | 8 | 5 |
| Domain | 42 | 1 | 7 | 5 |
| Data | 9 | 0 | 6 | 3 |
| Presentation | 72 | 0 | 12 | 12 |
| **合计** | **195** | **1** | **36** | **27** |

> **验证说明**：原报告含 14 个 🔴、113 个 🟡、69 个 🟢。经两轮源码交叉验证，共移除 10 个误报（含二次验证移除的 B5/C3/C9/D5），降级 7 个过级问题，修正多处描述不准确的问题，精简为上表。

---

## 🔴 阻塞级问题（1 项，必须修复）

### 1. PlaybackService — 未协调的 Task 竞态

**文件**: `Domain/Services/PlaybackService.swift`
**行号**: 109, 124, 136

**验证**: ✅ 源码确认

```swift
// Line 109 — togglePlayPause()
Task { await loadAndPlay(song: song) }

// Line 124 — playNext()
Task { await loadAndPlay(song: nextItem.song) }

// Line 136 — playPrevious()
Task { await loadAndPlay(song: prevItem.song) }
```

**问题**: 三个方法均创建未跟踪的 `Task`。`loadAndPlay` 内部有 `await engine.load(url:)`（line 295）作为挂起点。快速连续操作时，多个 Task 可交错执行：
1. 用户快速双击下一曲 → 创建 Task A 和 Task B
2. Task A 执行到 `await engine.load()` 挂起
3. Task B 开始执行，覆盖 `currentSong`（line 290）
4. Task A 恢复后继续设置 `engine.play()`，播放的是 Task A 的歌曲但 currentSong 已被 Task B 覆盖

**建议**: 引入 `private var loadTask: Task<Void, Never>?`，每次操作前 `loadTask?.cancel()` 取消前一个 Task。

---

## 🟡 重要问题（36 项，按类别分组）

### A. 线程安全（7 项）

| # | 文件 | 行号 | 验证 | 问题 |
|---|------|------|------|------|
| A1 | PlaybackService.swift | 336-349 | ✅ | Combine sink 闭包是 `@Sendable`，`Task { @MainActor }` 从类型系统角度必要，但每次事件都创建新 Task 有调度开销。可优化为 `.receive(on: DispatchQueue.main)` + `MainActor.assumeIsolated` |
| A2 | MusicLibraryService.swift | 106-124 | ✅ | `scheduleCommit` 中 Timer 闭包是 `@Sendable` 且内含 `await` 调用，`Task { @MainActor }` 是必需的（提供 async 上下文 + MainActor 隔离）。但可考虑用 `Task.detached` + `@MainActor` 函数替代以减少嵌套 |
| A3 | SleepTimerService.swift | 32-33 | ✅ | Timer 闭包是 `@Sendable`，`Task { @MainActor }` 从类型系统角度必要。但若 `tick()` 为同步方法，每秒创建新 Task 有不必要开销，可改用 `MainActor.assumeIsolated` |
| A4 | LyricsService.swift | 196-199 | ✅ | `nonisolated func hasExternalLyrics` 访问可能非线程安全的 `fileStorage`。Swift 6 严格并发下会编译警告 |
| A5 | SearchService.swift | 27-49 | ✅ | `Song` 和 `Metadata` 未显式声明 `Sendable`。所有属性均为 Sendable 类型，同模块内编译器可隐式推断，但显式声明是更好的实践 |
| A6 | CoreDataSongRepository.swift | 318-408 | ✅ | `fetchRecentlyPlayed` 在主线程 `viewContext.perform` 中执行 4 次独立 fetch + 映射构建 |
| A7 | ShareService.swift | 569-578 | ✅ | 直接使用 `UIApplication.shared`，未通过协议抽象。Domain 层不应依赖 UIKit |

### B. 性能（7 项）

| # | 文件 | 行号 | 验证 | 问题 |
|---|------|------|------|------|
| B1 | CoreDataSongRepository.swift | 410-474 | ✅ | `fetchArtistGroups/fetchAlbumGroups` 全量加载后在内存分组，未用 CoreData `dictionaryResultType` + `propertiesToGroupBy` 做 SQL 层 GROUP BY |
| B2 | CoreDataSongRepository.swift | 355 | ✅ | `fetchLimit = (startIndex + pageSize) * 10`，翻页偏移大时 fetchLimit 急剧增长 |
| B3 | AudioMetadataParser.swift | 9-70 | ✅ | 4 个 async 解析步骤串行执行，可用 `async let` 并行化 |
| B4 | ShareService.swift | 419-422 | ✅ | `buildSongIndex()` 加载全库歌曲构建匹配字典，大型库内存压力大。两次调用均有必要（分析+关联），但可用增量匹配优化 |
| B5 | LyricsPageView.swift | 74-76 | ✅ | `.onChange(of: engine.currentTime)` 频繁触发。但经源码确认：`currentLineIndex` 状态仅在行切换时变化，LazyVStack 仅渲染可见行。卡拉 OK 进度条在当前行 `lineProgress` 读取 `engine.currentTime` 是必要的。影响可控 |
| B6 | WebDAVService.swift | 136-178 | ✅ | `downloadAndImport` 串行下载，无并发支持。大量文件时速度慢 |
| B7 | BatchAddSongsView.swift | 96-97 | ✅ | `recomputeFiltered` 中 `Dictionary(grouping:)` + `.sorted` 在主线程同步执行 |

### C. 逻辑正确性（7 项）

| # | 文件 | 行号 | 验证 | 问题 |
|---|------|------|------|------|
| C1 | PlaybackService.swift | 74-84 | ✅ | `play(song:in:)` 未显式处理 `.error` 状态。当 engine.state == .error 时，同一首歌重播会 fallthrough 到 buildQueue + loadAndPlay 路径，行为正确但缺少显式分支和注释说明，属代码清晰度问题 |
| C2 | PlaybackService.swift | 275-295 | ✅ | `loadAndPlay` 中 `await engine.load(url:)` 后未检查歌曲是否仍为用户期望的歌曲（期间可能已被 playNext 替换） |
| C3 | CoreDataSongRepository.swift | 108-142 | ✅ | `softDelete` 中文件移至 pending_delete 操作在 `performBackground` 闭包外（line 134）。App 在 DB save 后、文件移动前崩溃时，DB 标记 softDeleted=true 但文件仍在原位 |
| C4 | CoreDataSongRepository.swift | 141 | ✅ | `moveToPendingDelete` 失败时追加空 `tempPath` 条目。`undoDelete` 中 `!file.tempPath.isEmpty` 守卫会跳过恢复（line 164），但原文件仍在原位，不会丢失 |
| C5 | CoreDataPlaylistRepository.swift | 117 | ✅ | `addSongs` 中 `propertiesToFetch = ["songId", "sortOrder"]` 对默认 `managedObjectResultType` 无效 |
| C6 | SongMapper.swift | 94 | ✅ | `updateEntity` 无条件设置 `softDeleted = false`。重导入相同文件会"复活"已删除歌曲。可能是预期行为但缺少注释 |
| C7 | LyricsPageView.swift | 14-15 | ✅ | 用户手动滚动后 `isUserScrolling = true`，3 秒超时后才恢复自动滚动。切歌时不会重置此状态，用户可能错过新歌位置 |

### D. 错误处理（4 项）

| # | 文件 | 行号 | 验证 | 问题 |
|---|------|------|------|------|
| D1 | ImportService.swift | 160-161 | ✅ | `try? await coverProcessor.processSongCover(...)` 静默吞噬封面处理错误。歌曲仍被保存但无封面 |
| D2 | ShareService.swift | 156-158 | ✅ | 磁盘空间不足仅记录日志，未通过 `ShareAnalysis` 向 UI 传递空间不足信息 |
| D3 | CoreDataSearchHistoryRepository.swift | 62-64 | ✅ | `saveHistory/deleteHistory/clearHistory` 错误通过 ErrorLogger 记录日志，但不向调用方传播（函数返回 Void 不 throw），调用方无法得知操作失败 |
| D4 | CoreDataSongRepository.swift | 18 | ✅ | `fetchAll` 在 `performFetch` 辅助方法中通过 ErrorLogger 记录错误后返回空数组，调用方无法区分"无数据"和"查询失败" |

### E. 架构合规（4 项）

| # | 文件 | 行号 | 验证 | 问题 |
|---|------|------|------|------|
| E1 | FullEnvironmentModifier.swift | 1-49 | ✅ | 所有视图强制依赖全部 8 个 Service，违反接口隔离。新增 Service 时所有接收该 modifier 的视图都受影响 |
| E2 | CoreDataPlaylistRepository.swift | 355-370 | ✅ | `maxSortOrder` 扩展定义在此文件底部但被 `CoreDataPlaylistGroupRepository` 使用，跨文件隐式依赖 |
| E3 | PlaylistMapper.swift | — | ✅ | 缺少 `toEntity`/`updateEntity`，Repository 创建 PlaylistEntity 时直接操作 entity 属性（如 CoreDataPlaylistRepository.swift L61-75） |
| E4 | PlaylistGroupMapper.swift | — | ✅ | 同上，缺少 `toEntity` |

### F. 内存管理（3 项）

| # | 文件 | 行号 | 验证 | 问题 |
|---|------|------|------|------|
| F1 | ShareService.swift | 31-34 | ✅ | `sharedSongs` + `sharedPlaylists` + `songIndex` 三份数据同时驻留内存。对大型音乐库（数千首），分享会话期间内存占用显著 |
| F2 | MusicLibraryService.swift | 106-124 | ✅ | `undoTimers: [UUID: Timer]` 通过 RunLoop 强引用。Timer 30 秒后会在回调中自行清理（removeValue），非真正泄漏，但快速连续删除多组歌曲时 30 秒窗口内可短暂累积多个 Timer |
| F3 | AudioMetadataParser.swift | 21/131 | ✅ | `ParsedMetadata.coverImageData` 可包含 MB 级图片数据。批量导入时连续创建 ParsedMetadata 可能内存峰值 |

### G. 安全（2 项）

| # | 文件 | 行号 | 验证 | 问题 |
|---|------|------|------|------|
| G1 | WebDAVAccountStore.swift | 40-52 | ✅ | `deleteAccount` 使用 `queue.async`（fire-and-forget），密码和账户删除非原子操作。App 崩溃可能导致 Keychain 残留 |
| G2 | WebDAVAccountStore.swift | 16 | ✅ | 账户元数据（URL、用户名）存于 UserDefaults 未加密，越狱设备可读取。密码已安全存于 Keychain（KeychainHelper.saveString），最敏感凭据已保护 |

### G. 数据准确性（2 项）

| # | 文件 | 行号 | 验证 | 问题 |
|---|------|------|------|------|
| H1 | CoreDataPlaylistRepository.swift | 326-350 | ✅ | `batchSongCounts` 聚合查询无 NSPredicate 过滤 softDeleted 歌曲的 PlaylistSongEntity 链接。软删除后歌单计数偏高 |
| H2 | CoreDataPlaylistGroupRepository.swift | 154-175 | ✅ | `batchPlaylistSongCounts` 同上，含 `playlistId IN %@` 过滤但仍未排除 softDeleted 歌曲关联 |

---

## 🟢 轻微问题（27 项，精选）

| # | 文件 | 问题 |
|---|------|------|
| 1 | Song.swift L4 | `unknownArtist`/`unknownAlbum` 硬编码中文，不可本地化 |
| 2 | SongMapper.swift L5 | `int16Nil` 为公开常量，应改 private |
| 3 | Song+Display.swift L8-14 | 手动格式化文件大小，应使用 `ByteCountFormatter` |
| 4 | PlaylistMapper.swift L17 | `entity.desc_` 下划线后缀缺少注释说明原因 |
| 5 | SongMapper.swift L63-69 | `isValidTrackNumber`/`isValidYear` 可见性应降低 |
| 6 | CoreDataSearchHistoryRepository.swift L48 | 历史记录上限硬编码为 10，应提取常量 |
| 7 | AlbumDetailView.swift L91-145 | 自定义歌曲行重复 SongRow 功能，违反 DRY |
| 8 | LibraryMainView.swift L103-134 | 搜索栏与 `SearchBar.swift` 布局结构高度相似，但额外支持 FocusState 和取消按钮。可考虑扩展 `SearchBar` 统一复用 |
| 9 | AllSongsView.swift L125-150 | 删除逻辑与 SongDeletionHelper 重复 |
| 10 | RootTabView.swift L42-63 | fullScreenCover 中重复注入已有 EnvironmentObject |
| 11 | NavigationBackgroundFixer.swift L39-51 | 依赖 SwiftUI responder chain 内部实现 |
| 12 | PlayerControlsBar.swift L52 | 硬编码透明度阈值，缺少设计 token |
| 13 | PlayerProgressBar.swift L27 | 使用 `.clear` 作哨兵值，可选 `Color?` 更清晰 |
| 14 | SongListView.swift L60 | `recentPlayRange == 0 ? 0 : recentPlayRange` 疑似死代码 |
| 15 | SettingsStorageSection.swift L110-116 | `calculateCacheSize()` 与 SettingsView 重复 |
| 16 | WebDAVAccountStore.swift L60-73 | `updateLastConnected` 使用 `queue.async`，非关键但 fire-and-forget |
| 17 | WebDAVService.swift L160-166 | 取消下载后旧进度回调可能用过时索引更新 |
| 18 | SearchService.swift L36-43 | `.artist` Tab 下仅匹配 artist，标题/专辑匹配但 artist 不匹配的结果被排除 |
| 19 | AppleMusicImportViewModel.swift L102 | 封面以 600x600 / JPEG 质量 1.0 提取，大量导入时内存峰值 |
| 20 | ImageCacheManaging.swift L1 | Domain 层 import UIKit，抽象层泄漏 |
| 21 | AlbumGridView.swift L36 | `.onChange(of: songs.count)` 元数据变更不触发刷新 |
| 22 | SearchResultView.swift L133-142 | `playContext(for:)` 对 `.all` Tab 固定使用 `.title` 排序，忽略用户当前排序选项 |
| 23 | CoverImageView.swift L37-41 | `onReceive(NotificationCenter)` 每个 CoverImageView 实例都评估 |
| 24 | SongRow.swift L36-45 | `#available(iOS 17.0, *)` 在 ForEach 每行检查 |
| 25 | CreatePlaylistSheet.swift L178-186 | "创建歌单"后 `dismiss()` 与新 sheet 呈现存在竞态 |
| 26 | ShareSongSelectorView.swift L21-28 | `filteredSongs` 每次视图更新都重新过滤 |
| 27 | UserPreferencesProviding.swift L10-12 | 字典使用 String 键（UUID 字符串），拼写错误导致静默失败 |

---

## 亮点（做得好的地方）

1. **DI 容器设计** — AppDIContainer 统一管理 Service 生命周期，注入清晰
2. **协议抽象** — Domain 层 19 个协议实现良好的依赖反转
3. **错误体系** — AppError 33 种类型 + ErrorLogger 结构化日志
4. **主题系统** — 4 套主题 + EnvironmentKey 注入，设计优雅
5. **安全实践** — WebDAV HTTP/HTTPS 验证、相机权限处理、沙盒路径管理
6. **CoreData 双上下文** — viewContext + backgroundContext + 显式合并
7. **零外部依赖** — 纯 iOS SDK，无第三方包风险
8. **Tab 状态保持** — opacity + allowsHitTesting 切换，NavigationStack 状态不丢失

---

## 优先修复建议

### P0 — 必须修复
1. **PlaybackService Task 竞态**（🔴 #1）— 唯一的真正阻塞级问题

### P1 — 尽快修复
2. **歌单计数 softDeleted 过滤**（H1, H2）— 影响用户看到的歌单歌曲数
3. **WebDAVAccountStore delete 同步化**（G1）— 数据一致性风险
4. **ImportService 封面错误处理**（D1）— 用户不可知封面导入失败

### P2 — 计划修复
5. **DRY 统一** — 搜索栏、歌曲行、删除逻辑、缓存计算
6. **CoreData 聚合优化** — 分组查询用 SQL 层 GROUP BY
7. **Mapper 完善** — 补齐 PlaylistMapper/PlaylistGroupMapper 的 toEntity
8. **环境注入优化** — FullEnvironmentModifier 拆分为按需注入
9. **并发模式优化** — 优化 Timer/Combine sink 中 Task 包装模式、为 Entity 添加 Sendable
