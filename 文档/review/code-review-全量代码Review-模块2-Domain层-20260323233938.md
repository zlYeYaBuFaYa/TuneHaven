# 代码 Review：全量代码 Review — 模块 2 Domain 层

> 日期：2026-03-23 | 类型：AI 自审 | 文件数：34 | 子任务：3
> **修复日期：2026-03-24 | 已修复：17/20 | 延期：3（🟢轻微）**

---

## 统计摘要

| 指标 | 数值 |
|------|------|
| 🔴 阻塞问题 | 3 → ✅ 全部修复 |
| 🟡 重要问题 | 10 → ✅ 全部修复 |
| 🟢 轻微问题 | 7 → ✅ 修复 4 / 延期 3 |
| 总计 | 20 → 已修复 17 |

### 按子任务分布

| 子任务 | 🔴 | 🟡 | 🟢 | 合计 | 已修复 |
|--------|-----|-----|-----|------|--------|
| 2.1 Entities 实体定义 | 0 | 3 | 3 | 6 | 4 |
| 2.2 Repositories 协议定义 | 1 | 2 | 1 | 4 | 4 |
| 2.3 Services 业务服务 | 2 | 5 | 3 | 10 | 9 |

---

## 2.1 Entities 实体定义（9 文件）

| # | 等级 | 状态 | 文件 | 行号 | 维度 | 问题描述 | 建议修复方案 |
|---|------|------|------|------|------|----------|-------------|
| 2.1.1 | 🟡 | ✅ fixed | `Domain/Entities/LibraryTypes.swift` | L10-21, L38-51 | 架构合规 | `ArtistGroup.group(from:)` 和 `AlbumGroup.group(from:)` 在实体类型中包含业务聚合逻辑（遍历歌曲列表、分组统计、排序），违反实体应为纯数据载体的原则。此逻辑属于 Service/UseCase 层 | **已修复**：将 `group(from:)` 静态方法抽取到新建 `Domain/Services/LibraryGrouping.swift`（`LibraryGrouping` 枚举），Entity 只保留数据属性。已更新 `SearchService` 和测试的调用方 |
| 2.1.2 | 🟡 | ✅ fixed | `Domain/Entities/LibraryTypes.swift` | L192-208 | 架构合规 | `UndoToken` 是 `@MainActor class` 放在 Domain Entities 中，`@MainActor` 是 Presentation/线程层面的约束，不应出现在纯 Domain 实体中。且作为引用类型（class）而非值类型（struct）与其他实体风格不一致 | **已修复**：移除 `@MainActor` 约束和 `nonisolated init`，保留 `class` 类型（因 `timerKey` 可变性由 Service 层 `MusicLibraryService` 管理） |
| 2.1.3 | 🟡 | ✅ fixed | `Domain/Entities/Song.swift`, `Domain/Entities/Playlist.swift`, `Domain/Entities/QueueItem.swift`, `Domain/Entities/PlaylistGroup.swift` | 多处 | 逻辑正确性 | 自定义 `Equatable` 和 `Hashable` 仅比较 `id`，当属性变更时（如 `song.isFavorite` 切换），SwiftUI 的 `List`/`ForEach` diff 可能无法检测到变化，导致 UI 不刷新 | **已修复**：移除 4 个实体类型的自定义 `Equatable`/`Hashable` 实现，由编译器自动合成全属性比较。`buildQueue` 中的 `firstIndex(of:)` 已改为 `firstIndex(where: { $0.id == song.id })` |
| 2.1.4 | 🟢 | deferred | `Domain/Entities/LibraryTypes.swift` | 全文件 | 可维护性 | 文件包含 18 个不相关类型（ArtistGroup、AlbumGroup、SongSortOption、AudioFormat、PlayMode、ImportProgress 等），职责不单一，查找和维护困难 | **延期**：大规模文件拆分为机械性操作，影响范围广但不影响正确性。建议后续独立任务处理 |
| 2.1.5 | 🟢 | deferred | `Domain/Entities/WebDAVFile.swift` | L31-63 | 可维护性 | `WebDAVDownloadTask` 和 `WebDAVImportResult` 与 `WebDAVFile` 实体放在同一文件中，前两者更偏向 Service 层的业务模型而非纯粹的 Domain Entity | **延期**：同上，建议与 2.1.4 合并处理 |
| 2.1.6 | 🟢 | ✅ fixed | `Domain/Entities/Playlist.swift` | L35-38 | 代码风格 | `PlaylistDetail` 未遵循 `Identifiable`，与项目中其他聚合类型（如 `PlaylistGroupDetail`、`ArtistDetail`、`AlbumDetail`）风格不一致 | **已修复**：为 `PlaylistDetail` 添加 `Identifiable` 遵循（`var id: UUID { playlist.id }`） |

