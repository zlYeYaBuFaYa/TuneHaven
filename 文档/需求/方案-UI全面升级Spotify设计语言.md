# 方案：UI 全面升级 — Spotify 设计语言 + 主题重设计

> 创建日期：2026-03-22 | 状态：已完成

---

## 1. 需求概述

### 1.1 核心需求

将 TuneHaven 的 UI 从当前「标准 SwiftUI 列表风格」全面升级为「Spotify 式设计语言」，同时**推翻现有 6 套主题，重新设计 3 套主题**，取消日/夜/跟随系统颜色模式切换，每套主题固定一种色调。

### 1.2 设计语言核心特征

| # | 特征 | 说明 |
|---|------|------|
| 1 | 卡片化布局 + 圆角容器 | 列表行、歌单项、播放器组件均使用卡片化容器 |
| 2 | 毛玻璃材质 | `.ultraThinMaterial` 用于浮动层（迷你播放器、Tab 栏、弹窗背景） |
| 3 | 主题渐变色光晕 | 播放页背景使用主题渐变色模拟封面色提取效果 |
| 4 | 高信息密度 + 呼吸感 | 密而不挤，歌名+艺术家+专辑，但保持足够间距 |
| 5 | 丰富微交互 | 按压缩放、波形动画、入场过渡、hover 高亮 |
| 6 | 纯 palette 取色 | 消除所有硬编码颜色，统一通过 `@Environment(\.themePalette)` 获取 |

### 1.3 主题重设计

**架构变更**：
- 移除颜色模式切换（日间/夜间/跟随系统）
- 每套主题固定一种 `ColorScheme`，不提供 light/dark 变体
- 6 套旧主题 → 4 套新主题

**配色约束**：
- 禁用：土黄、卡其、深棕、芥末黄等暖棕色系
- 禁用：深绿色色系
- 禁用：蓝紫渐变色

**3 套新主题**：

| # | 名称 | 风格 | 固定色调 | 色板方案 |
|---|------|------|---------|---------|
| 1 | **素云白简** | 现代简约 | 浅色（`.light`） | 暖白底 `#F7F6F3` / 强调色清新绿 `#4CAF82` / 薄荷浅底 `#E8F5EE` / 文字深灰 `#2C2C2E` |
| 2 | **晴空蔚蓝** | 清朗明亮 | 浅色（`.light`） | 浅蓝白底 `#F5F8FC` / 天空蓝 `#4A9FD8` → 浅天蓝 `#7FC0E8` 渐变 / 文字深蓝灰 `#1C2D3E` |
| 3 | **暮光玫瑰** | 温暖优雅 | 深色（`.dark`） | 深梅紫底 `#1A1520` / 玫瑰粉 `#E87B8A` → 珊瑚 `#F2A8B0` 渐变 / 文字暖白 `#F0E0E2` |
| 4 | **星际穹顶** | 星空科技 | 深色（`.dark`） | 太空黑底 `#0B0E17` / 电子青 `#00D4AA` → 冷钴蓝 `#2979FF` 渐变 / 星点粒子背景动画 |

### 1.4 优化维度

- **D — 全面 UI 重设计**：视觉 + 交互 + 设计语言 + 主题重设计
- **范围**：全部页面 + 主题系统重构（~50 个文件）
- **风格方向**：Spotify 设计语言，3 套固定色调主题

### 1.5 约束

- 不改变播放、导入等功能逻辑和数据流
- 保持 Clean Architecture 分层
- 分批实施，按页面/模块拆分子任务
- iOS 18.1+ 部署目标（无需 `#available` 兼容处理，可直接使用 `symbolEffect`、`presentationBackground` 等最新 API）
- 配色禁区：土黄/深棕/卡其色系、深绿色系、蓝紫渐变色

### 1.6 验收标准

- 所有页面视觉风格统一为 Spotify 设计语言
- 所有颜色通过 palette 获取，无硬编码
- 4 套新主题在所有页面均正常显示，切换无异常
- 颜色模式切换功能已移除，设置页无此入口
- 旧主题文件已清理
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
| 9 | 主题系统 | 6 套主题配色不满意；light/dark 双色板维护成本高；颜色模式切换增加设置复杂度 | 高 |

