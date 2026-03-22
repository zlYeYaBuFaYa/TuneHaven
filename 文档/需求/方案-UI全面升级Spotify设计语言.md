# 方案：UI 全面升级 — Spotify 设计语言重构

> 创建日期：2026-03-22 | 状态：Review 通过（AI 自审 3 轮），待用户最终确认

---

## 1. 需求概述

### 1.1 核心需求

将 TuneHaven 的 UI 从当前「标准 SwiftUI 列表风格」全面升级为「Spotify 式设计语言」，涵盖视觉、交互、设计语言三个维度，覆盖全部页面和主题系统。

### 1.2 设计语言核心特征

| # | 特征 | 说明 |
|---|------|------|
| 1 | 卡片化布局 + 圆角容器 | 列表行、歌单项、播放器组件均使用卡片化容器 |
| 2 | 毛玻璃材质 | `.ultraThinMaterial` 用于浮动层（迷你播放器、Tab 栏、弹窗背景） |
| 3 | 主题渐变色光晕 | 播放页背景使用主题渐变色模拟封面色提取效果 |
| 4 | 高信息密度 + 呼吸感 | 密而不挤，歌名+艺术家+专辑，但保持足够间距 |
| 5 | 丰富微交互 | 按压缩放、波形动画、入场过渡、hover 高亮 |
| 6 | 纯 palette 取色 | 消除所有硬编码颜色，统一通过 `@Environment(\.themePalette)` 获取 |

### 1.3 优化维度

- **D — 全面 UI 重设计**：视觉 + 交互 + 设计语言
- **范围**：全部页面 + 主题系统升级（~50 个文件）
- **风格方向**：Spotify 深色沉浸风设计语言（同时适配浅色/深色模式）

### 1.4 约束

- 不改变任何功能逻辑和数据流
- 保持 Clean Architecture 分层
- 兼容现有 6 套主题 + 浅/深色模式（12 种外观）
- 分批实施，按页面/模块拆分子任务
- iOS 16.1+ 部署目标
- iOS 版本兼容策略：`symbolEffect` 等 iOS 17+ API 需使用 `if #available(iOS 17, *)` 保护，低版本提供静态替代；`presentationBackground` 需 iOS 16.4+，低版本使用 `.background()` 降级

### 1.5 验收标准

- 所有页面视觉风格统一为 Spotify 设计语言
- 所有颜色通过 palette 获取，无硬编码
- 6 套主题 x 2 种颜色模式 = 12 种外观均正常显示
- 动画流畅无卡顿
- 编译通过，现有测试不回归

---

## 2. 现状分析

### 2.1 当前 UI 问题总览

| # | 页面/组件 | 问题 | 严重度 |
|---|----------|------|--------|
| 1 | 播放页 | 封面占比 85% 过大，信息区/控制区拥挤；进度条仅 4px 交互困难；歌词预览区域简陋 | 高 |
| 2 | 迷你播放器 | 进度条仅 2px 几乎不可见；整体视觉平淡无层次感；缺少与全屏播放器的视觉关联 | 高 |
| 3 | 音乐库 | 搜索栏/标签栏/工具栏三层堆叠显得拥挤；标签栏胶囊按钮视觉权重过重；歌曲列表标准 List 缺乏特色 | 中 |
| 4 | 歌单页 | 系统歌单图标视觉较重；用户歌单行缺乏设计感；无歌单封面预览的视觉吸引力 | 中 |
| 5 | 设置页 | 折叠区域视觉层次单一；无图标/插图点缀 | 低 |
| 6 | 通用 | 缺少入场/过渡动画；按钮无按压反馈；列表项无交错进入效果；Tab 栏过于朴素 | 中 |
| 7 | 通用 | `SongRow` 用 `onTapGesture` 而非 `Button`，缺无障碍/触觉反馈 | 中 |
| 8 | 通用 | 部分颜色硬编码（`.white`、`.black.opacity()`）未使用 palette | 低 |

### 2.2 需修改的文件清单

