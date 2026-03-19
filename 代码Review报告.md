# 代码 Review 报告

## 文档信息

| 项目 | 内容 |
|------|------|
| 项目名称 | TuneHaven — iOS 音乐播放器 |
| 审查日期 | 2026-03-19 |
| 审查范围 | 149 个 Swift 文件 |
| 审查重点 | 白屏问题根因、性能瓶颈、逻辑 Bug |

> 本报告仅包含经代码验证、当前确实存在的问题。已修复问题已移除。

---

## 问题总览

| 级别 | 数量 | 说明 |
|------|------|------|
| P0 致命 | 5 | 白屏根因 3 + 逻辑 Bug 2 |
| P1 严重 | 6 | 白屏关联 2 + 性能 2 + 弃用 API 1 + 主题不一致 1 |
| P2 中等 | 5 | 性能 2 + 代码质量 3 |
| P3 建议 | 3 | 可维护性改进 |
| **合计** | **19** | |

---

## P0 致命问题

### #1 `scheduleWindowRefresh` UIKit 直接操作与 SwiftUI 渲染管线冲突 — 白屏核心根因

- **文件**: `ThemeManager.swift` L57-83, L124-138 / `TuneHavenApp.swift` L91-105
- **验证**: `overrideUserInterfaceStyle` 设置出现在 `ThemeManager.swift` L79、L104；`scheduleWindowRefresh` 在 `TuneHavenApp.swift` 中被调用 4 次（L84、L89、L97、L169）
- **问题**:

`TuneHavenApp.onChange(of: scenePhase)` 中，当 App 回到前台：
1. `refreshPaletteScheme()` 立即修改 `@State paletteScheme` → 触发 SwiftUI 整棵视图树重渲染
2. `scheduleWindowRefresh(delay: 0.3)` → 0.3 秒后执行 `applyToWindows()`
3. `applyToWindows()` 直接设置 `window.overrideUserInterfaceStyle = style`，强制 UIKit trait collection 全树传播

当步骤 3 发生时 SwiftUI 可能还在 layout/commit 阶段，两个渲染系统同时操作同一个窗口的 trait → 渲染管线中断 → 白屏。

**为什么偶发**: 取决于 0.3s 后 SwiftUI 渲染管线所处的精确阶段。

---

### #2 `preferredColorScheme` 与 `overrideUserInterfaceStyle` 双重控制冲突 — 白屏根因

- **文件**: `TuneHavenApp.swift` L76 / `ThemeManager.swift` L79, L104
- **验证**: `.preferredColorScheme(themeManager.resolvedColorScheme)` 存在于 `TuneHavenApp.swift` L76；`window.overrideUserInterfaceStyle` 存在于 `ThemeManager.swift` L79 和 L104
- **问题**:

两种机制控制的是同一属性（UITraitCollection.userInterfaceStyle），但通过不同路径生效：
  - `.preferredColorScheme()` → SwiftUI 在下一个渲染周期应用
  - `overrideUserInterfaceStyle` → UIKit 立即生效

切换主题时两者的时序不一致，可能导致闪烁或白屏。

---

### #3 `UIAppearance` 全局代理 + 直接实例设置 = 多源竞争 — 白屏根因

- **文件**: `AppDelegate.swift` L34-35 / `ThemeManager.swift` L76-82
- **验证**: `UIWindow.appearance().backgroundColor` 和 `.overrideUserInterfaceStyle` 存在于 `AppDelegate.swift` L34-35；`window.overrideUserInterfaceStyle` 直接设置存在于 `ThemeManager.swift` L79, L104；`AppDelegate.applyNavigationBarAppearance()` 在 `ThemeManager.applyToWindows()` 中被调用（L76）
- **问题**:

三层同时控制 window 样式：

| 层面 | 设置时机 | 生效对象 |
|------|----------|----------|
| `UIWindow.appearance()` | App 启动 | 所有新创建的 UIWindow |
| `window.overrideUserInterfaceStyle` | 每次 scheduleRefresh | 已存在的 UIWindow |
| `.preferredColorScheme()` | SwiftUI 渲染 | SwiftUI 管理的 window |

当 SwiftUI 为 `fullScreenCover`/`sheet` 创建新 UIWindow 时，`UIWindow.appearance()` 代理生效的值可能与运行时直接设置的值不同步。

---

### #4 Timer key 不匹配 — 撤销删除永远失效

- **文件**: `MusicLibraryService.swift` L110-132
- **验证**: L111 `let tokenId = UUID()` 存储到 `undoTimers[tokenId]`；L128 用 `token.songIds.first` 查找。两个 key 来源完全不同，不可能匹配。
- **问题**:

```swift
// scheduleCommit 用随机 UUID 作 key
let tokenId = UUID()
undoTimers[tokenId] = timer

// invalidateTimer 用 songIds.first 查找
if let id = token.songIds.first {
    undoTimers[id]?.invalidate()    // 永远找不到
}
```

用户点击"撤销删除"时，定时器无法被取消，30 秒后歌曲仍被永久删除。

