import Foundation

enum LyricsLoadState: String, Equatable {
    case unavailable, loading, matching, loaded, notFound, networkError, saveError, instrumental

    var isBusy: Bool { self == .loading || self == .matching }
    var canRetry: Bool { self == .networkError || self == .saveError }
    var title: String {
        switch self {
        case .loading: return "正在读取歌词"
        case .matching: return "正在匹配歌词"
        case .notFound: return "没有找到匹配歌词"
        case .networkError: return "暂时无法匹配歌词"
        case .saveError: return "歌词保存失败"
        case .instrumental: return "器乐曲（无歌词）"
        default: return "暂无歌词"
        }
    }
    var message: String {
        switch self {
        case .loading, .matching: return "播放会继续，无需停留等待"
        case .networkError: return "请检查网络连接后重试，也可以添加本地歌词"
        case .saveError: return "请检查可用存储空间后重试"
        case .instrumental: return "已保存无歌词标记，也可以重新添加歌词"
        default: return "可以导入 LRC 文件，或搜索、粘贴歌词"
        }
    }
}

struct LyricsLoadResult {
    let state: LyricsLoadState
    var data: LyricsData? = nil
}
