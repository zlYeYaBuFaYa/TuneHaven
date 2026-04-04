# 全项目代码 Review 方案

> 创建日期：2026-04-04 | 状态：Review 通过

---

## 1. Review 背景

TuneHaven 项目经过多次迭代（播放器重构、歌单分享、订阅系统、全项目 Code Review 修复等），累积了 **183 个 Swift 源码文件**（约 **21,197 行**）和 **22 个测试文件**。上一轮全项目 Code Review 修复（`2026-04-01`）解决了 12 项阻塞级问题 + 3 项二轮修复（含 P0 竞态、P1 用户体验、P2 代码质量共 60+ 项），此后又完成了订阅系统实现（`2026-04-04`）。

当前需要对全项目进行系统性代码 Review，确保多轮迭代后的整体代码质量、架构合规性、以及各模块间集成的正确性。

---

## 2. Review 目标

| # | 目标 | 对应 Review 机制 |
|---|------|-----------------|
| 1 | **架构合规性** | 11 项 Review 维度中的「架构合规」 |
| 2 | **代码正确性与安全** | 11 项 Review 维度中的「逻辑正确性」「错误处理」「安全」「线程安全」 |
| 3 | **代码质量** | 11 项 Review 维度中的「代码风格」「API 设计」「代码整洁」「可维护性」 |
| 4 | **性能与内存** | 11 项 Review 维度中的「性能」「内存管理」 |
| 5 | **测试覆盖** | R15 子任务专项评估 |
| 6 | **回归验证** | R0 子任务专项验证 |
| 7 | **跨模块集成** | 所有子任务完成后的集成 Review 专项 |

> 目标 1~4 通过每个子任务（R1~R15）的 11 项 Review 维度落实；目标 5~7 通过专项子任务或专项流程落实。

---

## 3. Review 维度（11 项）

### A. 正确性与安全

| 维度 | 检查项 |
|------|--------|
| 逻辑正确性 | 业务逻辑完整、边界充分、状态一致、竞态防护 |
| 错误处理 | AppError 统一类型、传播链完整（Core/Data→Service→View）、ErrorLogger 记录 |
| 安全 | 输入校验、SandboxPathManager 路径、SecurityScoped URL、无硬编码敏感信息 |
| 线程安全 | @MainActor 正确、CoreData 双上下文、Combine sink 桥接、weak self |

### B. 质量与规范

| 维度 | 检查项 |
|------|--------|
| 架构合规 | Clean Architecture 分层、依赖单向、Repository 隔离、Service 即 ViewModel |
| 代码风格 | 驼峰命名、Swift 6.0 惯用法、格式一致、访问控制合理、无冗余代码 |
| API 设计 | 接口语义清晰、参数合理、async throws 一致、与现有风格统一 |
| 代码整洁 | 无死代码、无未使用 import、无废弃函数/类型、无注释代码块、无冗余文件 |

### C. 性能与可维护

| 维度 | 检查项 |
|------|--------|
| 性能 | 复杂度合理、无循环引用、避免不必要的计算/视图重建、懒加载 |
| 内存管理 | [weak self] 正确、大对象及时释放、cancellables 正确存储 |
| 可维护性 | SOLID、DRY、低耦合高内聚、职责单一、可扩展 |

### 问题分级

- 🔴 **阻塞**：逻辑错误、崩溃风险、安全漏洞、数据损坏
- 🟡 **重要**：性能隐患、可维护性问题、架构违规
- 🟢 **轻微**：风格微调、命名优化、性能小优化

### 通过标准

**R1~R15 通过条件**：11 项 Review 维度全部 ✅，且无任何级别（🔴🟡🟢）的未修复问题。

**R0（回归验证）通过条件**：上轮修复清单中的每一项修复均经逐项验证仍然有效（代码存在且逻辑未被后续迭代破坏）。若发现任何修复被回退或失效，记录为 🔴 阻塞问题，修复后方可通过。

### 已知技术债务处理

上轮 Review 明确标注了 9 项「暂缓/不修改」的已知技术债务（A1/A2/A3/B5/E1/F2/🟢11/🟢18/🟢20）。本轮 Review 遇到这些位置时：

