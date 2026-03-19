# 白屏 Bug 修复方案

## 问题描述

| 编号 | 问题 | 触发条件 | 频率 |
|------|------|----------|------|
| Bug1 | 打开 app，切换别的应用，过一段时间后再切换到 app，屏幕白屏 | 后台 → 前台 | 偶发 |
| Bug2 | 设置-外观 切换主题，屏幕白屏，无法点击 | 主题切换 | 偶发 |

## 根因分析

两个 bug 的根本原因相同：**UIKit 窗口属性修改与 SwiftUI 视图渲染管线的时序竞争（Race Condition）**。

### 竞争链路

```
@Published currentStyle 变更 / @State paletteScheme 变更
    ↓ 触发 SwiftUI 视图树重算（耗时不确定）
    ↓ 同时
applyToWindows() / refreshWindows()
    ↓ 直接修改 UIKit window.backgroundColor、overrideUserInterfaceStyle
    ↓
SwiftUI 内容尚未渲染完成，UIKit 窗口背景色（白色/浅色）暴露 → 白屏
```

### 具体问题点

#### 问题点 1：`ThemeManager.setTheme()` 同步调用 `applyToWindows()`

**文件**：`TuneHaven/App/Theme/ThemeManager.swift` 第 134-138 行

```swift
func setTheme(_ style: ThemeStyle) {
    currentStyle = style          // ① @Published 触发全局 SwiftUI 重绘
    storedThemeStyle = style.id
    applyToWindows()              // ② 立即修改 UIKit window 属性（与 ① 竞争）
}
```

`currentStyle` 变更触发了所有观察 `themeManager` 的视图重建（包括 ThemeBackgroundView 切换复杂背景），而 `applyToWindows()` 在同一 RunLoop 中立即修改 UIKit 属性，两者时序不可控。

#### 问题点 2：`scenePhase == .active` 时多重操作叠加

**文件**：`TuneHaven/App/TuneHavenApp.swift` 第 93-110 行

```swift
case .active:
    playbackService.checkSleepTimerOnForeground()
    refreshPaletteScheme()          // ① 修改 @State → 视图树重建
    themeManager.refreshWindows()   // ② 立即修改 UIKit window
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
        themeManager.refreshWindows()  // ③ 0.15s 后再次修改 UIKit window
    }
```

App 从后台恢复时，系统本身在重建 UI 快照，叠加上述三重操作，竞争更严重。

#### 问题点 3：`onChange(colorMode)` 时序不合理

**文件**：`TuneHaven/App/TuneHavenApp.swift` 第 86-92 行

```swift
.onChange(of: themeManager.colorMode) { _, newMode in
    themeManager.applyToWindows()       // ① 立即修改 UIKit
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
        refreshPaletteScheme()          // ② 0.05s 后修改 SwiftUI 状态
    }
}
```

顺序错误：应该先让 SwiftUI 完成状态更新，再去修改 UIKit 窗口属性。

#### 问题点 4：ThemeBackgroundView 切换时无过渡

**文件**：`TuneHaven/App/Theme/ThemeBackgroundView.swift`

主题切换时 `codeGeneratedBackground` 分支变更，旧的 Canvas 重量级视图被销毁、新的被创建，过渡期间背景为空，UIKit window 背景色暴露。

#### 问题点 5：RootTabView 中 ThemeBackgroundView 缺少 identity

**文件**：`TuneHaven/Presentation/Root/RootTabView.swift` 第 21 行

```swift
ThemeBackgroundView()   // 无 .id()，SwiftUI diff 可能产生异常
```

---

## 修复方案

### 修复 1：ThemeManager — 延后 UIKit 操作，与 SwiftUI 解耦

**文件**：`TuneHaven/App/Theme/ThemeManager.swift`

**改动**：

1. `setTheme()` 中将 `applyToWindows()` 延后到下一个 RunLoop，让 SwiftUI 先完成当前帧的 diff 计算。
2. `refreshWindows()` 增加节流防护（throttle），避免短时间内重复调用。
3. 新增 `scheduleWindowRefresh()` 统一管理延后刷新逻辑。

```swift
// 修改前
func setTheme(_ style: ThemeStyle) {
    currentStyle = style
    storedThemeStyle = style.id
    applyToWindows()    // 同步调用，与 SwiftUI 竞争
}

// 修改后
func setTheme(_ style: ThemeStyle) {
    currentStyle = style
    storedThemeStyle = style.id
    scheduleWindowRefresh()    // 延后执行，让 SwiftUI 先完成渲染
}

private var pendingRefreshWork: DispatchWorkItem?

/// 统一的延后窗口刷新，自动去重
func scheduleWindowRefresh(delay: TimeInterval = 0.05) {
    pendingRefreshWork?.cancel()
    let work = DispatchWorkItem { [weak self] in
        self?.applyToWindows()
    }
    pendingRefreshWork = work
    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
}
```

