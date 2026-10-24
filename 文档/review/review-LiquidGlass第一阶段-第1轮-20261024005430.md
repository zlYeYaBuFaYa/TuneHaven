# 方案 Review：Liquid Glass 第一阶段 - 第 1 轮

> 日期：2026-10-24 | 类型：AI 自审

## 结论：不通过

| 维度 | 结论 | 说明 |
|------|------|------|
| 需求覆盖 | ❌ | 玻璃路径若只看 `#available`，显式 `glassEffect` 在兼容键开着时仍可能画出新 Tab，不能满足「键开着 = 旧外观」 |
| 可执行性 | ✅ | 不迁移 TabView；导航栏、sheet、色板都能落在现有文件上 |
| 描述清晰度 | ✅ | 色值、分流条件和保留播放器渐变的原因写清了 |
| 逻辑合理性 | ❌ | 见上。只改 AppDelegate 而不收口 SwiftUI toolbar 时，主导航仍是不透明 surface，开/关键看不出导航差异 |
| 架构合规 | ✅ | 策略放在 App/Theme，不把 UIKit 外观塞进 Domain |
| 影响评估 | ✅ | 写了浅色主色变深、迷你播放条本期不动、编译依赖 Xcode 26 |
| 边界处理 | ❌ | 星际穹顶页面底是透明的。sheet 在玻璃路径若一律拿掉 `elevatedSurface`，文字会压在粒子背景上 |
| 性能考量 | ✅ | 不新增滚动计算；Tab 只铺一层玻璃，不用 interactive |

## 问题

1. [🔴] 分流只写 `#available(iOS 26, *)` 时，不能同时保证「键开着保持旧外观」和「关掉键能测玻璃」。显式 `glassEffect` 不保证会被兼容键关掉。
2. [🟡] 音乐库、歌单、设置以及内页的 `.toolbarBackground(palette.surface)` 会盖住 UIKit appearance。方案若只改 AppDelegate，导航验收无效。
3. [🟡] 有自绘背景的 sheet 不能和纯色主题共用「拿掉 presentationBackground」。

## 修改记录

本轮不通过，方案按下一条修改后再审。
