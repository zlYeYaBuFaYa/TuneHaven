# 方案：搜索历史接入 UI

> 创建日期：2026-03-20 | 状态：已完成

## 1. 需求概述

将已实现的 SearchService 搜索历史后端功能接入 LibraryMainView UI：

- **展示时机**：搜索框获得焦点且搜索文本为空时，在搜索结果区域显示搜索历史列表
- **历史内容**：每条显示关键词和搜索时间，按搜索时间倒序排列
- **交互操作**：
  - 点击历史词 → 回填到搜索框并触发搜索
  - 左滑单条删除
  - 提供"清空历史"按钮
- **自动保存**：搜索执行后自动保存到历史（SearchService 已有去重逻辑）
- **Tab 独立**：每个 Tab（全部/艺术家/专辑）独立维护搜索历史，最多 10 条

## 2. 现状分析

### 已有实现

| 组件 | 文件 | 状态 |
|------|------|------|
| SearchService.fetchHistory(tab:) | Domain/Services/SearchService.swift | ✅ 已实现，从 CoreData 按 Tab 查询，最多 10 条 |
| SearchService.saveHistory(keyword:tab:) | Domain/Services/SearchService.swift | ✅ 已实现，去重+超限淘汰最旧 |
| SearchService.deleteHistory(id:) | Domain/Services/SearchService.swift | ✅ 已实现 |
| SearchService.clearHistory() | Domain/Services/SearchService.swift | ✅ 已实现，清空所有 Tab 的历史 |
| SearchHistoryItem 模型 | Domain/Entities/LibraryTypes.swift | ✅ 已定义(id, keyword, searchedAt) |
| SearchHistoryEntity (CoreData) | MusicPlayer.xcdatamodeld | ✅ 已建表(id, keyword, tabContext, searchedAt) |
| @Published history: [SearchHistoryItem] | SearchService.swift:9 | ✅ 已声明，未被 UI 使用 |

### 需修改的文件清单

| 文件 | 改动类型 | 说明 |
|------|---------|------|
| LibraryMainView.swift | **修改** | 增加焦点追踪、搜索历史展示区域、保存历史调用 |
| SearchService.swift | **微调** | clearHistory 增加按 Tab 清空的重载 |

### 对现有功能的影响

- 搜索主流程不变，仅在"搜索框聚焦 + 文本为空"时插入历史展示层
- 搜索结果展示逻辑不变

## 3. 技术方案

### 3.1 整体设计

**数据流：**

```
用户聚焦搜索框(文本为空)
  → LibraryMainView 检测 isFocused && searchText.isEmpty
  → 调用 searchService.fetchHistory(tab: selectedTab)
  → searchService.history 更新(@Published)
  → 搜索历史视图展示

用户点击历史词
  → searchText = keyword
  → isSearchActive = true
  → 触发 performSearch → 展示搜索结果

搜索执行(performSearch)
  → 调用 searchService.saveHistory(keyword:tab:)
  → 刷新历史列表(下次展示时已更新)
```

**视图层级变更：**

```
LibraryMainView.body:
  VStack:
    searchBar              ← 增加 @FocusState 追踪
    tabBar
    Divider
    if isSearchActive && !debouncedQuery.isEmpty:
      SearchResultView     ← 现有搜索结果（不变）
    else if isFocused && searchText.isEmpty:
      searchHistoryView    ← 🆕 搜索历史
    else:
      libraryContent       ← 现有音乐库内容（不变）
```

### 3.2 详细实现

#### 3.2.1 LibraryMainView 改动

**1. 增加焦点状态追踪**

```swift
@FocusState private var isSearchFieldFocused: Bool
```

在 TextField 上绑定 `.focused($isSearchFieldFocused)`。

**2. 搜索栏增加焦点绑定**

```swift
TextField("搜索歌曲、艺术家或专辑", text: $searchText)
    .focused($isSearchFieldFocused)
```

取消按钮逻辑增加失焦：

```swift
Button {
    searchText = ""
    isSearchActive = false
    isSearchFieldFocused = false
} label: {
    Image(systemName: "xmark.circle.fill")
}
```

**3. body 中增加搜索历史条件分支**

在现有的 `if isSearchActive && !searchDebouncer.debouncedQuery.isEmpty` 和 `else { libraryContent }` 之间插入搜索历史分支：

```swift
else if isSearchFieldFocused && searchText.isEmpty {
    searchHistoryView
}
```

**4. 新增 searchHistoryView 计算属性**

内联在 LibraryMainView 中，不单独建文件（逻辑简单，与主视图紧耦合）：