### 2.2 需修改的文件清单

#### 主题系统 — 重构（8 文件改 + 6 文件删 + 3 文件新建）

**修改**：
- `TuneHaven/App/Theme/ThemeColorPalette.swift` — 扩展色板属性（新增 4 个）
- `TuneHaven/App/Theme/ThemeBackgroundView.swift` — ThemedCardModifier 硬编码修复 + cosmicParticles 动画
- `TuneHaven/App/Theme/ThemeManager.swift` — `ThemePaletteKey.defaultValue` 改为 `.cloudWhite.palette`；更新 `legacyMapping`（所有旧主题 ID 映射到 `cloud_white`）
- `TuneHaven/App/Theme/ThemeRegistry.swift` — 注册 4 套新主题替换 6 套旧主题；`defaultTheme` 改为 `.cloudWhite`
- `TuneHaven/App/Theme/WallpaperManager.swift` — 确认壁纸功能与新主题架构兼容
- `TuneHaven/App/AppStorageKey.swift` — 清理残留的 `colorMode` 常量

> 注：经代码验证，`ThemeManager` 已无 `colorMode` 属性，`SettingsAppearanceSection` 已无颜色模式选择器。颜色模式切换在之前迭代中已移除，仅需清理 `AppStorageKey` 中残留常量。

**删除（6 个旧主题文件）**：
- `ThemeStyle+MintBreeze.swift`（翠野清风）
- `ThemeStyle+DeepOcean.swift`
- `ThemeStyle+CyberNeon.swift`
- `ThemeStyle+GlacierBlue.swift`
- `ThemeStyle+AuroraDream.swift`
- `ThemeStyle+MidnightGold.swift`

**新建（4 个新主题文件）**：
- `ThemeStyle+CloudWhite.swift`（素云白简）
- `ThemeStyle+AzureSky.swift`（晴空蔚蓝）
- `ThemeStyle+TwilightRose.swift`（暮光玫瑰）
- `ThemeStyle+CosmicTech.swift`（星际穹顶）

> `ThemeVisualConfig.swift` 经评估无需修改。

#### 通用组件（8 文件）
- `TuneHaven/Presentation/Common/SongRow.swift`
- `TuneHaven/Presentation/Common/CoverImageView.swift`
- `TuneHaven/Presentation/Common/EmptyStateView.swift`
- `TuneHaven/Presentation/Common/SnackbarView.swift` — 3 处 `.white` 硬编码
- `TuneHaven/Presentation/Common/MiniPlayerBar.swift`
- `TuneHaven/Presentation/Common/NavigationBackgroundFixer.swift`
- `TuneHaven/Presentation/Common/ImportResultView.swift`
- `TuneHaven/Presentation/Common/QRCodeView.swift`

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
- `TuneHaven/Presentation/Playlist/PlaylistGroupView.swift`
- `TuneHaven/Presentation/Playlist/SongListView.swift`
- `TuneHaven/Presentation/Playlist/BatchAddSongsView.swift`

#### 播放器（4 文件）
- `TuneHaven/Presentation/Player/PlayerView.swift` — `.black.opacity()` 硬编码
- `TuneHaven/Presentation/Player/LyricsView.swift` — `.white`、`.black` 硬编码
- `TuneHaven/Presentation/Player/LyricsSearchView.swift` — 3 处 `.white` 硬编码
- `TuneHaven/Presentation/Player/PlayQueueView.swift`

#### 设置（5 文件）
- `TuneHaven/Presentation/Settings/SettingsView.swift`
- `TuneHaven/Presentation/Settings/SettingsImportSection.swift`
- `TuneHaven/Presentation/Settings/SettingsAppearanceSection.swift` — **移除颜色模式选择器** + 3 处 `.white` 硬编码
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

#### TuneHavenApp 入口（1 文件）
- `TuneHaven/TuneHavenApp.swift` — 移除 colorMode 相关的初始化/环境注入

### 2.3 对现有功能的影响

- **功能逻辑**：播放、导入、歌单等无影响
- **数据流**：无影响
- **主题系统**：**破坏性变更** — 6 套旧主题全部替换为 3 套新主题；移除颜色模式切换
- **用户设置迁移**：已保存的主题偏好和颜色模式偏好将失效，需提供默认值回退（默认选中「素云白简」）
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

