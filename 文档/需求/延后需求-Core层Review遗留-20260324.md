# 延后需求：Review 遗留问题

> 创建日期：2026-03-24 | 来源：模块 4 Core 层 / 模块 5 Presentation 层 Review

---

## 1. WiFiTransferServer 流式 multipart 解析（4.2.2）


| 属性   | 内容                                                                                                                                         |
| ---- | ------------------------------------------------------------------------------------------------------------------------------------------ |
| 等级   | 🟡 重要                                                                                                                                      |
| 文件   | `Core/Network/WiFiTransferServer.swift` L267-274                                                                                           |
| 维度   | 性能                                                                                                                                         |
| 问题   | `processUploadedTempFile` 通过 `Data(contentsOf:, options: .mappedIfSafe)` 将流式写入的临时文件全量回读到内存进行 multipart 解析。文件最大 500MB，大文件场景下内存峰值极高，可能触发 OOM |
| 建议   | 实现流式 multipart 解析器（基于 boundary 匹配 + 分段文件读取），避免全量加载。代码中已有 TODO 注释标注此问题                                                                      |
| 延后理由 | 需设计完整的流式解析器，涉及复杂的 boundary 匹配和分段读取逻辑，建议作为独立性能优化任务                                                                                          |


---

## 2. WiFiTransferServer 文件拆分（4.2.4）


| 属性   | 内容                                                                                                                                          |
| ---- | ------------------------------------------------------------------------------------------------------------------------------------------- |
| 等级   | 🟡 重要                                                                                                                                       |
| 文件   | `Core/Network/WiFiTransferServer.swift` 全文件（627 行）                                                                                          |
| 维度   | 可维护性                                                                                                                                        |
| 问题   | 单文件融合 HTTP 服务器生命周期管理、请求路由、密码认证、流式上传、multipart 解析、HTML 生成、网络工具等多个职责，违反单一职责原则                                                                 |
| 建议   | 按职责拆分为：`WiFiTransferServer`（生命周期 + 连接管理）、`WiFiHTTPHandler`（路由 + 响应构建）、`WiFiMultipartParser`（multipart 解析）；`WiFiTransferHTML` 已部分抽取可进一步独立为文件 |
| 延后理由 | 属于大型重构任务，拆分为 3+ 文件，需独立规划以确保不引入回归                                                                                                            |


---

## 3. CoreDataStack 容器名称更新（4.3.4）


| 属性   | 内容                                                                                             |
| ---- | ---------------------------------------------------------------------------------------------- |
| 等级   | 🟢 轻微                                                                                          |
| 文件   | `Core/Persistence/CoreDataStack.swift` L14                                                     |
| 维度   | 代码风格                                                                                           |
| 问题   | `NSPersistentContainer(name: "MusicPlayer")` 使用旧项目名 "MusicPlayer" 而非当前 App 名 "TuneHaven"，命名不一致 |
| 建议   | 在下次数据模型变更时一并修改容器名与 `.xcdatamodeld` 文件名，保持一致                                                    |
| 延后理由 | 不影响功能；修改需同步变更 .xcdatamodeld 文件名，建议在下次数据模型迭代时一并处理                                               |


---

## 4. 音频格式定义单一数据源（4.3.6）


| 属性   | 内容                                                                                            |
| ---- | --------------------------------------------------------------------------------------------- |
| 等级   | 🟢 轻微                                                                                         |
| 文件   | `Core/Utils/UTType+Audio.swift` L8-9                                                          |
| 维度   | 可维护性                                                                                          |
| 问题   | `UTType.allSupportedAudio` 与 `FileStorageService.supportedExtensions` 需手动同步，新增音频格式时易遗漏一方导致不一致 |
| 建议   | 定义单一数据源（如 `SupportedAudioFormat` 枚举），同时提供 `UTType` 和文件扩展名，消除手动同步需求                            |
| 延后理由 | 涉及跨模块联动（Core/Utils + Core/Storage + 可能的 AudioEngine），需统一设计格式注册机制                              |


---

## 5. RootTabView ZStack+opacity 全 Tab 常驻（5.1.3）


| 属性   | 内容                                                                                             |
| ---- | ---------------------------------------------------------------------------------------------- |
| 等级   | 🟡 重要                                                                                          |
| 文件   | `Presentation/Root/RootTabView.swift` L20-33                                                   |
| 维度   | 性能                                                                                             |
| 问题   | 使用 ZStack + opacity 管理 Tab 页面，三个 Tab 始终存在于视图层级中。不可见的 Tab 仍会接收 @Published 属性变化的 UI 更新，在数据频繁变化时可能产生不必要的视图重建 |
| 建议   | 通过 Instruments 监控不可见 Tab 的视图刷新频率；可考虑对不可见 Tab 使用 `.task(id:)` 机制暂停数据加载 |
| 延后理由 | 当前为切换流畅度和状态保持的合理权衡，需实际性能数据验证是否有优化必要                                     |


---

## 6. QRCodeView 直接引用 Core 层工具类（5.1.10）


| 属性   | 内容                                                            |
| ---- | ------------------------------------------------------------- |
| 等级   | 🟢 轻微                                                         |
| 文件   | `Presentation/Common/QRCodeView.swift` L13                    |
| 维度   | 架构合规                                                          |
| 问题   | Presentation 层直接引用 Core 层 `QRCodeGenerator` 工具类               |
| 建议   | 如需严格遵循架构，可通过协议抽象                                              |
| 延后理由 | 纯工具函数且无状态，当前实现可接受，仅作记录                                        |


---

## 7. PlayerView / LyricsPageView 手势逻辑重复（5.3.2）


| 属性   | 内容                                                            |
| ---- | ------------------------------------------------------------- |
| 等级   | 🟡 重要                                                         |
| 文件   | `Presentation/Player/LyricsView.swift` L77-174、`PlayerView.swift` L147-199 |
| 维度   | 可维护性                                                          |
| 问题   | 下拉/右滑关闭手势逻辑在两个文件中约 50 行相同代码，包括方向判断、偏移计算、阈值判断、动画恢复等 |
| 建议   | 提取为通用的 `DismissGestureModifier` 或工具方法复用，通过闭包参数传入 dismiss 行为 |
| 延后理由 | 两处手势上下文差异较大（PlayerView 有 showQueue/showLyricsPage guard 并调用 router.closePlayer()，LyricsView 调用 onDismiss()），强行提取会增加抽象复杂度，收益有限 |
