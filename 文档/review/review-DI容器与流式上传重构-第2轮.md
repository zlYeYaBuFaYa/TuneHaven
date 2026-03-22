# 方案 Review：DI 容器与流式上传重构 - 第 2 轮

> 日期：2026-03-22 | 类型：AI 自审

## 结论：通过

| 维度 | 结论 | 说明 |
|------|------|------|
| 需求覆盖 | ✅ | 4 项 Review 问题全部覆盖：#30 DI 容器、#27 LyricsService 注入、#12 流式上传、#5 确认无需修改 |
| 可执行性 | ✅ | 第 1 轮的 3 个阻塞问题已修正：private init 处理、AudioEngine 渐进策略、class 替代 inout |
| 描述清晰度 | ✅ | 伪代码可直接编码，依赖关系和创建顺序清晰 |
| 逻辑合理性 | ✅ | DI 容器仅持有 let 属性（不触发视图重算），各 Service 独立注入；流式上传两阶段策略合理 |
| 架构合规 | ✅ | AppDIContainer 在 App 层，不违反 Clean Architecture 分层；WiFi 重构限于 Core 层内部 |
| 影响评估 | ✅ | 文件清单已更正（AudioEngine 不改动），PlaybackService.shared 引用已验证仅 1 处 |
| 边界处理 | ✅ | 临时文件清理（启动 + 正常流程 defer）、Header 过大防护（16KB 限制）、非上传请求兼容 |
| 性能考量 | ✅ | mmap 避免全量加载、内存峰值约等于 NWConnection 单次 receive 的 1MB buffer |

## 第 1 轮问题修复确认

| 问题 | 修复方式 | 验证 |
|------|----------|------|
| 🔴 PlaybackService private init | 改为 internal init，保持默认参数 | ✅ 方案已更新 |
| 🔴 AudioEngine private init | 容器使用 AudioEngine.shared，不改 AudioEngine | ✅ 方案已更新，文件清单已修正 |
| 🔴 StreamingUploadContext inout | 改为 class（引用类型） | ✅ 方案已更新，风险评估已更新 |
| 🟡 PlaybackService init 参数不完整 | 保持现有默认参数不变 | ✅ 方案已明确 |
| 🟡 LyricsService 需 ObservableObject | 已添加协议遵守说明 | ✅ 方案已更新 |
| 🟡 临时文件启动清理 | 已补充 cleanupTempFiles 方法和调用位置 | ✅ 方案已更新 |
| 🟡 进度中缺少文件名 | 接受空字符串，后续优化 | ✅ 已记录 |

## 遗留事项（非阻塞，可后续迭代）

1. AudioEngine.shared 完全移除 — 需扩大改动范围，建议下一轮 DI 重构处理
2. PlaybackService 内部创建的 PlayQueueService / MusicLibraryService — 建议 Clean Architecture 全面重构时统一处理
3. 上传进度的文件名 — 可在 body 前几次读取中解析 Content-Disposition，建议后续优化
4. LyricsServiceTests 中的 `LyricsService.shared` 引用 — 测试代码需同步更新