1. **确认暂缓原因是否仍然成立**（如 iOS 16.4 部署目标限制、改动面过大等）
2. 原因仍成立 → 维持暂缓，不重复标记为问题
3. 原因已消失（如部署目标已提升）→ 重新标记为待修复问题

---

## 4. Review 范围与文件分布

### 4.1 项目整体规模

| 层级 | 目录 | 文件数 | 说明 |
|------|------|--------|------|
| **Core** | `Core/Audio` | 4 | 音频引擎、会话管理、锁屏 |
| | `Core/Cache` | 2 | 图片缓存 |
| | `Core/Network` | 7 | WiFi、WebDAV Client、分享 Server/Client |
| | `Core/Persistence` | 2 | CoreData 栈与迁移 |
| | `Core/Storage` | 2 | 文件存储、沙盒路径 |
| | `Core/Utils` | 10 | AppError、ErrorLogger、扩展、工具 |
| **Data** | `Data/Repositories` | 4 | CoreData Repository 实现 |
| | `Data/Mappers` | 3 | Entity 映射 |
| | `Data/MetadataParser` | 1 | 音频元数据解析 |
| | `Data/Extensions` + 根 | 2 | 扩展、WebDAV 账户存储 |
| **Domain** | `Domain/Entities` | 12 | 业务实体 |
| | `Domain/Repositories` | 20 | Repository 协议 |
| | `Domain/Services` | 14 | 核心业务服务 |
| **App** | `App` 根 | 10 | 入口、DI、偏好 |
| | `App/Theme` | 13 | 主题、壁纸、调色板 |
| | `App/Navigation` | 2 | 导航路由 |
| **Presentation** | `Common` | 20 | 通用组件 |
| | `Player` + `Root` | 9 | 播放器、根视图 |
| | `Library` | 9 | 音乐库 |
| | `Playlist` + `Sheets` | 8 | 歌单、弹窗 |
| | `Import` + `Import/WebDAV` | 10 | 导入 |
| | `Share` | 7 | 分享 |
| | `Settings` | 11 | 设置 |
| | `Subscription` | 1 | 订阅 |
| **Tests** | `TuneHavenTests` | 22 | 单元测试 |
| | `TuneHavenUITests` | 2 | UI 测试 |
| **合计** | | **207** | |

---

## 5. Review 分组策略

根据架构分层和功能模块，将 Review 拆分为 **16 个子任务**，确保每个子任务关注点单一、粒度适中（一般 7~20 个文件，测试类子任务因文件结构统一可适当放宽至 25 个）。严格按线性顺序从底层到上层逐个执行。

### 5.1 子任务列表