#### 主题系统（8 文件）
- `TuneHaven/App/Theme/ThemeColorPalette.swift` — 扩展色板属性
- `TuneHaven/App/Theme/ThemeBackgroundView.swift` — 背景视图优化 + ThemedCardModifier 硬编码修复
- 各 `ThemeStyle+*.swift`（6 个文件）— 新增色板属性值

> `ThemeVisualConfig.swift` 经评估无需修改：现有 `tabBarBlur`、`cardStyle` 等配置已足够，新增色板属性不涉及 VisualConfig 层。

#### 通用组件（8 文件）
- `TuneHaven/Presentation/Common/SongRow.swift`
- `TuneHaven/Presentation/Common/CoverImageView.swift`
- `TuneHaven/Presentation/Common/EmptyStateView.swift`
- `TuneHaven/Presentation/Common/SnackbarView.swift` — 3 处 `.white` 硬编码
- `TuneHaven/Presentation/Common/MiniPlayerBar.swift`
- `TuneHaven/Presentation/Common/NavigationBackgroundFixer.swift`
- `TuneHaven/Presentation/Common/ImportResultView.swift` — 导入结果展示
- `TuneHaven/Presentation/Common/QRCodeView.swift` — 二维码页面

#### 根视图 + Tab 栏（1 文件）
- `TuneHaven/Presentation/Root/RootTabView.swift`

#### 音乐库（7 文件）
- `TuneHaven/Presentation/Library/LibraryMainView.swift` — `.white` 硬编码
- `TuneHaven/Presentation/Library/AllSongsView.swift`
- `TuneHaven/Presentation/Library/ArtistListView.swift`
- `TuneHaven/Presentation/Library/ArtistDetailView.swift` — `.black.opacity()` 硬编码
- `TuneHaven/Presentation/Library/AlbumGridView.swift`
- `TuneHaven/Presentation/Library/AlbumDetailView.swift` — `.black.opacity()` 硬编码
- `TuneHaven/Presentation/Library/SearchResultView.swift`

#### 歌单（5 文件）
- `TuneHaven/Presentation/Playlist/PlaylistMainView.swift`
- `TuneHaven/Presentation/Playlist/PlaylistDetailView.swift`
- `TuneHaven/Presentation/Playlist/PlaylistGroupView.swift` — 歌单分组管理（遗漏修复）
- `TuneHaven/Presentation/Playlist/SongListView.swift`
- `TuneHaven/Presentation/Playlist/BatchAddSongsView.swift`

#### 播放器（4 文件）
- `TuneHaven/Presentation/Player/PlayerView.swift` — `.black.opacity()` 硬编码
- `TuneHaven/Presentation/Player/LyricsView.swift` — `.white`、`.black` 硬编码
- `TuneHaven/Presentation/Player/LyricsSearchView.swift` — 3 处 `.white` 硬编码（遗漏修复）
- `TuneHaven/Presentation/Player/PlayQueueView.swift`

#### 设置（5 文件）
- `TuneHaven/Presentation/Settings/SettingsView.swift`
- `TuneHaven/Presentation/Settings/SettingsImportSection.swift`
- `TuneHaven/Presentation/Settings/SettingsAppearanceSection.swift` — 3 处 `.white` 硬编码
- `TuneHaven/Presentation/Settings/SettingsPlaybackSection.swift`
- `TuneHaven/Presentation/Settings/SettingsHelpers.swift`

#### Sheet 弹窗（2 文件）
- `TuneHaven/Presentation/Sheets/CreatePlaylistSheet.swift`
- `TuneHaven/Presentation/Sheets/PlayerSheets.swift`

#### Import 视图（8 文件）
- `TuneHaven/Presentation/Import/ImportFilesView.swift`
- `TuneHaven/Presentation/Import/WiFiTransferView.swift` — `.black.opacity()` 硬编码
- `TuneHaven/Presentation/Import/AppleMusicImportView.swift`
- `TuneHaven/Presentation/Import/CloudDriveImportView.swift`
- `TuneHaven/Presentation/Import/WebDAV/WebDAVAccountListView.swift`
- `TuneHaven/Presentation/Import/WebDAV/WebDAVAccountEditView.swift`
- `TuneHaven/Presentation/Import/WebDAV/WebDAVBrowserView.swift` — `.white` 硬编码
- `TuneHaven/Presentation/Import/WebDAV/WebDAVDownloadView.swift`