---

### #5 PlaybackService 持有独立的 MusicLibraryService 实例 — 数据不同步

- **文件**: `PlaybackService.swift` L35
- **验证**: `self.libraryService = MusicLibraryService()` 确实存在于 L35，而 `TuneHavenApp.swift` L9 通过 `@StateObject` 创建了另一个实例注入 Environment
- **问题**:

`PlaybackService` 内部的 `libraryService` 与 UI 层使用的是不同对象。导致：
- `recordPlay()` 更新的播放计数不反映到 UI
- `toggleFavorite()` 后 UI 层歌曲列表不刷新
- 这是"收藏后歌单数量不变、需退出再进入才刷新"的核心原因

---

## P1 严重问题

### #6 Canvas 密集绘制 + 三个 Tab 同时在内存 — 白屏关联

- **文件**: 5 个 `*Background.swift`（共 12 个 Canvas）/ `RootTabView.swift` L23-33
- **验证**: 5 个 Background 文件中共有 12 个 `Canvas {}` 块，均无 `.drawingGroup()`；`RootTabView` 使用 `opacity` 切换保持三个 Tab 始终在视图树中
- **问题**:

前台恢复时，SwiftUI 重渲染所有可见视图：
- 3 个 Tab 的 ThemeBackgroundView 同时重绘 Canvas
- 以 `ComicPopBackground.halftonePattern` 为例：393×852 屏幕 / 24px 间距 ≈ **580 次** `context.fill`
- `DeepSpaceNeonBackground.scanLine`：852/4 = **213 条**线
- 密集 Canvas 绘制全在主线程 + UIKit 操作 → 主线程阻塞 → 白屏

---

### #7 主题切换时 `.id()` 导致渲染风暴 — 白屏关联

- **文件**: `ThemeBackgroundView.swift` L69
- **验证**: `.id(themeManager.currentStyle.id)` 确实存在于 L69
- **问题**:

`.id()` 变化 = SwiftUI 销毁旧视图 + 创建新视图。切换主题时：
1. 三个 Tab 的旧 Canvas 视图被销毁
2. 三个新 Canvas 视图同时创建并开始绘制
3. 同时 `scheduleWindowRefresh(fullApply: true)` 操作 UIKit
4. 加上 `.animation(.easeInOut(duration: 0.25))` 尝试动画过渡

全部在主线程叠加 → 渲染风暴 → 白屏。

---

### #8 每次查询都全量加载所有歌曲 — 性能瓶颈

- **文件**: `MusicLibraryService.swift` L22, L27, L45, L58, L67
- **验证**: `songRepo.fetchAll()` 在该文件中被调用 5 次（loadSongs、fetchSongsByArtist、fetchSongsByAlbum、fetchArtistDetail、fetchAlbumDetail）
- **问题**:

`fetchArtistDetail(artist:)` 和 `fetchAlbumDetail(album:artist:)` 先加载全部歌曲再内存过滤。1000 首歌曲时，每次查询都完整 Core Data fetch + Mapper 映射。用户切换标签页时触发，体验上可能感到卡顿。

---

### #9 `toggleFavorite` 触发全量重载 — 性能

- **文件**: `MusicLibraryService.swift` L90-93
- **验证**: L93 `await loadSongs()` 确实存在，每次 toggleFavorite 都重新加载整个歌曲库
- **问题**:

仅修改一首歌的收藏状态，却调用 `loadSongs()` 重新从 Core Data 加载所有歌曲并替换 `songs` 数组。大曲库时每次收藏/取消都有明显延迟。`softDelete` 和 `undoDelete` 同样存在此问题（L77、L87）。

---

### #10 `UIScreen.main` 已弃用（iOS 16+）

- **文件**: `TuneHavenApp.swift` L32, L121 / `AppDelegate.swift` L25 / `ThemeManager.swift` L68, L98 / `AlbumGridView.swift` L51
- **验证**: 共 6 处使用 `UIScreen.main`
- **问题**:

`UIScreen.main` 在 iOS 16+ 已标记 deprecated。iPad 分屏或 Stage Manager 下返回的尺寸/trait 可能不准确。`AlbumGridView` 中用于计算封面尺寸，其余用于判断 dark/light mode。

---

### #11 约 10 个视图硬编码 `.foregroundColor(.white)` 未跟随主题

- **文件**: `PlayerView.swift`、`SnackbarView.swift`、`PlaylistDetailView.swift`、`LyricsView.swift`、`PlaylistMainView.swift`、`WebDAVAccountListView.swift`、`LyricsSearchView.swift`、`WebDAVBrowserView.swift`、`CloudDriveImportView.swift`、`SettingsAppearanceSection.swift`
- **验证**: 以上 10 个文件均存在 `.foregroundColor(.white)` 硬编码
- **问题**:

项目有完善的 `ThemeColorPalette` 主题系统，但这些视图直接使用 `.white` 而非 `palette.textOnPrimary` 等主题色。在浅色主题或跟随系统模式下，白色文字可能不可见或与背景冲突。