| # | 子任务 | 涉及目录 | 文件数 | 重点关注 |
|---|--------|----------|--------|----------|
| R0 | **上轮修复回归验证** | 跨层（上轮修复涉及的 ~30 个文件） | 专项 | 逐项验证上轮修复（P0 竞态 ×1、P1 用户体验 ×3、P2 代码质量 4 批次共 60 项，含 9 项暂缓）是否仍然有效、未被后续迭代破坏 |
| R1 | **Core - 音频/缓存/持久化/存储** | `Core/Audio`、`Core/Cache`、`Core/Persistence`、`Core/Storage` | 10 | AudioEngine 状态机、CoreData 栈线程安全、文件沙盒路径、图片缓存内存管理 |
| R2 | **Core - 网络** | `Core/Network` | 7 | WiFi/WebDAV/分享网络层正确性、连接管理、超时处理、资源释放 |
| R3 | **Core - 工具与错误处理** | `Core/Utils` | 10 | AppError 体系完整性、ErrorLogger 线程安全、工具类职责单一、扩展合理性 |
| R4 | **Data 层** | `Data/` 全部 | 10 | Repository 实现与 Protocol 一致性、Mapper 映射完整性、CoreData 上下文使用、元数据解析健壮性 |
| R5 | **Domain - 实体** | `Domain/Entities` | 12 | Entity 设计合理性、Sendable 一致性、值类型语义、类型安全 |
| R6 | **Domain - Repository 协议** | `Domain/Repositories` | 20 | 接口设计一致性、async throws 统一、命名规范、与 Data 层实现匹配度 |
| R7 | **Domain - 业务服务** | `Domain/Services` | 14 | 服务间耦合度、状态管理一致性、async/await 正确性、竞态防护、错误传播链 |
| R8 | **App - 入口/DI/导航** | `App/` 根 + `App/Navigation` | 12 | DI 容器初始化顺序与完整性、生命周期管理、导航路由状态管理 |
| R9 | **App - 主题系统** | `App/Theme` | 13 | 主题切换线程安全、调色板完整性、壁纸管理内存、ThemeManager 状态一致性 |
| R10 | **Presentation - 通用组件** | `Presentation/Common` | 20 | 组件复用性、接口一致性、视图重建优化、@Environment 使用 |
| R11 | **Presentation - 播放器** | `Presentation/Player` + `Presentation/Root` | 9 | 播放器 UI 状态同步、进度条精度、控制栏交互、根视图 Tab 切换 |
| R12 | **Presentation - 音乐库与歌单** | `Presentation/Library` + `Presentation/Playlist` + `Presentation/Sheets` | 17 | 列表性能、批量操作正确性、搜索交互、Sheet 生命周期 |
| R13 | **Presentation - 导入与分享** | `Presentation/Import` + `Presentation/Share` | 17 | 导入流程完整性、WebDAV 错误恢复、分享网络异常处理、大文件传输内存 |
| R14 | **Presentation - 设置与订阅** | `Presentation/Settings` + `Presentation/Subscription` | 12 | 设置项持久化一致性、订阅状态同步、StoreKit 交互、功能门控正确性 |
| R15 | **测试代码** | `TuneHavenTests/` + `TuneHavenUITests/` | 24 | 测试覆盖率评估、Mock 完整性、断言质量、边界用例、测试命名规范、测试盲区识别 |

### 5.2 跨模块集成 Review（所有子任务完成后）

| 检查维度 | 内容 |
|----------|------|
| 依赖方向 | 验证无下层→上层反向依赖，Domain 层无 import UIKit/SwiftUI |
| DI 完整性 | 所有 Service 是否都通过 AppDIContainer 注入，是否存在遗漏 |
| 接口一致性 | Repository Protocol 与实现是否完全匹配，Service Protocol 与使用方是否一致 |
| 数据流完整性 | 从 CoreData 到 UI 的数据流是否通畅，@Published 驱动链是否完整 |
| 错误传播链 | AppError 从 Core→Data→Domain→Presentation 的传播是否连贯 |
| 主题一致性 | 所有视图是否通过 `@Environment(\.themePalette)` 获取颜色 |
| 全局状态 | .shared 单例使用是否合理，是否存在不必要的全局状态 |
| 死代码 | 跨模块层面是否存在未被任何调用方引用的 public/internal 接口 |

---

## 6. 执行流程

### 6.1 执行顺序

严格线性执行，同一时间仅有一个子任务处于进行中状态：

```
R0（回归验证）→ R1（Core-音频基础设施）→ R2（Core-网络）→ R3（Core-工具）
  → R4（Data层）→ R5（Domain-实体）→ R6（Domain-协议）→ R7（Domain-服务）
  → R8（App-入口DI）→ R9（App-主题）
  → R10（Presentation-通用）→ R11（Presentation-播放器）→ R12（Presentation-库歌单）
  → R13（Presentation-导入分享）→ R14（Presentation-设置订阅）
  → R15（测试代码）→ 跨模块集成Review → 汇总报告
```

底层优先：先 Review Core/Data/Domain 层，确保基础正确后再 Review 上层。

### 6.2 每个子任务的执行步骤

1. **列出文件清单**：确认该子任务涉及的所有 `.swift` 文件及其行数
2. **逐文件审查**：按 11 项 Review 维度逐文件检查
3. **记录问题**：按 🔴🟡🟢 分级记录，附文件名、行号、问题描述、修复建议
4. **子任务小结**：输出该子任务的 11 维度结论 + 问题列表
5. **产出报告**：写入独立的子任务 Review 报告文件

### 6.3 轮次与修复规则

每个子任务**独立走「Review → 修复 → 确认」循环**，而非整个项目一起走轮次：

