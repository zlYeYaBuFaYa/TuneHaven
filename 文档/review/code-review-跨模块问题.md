# 代码 Review：全量代码 Review — 模块 1 App 层

---

## 跨模块问题


| #   | 等级  | 状态   | 关联模块         | 文件                                                                               | 行号                                  | 维度   | 问题描述                                                                                                                                                                                                   | 建议修复方案                                                                                          |
| --- | --- | ---- | ------------ | -------------------------------------------------------------------------------- | ----------------------------------- | ---- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------- |
| X.1 | 🟢  | open | App ↔ Domain | `App/CoverImageProcessor.swift`、`Domain/Repositories/CoverImageProcessing.swift` | CoverImageProcessor L4, Protocol L4 | 线程安全 | `CoverImageProcessing` 协议未标注 `@MainActor`，但实现类 `CoverImageProcessor` 标注了 `@MainActor`。Swift 6 严格并发下，通过协议类型调用时不要求 MainActor 隔离，可能导致跨隔离域调用警告或运行时问题                                                       | 将协议方法改为 `async throws`（推荐，配合 1.1.4 的修复）；或在协议上添加 `@MainActor` 约束                                 |
| X.2 | 🟢  | open | App ↔ Domain | `App/TuneHavenApp.swift`、多个 Core 层文件                                             | L100-108                            | 架构合规 | `TuneHavenApp.initialize()` 直接调用 Core 层静态方法（`MigrationManager.shared`、`CoreDataStack.shared`、`SandboxPathManager`、`WiFiTransferServer`），App 层绕过 Domain/Service 直接依赖 Core 层，不符合 Clean Architecture 依赖方向 | 将启动初始化逻辑封装为 `AppBootstrapService`（Domain 层），通过 DI 容器注入，App 层仅调用 `bootstrapService.initialize()` |

# 代码 Review：全量代码 Review — 模块 2 Domain 层

---

## 跨模块问题汇总

| # | 等级 | 状态 | 关联模块 | 文件 | 维度 | 问题描述 | 建议修复方案 |
|---|------|------|---------|------|------|----------|-------------|
| 2.X.1 | 🔴 | open | Domain → Data | `AudioMetadataParsing.swift` | 架构合规 | Domain 协议返回值类型 `ParsedMetadata` 定义在 Data 层 | 同 2.2.1 |
| 2.X.2 | 🔴 | open | Domain → Core | `PlaybackService.swift` | 架构合规 | Domain Service 直接依赖 Core 层具体类 `AudioEngine` | 同 2.3.1 |
| 2.X.3 | 🔴 | open | Domain → Core/App | `LyricsService.swift` | 架构合规 | Domain Service 直接依赖 AVFoundation、FileManager、SandboxPathManager | 同 2.3.2 |
| 2.X.4 | 🟡 | open | Domain → Core | `LyricsService.swift` | 架构合规 | Domain Service 引用 Core 层定义的 `LRCLibAPIClientProtocol` | 同 2.3.4 |
| 2.X.5 | 🟡 | open | Domain → Core/App | `PlaybackService.swift` | 架构合规 | Domain Service 直接使用 `SandboxPathManager`、`ErrorLogger.shared` | 同 2.3.3 |

# 代码 Review：全量代码 Review — 模块 3 Data 层

---

## 跨模块问题


| #      | 等级  | 状态   | 关联模块        | 文件                                                         | 行号     | 维度   | 问题描述                                                 | 建议修复方案                         |
| ------ | --- | ---- | ----------- | ---------------------------------------------------------- | ------ | ---- | ---------------------------------------------------- | ------------------------------ |
| 3.1.17 | 🟡  | open | Data↔Domain | `AudioMetadataParser.swift` / `AudioMetadataParsing.swift` | L5-L20 | 架构合规 | `ParsedMetadata` 定义在 Data 层但被 Domain 协议返回类型引用，形成反向依赖 | 将 `ParsedMetadata` 移至 Domain 层 |


# 代码 Review：全量代码 Review — 模块 4 Core 层

---

## 跨模块问题


