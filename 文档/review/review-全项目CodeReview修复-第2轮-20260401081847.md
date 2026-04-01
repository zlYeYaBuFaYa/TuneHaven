# 方案 Review：全项目 Code Review 修复 - 第 2 轮

> 日期：2026-04-01 | 类型：AI 自审（第 1 轮发现问题并修复后确认轮）

## 结论：通过

| 维度 | 结论 | 说明 |
|------|------|------|
| 需求覆盖 | ✅ | 全部 64 项问题均已覆盖：54 项修复、7 项暂缓并说明原因、3 项标注为已知行为/设计 |
| 可执行性 | ✅ | 所有方案兼容 iOS 16.4 部署目标，第 1 轮修正了 `MainActor.assumeIsolated`（需 iOS 17+）的使用 |
| 描述清晰度 | ✅ | 每项均有文件路径 + 具体修改方案 + 伪代码，可直接据此编码 |
| 逻辑合理性 | ✅ | loadTask 取消机制 + 过期检查双重保障；两步查询过滤 softDeleted 逻辑正确 |
| 架构合规 | ✅ | BackgroundTaskProviding 遵循现有 DIP 模式；协议放 Domain 层，实现放 App 层 |
| 影响评估 | ✅ | D3/D4 协议变更已补充（第 1 轮修正），调用方影响已评估 |
| 边界处理 | ✅ | Task.isCancelled + currentSong?.id 检查；空 deletedIds 短路；nil loadTask?.cancel() 安全 |
| 性能考量 | ✅ | CoreData GROUP BY 替代内存分组；softDeleted 字段已有索引；TaskGroup 并发度 3 合理 |

## 第 1 轮发现的问题及修复记录

| # | 级别 | 问题 | 修复方式 |
|---|------|------|---------|
| 1 | 🔴 | A1/A3 使用 `MainActor.assumeIsolated` 需 iOS 17+ | 改为保持现有 `Task { @MainActor }` 模式 + 添加注释，标注为部署目标提升后优化 |
| 2 | 🟡 | C7（LyricsView）被错误归入 Domain 子批次 A | 移至 Presentation 子批次 C |
| 3 | 🟡 | D4 fetchAll 改 throws 未提及协议层变更 | 补充 `SongRepository` 协议签名同步修改 |
| 4 | 🟡 | D3 搜索历史方法改 throws 未提及协议层变更 | 补充 `SearchHistoryRepository` 协议签名同步修改 |
| 5 | 🟢 | 🟢20 ImageCacheManaging 去 UIKit 工作量被低估 | 改为暂缓，添加注释标注为架构债务 |
| 6 | 🟢 | 子批次执行顺序 D 应在 A 之前（A7 依赖 D） | 调整为 D → A → B → C |

## 第 2 轮新发现的问题及修复记录

| # | 级别 | 问题 | 修复方式 |
|---|------|------|---------|
| 7 | 🟢 | A1/A3 即使改为 `.receive(on:)` 仍需 `Task { @MainActor }` | 明确标注为"保持现有模式 + 注释"，列入暂缓项说明 |

所有问题均已修复，第 2 轮全部维度通过。