#### 3.1.2 主题系统重构

**架构变更**：

```
旧架构：ThemeStyle = id + palette(light) + palette(dark) + visualConfig + colorMode
新架构：ThemeStyle = id + palette(固定) + colorScheme(固定) + visualConfig
```

**ThemeManager 变更**：
- 移除 `@Published var colorMode: ColorMode`
- 移除 `applyColorMode()` 相关逻辑
- `palette` computed property 简化为 `currentStyle.palette`（不再根据 light/dark 条件选择）
- `applyToWindows()` 使用 `currentStyle.colorScheme` 固定设置窗口 colorScheme
- UserDefaults 中 `colorMode` key 不再读写，已保存的值自动忽略

**ThemeRegistry 变更**：
- 注册 4 套新主题，移除 6 套旧主题
- 默认主题：素云白简（`cloud_white`）

**SettingsAppearanceSection 变更**：
- 仅保留「主题风格」选择区，展示 4 套主题的预览卡片

#### 3.1.3 新主题详细色板

**主题 1：素云白简**（`cloud_white`）— 现代简约 / `.light`

| # | 属性 | 色值 | 说明 |
|---|------|------|------|
| 1 | primary | `#4CAF82` | 清新绿 |
| 2 | primaryDark | `#3D9B70` | 深绿 |
| 3 | primaryLight | `#E8F5EE` | 薄荷浅底 |
| 4 | background | `#F7F6F3` | 暖白 |
| 5 | surface | `#FFFFFF` | 纯白 |
| 6 | surfaceSecondary | `#F0EFEC` | 浅灰 |
| 7 | textPrimary | `#2C2C2E` | 深灰 |
| 8 | textSecondary | `#8E8E93` | 中灰 |
| 9 | textTertiary | `#AEAEB2` | 浅灰 |
| 10 | separator | `#E5E5EA` | 分割线 |
| 11 | secondary | `#A8D4B8` | 淡绿 |
| 12 | accent | `#E8706A` | 珊瑚粉（收藏心形等） |
| 13 | highlight | `#E8F5EE` | 薄荷高亮 |
| 14 | gradientStart | `#4CAF82` | 清新绿 |
| 15 | gradientEnd | `#81C9A3` | 浅绿 |
| 16 | playerBackground | `#F0EFEC` | 播放页底色 |
| 17 | playerText | `#2C2C2E` | 播放页主文字 |
| 18 | playerSubtext | `#8E8E93` | 播放页次文字 |
| 19 | progressBackground | `#E0DFD9` | 进度条底色 |
| 20 | iconSecondary | `#AEAEB2` | 次要图标 |
| 21 | tagBackground | `#E8F5EE` | 标签底色 |
| 22 | tagText | `#3D9B70` | 标签文字 |
| 23 | elevatedSurface | `#FFFFFF` | 浮动卡片 |
| 24 | cardShadow | `#000000` opacity 0.06 | 卡片阴影 |
| 25 | miniPlayerBg | `#F7F6F3` opacity 0.92 | 迷你播放器降级色 |
| 26 | hoverHighlight | `#4CAF82` opacity 0.08 | 按压高亮 |

**主题 2：晴空蔚蓝**（`azure_sky`）— 清朗明亮 / `.light`