---

## P2 中等问题

### #12 `displaySongs` 计算属性每次 body 评估重新过滤

- **文件**: `AllSongsView.swift` L15-18
- **验证**: `displaySongs` 是 `var` 计算属性，body 中多处引用
- **问题**:

每次 SwiftUI body 评估时重新计算过滤逻辑。1000 首歌曲 × 每次 body 评估至少一次过滤 + `lowercased()` 字符串比较。

---

### #13 BatchAddSongsView 搜索无防抖

- **文件**: `BatchAddSongsView.swift` L17-31
- **验证**: `filteredSongs` 和 `groupedByArtist` 均为计算属性，`searchText` 直接绑定到 TextField，无防抖机制
- **问题**:

`searchText` 每次变化都重新计算 `filteredSongs`（过滤）和 `groupedByArtist`（分组+排序）。用户输入每个字符都触发完整计算。`LibraryMainView` 已用 `SearchDebouncer` 防抖，此处应保持一致。

---

### #14 ImportService 重复日志行

- **文件**: `ImportService.swift` L16-17
- **验证**: 两行 `log.info("开始导入 \(urls.count) 个文件")` 连续存在
- **问题**: 复制粘贴遗留，同一日志打印两次。

---

### #15 PlayerView 中 8 处相同的 `asyncAfter` 模式

- **文件**: `PlayerView.swift`
- **验证**: `asyncAfter(deadline:` 出现 8 次
- **问题**:

```swift
activeSheet = nil
DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
    activeSheet = .sleepTimer
}
```

8 处相同模式，无法取消。用户快速连续操作时可能触发意外 sheet。应抽取为使用 `DispatchWorkItem` 的可取消方法。

---

### #16 ErrorLogger 每次创建新 DateFormatter

- **文件**: `AppError.swift` L151 / `TuneHavenCore/.../AppError.swift` L117
- **验证**: 两处 `ISO8601DateFormatter().string(from: Date())` 存在
- **问题**:

`AppLogger` 已用 `static let dateFormatter` 缓存，但 `ErrorLogger.isoDate()` 每次调用都创建新的 `ISO8601DateFormatter`。两个文件（主工程 + TuneHavenCore）都存在此问题。

---

## P3 建议

### #17 UserDefaults key 散落各处

- **文件**: `PlaybackService.swift`（15 次 UserDefaults 调用）、`ThemeManager.swift`、`WallpaperManager.swift`、`TuneHavenApp.swift`、`AppDelegate.swift`
- **验证**: 仅 `PlaybackService.swift` 就有 15 次 `UserDefaults.standard` 直接调用
- **问题**: 至少 8 个字符串 key 分布在不同文件，存在拼写错误风险，无编译器检查。

---

### #18 WiFiTransferServer 内嵌约 150 行 HTML/CSS/JS

- **文件**: `WiFiTransferServer.swift` L352-498
- **问题**: 前端代码混在 Swift 字符串中，无语法高亮、无法独立调试维护。

---

### #19 WiFiTransferServer `NWEndpoint.Port` 强制解包

- **文件**: `WiFiTransferServer.swift` L32
- **验证**: `NWEndpoint.Port(rawValue: port)!` 确实存在
- **问题**: 当前默认值 8080 不会触发崩溃，但缺乏防护。`NWEndpoint.Port(rawValue: 0)` 返回 `nil` 会导致崩溃。

---

## 修复优先级

### 第一批：解决白屏（最高优先级）

| # | 修复内容 | 预估 |
|---|----------|------|
| #1+#2+#3 | 移除 `window.overrideUserInterfaceStyle` 直接设置和 `UIWindow.appearance().overrideUserInterfaceStyle`，完全依赖 `.preferredColorScheme()`；`applyToWindows()` 仅保留 `window.backgroundColor` | 2h |
| #6 | Canvas 背景添加 `.drawingGroup()` | 0.5h |
| #7 | ThemeBackgroundView 移除 `.id(themeManager.currentStyle.id)` | 10min |

### 第二批：修复核心 Bug

| # | 修复内容 | 预估 |
|---|----------|------|
| #4 | Timer key 统一使用 `token.songIds.first` | 0.5h |
| #5 | PlaybackService 改为依赖注入 libraryService | 1h |

### 第三批：性能优化

| # | 修复内容 | 预估 |
|---|----------|------|
| #8 | fetchArtistDetail/fetchAlbumDetail 在数据库层面过滤 | 2h |
| #9 | toggleFavorite/softDelete 局部更新替代全量重载 | 1h |

### 第四批：代码质量

| # | 修复内容 | 预估 |
|---|----------|------|
| #10 | UIScreen.main 替换为 @Environment(\.colorScheme) / GeometryReader | 1h |
| #11 | 硬编码颜色替换为主题色 | 2h |
| #12-#16 | 其他代码质量问题 | 1.5h |
| #17-#19 | P3 建议项 | 1h |

---

**报告结束**