```swift
private var searchHistoryView: some View {
    List {
        if searchService.history.isEmpty {
            // 空状态
            VStack(spacing: 12) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 36))
                    .foregroundColor(palette.iconSecondary)
                Text("暂无搜索历史")
                    .foregroundColor(palette.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
            .listRowBackground(Color.clear)
        } else {
            Section {
                ForEach(searchService.history) { item in
                    Button {
                        searchText = item.keyword
                        isSearchActive = true
                        isSearchFieldFocused = false
                        Task {
                            searchResult = await searchService.search(
                                query: item.keyword, tab: selectedTab, allSongs: libraryService.songs
                            )
                        }
                    } label: {
                        HStack {
                            Image(systemName: "clock")
                                .foregroundColor(palette.iconSecondary)
                            Text(item.keyword)
                                .foregroundColor(palette.textPrimary)
                            Spacer()
                            Text(item.searchedAt.relativeDescription)
                                .font(.caption)
                                .foregroundColor(palette.textTertiary)
                        }
                    }
                    .listRowBackground(palette.surface)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            Task {
                                await searchService.deleteHistory(id: item.id)
                                await searchService.fetchHistory(tab: selectedTab)
                            }
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                }
            } header: {
                HStack {
                    Text("搜索历史")
                    Spacer()
                    Button("清空") {
                        Task {
                            await searchService.clearHistory(tab: selectedTab)
                            await searchService.fetchHistory(tab: selectedTab)
                        }
                    }
                    .font(.caption)
                    .foregroundColor(palette.accent)
                }
            }
        }
    }
    .listStyle(.insetGrouped)
    .scrollContentBackground(.hidden)
    .adaptiveBackground()
}
```

**5. 在焦点变化和 Tab 切换时加载历史**

```swift
.onChange(of: isSearchFieldFocused) { _, focused in
    if focused && searchText.isEmpty {
        Task { await searchService.fetchHistory(tab: selectedTab) }
    }
}
.onChange(of: selectedTab) { _, newTab in
    if isSearchFieldFocused && searchText.isEmpty {
        Task { await searchService.fetchHistory(tab: newTab) }
    }
}
```

**6. 搜索执行后保存历史**

在 `performSearch` 方法末尾追加：

```swift
private func performSearch(query: String) {
    guard !query.isEmpty else { return }
    Task {
        searchResult = await searchService.search(query: query, tab: selectedTab, allSongs: libraryService.songs)
        await searchService.saveHistory(keyword: query, tab: selectedTab)
    }
}
```

#### 3.2.2 SearchService 改动

增加按 Tab 清空历史的方法重载（现有 clearHistory 清空所有 Tab）：

```swift
func clearHistory(tab: LibraryTab) async {
    log.info("清除搜索历史: tab=\(tab.rawValue)")
    try? await stack.performBackground { ctx in
        let request = SearchHistoryEntity.fetchRequest()
        request.predicate = NSPredicate(format: "tabContext == %@", tab.rawValue)
        let results = try ctx.fetch(request)
        results.forEach { ctx.delete($0) }
    }
}
```

#### 3.2.3 时间格式化工具

为搜索历史的时间显示增加相对时间描述扩展（如"刚刚"、"5分钟前"、"昨天"）：

```swift
extension Date {
    var relativeDescription: String {
        let interval = -timeIntervalSinceNow
        if interval < 60 { return "刚刚" }
        if interval < 3600 { return "\(Int(interval / 60))分钟前" }
        if interval < 86400 { return "\(Int(interval / 3600))小时前" }
        if interval < 604800 { return "\(Int(interval / 86400))天前" }
        let fmt = DateFormatter()
        fmt.dateFormat = "MM-dd"
        return fmt.string(from: self)
    }
}
```

此扩展放在 LibraryMainView.swift 底部（文件内 fileprivate 级别），不影响其他模块。

### 3.3 备选方案

| 方案 | 优点 | 缺点 |
|------|------|------|
| A. 内联在 LibraryMainView（采用） | 简单直接，数据流清晰 | LibraryMainView 文件变大 |
| B. 独立 SearchHistoryView.swift | 职责分离 | 需要传递多个回调和状态，对于简单列表过度拆分 |

推荐 A：搜索历史 UI 逻辑简单（约 60 行），与搜索框交互紧密，内联更自然。

## 4. 影响范围

| 范围 | 影响 |
|------|------|
| LibraryMainView | 增加焦点追踪 + 搜索历史视图分支 + 保存历史调用 |
| SearchService | 增加 clearHistory(tab:) 重载 |
| 数据库 | 无变更，SearchHistoryEntity 已存在 |
| 其他页面 | 无影响 |
| 向后兼容 | 完全兼容，仅增加新 UI 展示 |

## 5. 测试要点

| 场景 | 预期 |
|------|------|
| 搜索框聚焦 + 文本为空 | 显示搜索历史列表 |
| 搜索框聚焦 + 无历史 | 显示"暂无搜索历史"空状态 |
| 执行搜索后再清空文本 | 历史列表包含刚搜索的关键词 |
| 点击历史词 | 回填搜索框并触发搜索 |
| 左滑删除单条 | 该条消失，列表刷新 |
| 点击清空 | 当前 Tab 所有历史清除 |
| 切换 Tab 后聚焦 | 显示对应 Tab 的历史 |
| 同一关键词多次搜索 | 仅保留一条，时间更新 |
| 超过 10 条 | 自动淘汰最旧一条 |
| 搜索结果展示 | 原有搜索流程不受影响 |
| 取消搜索（点击 X） | 失焦，回到音乐库内容 |

## 6. 风险评估

| 风险 | 等级 | 应对 |
|------|------|------|
| @FocusState 在某些 iOS 版本下行为不一致 | 低 | 项目目标 iOS 18.5+，@FocusState 表现稳定 |
| 频繁切换 Tab 导致 fetchHistory 多次调用 | 低 | CoreData viewContext 查询本身很轻量，无性能问题 |
| clearHistory 误操作 | 低 | 清空按钮位于不起眼位置，且仅清空当前 Tab |
