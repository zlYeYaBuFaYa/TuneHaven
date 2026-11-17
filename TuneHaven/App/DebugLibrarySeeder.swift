#if DEBUG
import Foundation

/// 仅调试构建：启动时从环境变量 `TUNEHAVEN_SEED_DIR` 指定的目录导入音频，
/// 用于在模拟器里检查 UI 重做的页面。走正常导入流程，曲库已有歌曲时不重复导入。
///
/// 用法：`SIMCTL_CHILD_TUNEHAVEN_SEED_DIR=/path/to/dir xcrun simctl launch <udid> <bundle id>`
@MainActor
enum DebugLibrarySeeder {
    static func seedIfRequested(importService: ImportService, libraryService: MusicLibraryService) async {
        guard let dir = ProcessInfo.processInfo.environment["TUNEHAVEN_SEED_DIR"], !dir.isEmpty,
              libraryService.songs.isEmpty else { return }
        let urls = ((try? FileManager.default.contentsOfDirectory(
            at: URL(fileURLWithPath: dir, isDirectory: true),
            includingPropertiesForKeys: nil
        )) ?? []).sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard !urls.isEmpty else { return }
        AppLogger.shared.info("[DebugSeeder] 导入 \(urls.count) 个调试文件")
        _ = await importService.importFromFiles(urls: urls) { _ in }
        await libraryService.loadSongs()
    }
}
#endif