### 2.3 对现有功能的影响

- **功能逻辑**：无影响，仅修改视图层
- **数据流**：无影响
- **主题系统**：需扩展色板属性，现有属性不删除
- **性能**：毛玻璃和渐变效果可能增加 GPU 负载，需控制使用密度

---

## 3. 技术方案

### 3.1 整体设计

#### 3.1.1 设计语言规范

**间距系统**（8pt Grid）：

| Token | 值 | 用途 |
|-------|----|------|
| `xs` | 4pt | 图标与文字间距 |
| `sm` | 8pt | 卡片内边距、行内间距 |
| `md` | 12pt | 组件间距 |
| `lg` | 16pt | 区块间距 |
| `xl` | 24pt | 大区块间距 |
| `2xl` | 32pt | 页面边距 |

**圆角系统**：

| 元素 | 圆角 |
|------|------|
| 歌曲封面（小） | 8pt |
| 歌曲封面（大/播放页） | 16pt |
| 卡片/容器 | 12pt |
| 按钮（胶囊） | 全圆角 |
| 播放按钮 | 圆形 |
| 迷你播放器 | 16pt |

**字体层级**：

| 层级 | 样式 | 用途 |
|------|------|------|
| H1 | `.title2.bold()` | 页面大标题 |
| H2 | `.title3.bold()` | 播放页歌名 |
| Body | `.subheadline.weight(.medium)` | 列表项标题 |
| Caption | `.caption` | 艺术家、专辑、时间 |
| Overline | `.caption2` + tracking | 分类标签、状态文字 |

#### 3.1.2 主题色板扩展

在 `ThemeColorPalette` 中新增以下语义色（已去除与现有属性重叠的冗余项）：

```swift
// 新增属性（4 项）
var elevatedSurface: Color   // 层级高于 surface 的卡片背景（浅色: 纯白; 深色: 深灰偏亮）
var cardShadow: Color        // 卡片阴影色（浅色: 黑+低透明度; 深色: 黑+极低透明度）
var miniPlayerBg: Color      // 迷你播放器 material 降级色（material 不可用时的兜底纯色）
var hoverHighlight: Color    // 列表行按压高亮色（主色 + 极低透明度）
```

**已去除的冗余属性**：
- ~~`activeIndicator`~~ → 直接复用 `palette.primary`
- ~~`playerGlowStart/End`~~ → 复用现有 `palette.gradientStart/End`，播放页光晕通过 opacity 变化区分层次
- ~~`cardBackground`~~ → 重命名为 `elevatedSurface`，与 `surface` 的关系明确为「更高层级」

**现有属性职责明确化**：
| 属性 | 用途 | 示例场景 |
|------|------|---------|
| `background` | 页面最底层背景 | 整体页面背景 |
| `surface` | 标准内容容器 | List 行背景、导航栏 |
| `elevatedSurface`（新） | 浮动/突出卡片 | 迷你播放器卡片、弹窗 |
| `surfaceSecondary` | 次级容器 | 搜索栏、输入框 |

#### 3.1.3 通用 ViewModifier / ButtonStyle

**复用现有 Modifier**，不新建冗余项：