```
子任务 Rx 第 1 轮 Review
  → 发现问题 → 生成修复代码 → 重跑相关测试确认无回归
  → 子任务 Rx 第 2 轮 Review（确认修复 + 检查是否引入新问题）
  → 通过 → 标记完成 → 进入子任务 R(x+1)
```

| 规则 | 说明 |
|------|------|
| 最少轮次 | **2 轮**（即使第 1 轮无问题，第 2 轮做确认） |
| 最多轮次 | **5 轮**，超限暂停汇报用户 |
| 通过条件 | 11 项维度全部 ✅，零未修复问题（🔴🟡🟢 全部修复） |
| 修复后验证 | 每次修复后必须重跑相关测试，确认无回归 |
| 第 2 轮起策略 | 可采用增量确认：仅复查修复点 + 修复可能影响的关联代码，无需重走全部维度。若增量确认发现新问题，回退到全量 Review |

### 6.4 修复阶段规范

Review 发现问题后的修复执行规范：

| 项目 | 规范 |
|------|------|
| 修复范围 | 按当前子任务涉及的文件范围内修复，跨子任务的问题记录后留到对应子任务处理 |
| 修复方式 | 🔴🟡🟢 三个级别的问题全部直接修复代码 |
| 复杂修复 | 单个问题修复涉及 ≥3 个文件或逻辑复杂时，先生成修复方案（`文档/需求/方案-全项目CodeReview修复-{时间戳}.md`）再执行 |
| 测试要求 | 修复后必须重跑 `xcodebuild test` 确认无回归 |
| 修复提交 | 每个子任务修复完成后独立 `git commit`，message 格式：`refactor: code review R{x} 修复（{问题数}项）` |

---

## 7. 产出物

### 7.1 文件清单

| 产出物 | 路径 | 说明 |
|--------|------|------|
| 子任务 Review 报告 | `文档/review/code-review-全项目-R{x}-{子任务名}-{yyyyMMddHHmmss}.md` | 每个子任务每轮独立一份 |
| 集成 Review 报告 | `文档/review/code-review-全项目-集成Review-{yyyyMMddHHmmss}.md` | 跨模块集成 Review 一份 |
| 汇总报告 | `文档/review/code-review-全项目-汇总-{yyyyMMddHHmmss}.md` | 最终汇总，含所有子任务结论 |
| 修复方案（如需） | `文档/需求/方案-全项目CodeReview修复-{yyyyMMddHHmmss}.md` | 仅复杂修复时生成 |
| 修复代码 | 对应源码文件 | 按 Review 报告修复 |

### 7.2 子任务 Review 报告模板

```markdown
# 全项目代码 Review - R{x}：{子任务名} - 第 {N} 轮

> 日期：YYYY-MM-DD | 类型：AI 自审

## 文件清单

| 文件 | 行数 |
|------|------|
| ... | ... |

## 结论：通过 / 不通过

| 维度 | 结论 | 说明 |
|------|------|------|
| 逻辑正确性 | ✅/❌ | ... |
| 错误处理 | ✅/❌ | ... |
| 安全 | ✅/❌ | ... |
| 线程安全 | ✅/❌ | ... |
| 架构合规 | ✅/❌ | ... |
| 代码风格 | ✅/❌ | ... |
| API 设计 | ✅/❌ | ... |
| 代码整洁 | ✅/❌ | ... |
| 性能 | ✅/❌ | ... |
| 内存管理 | ✅/❌ | ... |
| 可维护性 | ✅/❌ | ... |

## 问题列表（如有）

| # | 级别 | 文件:行号 | 描述 | 修复建议 |
|---|------|----------|------|----------|
| 1 | 🔴/🟡/🟢 | ... | ... | ... |

## 修改记录（第 2 轮起）

| 原问题 # | 修改方式 | 验证结果 |
|----------|---------|---------|
| ... | ... | ... |
```

---

## 8. 重点关注领域

基于项目迭代历史和上轮 Review 修复记录，以下领域需**重点审查**：

### 8.1 上轮修复回归（R0 专项）

上轮（`方案-全项目CodeReview修复-20260401081256.md`）修复清单：

