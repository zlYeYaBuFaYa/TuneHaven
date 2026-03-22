# 代码 Review：全局代码审查 - 第 1 轮

> 日期：2026-03-22 | 类型：AI 自审 | 范围：全部 120 个 Swift 源文件

## 结论：不通过

| 维度 | 结论 | 说明 |
|------|------|------|
| 逻辑正确性 | ✅ | 业务逻辑完整，播放/导入/歌单/队列等核心流程自洽 |
| 错误处理 | 🟡 | AppError 体系完善，但部分 `lyricsSource` 哨兵值处理存在隐患 |
| 安全 | ✅ | SandboxPathManager 统一路径、SecurityScoped URL 正确、无硬编码敏感信息 |
| 线程安全 | 🟡 | @MainActor 使用整体正确，但 PlaybackService 内部 init 存在冗余实例创建问题 |
| 架构合规 | 🟡 | Clean Architecture 分层整体良好，但存在 Domain 层直接引用 Data 层具体实现的违规 |
| 代码风格 | 🟡 | 整体规范，存在少量冗余代码和命名不一致 |
| API 设计 | ✅ | 接口语义清晰，async throws 一致 |
| 性能 | 🟡 | 整体合理，但 CoreData 读操作在 viewContext 上使用 withCheckedContinuation + perform 模式有多余封装 |
| 内存管理 | ✅ | [weak self] 使用正确，cancellables 正确存储 |
| 可维护性 | 🟡 | 整体良好，部分文件文档与代码不一致需同步 |

---

## 问题清单

### 🔴 阻塞问题

#### 1. [🔴] PlaybackService.init 创建冗余的 MusicLibraryService 实例
**文件**: `Domain/Services/PlaybackService.swift:36-38`

PlaybackService 作为单例，在 `private init` 中 `self.libraryService = MusicLibraryService()` 创建了一个新的 MusicLibraryService 实例，而 TuneHavenApp 中通过 `@StateObject` 创建了另一个实例作为 `@EnvironmentObject` 注入。这导致 PlaybackService 持有的 libraryService 与 UI 层使用的不是同一个实例，可能造成：
- `recordPlay()` 在 PlaybackService 的 libraryService 上调用，但 UI 不会刷新
- `loadSongs()` 数据不同步

虽然有 `configure(libraryService:)` 方法，但 **未在 TuneHavenApp 中调用**，所以冗余实例问题一直存在。

**建议**：在 TuneHavenApp.initialize() 中调用 `playbackService.configure(libraryService: libraryService)` 确保注入正确的实例。

#### 2. [🔴] Domain 层 Service 直接引用 Data 层具体实现（违反 Clean Architecture）
**文件**: 多个 Service 的 init 默认参数

以下 Service 在默认参数中直接引用了 Data 层的具体实现类，违反了 Clean Architecture 的依赖方向原则：

- `PlaybackService.init(playlistRepo: PlaylistRepository = CoreDataPlaylistRepository(), songRepo: SongRepository = CoreDataSongRepository())`
- `MusicLibraryService.init(songRepo: SongRepository = CoreDataSongRepository())`
- `PlaylistService.init(repo: PlaylistRepository = CoreDataPlaylistRepository(), ...)`
- `ImportService.init(songRepo: SongRepository = CoreDataSongRepository(), ...)`
- `SearchService.init(historyRepo: SearchHistoryRepository = CoreDataSearchHistoryRepository())`
- `LyricsService.init(repo: SongRepository = CoreDataSongRepository(), ...)`
- `PlaylistGroupService.init(repo: PlaylistGroupRepository = CoreDataPlaylistGroupRepository())`

Domain 层应只知道 Protocol，不应 import 或引用 Data 层的 `CoreData*Repository`。

**建议**：将默认实例的构造移到 App 层（TuneHavenApp 依赖注入处），Domain 层 Service 的 init 不提供默认值，或通过工厂/DI 容器解耦。

---

### 🟡 建议问题

#### 3. [🟡] updateLyrics 使用 Int16.min 作为 nil 哨兵值存在混淆风险
**文件**: `Data/Repositories/CoreDataSongRepository.swift:253`

```swift
entity.lyricsSource = lyricsSource?.rawValue ?? Int16.min
```

以及 `SongMapper.swift:17`:
```swift
entity.lyricsSource = song.lyricsSource?.rawValue ?? Int16.min
```

使用 `Int16.min` 作为"无值"哨兵是因为 CoreData Int16 不可空，但这个约定分散在多个文件中，且 `SongMapper.isValidLyricsSource` 同时检查 `-1` 和 `Int16.min` 两个旧/新哨兵值，增加了维护负担。

**建议**：统一定义一个常量（如 `SongMapper.nilSentinel = Int16.min`），并在所有读写位置引用同一常量。

#### 4. [🟡] ErrorLogger 和 AppLogger 存在大量重复代码
**文件**: `App/AppError.swift:116-253`

`ErrorLogger` 和 `AppLogger` 两个类的文件写入逻辑（`appendToLog/appendToFile`、`rotateIfNeeded`、`ISO8601DateFormatter`）几乎完全相同。

**建议**：提取一个私有的 `FileLogWriter` 工具类，ErrorLogger 和 AppLogger 复用其写入和轮转逻辑。

#### 5. [🟡] CoreDataStack.performBackground 缺少显式 merge 到 viewContext
**文件**: `Core/Persistence/CoreDataStack.swift:35-50`

技术文档（六、并发模型 6.2）描述的流程包含"显式合并到主线程"步骤，但实际代码仅依赖 `automaticallyMergesChangesFromParent = true` 作为合并机制，未显式调用 `viewContext.mergeChanges(fromContextDidSave:)`。

