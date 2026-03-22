# 代码 Review：DI 容器与流式上传重构 - 第 2 轮

> 日期：2026-03-22 | 类型：AI 自审（确认修复） | 范围：9 个文件

## 结论：通过

| 维度 | 结论 | 说明 |
|------|------|------|
| 逻辑正确性 | ✅ | bodyReadLoop 错误/完成路径已分离，上传中断不再尝试解析不完整数据 |
| 错误处理 | ✅ | 连接错误时正确清理临时文件和状态 |
| 安全 | ✅ | 无新增安全问题 |
| 线程安全 | ✅ | @MainActor 一致，@unchecked Sendable 合理 |
| 架构合规 | ✅ | DI 容器在 App 层，Clean Architecture 依赖方向正确 |
| 代码风格 | ✅ | 命名一致、MARK 分组清晰、无多余 import |
| API 设计 | ✅ | 公开接口不变，内部方法签名合理（beginStreamingUpload 含 ip 参数） |
| 性能 | ✅ | mmap + 直写、两阶段解析 |
| 内存管理 | ✅ | [weak self]、FileHandle closeFile、临时文件 defer 清理 |
| 可维护性 | ✅ | DI 容器集中管理、两阶段解析职责分明 |

## 第 1 轮问题修复确认

| 问题 | 修复方式 | 验证 |
|------|----------|------|
| 🟡 bodyReadLoop 连接错误处理 | error != nil 时直接清理临时文件 + 重置状态，不进入 processUploadedTempFile | ✅ L182-187 |
| 🟢 beginStreamingUpload 丢失 IP | 添加 `ip: String` 参数，调用处传入 ip | ✅ L228, L150 |
| 🟢 TuneHavenApp import AVFoundation | 已移除 | ✅ L1 |

## 改动文件最终确认

| # | 文件 | 状态 |
|---|------|------|
| 1 | `TuneHaven/App/AppDIContainer.swift` | ✅ 新增，14 个 let 属性，无 @Published |
| 2 | `TuneHaven/App/TuneHavenApp.swift` | ✅ 1 个 @StateObject，9 处 container.xxx 引用 |
| 3 | `TuneHaven/Domain/Services/PlaybackService.swift` | ✅ shared 移除，init 可见性正确 |
| 4 | `TuneHaven/Domain/Services/LyricsService.swift` | ✅ shared 移除，ObservableObject 添加 |
| 5 | `TuneHaven/Presentation/Player/PlayerView.swift` | ✅ @EnvironmentObject lyricsService，3 处替换 |
| 6 | `TuneHaven/Presentation/Settings/SongInfoEditView.swift` | ✅ @EnvironmentObject lyricsService，2 处替换 |
| 7 | `TuneHaven/Presentation/Player/LyricsSearchView.swift` | ✅ @EnvironmentObject lyricsService，3 处替换 |
| 8 | `TuneHavenTests/LyricsServiceTests.swift` | ✅ LyricsService() 替代 .shared |
| 9 | `TuneHaven/Core/Network/WiFiTransferServer.swift` | ✅ 两阶段解析 + 流式写入 + 错误清理 + IP 保留 |

## 残留引用检查

- `LyricsService.shared`：源码 0 处、测试 0 处 ✅
- `PlaybackService.shared`：源码 0 处、测试 0 处 ✅
- Linter 错误：0 个 ✅