```swift
// ✅ 复用现有 .themedCard() — 扩展 ThemeCardStyle 枚举，不新建 .spotifyCard()
// 在各主题的 visualConfig 中调整 cardStyle 以适配 Spotify 风格

// ✅ 新增 PressableButtonStyle（ButtonStyle 而非 ViewModifier，配合无障碍）
struct PressableButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.97
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}
// 用法：Button { ... } label: { ... }.buttonStyle(PressableButtonStyle())

// ✅ 波形动画指示器组件
struct WaveformIndicator: View {
    // 使用 TimelineView 驱动 4 根柱子的高度变化
    // iOS 17+ 使用 .symbolEffect(.variableColor.iterative)
    // iOS 16 降级为 TimelineView + sin() 函数周期动画
    var body: some View {
        if #available(iOS 17, *) {
            Image(systemName: "waveform")
                .symbolEffect(.variableColor.iterative)
        } else {
            // TimelineView 降级方案
            HStack(spacing: 2) { /* 4根animated bars */ }
        }
    }
}

// ✅ 列表行入场动画（仅对可见区域内的行生效）
extension View {
    func visibleRowEntrance(delay: Double) -> some View {
        // 仅在 onAppear 时触发一次 opacity+offset 动画
        // delay 上限 0.3s，避免大列表尾部等待过长
        self.modifier(VisibleRowEntranceModifier(delay: min(delay, 0.3)))
    }
}
```

### 3.2 详细实现

#### 批次 1：主题色板扩展 + 通用组件升级

**ThemeColorPalette.swift**
- 新增 4 个语义色属性（`elevatedSurface`、`cardShadow`、`miniPlayerBg`、`hoverHighlight`）
- 各主题文件（6 个）补充新属性的 light/dark 值

**ThemeBackgroundView.swift**
- `ThemedCardModifier` frosted 风格：`.stroke(Color.white.opacity(0.12))` → `.stroke(palette.separator.opacity(0.3))`

**SongRow.swift**
- `onTapGesture` → `Button` + `.buttonStyle(PressableButtonStyle())`
- 行背景改为 `palette.surface`
- 正在播放行：背景 `palette.hoverHighlight`，左侧添加 `WaveformIndicator`（iOS 17 symbolEffect / iOS 16 TimelineView 降级）

**CoverImageView.swift**
- 占位图使用 `palette` 色，移除硬编码 `.white.opacity(0.8)`
- 圆角跟随父组件参数

**MiniPlayerBar.swift**
- 外层包裹圆角容器（16pt）+ 毛玻璃背景
- 左右 margin 8pt，悬浮在 Tab 栏上方
- 进度条从 2px → 3px，使用渐变色填充
- 封面增加微弱阴影

**SnackbarView.swift**
- 消除 `.white` 硬编码，使用 palette 语义色

**ImportResultView.swift**
- 检查并清理硬编码颜色，统一使用 palette
- 结果展示卡片应用 `.themedCard()` 风格

**QRCodeView.swift**
- 检查并清理硬编码颜色，统一使用 palette

#### 批次 2：Tab 栏 + RootTabView

**RootTabView.swift — customTabBar**
- Tab 栏背景改为毛玻璃 `.ultraThinMaterial`（统一浅深色）
- 选中 Tab 图标下方添加小圆点指示器（`palette.primary`）
- 图标选中态：填充变体 + 主色；未选中态：线框 + 次要色
- Tab 切换添加弹性动画

#### 批次 3：音乐库页面

**LibraryMainView.swift**
- 搜索栏：保持胶囊样式，优化内边距和视觉权重
- 标签栏：胶囊按钮 → 底线指示器样式（选中项底部 2px 主色线）
- 选中标签文字色：`.white` 硬编码 → `palette.primary`

**AllSongsView.swift**
- 工具栏增加筛选/排序的 chip 样式按钮
- 列表行间距微调
- 正在播放行高亮背景色

**ArtistListView.swift / ArtistDetailView.swift**
- 艺术家行卡片化
- 详情页头部使用渐变背景

**AlbumGridView.swift / AlbumDetailView.swift**
- 专辑网格增加阴影和圆角
- 详情页头部沉浸式渐变

**SearchResultView.swift**
- 结果分组优化，section 标题视觉层级提升

#### 批次 4：歌单页面

**PlaylistMainView.swift**
- 系统歌单行：保持图标+渐变，增加微弱阴影
- 用户歌单行：封面增加圆角阴影，歌曲数改为 tag 样式
- 整体从 `.insetGrouped` 调整为更紧凑的布局