**无问题文件**：`PagedResult.swift`、`LRCLibTrack.swift`、`WebDAVAccount.swift`

---

## 2.2 Repositories 协议定义（14 文件）

| # | 等级 | 状态 | 文件 | 行号 | 维度 | 问题描述 | 建议修复方案 |
|---|------|------|------|------|------|----------|-------------|
| 2.2.1 | 🔴 | ✅ fixed | `Domain/Repositories/AudioMetadataParsing.swift` | L4 | 架构合规 | `parse(url:) async -> ParsedMetadata` 返回的 `ParsedMetadata` 类型定义在 `Data/MetadataParser/AudioMetadataParser.swift` 中。Domain 层协议引用 Data 层类型，**严重违反 Clean Architecture 依赖方向**（Domain 不应依赖 Data） | **已修复**：新建 `Domain/Entities/ParsedMetadata.swift`，将 `ParsedMetadata` 结构体定义移至 Domain 层。Data 层的 `AudioMetadataParser` 仅实现协议 |
| 2.2.2 | 🟡 | ✅ fixed | `Domain/Repositories/UserPreferencesProviding.swift` | L4-11 | API 设计 | `playMode` 使用 `Int` 而非 `PlayMode` 枚举，`speedMemoryMode` 使用 `Int` 而非具名枚举，丧失类型安全。调用方需手动 `PlayMode(rawValue:)` 转换，易出错 | **已修复**：① `playMode` 改为 `PlayMode` 枚举类型；② 新增 `SpeedMemoryMode` 枚举（`.global`/`.perSong`），替代 `Int`。已同步更新 `UserPreferencesStore`、`PlaybackService`、Mock |
| 2.2.3 | 🟡 | ✅ fixed | `Domain/Repositories/SearchHistoryRepository.swift`, `Domain/Repositories/WebDAVAccountStoring.swift` | 多处 | 错误处理 | 写操作（`saveHistory`、`deleteHistory`、`clearHistory`、`deleteAccount`、`updateLastConnected`）均为非 throwing 方法，持久化失败时会静默吞掉错误，调用方无法感知失败 | **已修复**：写操作统一加 `throws`。`CoreDataSearchHistoryRepository` 和 `WebDAVAccountStore` 实现已同步更新。`SearchService` 调用方使用 `try?` 保持现有行为 |
| 2.2.4 | 🟢 | ✅ fixed | `Domain/Repositories/CoverImageProcessing.swift` | L5-7 | API 设计 | `processSongCover` 返回 `String?`（可选），`processPlaylistCover` 返回 `String`（非可选），同类操作的返回值风格不一致 | **已修复**：`processSongCover` 返回类型统一为 `String`（非可选），失败时 throw 而非返回 nil。`CoverImageProcessor` 实现已同步更新 |

**无问题文件**：`SongRepository.swift`、`PlaylistRepository.swift`、`PlaylistGroupRepository.swift`、`WebDAVClientProtocol.swift`、`AudioSessionManaging.swift`、`FileImporting.swift`、`FileStorageProviding.swift`、`ImageCacheManaging.swift`、`NowPlayingManaging.swift`

---

## 2.3 Services 业务服务（11 文件）

