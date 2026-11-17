# 交互缺口实施与验证

日期：2026-11-17。沿用云霞／晴屿／月晕主题，无新增收费入口。

## 本轮实现

1. FLAC：读取原生 Vorbis Comment（标题、艺术家、专辑、曲目号、日期、类型、编码器）、封面与 STREAMINFO，补充系统未暴露的元数据。旧记录不自动批量回填，Ogg／MP4 等封装继续走既有解析。
2. 歌词：区分读取、匹配、无结果、网络失败、保存失败和器乐曲。网络失败可重试；本地添加始终可用；切歌、取消或手动添加后迟到结果不会覆盖当前选择。纯文本不再生成虚构时间轴。
3. 器乐曲：精确匹配或用户选择在线器乐曲结果后，复用现有 lyricsSource 字段持久化（值 3）；重启与备份恢复保留；添加新歌词替换标记。不需要 Core Data 模型迁移。
4. 歌单：排序态行尾菜单提供上移／下移；首尾禁用无效方向，避免只能拖动。
5. 歌单歌曲：独立草稿编辑页支持拖动和上移／下移；取消不落盘，保存后重开保留，当前队列不变。陈旧草稿和系统歌单拒绝覆盖。

此外，旧歌名歌词的读取／清理限制为歌词目录直接子文件，修复 Review T8 低危路径越界。

## 布局检查

- 标准 iPhone 日间：歌词状态、本地添加、重试、歌单移动菜单与歌曲编辑页。
- 375 pt 小屏：日夜模式及最大辅助功能字号；歌词页切换为整页滚动，重试／添加／播放控件可达。
- 无歌词不再显示禁用的字号／字形工具条；播放图标及紧凑时间标签上限为标准最大字号，避免重叠。
- iPhone 工程仍仅支持竖屏；设备旋转操作不等于 iPhone 横屏验收。

## 测试与边界

- 全量单元回归共 646 项通过（644 项 Swift Testing、2 项 XCTest），iPhone 模拟器的 4 项交互 UI 测试通过。
- iPad mini 横屏的最大字号控件可达性测试通过，但屏幕采集出现空白。重启后普通音乐库仍呈空白，上一轮基线 `342a511` 在同一模拟器也能复现。原因待查，iPad 视觉验收待完成。
- `FLACMetadataTests`：真实带中文标签的 FLAC、大小写／等号内容、坏长度、截断、图片选择与外部 URL 拒绝。
- `LyricsLoadStateTests`：匹配回调、无结果缓存、网络重试／权限、纯文本、Core Data 器乐曲持久化、备份、取消及手动选择竞态。
- `PlaylistOrderTests`：临时 SQLite 的真实排序、重读、陈旧草稿／重复 ID 拒绝及系统歌单隔离。内存库不支持现有 GROUP BY 计数，因此此组使用临时 SQLite。
- UI 状态截图通过 DEBUG fixture 展示；真实服务状态和持久化由单元测试验证，未向真实歌词服务发送歌曲信息。
- 完整 VoiceOver 焦点／朗读、真实在线歌词匹配、长歌词逐行填充、全部主题与 iPad 完整布局仍属于专项验收。

## 截图

- `lyrics-matching.png`、`lyrics-networkError.png`、`lyrics-notFound.png`、`lyrics-instrumental.png`：常规歌词状态。
- `playlist-order-tap-alternative.png`、`song-order-saved.png`：歌单与歌曲排序。
- `lyrics-error-375-light.png`、`lyrics-error-375-dark-ax5.png`：小屏日夜布局。
- `lyrics-ax5-375-retry.png`、`lyrics-ax5-375-controls.png`：最大字号下滚动前后的可达性。

- `ipad-library-current-blank.png`、`ipad-library-baseline-blank.png`：当前实现与上一轮基线的 iPad 音乐库空白对照。

## 接续位置

- FLAC 标签 `3967cf0`，歌词反馈与器乐曲 `404cca3`，歌单与歌曲排序 `76ea8b4`。原清单的 5 项交互缺口均已实施。
- 按任务清单继续处理 Review 中危项。iPad 空白另列为已知问题，可用同一模拟器或真机复核启动与界面渲染。
- 本地测试结果在 `/tmp/tunehaven-interaction-verified.xcresult`、`/tmp/tunehaven-interaction-ipad.xcresult`。仓库内保留截图和结果摘要。