**PlaylistDetailView.swift**
- 头部区域：歌单封面居中放大 + 渐变背景
- 歌曲列表视觉对齐音乐库

**PlaylistGroupView.swift**（遗漏修复）
- 分组管理页视觉统一

**BatchAddSongsView.swift**
- 选择状态视觉反馈增强（选中行高亮）

#### 批次 5：播放页 + 歌词页

**PlayerView.swift**
- 背景：多层渐变光晕（复用 `palette.gradientStart/End`，通过不同 opacity 层叠营造光晕效果）
- 封面：尺寸从 85% → 75%，圆角从 24 → 16，阴影使用 `palette.cardShadow`
- `.black.opacity()` 硬编码阴影 → `palette.cardShadow`
- 歌曲信息区：增加间距，歌词预览改为半透明卡片容器
- 进度条：高度从 4px → 6px，增加拖拽圆点指示器（hover 显示）
- 播放按钮：保持渐变圆形，`PressableButtonStyle` 按压缩放反馈
- 控制区整体间距优化

**LyricsView.swift**
- 当前行加粗效果增强
- 背景与播放页统一渐变
- `.white`、`.black` 硬编码 → palette 语义色（注意歌词渐变遮罩层的 `.black` 可能需保留，因其用于渐变透明度而非主题色 — 逐行审查决定）

**LyricsSearchView.swift**（遗漏修复）
- 3 处 `.foregroundColor(.white)` → 根据上下文使用 `palette.textPrimary` 或渐变按钮上的对比色

**PlayQueueView.swift**
- 行样式与 SongRow 统一
- 当前播放行高亮

#### 批次 6：设置页 + Sheet 弹窗

**SettingsView.swift + 各 Section**
- 折叠区标题增加圆角背景
- 行背景使用 `palette.surface`
- Section 图标视觉微调

**SettingsAppearanceSection.swift**
- 3 处 `.white` 硬编码 → palette 语义色

**Sheet 弹窗**
- 统一使用 `palette` 取色
- 弹窗圆角和背景优化

#### 批次 7：Import 视图（新增批次）

**统一检查以下 8 个 Import 视图的硬编码颜色和视觉风格**：
- `ImportFilesView.swift`
- `WiFiTransferView.swift` — `.black.opacity(0.15)` → `palette.cardShadow`
- `AppleMusicImportView.swift`
- `CloudDriveImportView.swift`
- `WebDAVAccountListView.swift`
- `WebDAVAccountEditView.swift`
- `WebDAVBrowserView.swift` — `.white` → `palette.textPrimary` 或适当语义色
- `WebDAVDownloadView.swift`

**优化内容**：
- 清理硬编码颜色，统一使用 palette
- 列表样式与音乐库/歌单页保持一致
- 按钮/操作区域应用 `PressableButtonStyle`

### 3.3 备选方案

| 方案 | 说明 | 优缺点 |
|------|------|--------|
| A（推荐）：分 7 批逐步实施 | 每批独立可测，出问题易回滚 | 优：风险低、可控；缺：周期较长 |
| B：一次性全量重构 | 一次完成所有文件修改 | 优：一步到位；缺：改动量大、风险高、Review 困难 |
| C：仅重点页面 | 只改播放页 + 迷你播放器 + 音乐库 | 优：工作量小；缺：风格不统一 |

**推荐方案 A**：分 7 批逐步实施，每批完成后独立 Review 和测试。

---

## 4. 影响范围

| 范围 | 影响 |
|------|------|
| 受影响模块 | Presentation 层全部页面、App/Theme 层 |
| 不受影响 | Domain 层、Data 层、Core 层、所有 Service |
| 数据库变更 | 无 |
| 向后兼容性 | 完全兼容，仅视图层变更 |
| 主题系统 | 扩展（新增属性），不删除现有属性 |

---

## 5. 测试要点