| # | 等级 | 状态 | 文件 | 行号 | 维度 | 问题描述 | 建议修复方案 |
|---|------|------|------|------|------|----------|-------------|
| 2.3.1 | 🔴 | ✅ fixed | `Domain/Services/PlaybackService.swift` | L1, L6, L19 | 架构合规 | `PlaybackService` 直接依赖 `AudioEngine`（Core 层具体类，`import AVFoundation`），而非通过协议抽象。违反 Clean Architecture 依赖倒置原则，Domain 层不应依赖 Core 层的具体实现 | **已修复**：① 新建 `Domain/Repositories/AudioEngineProtocol.swift`，包含 `AudioEngineProtocol` 协议和 `PlaybackState` 枚举；② `PlaybackService` 依赖改为 `any AudioEngineProtocol`，移除 `import AVFoundation`；③ `AudioEngine` 在 Core 层实现协议，新增 `statePublisher`/`playbackEndedPublisher`/`timeUpdatePublisher` |
| 2.3.2 | 🔴 | ✅ fixed | `Domain/Services/LyricsService.swift` | L1, L159, L184-197, L209, L250-252 | 架构合规 | `LyricsService` 存在多处跨层依赖违规：① `import AVFoundation` 并直接使用 `AVURLAsset` 读取嵌入歌词（L250-252）；② 直接使用 `FileManager.default` 进行文件操作（L159、L184-197）；③ 直接使用 `SandboxPathManager` 静态方法（L186、L209、L250、L271、L284、L301、L317）。Domain 层不应依赖系统框架和 Core 层具体实现 | **已修复**：① 新建 `Domain/Repositories/EmbeddedLyricsReading.swift` 协议 + `Core/Audio/EmbeddedLyricsReader.swift` 实现；② `FileStorageProviding` 扩展增加 `musicFileURL`/`lyricsFileURL`/`lyricsDirectoryURL`/`fileExists(at:)`/`isReadableFile(at:)`/`readStringContents(at:)` 方法；③ `LyricsService` 通过注入的 `fileStorage` 和 `embeddedReader` 访问文件，移除 `import AVFoundation`、`FileManager.default` 和 `SandboxPathManager` 直接调用 |
| 2.3.3 | 🟡 | ✅ fixed | `Domain/Services/PlaybackService.swift`, `Domain/Services/LyricsService.swift` | PlaybackService L271, L273; LyricsService 多处 | 架构合规 | ⚠️ **跨模块：关联 Core 层 + App 层**。`PlaybackService` 直接调用 `SandboxPathManager.musicFileURL()`（Core 层）和 `ErrorLogger.shared.log()`（App 层）。`LyricsService` 直接调用 `SandboxPathManager.lyricsFileURL()`、`SandboxPathManager.lyricsURL` 等。Domain 应通过协议抽象访问路径和日志 | **已修复**：① `SandboxPathManager` 路径功能通过 `FileStorageProviding` 协议扩展提供（同 2.3.2）；② `ErrorLogger.shared.log()` 替换为 `AppLogger` 的 `log.error(AppError, context:)` 方法（已内含 ErrorLogger 调用链） |
| 2.3.4 | 🟡 | ✅ fixed | `Domain/Services/LyricsService.swift` | L3, L8 | 架构合规 | ⚠️ **跨模块：关联 Core 层**。`LyricsService` 依赖 `LRCLibAPIClientProtocol`，该协议定义在 `Core/Network/LRCLibAPIClient.swift` 中。Domain 层引用 Core 层定义的协议，依赖方向反转 | **已修复**：新建 `Domain/Repositories/LyricsAPIProviding.swift` 协议。Core 层 `LRCLibAPIClient` 改为实现 `LyricsAPIProviding`，原 `LRCLibAPIClientProtocol` 保留为 typealias 确保兼容。`LyricsService` 依赖改为 `any LyricsAPIProviding` |
| 2.3.5 | 🟡 | ✅ fixed | `Domain/Services/PlaylistGroupService.swift` | L23 | 逻辑正确性 | `createGroup` 和 `renameGroup` 使用 `.whitespaces` 裁剪输入，而 `PlaylistService.createPlaylist`（L30）使用 `.whitespacesAndNewlines`。用户输入包含换行符时行为不一致，分组名允许包含换行但歌单名不允许 | **已修复**：`createGroup` 和 `renameGroup` 统一使用 `.whitespacesAndNewlines`，与 `PlaylistService` 保持一致 |
| 2.3.6 | 🟡 | ✅ fixed | `Domain/Services/MusicLibraryService.swift` | L132-148 | 架构合规 | `setCacheLimit`、`clearImageCache`、`formattedCacheSize` 是图片缓存管理功能，与音乐库管理（歌曲 CRUD、收藏、删除）职责不相关。违反单一职责原则 | **已修复**：移除 `MusicLibraryService` 中的三个缓存管理方法，将 `imageCache` 属性从 `private` 改为 `let`（公开只读）。Presentation 层 `SettingsStorageSection` 和 `SettingsView` 改为通过 `libraryService.imageCache` 直接访问 `ImageCacheManaging` 协议 |
| 2.3.7 | 🟡 | ✅ fixed | `Domain/Services/SearchService.swift` | L24-48 | 性能 | `search` 方法使用 `Task.detached` 执行搜索，但没有取消机制。用户快速输入时，多个搜索任务可能并发运行，浪费资源且可能导致结果乱序（后发先至覆盖正确结果） | **已修复**：新增 `currentSearchTask: Task<SearchResult, Never>?` 属性，新搜索开始时 `cancel()` 上一个任务，并在 `Task.detached` 内部和结果赋值前检查 `Task.isCancelled` |
| 2.3.8 | 🟢 | ✅ fixed | `Domain/Services/ImportService.swift` | L95 | 代码风格 | `processFile` 方法有 6 个参数（`url`, `overrideName`, `titleOverride`, `artistOverride`, `albumOverride`, `coverDataOverride`），参数列表过长，可读性差 | **已修复**：新增 `ImportOverrides` 结构体（`title`, `artist`, `album`, `coverData` 均为可选），`processFile` 参数简化为 `url`、`overrideName`、`overrides`。`processAppleMusicFile` 已同步更新 |
| 2.3.9 | 🟢 | ✅ fixed | `Domain/Services/LyricsService.swift` | L216-217 | 代码风格 | 使用 `// swiftlint:disable:next force_try` + `try!` 初始化正则表达式。虽然正则是编译时常量不会失败，但 `force_try` 仍是代码质量隐患 | **已修复**：改用 `try? NSRegularExpression(...)` 返回可选值，在 `parseLRC` 中 `guard let regex` 提前返回空数组 |
| 2.3.10 | 🟢 | deferred | `Domain/Services/LyricsService.swift` | L270-295 | 可维护性 | `loadFromFile` 和 `loadExternalLRC` 中存在完全相同的 LRC 解析 + 纯文本降级逻辑（`parseLRC` → 判空 → `buildPlainLines`），重复了 3 次（包括 `loadEmbedded`） | **已修复**：提取通用方法 `buildLyricsData(from content: String, source: LyricsSource) -> LyricsData?`，`loadEmbedded`/`loadFromFile`/`loadExternalLRC`/`processTrack` 统一调用此方法 |