| # | 属性 | 色值 | 说明 |
|---|------|------|------|
| 1 | primary | `#4A9FD8` | 天空蓝 |
| 2 | primaryDark | `#3A86BE` | 深天蓝 |
| 3 | primaryLight | `#E3F0FA` | 浅蓝底 |
| 4 | background | `#F5F8FC` | 浅蓝白 |
| 5 | surface | `#FFFFFF` | 纯白 |
| 6 | surfaceSecondary | `#EDF2F8` | 淡蓝灰 |
| 7 | textPrimary | `#1C2D3E` | 深蓝灰 |
| 8 | textSecondary | `#7A8EA0` | 蓝灰 |
| 9 | textTertiary | `#A0B0C0` | 浅蓝灰 |
| 10 | separator | `#DDE6EF` | 蓝灰线 |
| 11 | secondary | `#7FC0E8` | 浅天蓝 |
| 12 | accent | `#E87070` | 珊瑚红（收藏心形等） |
| 13 | highlight | `#E3F0FA` | 浅蓝高亮 |
| 14 | gradientStart | `#4A9FD8` | 天空蓝 |
| 15 | gradientEnd | `#7FC0E8` | 浅天蓝 |
| 16 | playerBackground | `#EDF2F8` | 播放页底色 |
| 17 | playerText | `#1C2D3E` | 播放页主文字 |
| 18 | playerSubtext | `#7A8EA0` | 播放页次文字 |
| 19 | progressBackground | `#D5DEE8` | 进度条底色 |
| 20 | iconSecondary | `#A0B0C0` | 次要图标 |
| 21 | tagBackground | `#E3F0FA` | 标签底色 |
| 22 | tagText | `#3A86BE` | 标签文字 |
| 23 | elevatedSurface | `#FFFFFF` | 浮动卡片 |
| 24 | cardShadow | `#000000` opacity 0.06 | 卡片阴影 |
| 25 | miniPlayerBg | `#F5F8FC` opacity 0.92 | 迷你播放器降级色 |
| 26 | hoverHighlight | `#4A9FD8` opacity 0.07 | 按压高亮 |

**主题 3：暮光玫瑰**（`twilight_rose`）— 温暖优雅 / `.dark`

| # | 属性 | 色值 | 说明 |
|---|------|------|------|
| 1 | primary | `#E87B8A` | 玫瑰粉 |
| 2 | primaryDark | `#D0606E` | 深玫瑰 |
| 3 | primaryLight | `#F2A8B0` | 浅珊瑚 |
| 4 | background | `#1A1520` | 深梅紫 |
| 5 | surface | `#221A28` | 暗梅 |
| 6 | surfaceSecondary | `#2A1E30` | 中梅紫 |
| 7 | textPrimary | `#F0E0E2` | 暖白 |
| 8 | textSecondary | `#A08A92` | 暖灰 |
| 9 | textTertiary | `#6B5A65` | 暗暖灰 |
| 10 | separator | `#352840` | 梅紫线 |
| 11 | secondary | `#C96878` | 深玫瑰 |
| 12 | accent | `#E87B8A` | 玫瑰粉（收藏心形等） |
| 13 | highlight | `#2A1E30` | 梅紫高亮 |
| 14 | gradientStart | `#E87B8A` | 玫瑰粉 |
| 15 | gradientEnd | `#F2A8B0` | 浅珊瑚 |
| 16 | playerBackground | `#18121C` | 播放页深底 |
| 17 | playerText | `#F0E0E2` | 播放页主文字 |
| 18 | playerSubtext | `#A08A92` | 播放页次文字 |
| 19 | progressBackground | `#352840` | 进度条底色 |
| 20 | iconSecondary | `#6B5A65` | 次要图标 |
| 21 | tagBackground | `#2A1E30` | 标签底色 |
| 22 | tagText | `#F2A8B0` | 标签文字 |
| 23 | elevatedSurface | `#2A1E30` | 浮动卡片 |
| 24 | cardShadow | `#000000` opacity 0.30 | 卡片阴影 |
| 25 | miniPlayerBg | `#1A1520` opacity 0.92 | 迷你播放器降级色 |
| 26 | hoverHighlight | `#E87B8A` opacity 0.08 | 按压高亮 |

**主题 4：星际穹顶**（`cosmic_tech`）— 星空科技 / `.dark`

