# 代码 Review：全量代码 Review — 模块 1 App 层

---

## 跨模块问题


| #   | 等级  | 状态   | 关联模块         | 文件                                                                               | 行号                                  | 维度   | 问题描述                                                                                                                                                                                                   | 建议修复方案                                                                                          |
| --- | --- | ---- | ------------ | -------------------------------------------------------------------------------- | ----------------------------------- | ---- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------- |
| X.1 | 🟢  | fixed | App ↔ Domain | `App/CoverImageProcessor.swift`、`Domain/Repositories/CoverImageProcessing.swift` | CoverImageProcessor L4, Protocol L4 | 线程安全 | `CoverImageProcessing` 协议未标注 `@MainActor`，但实现类 `CoverImageProcessor` 标注了 `@MainActor`。Swift 6 严格并发下，通过协议类型调用时不要求 MainActor 隔离，可能导致跨隔离域调用警告或运行时问题                                                       | ~~将协议方法改为 `async throws`~~ **已修复**：协议方法已为 `async throws`，实现类已移除 `@MainActor` |
| X.2 | 🟢  | fixed | App ↔ Domain | `App/TuneHavenApp.swift`、`App/AppDIContainer.swift`                                             | L100-108                            | 架构合规 | `TuneHavenApp.initialize()` 直接调用 Core 层静态方法（`MigrationManager.shared`、`CoreDataStack.shared`、`SandboxPathManager`、`WiFiTransferServer`），App 层绕过 Domain/Service 直接依赖 Core 层，不符合 Clean Architecture 依赖方向 | ~~封装为 AppBootstrapService~~ **已修复**：启动逻辑封装到 `AppDIContainer.bootstrap()` 方法中，`TuneHavenApp` 仅调用 `container.bootstrap()` |

# 代码 Review：全量代码 Review — 模块 2 Domain 层

---

## 跨模块问题汇总

| # | 等级 | 状态 | 关联模块 | 文件 | 维度 | 问题描述 | 建议修复方案 |
|---|------|------|---------|------|------|----------|-------------|
| 2.X.1 | 🔴 | fixed | Domain → Data | `AudioMetadataParsing.swift` | 架构合规 | Domain 协议返回值类型 `ParsedMetadata` 定义在 Data 层 | **已修复**：`ParsedMetadata` 已移至 `Domain/Entities/ParsedMetadata.swift` |
| 2.X.2 | 🔴 | fixed | Domain → Core | `PlaybackService.swift` | 架构合规 | Domain Service 直接依赖 Core 层具体类 `AudioEngine` | **已修复**：通过 `AudioEngineProtocol`（Domain 层）解耦，PlaybackService 使用 `any AudioEngineProtocol` |
| 2.X.3 | 🔴 | fixed | Domain → Core/App | `LyricsService.swift` | 架构合规 | Domain Service 直接依赖 AVFoundation、FileManager、SandboxPathManager | **已修复**：通过 `FileStorageProviding`、`EmbeddedLyricsReading` 协议注入，不再直接依赖 Core/App |
| 2.X.4 | 🟡 | fixed | Domain → Core | `LyricsService.swift` | 架构合规 | Domain Service 引用 Core 层定义的 `LRCLibAPIClientProtocol` | **已修复**：新增 `LyricsAPIProviding` 协议在 Domain 层，`LRCLibAPIClient` 实现该协议 |
| 2.X.5 | 🟡 | fixed | Domain → Core/App | `PlaybackService.swift` | 架构合规 | Domain Service 直接使用 `SandboxPathManager`、`ErrorLogger.shared` | **已修复**：通过 `FileStorageProviding`、`UserPreferencesProviding` 等协议注入 |

# 代码 Review：全量代码 Review — 模块 3 Data 层

---

## 跨模块问题


| #      | 等级  | 状态   | 关联模块        | 文件                                                         | 行号     | 维度   | 问题描述                                                 | 建议修复方案                         |
| ------ | --- | ---- | ----------- | ---------------------------------------------------------- | ------ | ---- | ---------------------------------------------------- | ------------------------------ |
| 3.1.17 | 🟡  | fixed | Data↔Domain | `AudioMetadataParser.swift` / `AudioMetadataParsing.swift` | L5-L20 | 架构合规 | `ParsedMetadata` 定义在 Data 层但被 Domain 协议返回类型引用，形成反向依赖 | **已修复**：`ParsedMetadata` 已移至 `Domain/Entities/` |


# 代码 Review：全量代码 Review — 模块 4 Core 层

---

## 跨模块问题