**原理**：`DispatchWorkItem` + `cancel()` 实现去重，确保短时间内多次调用只执行最后一次。0.05s 的延迟让 SwiftUI 有时间完成视图 diff 和布局。

---

### 修复 2：TuneHavenApp — 优化 scenePhase 处理

**文件**：`TuneHaven/App/TuneHavenApp.swift`

**改动**：

1. `.active` 时：先 `refreshPaletteScheme()`（SwiftUI 状态），然后将 `refreshWindows()` 延后更长时间（0.3s），并移除 0.15s 的二次刷新。
2. 使用 `scheduleWindowRefresh()` 替代直接调用。

```swift
// 修改前
case .active:
    playbackService.checkSleepTimerOnForeground()
    refreshPaletteScheme()
    themeManager.refreshWindows()
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
        themeManager.refreshWindows()   // 二次刷新
    }

// 修改后
case .active:
    playbackService.checkSleepTimerOnForeground()
    refreshPaletteScheme()
    themeManager.scheduleWindowRefresh(delay: 0.3)   // 延后足够时间，让 SwiftUI 完成重建
```

**原理**：0.3s 足以让 SwiftUI 完成从后台恢复后的视图树重建。使用 `scheduleWindowRefresh` 自带去重，不再需要手动二次刷新。

---

### 修复 3：TuneHavenApp — 优化 colorMode 变更处理

**文件**：`TuneHaven/App/TuneHavenApp.swift`

**改动**：调整顺序，先更新 SwiftUI 状态，再延后刷新 UIKit。

```swift
// 修改前
.onChange(of: themeManager.colorMode) { _, newMode in
    themeManager.applyToWindows()       // 先 UIKit
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
        refreshPaletteScheme()          // 后 SwiftUI
    }
}

// 修改后
.onChange(of: themeManager.colorMode) { _, newMode in
    refreshPaletteScheme()                          // 先 SwiftUI
    themeManager.scheduleWindowRefresh(delay: 0.1)  // 后 UIKit（延后）
}
```

---

### 修复 4：ThemeBackgroundView — 添加过渡动画

**文件**：`TuneHaven/App/Theme/ThemeBackgroundView.swift`

**改动**：为背景切换添加 `transition` 和 `animation`，确保新旧背景有过渡期，避免渲染真空。

```swift
// 修改前
var body: some View {
    ZStack {
        if wallpaperManager.useCustomWallpaper, let image = wallpaperManager.currentWallpaper {
            userWallpaperBackground(image)
        } else {
            themeBackground
        }
    }
    .ignoresSafeArea()
}

// 修改后
var body: some View {
    ZStack {
        palette.background      // 保底纯色背景层，确保永远不透出 UIKit 窗口色

        if wallpaperManager.useCustomWallpaper, let image = wallpaperManager.currentWallpaper {
            userWallpaperBackground(image)
                .transition(.opacity)
        } else {
            themeBackground
                .id(themeManager.currentStyle.id)   // 明确 identity
                .transition(.opacity)
        }
    }
    .animation(.easeInOut(duration: 0.25), value: themeManager.currentStyle.id)
    .ignoresSafeArea()
}
```

**原理**：
- 底层增加一个 `palette.background` 纯色兜底层，即使上层背景在切换过渡中，用户也不会看到 UIKit window 的白色背景。
- `.id(themeManager.currentStyle.id)` 让 SwiftUI 在主题切换时明确知道身份变更，使用 `.transition(.opacity)` 做淡入淡出过渡。

---

### 修复 5：RootTabView — 为 ThemeBackgroundView 添加稳定 identity

**文件**：`TuneHaven/Presentation/Root/RootTabView.swift`

**改动**：

```swift
// 修改前
ZStack {
    ThemeBackgroundView()

// 修改后
ZStack {
    ThemeBackgroundView()
        .id("root_theme_bg")   // 稳定 identity，防止 SwiftUI diff 异常
```

---

## 涉及文件清单

| 文件 | 改动类型 |
|------|----------|
| `TuneHaven/App/Theme/ThemeManager.swift` | 修改 `setTheme()`，新增 `scheduleWindowRefresh()` |
| `TuneHaven/App/TuneHavenApp.swift` | 修改 `scenePhase` 处理、`colorMode` 处理、`initialize()` |
| `TuneHaven/App/Theme/ThemeBackgroundView.swift` | 添加保底背景层、transition 动画、id |
| `TuneHaven/Presentation/Root/RootTabView.swift` | 添加 ThemeBackgroundView 的稳定 id |

## 风险评估

- **风险等级**：低。改动主要是调整时序和添加过渡，不涉及业务逻辑变更。
- **副作用**：主题切换时会有 0.25s 的淡入淡出过渡动画，视觉上更平滑。
- **兼容性**：所有改动兼容 iOS 15.0+。