| # | 属性 | 色值 | 说明 |
|---|------|------|------|
| 1 | primary | `#00D4AA` | 电子青 |
| 2 | primaryDark | `#00B894` | 深电子青 |
| 3 | primaryLight | `#33E0BE` | 浅电子青 |
| 4 | background | `#0B0E17` | 太空黑 |
| 5 | surface | `#131829` | 深夜蓝 |
| 6 | surfaceSecondary | `#1A2038` | 暗蓝 |
| 7 | textPrimary | `#E8EAF0` | 星光白 |
| 8 | textSecondary | `#8A90A5` | 星尘灰 |
| 9 | textTertiary | `#565C75` | 暗星灰 |
| 10 | separator | `#232842` | 夜蓝线 |
| 11 | secondary | `#2979FF` | 冷钴蓝 |
| 12 | accent | `#FF6B8A` | 星红（收藏心形等） |
| 13 | highlight | `#1A2038` | 暗蓝高亮 |
| 14 | gradientStart | `#00D4AA` | 电子青 |
| 15 | gradientEnd | `#2979FF` | 冷钴蓝 |
| 16 | playerBackground | `#080B14` | 播放页深空底 |
| 17 | playerText | `#E8EAF0` | 播放页主文字 |
| 18 | playerSubtext | `#8A90A5` | 播放页次文字 |
| 19 | progressBackground | `#232842` | 进度条底色 |
| 20 | iconSecondary | `#565C75` | 次要图标 |
| 21 | tagBackground | `#1A2038` | 标签底色 |
| 22 | tagText | `#33E0BE` | 标签文字 |
| 23 | elevatedSurface | `#1A2038` | 浮动卡片 |
| 24 | cardShadow | `#000000` opacity 0.35 | 卡片阴影 |
| 25 | miniPlayerBg | `#0B0E17` opacity 0.92 | 迷你播放器降级色 |
| 26 | hoverHighlight | `#00D4AA` opacity 0.08 | 按压高亮 |

> 星际穹顶配有专属星点粒子背景动画（`ThemePatternType.cosmicParticles`）。

#### 3.1.4 主题色板扩展

在 `ThemeColorPalette` 中新增 4 个语义色属性：

```swift
var elevatedSurface: Color   // 浮动/突出卡片背景
var cardShadow: Color        // 卡片阴影色
var miniPlayerBg: Color      // 迷你播放器 material 降级色
var hoverHighlight: Color    // 列表行按压高亮色
```

**现有属性职责明确化**：

| 属性 | 用途 | 示例场景 |
|------|------|---------|
| `background` | 页面最底层背景 | 整体页面背景 |
| `surface` | 标准内容容器 | List 行背景、导航栏 |
| `elevatedSurface`（新） | 浮动/突出卡片 | 迷你播放器卡片、弹窗 |
| `surfaceSecondary` | 次级容器 | 搜索栏、输入框 |

#### 3.1.5 通用 ViewModifier / ButtonStyle

**复用现有 Modifier**，不新建冗余项：

```swift
// ✅ 复用现有 .themedCard() — 不新建 .spotifyCard()

// ✅ 新增 PressableButtonStyle
struct PressableButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.97
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

// ✅ 波形动画指示器（iOS 17 symbolEffect / iOS 16 TimelineView 降级）
struct WaveformIndicator: View {
    var body: some View {
        if #available(iOS 17, *) {
            Image(systemName: "waveform")
                .symbolEffect(.variableColor.iterative)
        } else {
            HStack(spacing: 2) { /* TimelineView + sin() 驱动 4 根柱子 */ }
        }
    }
}

// ✅ 可见行入场动画（delay 上限 0.3s）
extension View {
    func visibleRowEntrance(delay: Double) -> some View {
        self.modifier(VisibleRowEntranceModifier(delay: min(delay, 0.3)))
    }
}
```

### 3.2 详细实现

#### 批次 1：主题系统重构 + 通用组件升级

**ThemeColorPalette.swift**
- 新增 4 个语义色属性（`elevatedSurface`、`cardShadow`、`miniPlayerBg`、`hoverHighlight`）

**ThemeManager.swift**
- `ThemePaletteKey.defaultValue` 改为 `.cloudWhite.palette`
- 更新 `legacyMapping`：所有旧主题 ID（`mint_breeze`、`deep_ocean`、`cyber_neon`、`glacier_blue`、`aurora_dream`、`midnight_gold` 及更早的旧 ID）统一映射到 `cloud_white`
- `storedThemeStyle` 默认值改为 `"cloud_white"`

**ThemeRegistry.swift**
- `bootstrap()` 中注册 3 套新主题替换 6 套旧主题
- `defaultTheme` 改为 `.cloudWhite`

**AppStorageKey.swift**
- 清理残留的 `static let colorMode` 常量