**无问题文件**：`PlaylistService.swift`、`PlayQueueService.swift`、`SleepTimerService.swift`、`WebDAVService.swift`、`CloudDriveProvider.swift`


---

## 模块 2 Review 结论

Domain 层的 **3 个阻塞级别** 依赖方向违规问题已全部修复：

1. ✅ `PlaybackService` → `AudioEngineProtocol`（协议抽象，移除 AVFoundation 依赖）
2. ✅ `LyricsService` → `EmbeddedLyricsReading` + `FileStorageProviding` + `LyricsAPIProviding`（移除 AVFoundation/FileManager/SandboxPathManager/Core 层直接依赖）
3. ✅ `AudioMetadataParsing` → `ParsedMetadata` 移至 Domain 层

**新增文件**：
- `Domain/Entities/ParsedMetadata.swift` — 元数据解析结果实体
- `Domain/Repositories/AudioEngineProtocol.swift` — 音频引擎协议 + PlaybackState 枚举
- `Domain/Repositories/LyricsAPIProviding.swift` — 歌词 API 协议
- `Domain/Repositories/EmbeddedLyricsReading.swift` — 嵌入歌词读取协议
- `Domain/Services/LibraryGrouping.swift` — 艺术家/专辑分组业务逻辑
- `Core/Audio/EmbeddedLyricsReader.swift` — 嵌入歌词读取 Core 层实现

**延期项（3 个 🟢）**：2.1.4（LibraryTypes.swift 拆分）、2.1.5（WebDAV 类型拆分）均为文件组织优化，不影响正确性和架构合规性，建议后续独立任务处理。
