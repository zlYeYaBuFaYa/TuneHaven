# 延后需求：Core 层 Review 遗留问题

> 创建日期：2026-03-24 | 来源：code-review-全量代码Review-模块4-Core层-20260323235952.md

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


