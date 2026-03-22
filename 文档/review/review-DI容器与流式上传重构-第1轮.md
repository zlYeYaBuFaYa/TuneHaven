# 方案 Review：DI 容器与流式上传重构 - 第 1 轮

> 日期：2026-03-22 | 类型：AI 自审

## 结论：不通过

| 维度 | 结论 | 说明 |
|------|------|------|
| 需求覆盖 | ✅ | 三项 Review 问题均已覆盖（#30 DI 重构、#27 LyricsService 注入、#12 流式上传、#5 确认无需修改） |
| 可执行性 | ❌ | 存在 3 个可执行性阻塞问题 |
| 描述清晰度 | ⚠️ | 伪代码整体清晰，但 StreamingUploadContext 的闭包捕获方式有误 |
| 逻辑合理性 | ⚠️ | PlaybackService init 改造方案与现有 `private init` 冲突 |
| 架构合规 | ✅ | DI 容器模式符合 Clean Architecture 依赖方向，容器在 App 层 |
| 影响评估 | ⚠️ | 遗漏了 PlaybackService 内部 AudioEngine 依赖的处理方式 |
| 边界处理 | ⚠️ | WiFi 上传中 App 进入后台 / 连接中断的临时文件清理需细化 |
| 性能考量 | ✅ | mmap 策略合理，内存峰值可控 |

## 问题

### 🔴 阻塞问题

#### 1. PlaybackService `private init` — 容器无法直接创建实例

方案中写 `self.playbackService = PlaybackService(engine: audioEngine)`，但实际 `PlaybackService` 的 init 是 `private`：

```swift
private init(playlistRepo: PlaylistRepository = CoreDataPlaylistRepository(),
            songRepo: SongRepository = CoreDataSongRepository())
```

**需二选一**：
- A. 将 `private init` 改为 `internal init`，容器外部创建（推荐 — 与 DI 模式一致）
- B. 保留 `static let shared`，容器通过 `PlaybackService.shared` 获取（最小改动但未消除单例）

→ 推荐 A：既然引入 DI 容器，就应该让容器成为唯一创建源。

#### 2. AudioEngine `private init` — 容器无法创建实例

`AudioEngine` 的 init 也是 `private`。方案中 `self.audioEngine = AudioEngine()` 无法编译。

**处理方式**：
- 本次保留 `AudioEngine.shared`（渐进策略在方案中已提及但 init 代码写错了）
- 容器中改为 `self.audioEngine = AudioEngine.shared`
- PlaybackService init 仍默认使用 `AudioEngine.shared`

#### 3. StreamingUploadContext `inout` 在闭包中不可用

方案中 `bodyReadLoop(context: inout StreamingUploadContext, ...)` 使用 `inout` 参数，但：
- NWConnection.receive 的闭包是 `@escaping` 的
- Swift 禁止 `@escaping` 闭包捕获 `inout` 参数

**修正**：将 `StreamingUploadContext` 改为 `class`（引用类型），闭包可直接持有引用并修改属性。

### 🟡 建议问题

#### 4. PlaybackService init 参数不完整

方案中 `PlaybackService(engine: audioEngine)` 只传了 engine，但实际 init 还创建了 `PlayQueueService()` 和 `MusicLibraryService()`。如果要让容器管理所有依赖，应考虑将这两个也通过参数注入。但这会扩大改动范围。

→ 建议本次仅将 `private init` 改为 `internal init`，保持现有默认参数不变。AudioEngine 注入可作为后续迭代。

#### 5. 遗漏：LyricsService 需声明 ObservableObject

方案中 `LyricsService` 改为通过 `@EnvironmentObject` 注入，但当前 `LyricsService` 未遵守 `ObservableObject`。需添加协议遵守。

> 实际上 `LyricsService` 没有 `@Published` 属性（无需驱动视图更新），添加 `ObservableObject` 遵守仅是为了满足 `@EnvironmentObject` 的类型约束。

#### 6. WiFi 上传 — 临时文件启动清理

方案提到"App 启动时扫描 `wifi_upload_*.tmp` 并清理"，但未说明在哪里实现。

→ 建议在 `TuneHavenApp.initialize()` 中添加 `WiFiTransferServer.cleanupTempFiles()` 调用。

#### 7. WiFi 上传 — 进度中缺少文件名

`updateTransferProgress` 中 `fileName` 传空字符串，因为文件名在 multipart header 中，流式写入阶段尚未解析 body。

→ 建议改进：文件名在 body 的 multipart header 部分（最前面几百字节），可以在 bodyReadLoop 的前几次读取中解析 Content-Disposition 获取文件名。但这会增加复杂度，建议本次接受空文件名，后续优化。

## 修改计划

1. 修正 PlaybackService：`private init` → `internal init`，保留默认参数
2. 修正 AudioEngine：容器中使用 `AudioEngine.shared`，不改 AudioEngine 本身
3. 修正 StreamingUploadContext：struct → class
4. 补充 LyricsService：添加 `: ObservableObject` 遵守
5. 补充临时文件清理位置
6. 更新方案文档中的对应代码示例