**删除 6 个旧主题文件，新建 3 个**：
- 新建 `ThemeStyle+CloudWhite.swift`（素云白简完整色板）
- 新建 `ThemeStyle+GlacierSilver.swift`（冰川银辉完整色板）
- 新建 `ThemeStyle+CosmicTech.swift`（星际穹顶完整色板 + cosmicParticles 背景）

**ThemeBackgroundView.swift**
- `ThemedCardModifier` frosted 风格硬编码修复
- 新增 `cosmicParticles` 背景动画支持

**TuneHavenApp.swift**
- 确认主题偏好迁移由 ThemeManager.init() 的 legacyMapping 自动处理，无需额外改动（除非有 colorMode 相关代码残留）

**SongRow.swift**
- `onTapGesture` → `Button` + `PressableButtonStyle`
- 正在播放行：`palette.hoverHighlight` 背景 + `WaveformIndicator`

**CoverImageView.swift**
- 移除 `.white.opacity(0.8)` 硬编码

**SnackbarView.swift**
- 消除 `.white` 硬编码

**ImportResultView.swift / QRCodeView.swift**
- 清理硬编码颜色

#### 批次 2：Tab 栏 + 迷你播放器重设计

**RootTabView.swift — customTabBar**
- Tab 栏背景：毛玻璃 `.ultraThinMaterial`
- 选中 Tab：图标填充变体 + `palette.primary` + 底部小圆点指示器
- Tab 切换弹性动画

**MiniPlayerBar.swift**
- 圆角容器（16pt）+ 毛玻璃背景
- 进度条 2px → 3px，渐变色填充

#### 批次 3：音乐库页面

**LibraryMainView.swift**
- 标签栏：胶囊按钮 → 底线指示器
- `.white` 硬编码 → `palette.primary`

**AllSongsView.swift** — 工具栏 chip 样式、行间距
**ArtistListView / ArtistDetailView** — 卡片化、渐变头部
**AlbumGridView / AlbumDetailView** — 阴影圆角、沉浸式头部
**SearchResultView** — section 标题层级提升

#### 批次 4：歌单页面

**PlaylistMainView** — 阴影、tag 样式歌曲数
**PlaylistDetailView** — 封面放大 + 渐变背景
**PlaylistGroupView** — 视觉统一
**BatchAddSongsView** — 选中行高亮

#### 批次 5：播放页 + 歌词页

**PlayerView.swift**
- 渐变光晕背景（`palette.gradientStart/End`）
- 封面 85% → 75%，圆角 24 → 16
- 进度条 4px → 6px + 拖拽圆点
- `PressableButtonStyle` 播放按钮

**LyricsView.swift** — 加粗增强、渐变统一、硬编码审查
**LyricsSearchView.swift** — 3 处 `.white` 修复
**PlayQueueView.swift** — 与 SongRow 统一

#### 批次 6：设置页 + Sheet 弹窗

**SettingsAppearanceSection.swift**
- 「主题风格」展示 3 套新主题预览卡片（替换旧的 6 套预览）
- 3 处 `.white` 硬编码修复
- 确认无颜色模式选择器残留（经代码验证已无）

**SettingsView.swift + 其余 Section** — 折叠区圆角、行背景统一
**Sheet 弹窗** — palette 取色统一

#### 批次 7：Import 视图

8 个 Import 视图统一检查硬编码颜色和视觉风格。

### 3.3 备选方案

| 方案 | 说明 | 优缺点 |
|------|------|--------|
| A（推荐）：分 7 批逐步实施 | 每批独立可测，出问题易回滚 | 优：风险低、可控；缺：周期较长 |
| B：一次性全量重构 | 一次完成所有文件修改 | 优：一步到位；缺：改动量大、风险高 |
| C：仅重点页面 | 只改播放页 + 迷你播放器 + 音乐库 | 优：工作量小；缺：风格不统一 |

**推荐方案 A**：分 7 批逐步实施。

---

## 4. 影响范围

| 范围 | 影响 |
|------|------|
| 受影响模块 | Presentation 层全部页面、App/Theme 层、TuneHavenApp 入口 |
| 不受影响 | Domain 层、Data 层、Core 层、所有 Service（除 ThemeManager） |
| 数据库变更 | 无 |
| UserDefaults | `colorMode` key 废弃；`themeId` 若为旧主题 ID 则回退默认 |
| 向后兼容性 | 主题系统为破坏性变更，旧主题偏好自动迁移 |

