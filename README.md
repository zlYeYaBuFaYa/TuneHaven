# TuneHaven

> iOS 本地优先音乐播放器：曲库、有损播放、歌单和本地导入离线免费可用，Premium 解锁无损播放、高级主题、WebDAV 导入和在线歌词。

[![Swift](https://img.shields.io/badge/Swift-5.0-orange.svg)](https://swift.org)
[![iOS](https://img.shields.io/badge/iOS-18.0+-blue.svg)](https://apple.com/ios)
[![Xcode](https://img.shields.io/badge/Xcode-27+-brightgreen.svg)](https://developer.apple.com/xcode)

## 功能

| 模块 | 内容 |
|------|------|
| 导入 | 文件、Apple Music（过滤 DRM）、百度网盘、WiFi 浏览器上传（可设密码）、从其他 App 打开、WebDAV（Premium）。8 种格式，单文件 ≤ 500MB，按内容去重 |
| 播放 | 顺序 / 单曲循环 / 列表循环 / 加权随机，0.5x–2.0x 倍速（全局或单曲记忆），定时关闭，后台播放与锁屏控制，启动恢复上次歌曲，无损播放（Premium） |
| 音乐库 | 全部 / 艺术家 / 专辑浏览，6 种排序，格式筛选，收藏，删除 30 秒内可撤销 |
| 搜索 | 原文、拼音全拼、拼音首字母、单字符容错；音乐库与歌单内搜索；按标签保存搜索历史 |
| 歌单 | 我喜欢、最近播放、自建歌单、分组、拖拽排序、批量添加、自动拼封面、播放队列 |
| 歌词 | 内嵌、导入 LRC、手动粘贴、在线匹配（Premium）；卡拉 OK 逐行填充、缩放、简繁切换 |
| 主题 | 素云白简、晴空蔚蓝（免费）；暮光玫瑰、星际穹顶（Premium）。iOS 26/27 使用 Liquid Glass，iOS 18–25 保持旧外观 |
| 分享 | 同一 WiFi 下扫码直传歌曲和歌单，自动跳过对方已有的歌 |
| 备份 | 导出 `.tunehaven`；恢复支持合并 / 替换曲库 / 仅偏好，失败自动回滚 |
| 订阅 | StoreKit 2 年度订阅与终身买断，新用户试用 30 天，到期温和降级 |

完整规则和已知缺口见 [需求文档](docs/需求文档.md)。

## 技术栈

Swift 5.0 · SwiftUI · Clean Architecture + MVVM · Core Data · AVFoundation · Network Framework · StoreKit 2 · Combine + async/await · XCTest。无第三方依赖。

```
App → Presentation → Domain ← Data
                       ↑
                     Core（音频、缓存、网络、持久化、存储）
```

架构与实现细节见 [技术设计文档](docs/技术设计文档.md)。

## 构建与测试

环境：Xcode 27+（iOS 27 SDK），部署目标 iOS 18.0。

```bash
# 构建
xcodebuild -project TuneHaven.xcodeproj -scheme TuneHaven \
  -destination 'platform=iOS Simulator,name=iPhone 16'

# 测试
xcodebuild test -project TuneHaven.xcodeproj -scheme TuneHaven \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

也可以在 Xcode 中打开 `TuneHaven.xcodeproj`，用 Command + R 运行，Command + U 测试。

目录结构、数据库、Info.plist 配置和测试清单见 [项目文档](docs/项目文档.md)。

## 提审前检查

- 隐私政策 `https://tunehaven.app/privacy` 不在本仓库托管，提审前必须确认可以公开访问
- 内购商品 `com.tunehaven.subscription.yearly`、`com.tunehaven.lifetime` 需在 App Store Connect 配置

## 隐私

曲库只保存在设备上，不内置广告和追踪 SDK。只有购买/恢复购买、在线歌词、用户配置的 WebDAV 会联网；WiFi 传输和分享直传只在局域网内进行。

## 文档

| 文档 | 内容 |
|------|------|
| [需求文档](docs/需求文档.md) | 功能、业务规则、Free/Premium 权限、已知缺口 |
| [技术设计文档](docs/技术设计文档.md) | 架构、各服务实现、协议、存储、错误码、隐私清单 |
| [项目文档](docs/项目文档.md) | 技术栈、目录、数据库、配置、构建测试、代码遗留 |

## 代码统计

| 类型 | 行数 |
|------|------|
| 主项目 | 25,290 |
| 测试 | 8,069 |
| 合计 | 33,359（Swift 文件 234 个） |

## 许可证

MIT License