| #     | 等级  | 状态   | 关联模块          | 文件                                                                                                                                                                                             | 维度   | 问题描述                                                                                                     | 建议修复方案                                          |
| ----- | --- | ---- | ------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---- | -------------------------------------------------------------------------------------------------------- | ----------------------------------------------- |
| 4.X.1 | 🟡  | open | Core → App    | `AudioEngine.swift`、`AudioSessionManager.swift`、`NowPlayingManager.swift`、`WiFiTransferServer.swift`、`MigrationManager.swift`、`SandboxPathManager.swift`、`ImageCacheManager.swift` 等 Core 层多文件 | 架构合规 | Core 层系统性依赖 App 层的 `AppError`、`AppLogger`、`ErrorLogger`（均定义在 `App/AppError.swift`）。几乎所有 Core 层文件都存在此反向依赖 | 同 4.1.1：将这些基础类型下沉至 Core/Utils 或独立的 Foundation 层 |
| 4.X.2 | 🟡  | open | Core ↔ Domain | `Core/Network/LRCLibAPIClient.swift`、`Domain/Services/LyricsService.swift`                                                                                                                     | 架构合规 | `LRCLibAPIClientProtocol` 定义在 Core 层，但 Domain 层依赖此协议。按 Clean Architecture 协议应定义在 Domain 层                | 同 4.2.5 / 2.3.4                                 |



# 代码 Review：全量代码 Review — 模块 5 Presentation 层（子任务 5.1 / 5.2 / 5.3）

---

## 跨模块问题


| #     | 等级  | 状态   | 关联模块                        | 文件                                                                                            | 维度    | 问题描述                                                                                                                                                           | 建议修复方案                                              |
| ----- | --- | ---- | --------------------------- | --------------------------------------------------------------------------------------------- | ----- | -------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------- |
| 5.X.1 | 🟡  | open | Presentation → Core         | `CoverImageView.swift`                                                                        | 架构合规  | Presentation 层直接依赖 Core 层 `ImageCacheManager.shared` 单例。`CoverImageView` 是项目中使用最广泛的通用组件之一，此依赖影响面大                                                              | 同 5.1.1                                             |
| 5.X.2 | 🟡  | open | 5.2 ↔ 5.2（视图间状态同步）          | `ArtistListView.swift`、`AlbumGridView.swift`、`ArtistDetailView.swift`、`AlbumDetailView.swift` | 逻辑正确性 | 列表视图和详情视图的数据均为本地 @State 一次性加载，不响应 `libraryService.songs` 变化，导致导入/删除歌曲后 UI 不一致                                                                                  | 同 5.2.1、5.2.2                                       |
| 5.X.3 | 🟢  | open | 5.1 ↔ 5.3 ↔ 5.4 ↔ 5.6（全局模式） | 多处                                                                                            | 代码风格  | `.whitespaces` vs `.whitespacesAndNewlines` 裁剪不一致问题遍及 Common（CreatePlaylistSheet）、Player（PlayQueueView）、Playlist（PlaylistGroupView）、Settings（SongInfoEditView） | 全局统一使用 `.whitespacesAndNewlines`，可考虑提取为 String 扩展方法 |
| 5.X.4 | 🟢  | open | 5.1 ↔ 5.2 ↔ 5.3（全局模式）       | 多处                                                                                            | 错误处理  | `try?` 静默吞掉错误的模式在 toggleFavorite、歌词导入/删除、封面操作、添加到歌单等场景中普遍存在                                                                                                    | 建立项目级 error handling 规范：用户可感知的操作必须在失败时给出反馈          |

# 代码 Review：全量代码 Review — 模块 5 Presentation 层（子任务 5.4 / 5.5 / 5.6）

---

## 跨模块问题


| #     | 等级  | 状态   | 关联模块                         | 文件                                          | 维度    | 问题描述                                                                                                                                     | 建议修复方案        |
| ----- | --- | ---- | ---------------------------- | ------------------------------------------- | ----- | ---------------------------------------------------------------------------------------------------------------------------------------- | ------------- |
| 5.X.1 | 🟡  | open | Presentation → Core          | `OpenInImportHandler.swift`                 | 架构合规  | Presentation 层直接依赖 Core 层 `FileStorageService.shared`、`SandboxPathManager.documentsURL`、`FileManager.default`，违反 Clean Architecture 依赖方向 | 同 5.5.1、5.5.7 |
| 5.X.2 | 🟢  | open | Presentation → Domain (放置不当) | `SettingsView.swift`                        | 架构合规  | `RecentPlayRange` 枚举定义在 Presentation 层但承载 Domain 语义                                                                                      | 同 5.6.1       |
| 5.X.3 | 🟢  | open | 5.4 ↔ 5.6                    | `SongListView.swift` ↔ `SettingsView.swift` | 逻辑正确性 | `SongListView` 硬编码 30 天，忽略了 `SettingsView` 中 `recentPlayRange` 的用户设置                                                                     | 同 5.4.1       |