---

## 5. 测试要点

| 场景 | 验证内容 |
|------|----------|
| 主题切换 | 4 套新主题逐一切换，所有页面颜色正确 |
| 默认主题 | 新安装/旧偏好迁移后默认显示「素云白简」 |
| 颜色模式确认 | 确认设置页无颜色模式入口（已在前序迭代移除）；AppStorageKey 残留已清理 |
| 旧主题清理 | 旧主题文件已删除，ThemeRegistry 无旧注册 |
| 动画流畅度 | Tab 切换、列表滚动、播放页转场无卡顿 |
| 无障碍 | SongRow Button 替换后 VoiceOver 可用 |
| 边界情况 | 空列表、超长歌名、无封面等场景视觉正常 |
| 回归测试 | 播放、收藏、删除、导入等功能不受影响 |
| 性能 | 毛玻璃/渐变效果不导致 GPU 过载；星际穹顶粒子动画帧率 |
| iOS 兼容性 | iOS 18.1+ 最新 API 直接可用，无降级路径 |
| 硬编码清查 | 全局搜索 `.white`、`.black`、`Color(hex`、`Color(red` 确认零遗漏 |

---

## 6. 风险评估

| 风险 | 概率 | 影响 | 应对策略 |
|------|------|------|----------|
| 旧主题偏好迁移失败 | 中 | 中 | ThemeManager 初始化时检测旧 ID → 回退默认主题；不 crash |
| 毛玻璃效果在旧设备卡顿 | 中 | 中 | 降级：`palette.miniPlayerBg` 半透明纯色替代 material |
| 多层 material 叠加 GPU 压力 | 中 | 中 | 三层 blur 在 iPhone SE 3 上测试帧率；低端设备降级 |
| 星际穹顶粒子动画性能 | 中 | 中 | 粒子数量控制在 30-50 个；使用 Canvas/TimelineView 而非大量 SwiftUI 视图 |
| 硬编码颜色遗漏 | 中 | 低 | 每批完成后全局搜索确认 |
| iOS 版本兼容 | — | — | iOS 18.1+ 部署，所有现代 API 直接可用，无需兼容处理 |
| 大列表入场动画性能 | 中 | 低 | 入场动画 delay 上限 0.3s |
| 移除颜色模式后用户不适应 | 低 | 低 | 3 套主题覆盖浅/冷/深三种基调，满足不同光线环境需求 |

---

## 7. 分批实施计划

| 批次 | 内容 | 文件操作 | 依赖 |
|------|------|---------|------|
| 1 | 主题系统重构 + 通用组件升级（ThemeColorPalette、ThemeManager、ThemeRegistry、ThemeStyle、ThemeBackgroundView、WallpaperManager、TuneHavenApp、删除 6 旧主题文件、新建 4 新主题文件、SongRow、CoverImage、EmptyState、Snackbar、ImportResultView、QRCodeView） | 改 13 + 删 6 + 新 4 | 无 |
| 2 | Tab 栏 + 迷你播放器（RootTabView、MiniPlayerBar） | 改 2 | 批次 1 |
| 3 | 音乐库页面（7 文件） | 改 7 | 批次 1 |
| 4 | 歌单页面（5 文件） | 改 5 | 批次 1 |
| 5 | 播放页 + 歌词页（4 文件） | 改 4 | 批次 1 |
| 6 | 设置页 + Sheet 弹窗（7 文件，含颜色模式移除） | 改 7 | 批次 1 |
| 7 | Import 视图（8 文件） | 改 8 | 批次 1 |

**总计：改 ~46 + 删 6 + 新建 3 = ~55 个文件操作**

> 批次 2-7 之间互相独立，可并行或任意顺序实施。批次 1 是所有后续批次的前置依赖。

---

## 原型参考

- Style B（Spotify 深色沉浸风）原型：`文档/ui-prototype/style-b-spotify.html`
- Style C（极简纯净风）原型：`文档/ui-prototype/style-c-minimal.html`（仅供对比参考）