| 场景 | 验证内容 |
|------|----------|
| 主题切换 | 6 套主题逐一切换，所有页面颜色正确 |
| 颜色模式 | 日间/夜间/跟随系统三种模式，视觉正确 |
| 动画流畅度 | Tab 切换、列表滚动、播放页转场无卡顿 |
| 无障碍 | SongRow Button 替换后 VoiceOver 可用 |
| 边界情况 | 空列表、超长歌名、无封面等场景视觉正常 |
| 回归测试 | 播放、收藏、删除、导入等功能不受影响 |
| 性能 | 毛玻璃/渐变效果不导致 GPU 过载；多层 material 叠加测试 |
| iOS 兼容性 | iOS 16.1 设备上 `#available` 降级路径正常工作 |
| 硬编码清查 | 全局搜索 `.white`、`.black`、`Color(hex`、`Color(red` 确认零遗漏 |

---

## 6. 风险评估

| 风险 | 概率 | 影响 | 应对策略 |
|------|------|------|----------|
| 毛玻璃效果在旧设备卡顿 | 中 | 中 | 降级方案：使用 `palette.miniPlayerBg`（半透明纯色）替代 material |
| 多层 material 叠加 GPU 压力 | 中 | 中 | MiniPlayerBar + TabBar + NavigationBar 三层 blur 叠加时在 iPhone SE 3 上测试帧率；低端设备降级为纯色+opacity |
| 12 种外观组合有遗漏 | 高 | 低 | 每批完成后逐一验证 12 种组合 |
| 分批实施中间态风格不一致 | 中 | 低 | 按依赖关系排序批次，先底层后上层 |
| 硬编码颜色遗漏 | 中 | 低 | 每批完成后全局搜索 `.white`、`.black`、`Color(hex`、`Color(red` 确认清理完毕 |
| iOS 16.1 API 不兼容 | 低 | 高 | `symbolEffect` 使用 `if #available(iOS 17, *)` 保护；`presentationBackground` 使用 `if #available(iOS 16.4, *)` 保护 |
| 大列表入场动画性能 | 中 | 低 | 入场动画仅作用于首次 onAppear 的可见行，delay 上限 0.3s |

---

## 7. 分批实施计划

| 批次 | 内容 | 文件数 | 依赖 |
|------|------|--------|------|
| 1 | 主题色板扩展 + 通用组件升级（ThemeColorPalette、6x ThemeStyle+*、ThemeBackgroundView、SongRow、CoverImage、EmptyState、Snackbar、ImportResultView、QRCodeView） | 16 | 无 |
| 2 | Tab 栏 + 迷你播放器重设计（RootTabView、MiniPlayerBar） | 2 | 批次 1 |
| 3 | 音乐库页面（LibraryMainView、AllSongsView、ArtistListView、ArtistDetailView、AlbumGridView、AlbumDetailView、SearchResultView） | 7 | 批次 1 |
| 4 | 歌单页面（PlaylistMainView、PlaylistDetailView、PlaylistGroupView、SongListView、BatchAddSongsView） | 5 | 批次 1 |
| 5 | 播放页 + 歌词页（PlayerView、LyricsView、LyricsSearchView、PlayQueueView） | 4 | 批次 1 |
| 6 | 设置页 + Sheet 弹窗（SettingsView、SettingsImportSection、SettingsAppearanceSection、SettingsPlaybackSection、SettingsHelpers、CreatePlaylistSheet、PlayerSheets） | 7 | 批次 1 |
| 7 | Import 视图（ImportFilesView、WiFiTransferView、AppleMusicImportView、CloudDriveImportView、4x WebDAV 视图） | 8 | 批次 1 |

**总计：~50 个文件**（含 6 个主题配色文件）

> 批次 2-7 之间互相独立，可并行或任意顺序实施。批次 1 是所有后续批次的前置依赖。

---

## 原型参考

- Style B（Spotify 深色沉浸风）原型：`文档/ui-prototype/style-b-spotify.html`
- Style C（极简纯净风）原型：`文档/ui-prototype/style-c-minimal.html`（仅供对比参考）