虽然 `automaticallyMergesChangesFromParent` 在大多数场景下够用，但与技术文档描述不一致。此外，自动合并的时机不可控（可能有微小延迟），在写入后立即读取的场景下可能读到旧数据。

**建议**：
- 方案 A：补充显式 merge（如文档所述），确保写入后立即可读
- 方案 B：更新技术文档使其与实际实现一致

#### 6. [🟡] ThemeRegistry 使用 NSLock 但 ThemeManager 标注 @MainActor
**文件**: `App/Theme/ThemeRegistry.swift`

ThemeRegistry 使用 `NSLock` + `@unchecked Sendable` 保证线程安全，但实际上 `bootstrap()` 和 `theme(for:)` 只在 ThemeManager（@MainActor）中调用，永远在主线程。这个锁是多余的。

**建议**：如果确定只在主线程使用，可以简化为 `@MainActor`；如果需要跨线程访问，保留 NSLock 但添加注释说明原因。

#### 7. [🟡] PlaybackService.shared 单例模式与 EnvironmentObject 注入混合使用
**文件**: `TuneHavenApp.swift:19` & `PlaybackService.swift:8`

PlaybackService 同时使用了 `static let shared` 单例模式和 `@EnvironmentObject` 注入：
```swift
private let playbackService = PlaybackService.shared  // TuneHavenApp
```

文档要求"Presentation 层统一通过 @EnvironmentObject 获取，不直接引用 .shared"，但 PlaybackService 内部通过 `.shared` 初始化，且 `AudioEngine.shared` 也被直接引用。

**建议**：保持一致性，PlaybackService 内部对 AudioEngine 的引用可以保留（因为都是单例），但应在文档中明确说明"Core 层基础设施单例允许直接引用"这一例外规则。

#### 8. [🟡] SongRow 中 `song.duration.formattedTime` 扩展与 `DurationFormatter.format()` 功能重复
**文件**: `Presentation/Common/SongRow.swift:114-126` & `Core/Utils/DurationFormatter.swift`

TimeInterval 上有 `formattedTime` 扩展属性，同时 `DurationFormatter.format()` 也提供同样功能。Song 实体上还有 `formatDuration()` 方法。三处提供相同功能但实现分散。

**建议**：统一使用 `DurationFormatter.format()`，移除重复的 `TimeInterval.formattedTime` 扩展，避免维护多份格式化逻辑。

---

### 🟢 优化问题

#### 9. [🟢] AppStorageKey 缺少排序相关键名
**文件**: `App/AppStorageKey.swift`

`AppStorageKey` 中缺少 `song_sort_option` 和 `song_sort_ascending` 的常量定义，但技术文档（十二、持久化策略）提到了这两个 UserDefaults 键。应统一通过 AppStorageKey 管理所有键名。

**建议**：补充 `static let songSortOption = "song_sort_option"` 和 `static let songSortAscending = "song_sort_ascending"`。

#### 10. [🟢] 项目文档与实际代码不同步
**文件**: `项目文档.md` 多处

项目文档中的主题列表仍是旧版（meadowBreeze/roseDream/frostElegance 等），但代码中已迁移为新主题（mintBreeze/deepOcean/cyberNeon/glacierBlue/auroraDream/midnightGold）。技术文档中的主题 ID 也是旧的。

此外，项目文档提到 `AppDelegate.swift` 文件，但实际代码中 AppDelegate 的配置功能已内联到 `TuneHavenApp.swift`。

项目文档中的错误类型描述为"21 种"，但 AppError 实际已有 30+ 个 case（增加了 WebDAV 和歌词相关错误）。

**建议**：在本次 Review 完成修复后，统一更新三份根目录文档。

#### 11. [🟢] LyricsLine 每次创建都生成新 UUID
**文件**: `Domain/Entities/LibraryTypes.swift:192-198`

LyricsLine 在 `init` 中每次创建都调用 `UUID()`，对于大量歌词行可能有不必要的开销。且这个 id 仅用于 SwiftUI List 的 Identifiable，实际上用 `timestamp + text` 的组合即可唯一标识。

**建议**：可以保留，性能影响微小，但如有必要可用 hash 值替代 UUID。

#### 12. [🟢] ImageCacheManager.clearAll() 方法使用 async 但内部未使用 await
**文件**: `Core/Cache/ImageCacheManager.swift:62-78`

`clearAll()` 标注为 `async` 但内部没有 `await` 调用，所有操作都是同步的（除了最后一个 `fileQueue.async`，但那不需要等待）。

**建议**：移除 `async` 标注，或在 fileQueue 操作上使用 `await` 确保清理完成后才返回。

---

## 修改建议优先级

| 优先级 | 问题编号 | 描述 |
|--------|---------|------|
| P0 | #1 | PlaybackService 冗余实例 — 注入 libraryService |
| P0 | #2 | Domain 层解耦 Data 层具体实现 |
| P1 | #3 | 统一 lyricsSource 哨兵值常量 |
| P1 | #4 | 提取日志文件写入工具类 |
| P1 | #5 | CoreDataStack merge 策略与文档对齐 |
| P1 | #8 | 统一时长格式化方法 |
| P2 | #6 | ThemeRegistry 锁策略优化 |
| P2 | #7 | 单例 vs EnvironmentObject 文档化 |
| P2 | #9 | 补充 AppStorageKey 缺失常量 |
| P2 | #10 | 文档同步更新 |
| P3 | #11 | LyricsLine UUID 生成优化 |
| P3 | #12 | clearAll async 标注修正 |