| #     | 等级  | 状态   | 关联模块          | 文件                                                                                                                                                                                             | 维度   | 问题描述                                                                                                     | 建议修复方案                                          |
| ----- | --- | ---- | ------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---- | -------------------------------------------------------------------------------------------------------- | ----------------------------------------------- |
| 4.X.1 | 🟡  | fixed | Core → App    | `AudioEngine.swift`、`AudioSessionManager.swift`、`NowPlayingManager.swift`、`WiFiTransferServer.swift`、`MigrationManager.swift`、`SandboxPathManager.swift`、`ImageCacheManager.swift` 等 Core 层多文件 | 架构合规 | Core 层系统性依赖 App 层的 `AppError`、`AppLogger`、`ErrorLogger`（均定义在 `App/AppError.swift`）。几乎所有 Core 层文件都存在此反向依赖 | **已修复**：`AppError.swift`、`AppLogger.swift`、`ErrorLogger.swift` 已下沉至 `Core/Utils/` |
| 4.X.2 | 🟡  | fixed | Core ↔ Domain | `Core/Network/LRCLibAPIClient.swift`、`Domain/Services/LyricsService.swift`                                                                                                                     | 架构合规 | `LRCLibAPIClientProtocol` 定义在 Core 层，但 Domain 层依赖此协议。按 Clean Architecture 协议应定义在 Domain 层                | **已修复**：新增 `LyricsAPIProviding` 协议在 `Domain/Repositories/`，`LRCLibAPIClient` 实现该协议 |



# 代码 Review：全量代码 Review — 模块 5 Presentation 层（子任务 5.1 / 5.2 / 5.3）

---

## 跨模块问题


| #     | 等级  | 状态   | 关联模块                        | 文件                                                                                            | 维度    | 问题描述                                                                                                                                                           | 建议修复方案                                              |
| ----- | --- | ---- | --------------------------- | --------------------------------------------------------------------------------------------- | ----- | -------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------- |
| 5.X.1 | 🟡  | fixed | Presentation → Core         | `CoverImageView.swift`                                                                        | 架构合规  | Presentation 层直接依赖 Core 层 `ImageCacheManager.shared` 单例。`CoverImageView` 是项目中使用最广泛的通用组件之一，此依赖影响面大                                                              | **已修复**：扩展 `ImageCacheManaging` 协议添加图片获取方法，通过 SwiftUI `@Environment(\.imageCache)` 注入，CoverImageView 不再直接引用 `ImageCacheManager` |
| 5.X.2 | 🟡  | fixed | 5.2 ↔ 5.2（视图间状态同步）          | `ArtistListView.swift`、`AlbumGridView.swift`、`ArtistDetailView.swift`、`AlbumDetailView.swift` | 逻辑正确性 | 列表视图和详情视图的数据均为本地 @State 一次性加载，不响应 `libraryService.songs` 变化，导致导入/删除歌曲后 UI 不一致                                                                                  | **已修复**：四个视图均添加 `.onChange(of: libraryService.songs.count)` 触发重新加载 |
| 5.X.3 | 🟢  | fixed | 5.1 ↔ 5.3 ↔ 5.4 ↔ 5.6（全局模式） | 多处                                                                                            | 代码风格  | `.whitespaces` vs `.whitespacesAndNewlines` 裁剪不一致问题遍及 Common（CreatePlaylistSheet）、Player（PlayQueueView）、Playlist（PlaylistGroupView）、Settings（SongInfoEditView） | **已修复**：全局统一使用 `.whitespacesAndNewlines`，涉及 Presentation 层 6 个文件 + Domain 层 2 个文件 |
| 5.X.4 | 🟢  | fixed | 5.1 ↔ 5.2 ↔ 5.3（全局模式）       | 多处                                                                                            | 错误处理  | `try?` 静默吞掉错误的模式在 toggleFavorite、歌词导入/删除、封面操作、添加到歌单等场景中普遍存在                                                                                                    | **已修复**：toggleFavorite（AllSongsView/ArtistDetailView/LibraryMainView）、歌词导入/删除（SongInfoEditView）均改为 do/catch + snackbar 反馈。清理类 try?（FileManager.removeItem）保留 |

# 代码 Review：全量代码 Review — 模块 5 Presentation 层（子任务 5.4 / 5.5 / 5.6）

---

## 跨模块问题


| #     | 等级  | 状态   | 关联模块                         | 文件                                          | 维度    | 问题描述                                                                                                                                     | 建议修复方案        |
| ----- | --- | ---- | ---------------------------- | ------------------------------------------- | ----- | ---------------------------------------------------------------------------------------------------------------------------------------- | ------------- |
| 5.X.1 | 🟡  | fixed | Presentation → Core          | `OpenInImportHandler.swift`                 | 架构合规  | Presentation 层直接依赖 Core 层 `FileStorageService.shared`、`SandboxPathManager.documentsURL`、`FileManager.default`，违反 Clean Architecture 依赖方向 | **已修复**：通过 `FileStorageProviding` 协议注入（新增 `documentsURL`、`contentsOfDirectory` 方法），不再直接引用 Core 层 |
| 5.X.2 | 🟢  | fixed | Presentation → Domain (放置不当) | `SettingsView.swift`                        | 架构合规  | `RecentPlayRange` 枚举定义在 Presentation 层但承载 Domain 语义                                                                                      | **已修复**：`RecentPlayRange` 已移至 `Domain/Entities/LibraryTypes.swift`，`recentPlayRange` 属性已加入 `UserPreferencesProviding` 协议 |
| 5.X.3 | 🟢  | fixed | 5.4 ↔ 5.6                    | `SongListView.swift` ↔ `SettingsView.swift` | 逻辑正确性 | `SongListView` 硬编码 30 天，忽略了 `SettingsView` 中 `recentPlayRange` 的用户设置                                                                     | **已修复**：`SongListView` 通过 `@AppStorage(AppStorageKey.recentPlayRange)` 读取用户设置 |