| 批次 | 内容 | 涉及文件 | 验证要点 |
|------|------|----------|---------|
| P0 | PlaybackService loadTask 竞态修复 | `PlaybackService.swift` | loadTask cancel/check 机制是否仍存在 |
| P1-H1/H2 | 歌单歌曲计数排除 softDeleted | `CoreDataPlaylistRepository.swift`、`CoreDataPlaylistGroupRepository.swift` | softDeleted 过滤是否仍在 batchSongCounts 中 |
| P1-G1 | WebDAVAccountStore deleteAccount 同步化 | `WebDAVAccountStore.swift` | 是否仍为 queue.sync |
| P1-D1 | ImportService 封面错误传播 | `ImportService.swift` | try? 是否已改为 try + catch |
| P2-A | Domain 层修复（Task @MainActor 注释、Sendable 等） | 8 个 Domain 层文件 | 注释和声明是否保留 |
| P2-B | Data 层修复（聚合查询、原子操作、Mapper 等） | 8 个 Data 层文件 | 查询优化和修复是否保留 |
| P2-C | Presentation 层修复（组件复用、常量提取等） | 18 个 Presentation 层文件 | UI 修复是否保留 |
| P2-D | App 层修复（BackgroundTaskProviding 等） | 2+1 个文件 | 协议和 DI 注入是否正确 |

### 8.2 新增订阅系统（R7/R8/R14 重点）

| 关注点 | 涉及文件 | 说明 |
|--------|----------|------|
| StoreKit 2 集成 | `App/StoreKitSubscriptionProvider.swift` | 交易验证、恢复购买流程 |
| 订阅状态同步 | `Domain/Services/SubscriptionService.swift` | 状态变更的及时性和一致性 |
| 功能门控 | `Presentation/Subscription/` | 付费功能的正确拦截 |
| 协议设计 | `Domain/Entities/SubscriptionTypes.swift` | SubscriptionProviding 接口完整性 |

### 8.3 竞态与并发

| 关注点 | 涉及文件 | 说明 |
|--------|----------|------|
| PlaybackService Task 管理 | `Domain/Services/PlaybackService.swift` | 验证 loadTask 修复效果，检查类似模式 |
| CoreData 上下文安全 | `Core/Persistence/`、`Data/Repositories/` | 双上下文模式是否正确使用 |
| Combine 订阅管理 | 所有使用 `.sink` 的文件 | cancellables 正确存储，无泄漏 |
| @MainActor 一致性 | 所有 Service | @Published 写入都在 @MainActor 上下文 |

### 8.4 分享功能

| 关注点 | 涉及文件 | 说明 |
|--------|----------|------|
| 网络安全 | `Core/Network/ShareServer.swift`、`ShareClient.swift` | 局域网 HTTP 服务的安全性 |
| 资源释放 | `Domain/Services/ShareService.swift` | 服务器/客户端的正确启停 |
| 大文件传输 | 分享相关文件 | 内存占用、传输中断恢复 |

### 8.5 架构合规

| 关注点 | 说明 |
|--------|------|
| 依赖方向 | Domain 层是否引入了不应有的上层/框架依赖 |
| .shared 收敛 | 基础设施单例是否按规划逐步迁移到 DI |
| Protocol 一致性 | 15 个基础设施协议与实现是否完全匹配 |

---

## 9. 风险与应对

| 风险 | 影响 | 应对 |
|------|------|------|
| 文件数量大（183），Review 耗时长 | 单个子任务内可能遗漏 | 按子任务逐批执行、每批独立验收，通过后不回头 |
| 修复引入新问题 | 回归风险 | 每次修复后重跑测试，子任务第 2 轮 Review 覆盖修改点 |
| 跨模块问题难定位 | 集成问题暴露晚 | 全部子任务完成后做跨模块集成 Review |
| 上下文窗口限制 | 大文件可能无法一次读完 | 按函数/代码块分段 Review |
| 子任务连续失败 | 流程阻塞 | 同一子任务连续失败 3 次暂停汇报用户 |
| Review 轮次过多 | 效率下降 | 单个子任务最多 5 轮，超限暂停汇报 |
