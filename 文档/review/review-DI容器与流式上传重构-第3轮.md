# 方案 Review：DI 容器与流式上传重构 - 第 3 轮

> 日期：2026-03-22 | 类型：AI 深度自审（用户要求追加）

## 结论：不通过（发现 2 个 🟡 建议 + 2 个 🟢 优化，无 🔴 阻塞）

| 维度 | 结论 | 说明 |
|------|------|------|
| 需求覆盖 | ✅ | 不变 |
| 可执行性 | ⚠️ | TuneHavenApp 内部方法引用未更新、测试文件遗漏 |
| 描述清晰度 | ⚠️ | TuneHavenApp 重构伪代码仅展示了 body，遗漏了 initialize()、ensureOpenInHandler() 等方法体 |
| 逻辑合理性 | ✅ | 不变 |
| 架构合规 | ✅ | 不变 |
| 影响评估 | ⚠️ | 遗漏了测试文件的同步修改 |
| 边界处理 | ✅ | 不变 |
| 性能考量 | ⚠️ | processUploadedTempFile 中 parseMultipart 的 Data 拷贝可优化 |

## 问题

### 🟡 建议问题

#### 1. TuneHavenApp 内部方法中的 Service 引用未在方案中覆盖

方案中 TuneHavenApp 重构伪代码只展示了 `body` 部分和 `@StateObject` 声明，但以下方法体中直接引用了旧的 Service 属性名，重构后需全部改为 `container.xxx`：

| 方法 | 引用的属性 | 需改为 |
|------|-----------|--------|
| `initialize()` L117 | `playlistService` | `container.playlistService` |
| `initialize()` L118-119 | `libraryService` | `container.libraryService` |
| `initialize()` L121 | `playbackService` | `container.playbackService` |
| `initialize()` L131 | `themeManager` | `container.themeManager` |
| `ensureOpenInHandler()` L101-104 | `importService`, `libraryService`, `snackbar` | `container.xxx` |
| `onChange(scenePhase)` L80 | `playbackService` | `container.playbackService` |
| `onAppear` L74 | `themeManager` | `container.themeManager` |
| `body` L30 | `themeManager.palette.background` | `container.themeManager.palette.background` |
| `body` L67 | `themeManager.colorScheme` | `container.themeManager.colorScheme` |

共 9 处引用需要同步修改。方案的 TuneHavenApp 伪代码应补充 `initialize()` 和 `ensureOpenInHandler()` 的改写示例，避免编码阶段遗漏。

#### 2. LyricsServiceTests.swift 未列入文件修改清单

测试文件 `TuneHavenTests/LyricsServiceTests.swift` 第 11 行：

```swift
private let service = LyricsService.shared
```

移除 `LyricsService.shared` 后此处会编译失败。需改为：

```swift
private let service = LyricsService()
```

方案文件清单应增加此文件。

### 🟢 优化问题

#### 3. processUploadedTempFile — parseMultipart 中的 Data 拷贝

当前 `parseMultipart` 中写入文件的代码为：

```swift
try Data(fileData).write(to: destURL)
```

`Data(fileData)` 会从 mmap 映射中创建一份物理内存拷贝。对于 500MB 文件，此处仍会短暂占用 ~500MB 物理内存。

**优化建议**：改为直接写入，避免拷贝：

```swift
try fileData.write(to: destURL)
```

`fileData` 本身是 `Data`（mmap 支持的子范围），直接调用 `.write(to:)` 可让 OS 按页读取并写入，物理内存峰值大幅降低。

> 此问题属于 `parseMultipart` 的既有代码问题，但既然本次重构涉及上传链路，建议一并修复以确保 "≤ 10MB" 的验收标准。

#### 4. StreamingUploadContext — Swift 6 Sendable 合规

`StreamingUploadContext` 是 `class`（引用类型），在 NWConnection.receive 的 `@escaping` 闭包中跨隔离域传递（非 `@MainActor` 回调 → `Task { @MainActor ... }`）。Swift 6 严格并发模式下可能警告 non-Sendable 类型跨隔离域。

**建议**：添加 `@unchecked Sendable` 遵守，因为实际上所有读写都在 `@MainActor` 上执行：

```swift
private final class StreamingUploadContext: @unchecked Sendable {
    // ...
}
```

## 修改计划

1. 方案文档补充 TuneHavenApp 内部方法（`initialize()`、`ensureOpenInHandler()`）的改写示例
2. 文件修改清单增加 `TuneHavenTests/LyricsServiceTests.swift`
3. 需求 2 补充：`parseMultipart` 中 `Data(fileData)` 改为 `fileData` 直接写入
4. `StreamingUploadContext` 添加 `@unchecked Sendable`
